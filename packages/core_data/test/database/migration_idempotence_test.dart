import 'package:core_data/database/app_database.dart';
import 'package:core_data/database/dao/document.dao.dart';
import 'package:drift/drift.dart' show QueryExecutor, QueryRow;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import 'v1_database.dart';
import 'v2_database.dart';

/// La migration 1 -> 2 doit etre rejouable : une vraie base s'est retrouvee
/// avec tous les objets v2 deja presents (colonnes, tables, FTS5, triggers)
/// mais `user_version = 1`. L'ouvrir doit reussir sans perte ni doublon, et
/// une migration interrompue a mi-chemin doit etre completee.

typedef _Object = (String type, String name);

const List<String> _v1Tables = <String>[
  'sessions',
  'transcript_segments',
  'summaries',
];

/// Objets du schema (tables, tables virtuelles et leurs tables internes,
/// triggers, index), hors objets internes de SQLite.
Future<Set<_Object>> _objects(AppDatabase db) async {
  final List<Map<String, Object?>> rows =
      (await db
              .customSelect(
                'SELECT type, name FROM sqlite_master '
                "WHERE name NOT LIKE 'sqlite_%'",
              )
              .get())
          .map((QueryRow r) => r.data)
          .toList();
  return <_Object>{
    for (final Map<String, Object?> r in rows)
      (r['type']! as String, r['name']! as String),
  };
}

Future<List<String>> _columns(AppDatabase db, String table) async {
  final List<QueryRow> rows = await db
      .customSelect('PRAGMA table_info("$table")')
      .get();
  return <String>[for (final QueryRow r in rows) r.data['name']! as String];
}

Future<int> _count(AppDatabase db, String table) async {
  final QueryRow row = await db
      .customSelect('SELECT COUNT(*) AS n FROM "$table"')
      .getSingle();
  return row.data['n']! as int;
}

Future<int> _userVersion(AppDatabase db) async {
  final QueryRow row = await db.customSelect('PRAGMA user_version').getSingle();
  return row.data['user_version']! as int;
}

/// Schema d'une base v2 neuve : objets, colonnes par table, et les
/// instructions SQL qui creent les objets v2 (pour fabriquer les fixtures).
class _FreshV2 {
  _FreshV2(this.objects, this.columns, this.statements, this.addedColumns);

  final Set<_Object> objects;
  final Map<String, List<String>> columns;

  /// `CREATE ...` des objets ajoutes par la v2, par nom, dans l'ordre
  /// tables, tables virtuelles, triggers, index.
  final Map<String, String> statements;

  /// `ALTER TABLE ... ADD COLUMN ...` des colonnes ajoutees aux tables v1,
  /// par "table.colonne".
  final Map<String, String> addedColumns;

  static Future<_FreshV2> load() async {
    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    try {
      final Set<_Object> objects = await _objects(db);
      final Map<String, List<String>> columns = <String, List<String>>{};
      for (final _Object o in objects.where((_Object o) => o.$1 == 'table')) {
        columns[o.$2] = await _columns(db, o.$2);
      }

      final List<QueryRow> rows = await db
          .customSelect(
            'SELECT type, name, sql FROM sqlite_master '
            "WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%'",
          )
          .get();
      final List<Map<String, Object?>> all = <Map<String, Object?>>[
        for (final QueryRow r in rows) r.data,
      ];
      final List<String> virtualTables = <String>[
        for (final Map<String, Object?> r in all)
          if ((r['sql']! as String).toUpperCase().startsWith('CREATE VIRTUAL'))
            r['name']! as String,
      ];
      bool isShadow(String name) =>
          virtualTables.any((String v) => name.startsWith('${v}_'));
      int rank(Map<String, Object?> r) {
        final String sql = (r['sql']! as String).toUpperCase();
        if (sql.startsWith('CREATE VIRTUAL')) return 1;
        return switch (r['type']) {
          'table' => 0,
          'trigger' => 2,
          _ => 3,
        };
      }

      final List<Map<String, Object?>> v2 =
          all
              .where(
                (Map<String, Object?> r) =>
                    !_v1Tables.contains(r['name']) &&
                    !isShadow(r['name']! as String),
              )
              .toList()
            ..sort(
              (Map<String, Object?> a, Map<String, Object?> b) =>
                  rank(a).compareTo(rank(b)),
            );

      final Map<String, String> addedColumns = <String, String>{};
      for (final String table in <String>['sessions', 'transcript_segments']) {
        final List<QueryRow> info = await db
            .customSelect('PRAGMA table_info("$table")')
            .get();
        for (final QueryRow r in info) {
          final Map<String, Object?> c = r.data;
          final String name = c['name']! as String;
          if (const <String>[
            'calendar_event_id',
            'calendar_event_title',
            'attendees',
            'speaker',
          ].contains(name)) {
            addedColumns['$table.$name'] =
                'ALTER TABLE "$table" ADD COLUMN "$name" ${c['type']}';
          }
        }
      }

      return _FreshV2(objects, columns, <String, String>{
        for (final Map<String, Object?> r in v2)
          r['name']! as String: r['sql']! as String,
      }, addedColumns);
    } finally {
      await db.close();
    }
  }
}

