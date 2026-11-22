import 'package:core_data/database/app_database.dart';
import 'package:core_data/database/dao/document.dao.dart';
import 'package:drift/drift.dart' show QueryRow;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import 'v1_database.dart';

/// Schéma v3 (tour 6, point 2) : `transcript_segments.is_partial`, booléen
/// non nul, faux par défaut. Même rigueur que 1 -> 2 :
/// - 2 -> 3 garde chaque ligne, avec is_partial = faux ;
/// - IDEMPOTENTE : une base qui a déjà la colonne mais `user_version = 2`
///   s'ouvre sans erreur (une vraie base a fini dans cet état pour la v2),
///   sans écraser les valeurs déjà écrites ;
/// - une base v1 s'ouvre jusqu'à la v3, données gardées ;
/// - la table FTS, les triggers et chaque objet v2 restent, une fois chacun.
/// La v3 n'ajoute qu'une instruction (ADD COLUMN) : le cas « à moitié
/// appliqué » est celui où la colonne existe déjà.

Future<List<Map<String, Object?>>> _rows(AppDatabase db, String sql) async =>
    <Map<String, Object?>>[
      for (final QueryRow r in await db.customSelect(sql).get()) r.data,
    ];

Future<int> _userVersion(AppDatabase db) async =>
    (await _rows(db, 'PRAGMA user_version')).single['user_version']! as int;

Future<Map<String, int>> _objectCounts(AppDatabase db) async {
  final Map<String, int> counts = <String, int>{};
  for (final Map<String, Object?> r in await _rows(
    db,
    "SELECT type, name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'",
  )) {
    final String key = '${r['type']}:${r['name']}';
    counts[key] = (counts[key] ?? 0) + 1;
  }
  return counts;
}

Future<Map<String, Object?>?> _isPartialColumn(AppDatabase db) async {
  for (final Map<String, Object?> c in await _rows(
    db,
    'PRAGMA table_info("transcript_segments")',
  )) {
    if (c['name'] == 'is_partial') return c;
  }
  return null;
}

/// Ce qu'une base v2 contient en plus d'une v1, d'après une base neuve :
/// tables, FTS5, triggers, index, et colonnes ajoutées (sauf is_partial).
class _V2Statements {
  _V2Statements(this.statements, this.fresh);

  final List<String> statements;
  final Map<String, int> fresh;

  static const List<String> _v1Tables = <String>[
    'sessions',
    'transcript_segments',
    'summaries',
  ];
  static const List<String> _v2Columns = <String>[
    'calendar_event_id',
    'calendar_event_title',
    'attendees',
    'speaker',
  ];

  static Future<_V2Statements> load() async {
    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    try {
      final Map<String, int> fresh = await _objectCounts(db);
      final List<Map<String, Object?>> all = await _rows(
        db,
        'SELECT type, name, sql FROM sqlite_master '
        "WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%'",
      );
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

      final List<Map<String, Object?>> objects =
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
      final List<String> columns = <String>[];
      for (final String table in <String>['sessions', 'transcript_segments']) {
        for (final Map<String, Object?> c in await _rows(
          db,
          'PRAGMA table_info("$table")',
        )) {
          if (_v2Columns.contains(c['name'])) {
            columns.add(
              'ALTER TABLE "$table" ADD COLUMN "${c['name']}" ${c['type']}',
            );
          }
        }
      }
      return _V2Statements(<String>[
        ...columns,
        for (final Map<String, Object?> r in objects) r['sql']! as String,
        "INSERT INTO documents (id, title, path, added_at) VALUES ('budget', "
            "'Budget 2027', '/Users/me/Documents/budget.md', "
            "'2026-11-20T08:00:00.000')",
        'INSERT INTO document_chunks (id, document_id, position, content) '
            "VALUES ('budget-0', 'budget', 0, "
            "'Le budget marketing 2027 est fixé à 40 000 euros.')",
      ], fresh);
    } finally {
      await db.close();
    }
  }
}

void main() {
  late _V2Statements v2;

  setUpAll(() async => v2 = await _V2Statements.load());

  Future<void> expectV3(AppDatabase db) async {
    expect(await _userVersion(db), 3);
    final Map<String, Object?>? column = await _isPartialColumn(db);
    expect(column, isNotNull, reason: 'colonne is_partial');
    expect(column!['notnull'], 1);
    expect('${column['dflt_value']}'.toLowerCase(), anyOf('0', 'false'));
    final Map<String, int> counts = await _objectCounts(db);
    expect(counts, v2.fresh, reason: 'chaque objet, une fois, comme neuf');
    expect(
      counts.keys.where((String k) => k.startsWith('trigger:')),
      isNotEmpty,
      reason: 'les triggers FTS sont là',
    );
  }

  Future<List<Object?>> partialFlags(AppDatabase db) async => <Object?>[
    for (final Map<String, Object?> r in await _rows(
      db,
      'SELECT is_partial FROM transcript_segments ORDER BY id',
    ))
      r['is_partial'],
  ];

  test('une base neuve a la colonne is_partial', () async {
    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    expect(db.schemaVersion, 3);
    await expectV3(db);
  });

  group('2 -> 3', () {
    test('garde chaque ligne, marquée complète', () async {
      final AppDatabase db = AppDatabase(
        v1DatabaseWithData(extraStatements: v2.statements, userVersion: 2),
      );
      addTearDown(db.close);

      expect(
        (await _rows(
          db,
          'SELECT COUNT(*) AS n FROM transcript_segments',
        )).single['n'],
        2,
      );
      expect(await partialFlags(db), <Object?>[0, 0]);
      expect(
        (await _rows(db, 'SELECT COUNT(*) AS n FROM summaries')).single['n'],
        2,
      );
      await expectV3(db);
    });

    test('la recherche plein texte marche toujours', () async {
      final AppDatabase db = AppDatabase(
        v1DatabaseWithData(extraStatements: v2.statements, userVersion: 2),
      );
      addTearDown(db.close);

      expect(
        (await DocumentDao(db).search('marketing')).single.documentTitle,
        'Budget 2027',
      );
    });
  });

  group('colonne déjà là mais user_version = 2', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(
        v1DatabaseWithData(
          extraStatements: <String>[
            ...v2.statements,
            'ALTER TABLE "transcript_segments" ADD COLUMN "is_partial" '
                'INTEGER NOT NULL DEFAULT 0 CHECK ("is_partial" IN (0, 1))',
            "UPDATE transcript_segments SET is_partial = 1 WHERE id = 'seg-2'",
          ],
          userVersion: 2,
        ),
      );
    });
    tearDown(() => db.close());

    test(
      's ouvre sans erreur, colonne une seule fois, valeurs gardées',
      () async {
        final List<Map<String, Object?>> columns = await _rows(
          db,
          'PRAGMA table_info("transcript_segments")',
        );
        expect(
          columns.where((Map<String, Object?> c) => c['name'] == 'is_partial'),
          hasLength(1),
        );
        expect(await partialFlags(db), <Object?>[0, 1]);
        await expectV3(db);
      },
    );
  });

  test('une base v1 s ouvre jusqu à la v3, données gardées', () async {
    final AppDatabase db = AppDatabase(v1DatabaseWithData());
    addTearDown(db.close);

    expect(
      (await _rows(db, 'SELECT COUNT(*) AS n FROM sessions')).single['n'],
      1,
    );
    expect(await partialFlags(db), <Object?>[0, 0]);
    await expectV3(db);
  });
}
