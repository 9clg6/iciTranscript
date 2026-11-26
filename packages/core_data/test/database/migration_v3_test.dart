import 'package:core_data/database/app_database.dart';
import 'package:core_data/database/dao/document.dao.dart';
import 'package:drift/drift.dart' show QueryRow;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import 'v1_database.dart';
import 'v2_database.dart';

/// Schéma v3 (T4) : `detected_questions` gagne `status` (texte non nul :
/// unanswered, answered, declined, truncated, failed), `speaker` et `source`
/// (texte, nullables). La migration 2 -> 3 garde toutes les lignes et se
/// rejoue sans erreur, comme 1 -> 2 : une vraie base a déjà eu les nouveaux
/// objets avec un `user_version` plus ancien.
///
/// Rangement des lignes v2 : réponse présente -> 'answered', sinon
/// 'unanswered'. Une valeur déjà posée par une migration passée est gardée.
Future<Map<String, ({int notNull})>> _columns(AppDatabase db) async {
  final List<QueryRow> rows = await db
      .customSelect('PRAGMA table_info("detected_questions")')
      .get();
  return <String, ({int notNull})>{
    for (final QueryRow r in rows)
      r.data['name']! as String: (notNull: r.data['notnull']! as int),
  };
}

Future<int> _userVersion(AppDatabase db) async =>
    (await db.customSelect('PRAGMA user_version').getSingle())
            .data['user_version']!
        as int;

Future<int> _count(AppDatabase db, String table) async =>
    (await db.customSelect('SELECT COUNT(*) AS n FROM "$table"').getSingle())
            .data['n']!
        as int;

Future<Map<String, Map<String, Object?>>> _questions(AppDatabase db) async {
  final List<QueryRow> rows = await db
      .customSelect(
        'SELECT id, status, speaker, source, answer FROM detected_questions',
      )
      .get();
  return <String, Map<String, Object?>>{
    for (final QueryRow r in rows) r.data['id']! as String: r.data,
  };
}