const List<String> _v2Rows = <String>[
  'INSERT INTO detected_questions (id, session_id, question, timestamp_ms, '
      "created_at) VALUES ('q-1', 'session-1', 'Quel est le budget ?', 4000, "
      "'2026-11-20T09:00:05.000')",
  "INSERT INTO documents (id, title, path, added_at) VALUES ('budget', "
      "'Budget 2027', '/Users/me/Documents/budget.md', "
      "'2026-11-20T08:00:00.000')",
  'INSERT INTO document_chunks (id, document_id, position, content) VALUES '
      "('budget-0', 'budget', 0, "
      "'Le budget marketing 2027 est fixé à 40 000 euros.')",
];

void main() {
  late _FreshV2 fresh;

  setUpAll(() async => fresh = await _FreshV2.load());

  Future<void> expectV2Schema(AppDatabase db) async {
    expect(await _objects(db), fresh.objects);
    for (final MapEntry<String, List<String>> t in fresh.columns.entries) {
      expect(
        await _columns(db, t.key),
        unorderedEquals(t.value),
        reason: 'colonnes de ${t.key}',
      );
    }
    expect(await _userVersion(db), db.schemaVersion);
  }

  group('base déjà migrée mais marquée v1', () {
    late AppDatabase db;

    setUp(() {
      expect(
        fresh.statements.keys,
        containsAll(<String>[
          'detected_questions',
          'documents',
          'document_chunks',
        ]),
        reason: 'le schéma v2 neuf doit contenir les tables du besoin',
      );
      db = AppDatabase(
        v1DatabaseWithData(
          extraStatements: <String>[
            ...fresh.addedColumns.values,
            ...fresh.statements.values,
            ..._v2Rows,
          ],
        ),
      );
    });
    tearDown(() => db.close());

    test('s’ouvre et garde toutes les lignes', () async {
      expect(await _count(db, 'sessions'), 1);
      expect(await _count(db, 'transcript_segments'), 2);
      expect(await _count(db, 'summaries'), 2);
      expect(await _count(db, 'detected_questions'), 1);
      expect(await _count(db, 'documents'), 1);
      expect(await _count(db, 'document_chunks'), 1);
    });

    test(
      'a le schéma d’une base v2 neuve, chaque table et trigger une fois',
      () async {
        await expectV2Schema(db);
      },
    );

    test(
      'la recherche fonctionne et chaque morceau n’y figure qu’une fois',
      () async {
        final DocumentDao dao = DocumentDao(db);
        expect(
          (await dao.search('marketing')).single.documentTitle,
          'Budget 2027',
        );

        await db
            .into(db.documentChunks)
            .insert(
              DocumentChunksCompanion.insert(
                id: 'budget-1',
                documentId: 'budget',
                position: 1,
                content: 'Le recrutement de deux développeurs est financé.',
              ),
            );
        expect(
          (await dao.search('recrutement')).single.content,
          'Le recrutement de deux développeurs est financé.',
        );

        await (db.delete(
          db.documents,
        )..where(($DocumentsTable t) => t.id.equals('budget'))).go();
        expect(await dao.search('budget'), isEmpty);
        expect(await dao.search('recrutement'), isEmpty);
      },
    );
  });

  group('migration interrompue à mi-chemin', () {
    late AppDatabase db;

    setUp(() {
      // Deja passes : deux colonnes et deux tables. Manquent : les autres
      // colonnes, document_chunks, la table FTS5 et les triggers.
      db = AppDatabase(
        v1DatabaseWithData(
          extraStatements: <String>[
            fresh.addedColumns['sessions.calendar_event_id']!,
            fresh.addedColumns['transcript_segments.speaker']!,
            fresh.statements['detected_questions']!,
            fresh.statements['documents']!,
            _v2Rows[0],
            _v2Rows[1],
          ],
        ),
      );
    });
    tearDown(() => db.close());

    test('s’ouvre sans erreur et garde toutes les lignes', () async {
      expect(await _count(db, 'sessions'), 1);
      expect(await _count(db, 'transcript_segments'), 2);
      expect(await _count(db, 'summaries'), 2);
      expect(await _count(db, 'detected_questions'), 1);
      expect(await _count(db, 'documents'), 1);
    });

    test('complète le schéma jusqu’à celui d’une base v2 neuve', () async {
      await expectV2Schema(db);
    });

    test('la recherche fonctionne une fois le schéma complété', () async {
      await db
          .into(db.documentChunks)
          .insert(
            DocumentChunksCompanion.insert(
              id: 'budget-0',
              documentId: 'budget',
              position: 0,
              content: 'Le budget marketing 2027 est fixé à 40 000 euros.',
            ),
          );

      final DocumentSearchResult hit = (await DocumentDao(
        db,
      ).search('marketing')).single;
      expect(hit.documentTitle, 'Budget 2027');
    });
  });

  // Schéma v4 (prix de la transcription en ligne, 2026-11-26) : `sessions`
  // gagne `cloud_realtime_ms` et `cloud_batch_ms` (INTEGER non nuls, défaut
  // 0) : ms d'audio facturées par Mistral (temps réel, rattrapage batch).
  // Migration 3 -> 4 rejouable comme les autres : une base peut déjà avoir
  // tout ou partie des colonnes avec `user_version = 3`.
  group('v3 -> v4 : usage Mistral par session', () {
    const List<String> cloudColumns = <String>[
      'cloud_realtime_ms',
      'cloud_batch_ms',
    ];

    Future<Map<String, Object?>> sessionRow(AppDatabase db) async =>
        (await db
                .customSelect("SELECT * FROM sessions WHERE id = 'session-1'")
                .getSingle())
            .data;

    Future<void> expectV4(AppDatabase db) async {
      expect(await _userVersion(db), 4);
      final List<String> cols = await _columns(db, 'sessions');
      for (final String c in cloudColumns) {
        expect(
          cols.where((String n) => n == c),
          hasLength(1),
          reason: '$c une fois dans sessions',
        );
      }
      final AppDatabase fresh = AppDatabase(NativeDatabase.memory());
      final Set<String> freshCols = (await _columns(fresh, 'sessions')).toSet();
      await fresh.close();
      expect(cols.toSet(), freshCols, reason: 'colonnes d une v4 neuve');
    }

    Future<void> expectRowsKept(AppDatabase db) async {
      expect(await _count(db, 'sessions'), 1);
      expect(await _count(db, 'transcript_segments'), 2);
      expect(await _count(db, 'detected_questions'), 2);
      expect(await _count(db, 'documents'), 1);
      expect((await sessionRow(db))['title'], 'Point client');
    }

    Future<void> expectDefaultZero(AppDatabase db) async {
      await db.customStatement(
        'INSERT INTO sessions (id, title, created_at, updated_at, status) '
        "VALUES ('session-new', 'Nouvelle', '2026-11-26T10:00:00.000', "
        "'2026-11-26T10:00:00.000', 'completed')",
      );
      final Map<String, Object?> row =
          (await db
                  .customSelect(
                    "SELECT * FROM sessions WHERE id = 'session-new'",
                  )
                  .getSingle())
              .data;
      expect(row['cloud_realtime_ms'], 0);
      expect(row['cloud_batch_ms'], 0);
    }

    test('une base v4 neuve a les deux colonnes, à 0 par défaut', () async {
      final AppDatabase db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      expect(await _columns(db, 'sessions'), containsAll(cloudColumns));
      await db.customStatement(
        'INSERT INTO sessions (id, title, created_at, updated_at, status) '
        "VALUES ('session-1', 'Point client', '2026-11-26T10:00:00.000', "
        "'2026-11-26T10:00:00.000', 'completed')",
      );
      expect((await sessionRow(db))['cloud_realtime_ms'], 0);
      expect((await sessionRow(db))['cloud_batch_ms'], 0);
    });

    test('v3 propre : schéma v4, lignes gardées, usage à 0', () async {
      final AppDatabase db = AppDatabase(_v3DatabaseWithData());
      addTearDown(db.close);
      await expectV4(db);
      await expectRowsKept(db);
      final Map<String, Object?> row = await sessionRow(db);
      expect(row['cloud_realtime_ms'], 0);
      expect(row['cloud_batch_ms'], 0);
      await expectDefaultZero(db);
    });

    test('colonnes v4 déjà là (usage rangé) mais user_version = 3 : '
        's ouvre, chaque colonne une fois, l usage est gardé', () async {
      final AppDatabase db = AppDatabase(
        _v3DatabaseWithData(
          extraStatements: <String>[
            'ALTER TABLE "sessions" ADD COLUMN "cloud_realtime_ms" INTEGER '
                'NOT NULL DEFAULT 0',
            'ALTER TABLE "sessions" ADD COLUMN "cloud_batch_ms" INTEGER '
                'NOT NULL DEFAULT 0',
            'UPDATE sessions SET cloud_realtime_ms = 90000, '
                "cloud_batch_ms = 60000 WHERE id = 'session-1'",
          ],
        ),
      );
      addTearDown(db.close);
      await expectV4(db);
      await expectRowsKept(db);
      final Map<String, Object?> row = await sessionRow(db);
      expect(row['cloud_realtime_ms'], 90000);
      expect(row['cloud_batch_ms'], 60000);
    });

    test('migration 3 -> 4 interrompue (une colonne seulement) : complétée, '
        'la valeur déjà rangée gardée', () async {
      final AppDatabase db = AppDatabase(
        _v3DatabaseWithData(
          extraStatements: <String>[
            'ALTER TABLE "sessions" ADD COLUMN "cloud_realtime_ms" INTEGER '
                'NOT NULL DEFAULT 0',
            'UPDATE sessions SET cloud_realtime_ms = 1234 '
                "WHERE id = 'session-1'",
          ],
        ),
      );
      addTearDown(db.close);
      await expectV4(db);
      await expectRowsKept(db);
      final Map<String, Object?> row = await sessionRow(db);
      expect(row['cloud_realtime_ms'], 1234);
      expect(row['cloud_batch_ms'], 0);
      await expectDefaultZero(db);
    });

    test('garde : une base v1 va jusqu à la v4, usage à 0', () async {
      final AppDatabase db = AppDatabase(v1DatabaseWithData());
      addTearDown(db.close);
      expect(await _userVersion(db), 4);
      expect(await _columns(db, 'sessions'), containsAll(cloudColumns));
      expect(await _count(db, 'sessions'), 1);
      await expectDefaultZero(db);
    });
  });
}

/// Base v3 figée (v2 + les trois colonnes v3 de `detected_questions`),
/// `user_version = 3`. Ne pas la dériver du code courant (v4).
QueryExecutor _v3DatabaseWithData({
  List<String> extraStatements = const <String>[],
}) => NativeDatabase.memory(
  // ponytail: type `Database` de package:sqlite3, non dépendance directe.
  // ignore: always_specify_types
  setup: (raw) {
    kV2Schema.forEach(raw.execute);
    <String>[
      'ALTER TABLE "detected_questions" ADD COLUMN "status" TEXT NOT NULL '
          "DEFAULT 'unanswered'",
      'ALTER TABLE "detected_questions" ADD COLUMN "speaker" TEXT NULL',
      'ALTER TABLE "detected_questions" ADD COLUMN "source" TEXT NULL',
    ].forEach(raw.execute);
    kV2Rows.forEach(raw.execute);
    extraStatements.forEach(raw.execute);
    raw.execute('PRAGMA user_version = 3');
  },
);
