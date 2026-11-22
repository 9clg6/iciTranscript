import 'dart:convert';

import 'package:core_data/database/app_database.dart';
import 'package:core_data/database/dao/session.dao.dart';
import 'package:core_data/database/dao/transcript_segment.dao.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import 'v1_database.dart';

/// Schema v2 : liens agenda et participants sur les sessions, locuteur par
/// segment, questions detectees avec leur reponse et leurs sources.
void main() {
  group('migration 1 -> 2', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase(v1DatabaseWithData()));
    tearDown(() => db.close());

    test('conserve les sessions, les segments et les résumés existants',
        () async {
      final List<Session> sessions = await db.select(db.sessions).get();
      expect(sessions.map((Session s) => (s.id, s.title, s.durationSeconds)),
          <(String, String, int?)>[('session-1', 'Point hebdo', 2700)]);

      final List<TranscriptSegment> segments =
          await TranscriptSegmentDao(db).getBySessionId('session-1');
      expect(segments.map((TranscriptSegment s) => s.textContent),
          <String>['Bonjour à tous.', 'On commence par le budget.']);

      final List<Summary> summaries = await db.select(db.summaries).get();
      expect(summaries.map((Summary s) => s.id),
          containsAll(<String>['summary-1', 'summary-orphan']));
    });

    test('les nouvelles colonnes valent null sur les lignes migrées',
        () async {
      final Session session = (await db.select(db.sessions).get()).single;
      expect(session.calendarEventId, isNull);
      expect(session.calendarEventTitle, isNull);
      expect(session.attendees, isNull);

      final List<TranscriptSegment> segments =
          await db.select(db.transcriptSegments).get();
      expect(segments.map((TranscriptSegment s) => s.speaker),
          everyElement(isNull));
    });

    test('la base migrée accepte une question détectée', () async {
      await db.into(db.detectedQuestions).insert(
            DetectedQuestionsCompanion.insert(
              id: 'q-1',
              sessionId: 'session-1',
              question: 'Quel est le budget ?',
              timestampMs: 4000,
              createdAt: '2026-11-20T09:00:05.000',
            ),
          );
      expect(await db.select(db.detectedQuestions).get(), hasLength(1));
    });
  });

  group('schéma v2', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<void> insertSession(String id) => SessionDao(db).insertSession(
          SessionsCompanion.insert(
            id: id,
            title: 'Réunion $id',
            createdAt: '2026-11-22T10:00:00.000',
            updatedAt: '2026-11-22T10:00:00.000',
            status: 'completed',
          ),
        );

    test('une session garde son événement d’agenda et ses participants',
        () async {
      await SessionDao(db).insertSession(
        SessionsCompanion.insert(
          id: 'session-1',
          title: 'Revue produit',
          createdAt: '2026-11-22T10:00:00.000',
          updatedAt: '2026-11-22T10:00:00.000',
          status: 'completed',
          calendarEventId: const Value<String?>('evt-42'),
          calendarEventTitle: const Value<String?>('Revue produit Q4'),
          attendees: Value<String?>(jsonEncode(<String>['Alice', 'Bérénice'])),
        ),
      );

      final Session session = (await SessionDao(db).getById('session-1'))!;
      expect(session.calendarEventId, 'evt-42');
      expect(session.calendarEventTitle, 'Revue produit Q4');
      expect(jsonDecode(session.attendees!), <String>['Alice', 'Bérénice']);
    });

    test('un segment garde son locuteur', () async {
      await insertSession('session-1');
      await TranscriptSegmentDao(db).insertSegment(
        TranscriptSegmentsCompanion.insert(
          id: 'seg-1',
          sessionId: 'session-1',
          source: 'output',
          textContent: 'Je suis Alice.',
          timestampMs: 1000,
          createdAt: '2026-11-22T10:00:01.000',
          speaker: const Value<String?>('Intervenant 2'),
        ),
      );

      final TranscriptSegment segment =
          (await TranscriptSegmentDao(db).getBySessionId('session-1')).single;
      expect(segment.speaker, 'Intervenant 2');
    });

    test('une question avec réponse et sources se relit à l’identique',
        () async {
      await insertSession('session-1');
      final List<Map<String, String>> sources = <Map<String, String>>[
        <String, String>{
          'documentId': 'doc-1',
          'title': 'Budget 2027',
          'excerpt': 'Le budget marketing est fixé à 40 000 €.',
        },
      ];
      await db.into(db.detectedQuestions).insert(
            DetectedQuestionsCompanion.insert(
              id: 'q-1',
              sessionId: 'session-1',
              segmentId: const Value<String?>('seg-7'),
              question: 'Quel est le budget marketing ?',
              timestampMs: 63000,
              answer: const Value<String?>('40 000 €, validé en octobre.'),
              answerModel: const Value<String?>('claude-haiku-5-5'),
              sources: Value<String?>(jsonEncode(sources)),
              createdAt: '2026-11-22T10:01:03.000',
            ),
          );

      final DetectedQuestion q =
          (await db.select(db.detectedQuestions).get()).single;
      expect(q.sessionId, 'session-1');
      expect(q.segmentId, 'seg-7');
      expect(q.question, 'Quel est le budget marketing ?');
      expect(q.timestampMs, 63000);
      expect(q.answer, '40 000 €, validé en octobre.');
      expect(q.answerModel, 'claude-haiku-5-5');
      expect(jsonDecode(q.sources!), sources);
      expect(q.createdAt, '2026-11-22T10:01:03.000');
    });

    test('une question pas encore répondue a réponse, modèle et sources null',
        () async {
      await insertSession('session-1');
      await db.into(db.detectedQuestions).insert(
            DetectedQuestionsCompanion.insert(
              id: 'q-1',
              sessionId: 'session-1',
              question: 'On livre quand ?',
              timestampMs: 1000,
              createdAt: '2026-11-22T10:00:01.000',
            ),
          );

      final DetectedQuestion q =
          (await db.select(db.detectedQuestions).get()).single;
      expect(q.segmentId, isNull);
      expect(q.answer, isNull);
      expect(q.answerModel, isNull);
      expect(q.sources, isNull);
    });

    test('supprimer une session supprime ses questions, pas celles des autres',
        () async {
      await insertSession('session-1');
      await insertSession('session-2');
      await TranscriptSegmentDao(db).insertSegment(
        TranscriptSegmentsCompanion.insert(
          id: 'seg-1',
          sessionId: 'session-1',
          source: 'output',
          textContent: 'Quel est le budget ?',
          timestampMs: 1000,
          createdAt: '2026-11-22T10:00:01.000',
        ),
      );
      for (final (String id, String session) in <(String, String)>[
        ('q-1', 'session-1'),
        ('q-2', 'session-1'),
        ('q-3', 'session-2'),
      ]) {
        await db.into(db.detectedQuestions).insert(
              DetectedQuestionsCompanion.insert(
                id: id,
                sessionId: session,
                question: 'Question $id ?',
                timestampMs: 1000,
                createdAt: '2026-11-22T10:00:01.000',
              ),
            );
      }

      // Meme ordre que DeleteSessionUseCase : segments, puis session.
      await TranscriptSegmentDao(db).deleteBySessionId('session-1');
      await SessionDao(db).deleteById('session-1');

      final List<DetectedQuestion> left =
          await db.select(db.detectedQuestions).get();
      expect(left.map((DetectedQuestion q) => q.id), <String>['q-3']);
    });

    test('supprimer une session qui a un résumé reste possible', () async {
      // DeleteSessionUseCase ne supprime pas le resume : si les cles
      // etrangeres sont appliquees, ce cas ne doit pas lever d'erreur.
      await insertSession('session-1');
      await db.into(db.summaries).insert(
            SummariesCompanion.insert(
              id: 'summary-1',
              sessionId: 'session-1',
              content: 'Budget validé.',
              model: 'mistral',
              createdAt: '2026-11-22T11:00:00.000',
            ),
          );
      await db.into(db.detectedQuestions).insert(
            DetectedQuestionsCompanion.insert(
              id: 'q-1',
              sessionId: 'session-1',
              question: 'Quel est le budget ?',
              timestampMs: 1000,
              createdAt: '2026-11-22T10:00:01.000',
            ),
          );

      await TranscriptSegmentDao(db).deleteBySessionId('session-1');
      await SessionDao(db).deleteById('session-1');

      expect(await SessionDao(db).getById('session-1'), isNull);
      expect(await db.select(db.detectedQuestions).get(), isEmpty);
    });
  });
}