void main() {
  late Set<String> freshColumns;

  setUpAll(() async {
    final AppDatabase fresh = AppDatabase(NativeDatabase.memory());
    freshColumns = (await _columns(fresh)).keys.toSet();
    await fresh.close();
  });

  // Schéma v4 (2026-11-26, prix de la transcription en ligne) : la base
  // migrée est à la version courante, plus 3.
  Future<void> expectV3(AppDatabase db) async {
    expect(await _userVersion(db), db.schemaVersion);
    final Map<String, ({int notNull})> cols = await _columns(db);
    expect(cols.keys, containsAll(<String>['status', 'speaker', 'source']));
    expect(cols.keys.toSet(), freshColumns, reason: 'colonnes d\'une v3 neuve');
    expect(cols['status']!.notNull, 1, reason: 'status non nul');
  }

  Future<void> expectV2RowsKept(AppDatabase db) async {
    expect(await _count(db, 'sessions'), 1);
    expect(await _count(db, 'transcript_segments'), 2);
    expect(await _count(db, 'detected_questions'), 2);
    expect(await _count(db, 'documents'), 1);
    expect(
      (await DocumentDao(db).search('marketing')).single.documentTitle,
      'Budget 2027',
    );
  }

  test('une base v3 neuve a status, speaker et source', () async {
    expect(freshColumns, containsAll(<String>['status', 'speaker', 'source']));
  });

  group('v2 propre -> v3', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(v2DatabaseWithData()));
    tearDown(() => db.close());

    test('schéma v3, toutes les lignes gardées', () async {
      await expectV3(db);
      await expectV2RowsKept(db);
    });

    test('question répondue -> answered ; sans réponse -> unanswered ; '
        'locuteur et source inconnus', () async {
      final Map<String, Map<String, Object?>> q = await _questions(db);
      expect(q['q-answered']!['status'], 'answered');
      expect(q['q-answered']!['answer'], '40 000 €.');
      expect(q['q-open']!['status'], 'unanswered');
      expect(q['q-open']!['speaker'], isNull);
      expect(q['q-open']!['source'], isNull);
    });
  });

  group('objets v3 déjà là mais user_version = 2', () {
    late AppDatabase db;
    setUp(
      () => db = AppDatabase(
        v2DatabaseWithData(
          extraStatements: <String>[
            'ALTER TABLE "detected_questions" ADD COLUMN "status" TEXT NOT NULL '
                "DEFAULT 'unanswered'",
            'ALTER TABLE "detected_questions" ADD COLUMN "speaker" TEXT NULL',
            'ALTER TABLE "detected_questions" ADD COLUMN "source" TEXT NULL',
            "UPDATE detected_questions SET status = 'answered' "
                "WHERE id = 'q-answered'",
            "UPDATE detected_questions SET status = 'declined', speaker = '1', "
                "source = 'output' WHERE id = 'q-open'",
          ],
        ),
      ),
    );
    tearDown(() => db.close());

    test(
      's\'ouvre sans erreur, chaque colonne une fois, lignes gardées',
      () async {
        await expectV3(db);
        await expectV2RowsKept(db);
      },
    );

    test('les états et locuteurs déjà rangés sont gardés', () async {
      final Map<String, Map<String, Object?>> q = await _questions(db);
      expect(q['q-answered']!['status'], 'answered');
      expect(q['q-open']!['status'], 'declined');
      expect(q['q-open']!['speaker'], '1');
      expect(q['q-open']!['source'], 'output');
    });
  });

  group('migration 2 -> 3 interrompue (status ajouté, pas rangé ; speaker et '
      'source absents)', () {
    late AppDatabase db;
    setUp(
      () => db = AppDatabase(
        v2DatabaseWithData(
          extraStatements: <String>[
            'ALTER TABLE "detected_questions" ADD COLUMN "status" TEXT NOT NULL '
                "DEFAULT 'unanswered'",
          ],
        ),
      ),
    );
    tearDown(() => db.close());

    test('complète le schéma, lignes gardées', () async {
      await expectV3(db);
      await expectV2RowsKept(db);
    });

    test(
      'finit le rangement : la question répondue devient answered',
      () async {
        final Map<String, Map<String, Object?>> q = await _questions(db);
        expect(q['q-answered']!['status'], 'answered');
        expect(q['q-open']!['status'], 'unanswered');
      },
    );
  });

  group('garde : une base v1 va jusqu\'à la v3', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(v1DatabaseWithData()));
    tearDown(() => db.close());

    test('schéma v3, sessions, segments et résumés gardés', () async {
      await expectV3(db);
      expect(await _count(db, 'sessions'), 1);
      expect(await _count(db, 'transcript_segments'), 2);
      expect(await _count(db, 'summaries'), 2);
    });
  });

  group('cas réel : base v1 qui avait déjà les objets v2 (chemin 1 -> 2 '
      'rejouable), puis passage en v3', () {
    // Objets v2 créés comme sur le vrai fichier : colonnes ajoutées par
    // ALTER aux tables v1, tables v2 créées ensuite.
    final List<String> v2ObjectsOnV1 = <String>[
      'ALTER TABLE "sessions" ADD COLUMN "calendar_event_id" TEXT NULL',
      'ALTER TABLE "sessions" ADD COLUMN "calendar_event_title" TEXT NULL',
      'ALTER TABLE "sessions" ADD COLUMN "attendees" TEXT NULL',
      'ALTER TABLE "transcript_segments" ADD COLUMN "speaker" TEXT NULL',
      ...kV2Schema.sublist(3),
      ...kV2Rows.sublist(3),
    ];

    for (final int version in <int>[1, 2]) {
      test(
        'user_version = $version : v3, lignes gardées, questions rangées',
        () async {
          final AppDatabase db = AppDatabase(
            v1DatabaseWithData(
              extraStatements: v2ObjectsOnV1,
              userVersion: version,
            ),
          );
          addTearDown(db.close);

          await expectV3(db);
          expect(await _count(db, 'sessions'), 1);
          expect(await _count(db, 'transcript_segments'), 2);
          expect(await _count(db, 'summaries'), 2);
          expect(await _count(db, 'detected_questions'), 2);
          expect(
            (await DocumentDao(db).search('marketing')).single.documentTitle,
            'Budget 2027',
          );
          final Map<String, Map<String, Object?>> q = await _questions(db);
          expect(q['q-answered']!['status'], 'answered');
          expect(q['q-open']!['status'], 'unanswered');
        },
      );
    }
  });
}
