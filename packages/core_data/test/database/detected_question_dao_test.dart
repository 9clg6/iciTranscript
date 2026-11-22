import 'dart:convert';

import 'package:core_data/database/app_database.dart';
import 'package:core_data/database/dao/detected_question.dao.dart';
import 'package:core_data/database/dao/session.dao.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:test/test.dart';

/// Questions détectées en direct (T4, besoin 9) : sauvées à la détection,
/// complétées à la fin du flux, relues par session, supprimées avec elle.
///
/// API supposée (lib/database/dao/detected_question.dao.dart) :
/// `DetectedQuestionDao(AppDatabase db)` avec
/// - `Future<void> insertDetected({required String id, required String sessionId, String? segmentId, required String question, required int timestampMs, required DateTime createdAt})`
/// - `Future<void> saveAnswer(String id, {required String answer, required String model, required List<({String documentId, String title, String excerpt})> sources})`
///   (sources rangées en JSON `[{documentId, title, excerpt}]`)
/// - `Future<List<DetectedQuestion>> forSession(String sessionId)`, par
///   `timestampMs` croissant
/// - `Future<void> deleteById(String id)`
/// « Sans réponse » = `answer` null (pas de colonne d'état : schéma v2 gardé).
void main() {
  late AppDatabase db;
  late DetectedQuestionDao dao;

  Future<void> insertSession(String id) => SessionDao(db).insertSession(
    SessionsCompanion.insert(
      id: id,
      title: 'Réunion $id',
      createdAt: '2026-11-22T10:00:00.000',
      updatedAt: '2026-11-22T10:00:00.000',
      status: 'completed',
    ),
  );

  Future<void> detect(
    String id, {
    String session = 's1',
    int at = 1000,
    String? segmentId,
  }) => dao.insertDetected(
    id: id,
    sessionId: session,
    segmentId: segmentId,
    question: 'Question $id ?',
    timestampMs: at,
    createdAt: DateTime(2026, 11, 22, 10),
  );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dao = DetectedQuestionDao(db);
    await insertSession('s1');
    await insertSession('s2');
  });
  tearDown(() => db.close());

  test('une question détectée se relit avec son segment et son heure, sans '
      'réponse', () async {
    await detect('q1', at: 65000, segmentId: 'seg-7');

    final DetectedQuestion q = (await dao.forSession('s1')).single;
    expect(q.id, 'q1');
    expect(q.segmentId, 'seg-7');
    expect(q.question, 'Question q1 ?');
    expect(q.timestampMs, 65000);
    expect(q.answer, isNull);
    expect(q.answerModel, isNull);
  });

  test('la réponse, le modèle et les sources complètent la même ligne',
      () async {
    await detect('q1');

    await dao.saveAnswer(
      'q1',
      answer: 'Le 12 mars.',
      model: 'claude-haiku-5-5',
      sources: const <({String documentId, String title, String excerpt})>[
        (documentId: 'doc-1', title: 'Contrat', excerpt: 'Livraison le 12 mars.'),
      ],
    );

    final List<DetectedQuestion> all = await dao.forSession('s1');
    expect(all, hasLength(1));
    expect(all.single.answer, 'Le 12 mars.');
    expect(all.single.answerModel, 'claude-haiku-5-5');
    expect(jsonDecode(all.single.sources!), <Map<String, String>>[
      <String, String>{
        'documentId': 'doc-1',
        'title': 'Contrat',
        'excerpt': 'Livraison le 12 mars.',
      },
    ]);
  });

  test('par session, dans l\'ordre de la réunion', () async {
    await detect('late', at: 90000);
    await detect('early', at: 10000);
    await detect('other', session: 's2');

    expect(
      (await dao.forSession('s1')).map((DetectedQuestion q) => q.id),
      <String>['early', 'late'],
    );
  });

  test('supprimer une question (Ignorer) ne touche pas les autres', () async {
    await detect('q1');
    await detect('q2');

    await dao.deleteById('q1');

    expect(
      (await dao.forSession('s1')).map((DetectedQuestion q) => q.id),
      <String>['q2'],
    );
  });

  test('garde : supprimer la session supprime ses questions', () async {
    await detect('q1');
    await detect('q2', session: 's2');

    await SessionDao(db).deleteById('s1');

    expect(await dao.forSession('s1'), isEmpty);
    expect(await dao.forSession('s2'), hasLength(1));
  });
}
