import 'dart:convert';

import 'package:core_domain/domain/entities/english_feedback.entity.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/live_answers/live_answers.service.dart'
    show LiveAnswerModel;
import 'package:ici_transcript/application/services/live_coach/live_coach.service.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';

import '../../../helpers/live_answers_fakes.dart'
    show ScriptedLlmProvider, ScriptedStream, requestText;

/// Coach anglais EN DIRECT (optionnel, coupé par défaut).
///
/// Besoin : pendant la réunion, les phrases anglaises FINALES de
/// l'utilisateur (micro seulement) sont corrigées par lots : au plus une
/// requête par ~20 s, et seulement s'il y a de nouvelles phrases. Seulement
/// avec un fournisseur en ligne configuré et autorisé : une sonde a mesuré
/// qu'une génération locale fait passer le délai de transcription de 1,8 s à
/// 6–24 s, donc avec le modèle local RIEN ne part (état « indisponible »).
/// Ne retarde ni ne bloque jamais la transcription : un échec est
/// silencieux (état « indisponible »), une requête muette n'empêche pas les
/// phrases suivantes d'entrer, l'arrêt l'abandonne. Ce qui a été trouvé
/// reste lisible après l'arrêt pour être rangé dans la note, avec les ids
/// des phrases déjà corrigées (la passe d'après l'appel ne les refait pas).
///
/// Décision prise (spec) : premier lot sans attente (une phrase arrivée
/// plus de 20 s après la requête précédente part tout de suite), les
/// suivantes attendent la fin des 20 s et partent ensemble.
///
/// API supposée (à créer), lib/application/services/live_coach/
/// live_coach.service.dart :
/// - `LiveCoachService({resolveModel, interval})` : `resolveModel` rend
///   `Future<LiveAnswerModel?>`, `interval` vaut 20 s par défaut ; modèle relu à chaque lot ;
/// - `start(sessionId)`, `Future<void> stop()`,
///   `void onSegmentFinalized(TranscriptSegmentEntity)` ;
/// - `LiveCoachSnapshot get snapshot` (`corrections`, `unavailable`),
///   `Stream<LiveCoachSnapshot> get snapshots`,
///   `Set<String> get coachedSegmentIds`.
/// Réponse du modèle : même JSON que le coach d'après l'appel ; heure d'une
/// correction = celle de la phrase qui contient `original`.
void main() {
  late ScriptedLlmProvider llm;
  late LiveCoachService coach;
  late LiveAnswerModel? model;

  void setUpCoach({bool isLocal = false, bool ready = true}) {
    llm = ScriptedLlmProvider();
    model = ready
        ? LiveAnswerModel(
            provider: llm,
            modelId: 'claude-test',
            isLocal: isLocal,
          )
        : null;
    coach = LiveCoachService(resolveModel: () async => model)..start('s1');
  }

  int n = 0;
  TranscriptSegmentEntity seg(
    String text, {
    required int atMs,
    AudioSource source = AudioSource.input,
  }) => TranscriptSegmentEntity(
    id: 'seg-${++n}',
    sessionId: 's1',
    source: source,
    text: text,
    timestampMs: atMs,
    createdAt: DateTime(2026, 11, 23, 10),
  );

  TranscriptSegmentEntity say(String text, {int atMs = 60000}) {
    final TranscriptSegmentEntity s = seg(text, atMs: atMs);
    coach.onSegmentFinalized(s);
    return s;
  }

  String answer(List<(String, String)> fixes) => jsonEncode(<String, Object?>{
    'overall': 'Bon niveau.',
    'corrections': <Map<String, String>>[
      for (final (String original, String corrected) in fixes)
        <String, String>{
          'original': original,
          'corrected': corrected,
          'category': 'grammar',
          'explanation': 'Explication courte.',
        },
    ],
  });

  const Duration interval = Duration(seconds: 20);

  test('une phrase anglaise finale de l\'utilisateur part tout de suite au '
      'fournisseur en ligne', () {
    fakeAsync((FakeAsync async) {
      setUpCoach();
      say('I am agree with you on this point.');
      async.flushMicrotasks();

      expect(llm.streams, hasLength(1));
      expect(requestText(llm.last.request), contains('I am agree with you'));
    });
  });

  test('au plus une requête par 20 s ; les phrases arrivées entre-temps '
      'partent ensemble, sans rien perdre', () {
    fakeAsync((FakeAsync async) {
      setUpCoach();
      say('I am agree with you on this point.');
      async.flushMicrotasks();
      llm.last.reply(answer(<(String, String)>[]));
      async.elapse(const Duration(seconds: 5));
      say('He have sent the deck to the client.', atMs: 65000);
      async.elapse(const Duration(seconds: 5));
      say('We was ready for the demo yesterday.', atMs: 70000);

      async.elapse(const Duration(seconds: 9));
      expect(llm.streams, hasLength(1), reason: 'moins de 20 s');

      async.elapse(const Duration(seconds: 2));
      expect(llm.streams, hasLength(2));
      final String second = requestText(llm.last.request);
      expect(second, contains('He have sent the deck'));
      expect(second, contains('We was ready for the demo'));
      expect(second, isNot(contains('I am agree')));
    });
  });

  test('rien de nouveau : aucune autre requête', () {
    fakeAsync((FakeAsync async) {
      setUpCoach();
      say('I am agree with you on this point.');
      async.flushMicrotasks();
      llm.last.reply(answer(<(String, String)>[]));

      async.elapse(const Duration(minutes: 3));

      expect(llm.streams, hasLength(1));
    });
  });

  test(
    'l\'interlocuteur, une phrase en français, un repère : rien ne part',
    () {
      fakeAsync((FakeAsync async) {
        setUpCoach();
        coach
          ..onSegmentFinalized(
            seg(
              'Can you send me the slides today?',
              atMs: 1000,
              source: AudioSource.output,
            ),
          )
          ..onSegmentFinalized(
            seg(
              'Je pense que le budget est validé pour la semaine.',
              atMs: 2000,
            ),
          )
          ..onSegmentFinalized(
            seg(
              LiveTranscriptionService.untranscribedMarkerText(3000, 6000),
              atMs: 3000,
            ),
          )
          ..onSegmentFinalized(
            seg(LiveTranscriptionService.gapMarkerText(7000, 9000), atMs: 7000),
          );

        async.elapse(const Duration(minutes: 1));

        expect(llm.streams, isEmpty);
      });
    },
  );

  for (final (String name, bool isLocal, bool ready) in <(String, bool, bool)>[
    ('modèle local (envoi coupé ou pas de clé)', true, true),
    ('aucun modèle prêt', false, false),
  ]) {
    test('$name : rien n\'est envoyé, l\'état dit « indisponible »', () {
      fakeAsync((FakeAsync async) {
        setUpCoach(isLocal: isLocal, ready: ready);
        say('I am agree with you on this point.');
        async.elapse(interval * 3);
        say('He have sent the deck to the client.', atMs: 125000);
        async.elapse(interval * 3);

        expect(llm.streams, isEmpty);
        expect(coach.snapshot.unavailable, isTrue);
        expect(coach.coachedSegmentIds, isEmpty);
      });
    });
  }

  test('envoi coupé en pleine réunion : le lot suivant ne part pas', () {
    fakeAsync((FakeAsync async) {
      setUpCoach();
      say('I am agree with you on this point.');
      async.flushMicrotasks();
      llm.last.reply(answer(<(String, String)>[]));
      model = LiveAnswerModel(provider: llm, modelId: 'mistral', isLocal: true);

      say('He have sent the deck to the client.', atMs: 65000);
      async.elapse(interval * 2);

      expect(llm.streams, hasLength(1));
      expect(coach.snapshot.unavailable, isTrue);
    });
  });

  test('une correction trouvée : montrée avec l\'heure de la phrase, la '
      'phrase comptée comme corrigée', () {
    fakeAsync((FakeAsync async) {
      setUpCoach();
      final TranscriptSegmentEntity s = say(
        'I am agree with you on this point.',
        atMs: 65000,
      );
      async.flushMicrotasks();
      llm.last.reply(answer(<(String, String)>[('I am agree', 'I agree')]));
      async.flushMicrotasks();

      final EnglishCorrectionEntity c = coach.snapshot.corrections.single;
      expect(c.corrected, 'I agree');
      expect(c.timestampMs, 65000);
      expect(coach.coachedSegmentIds, contains(s.id));
      expect(coach.snapshot.unavailable, isFalse);
    });
  });

  test('échec d\'un lot : silencieux, état « indisponible », ses phrases ne '
      'comptent pas comme corrigées ; un lot suivant réussi l\'efface', () {
    fakeAsync((FakeAsync async) {
      setUpCoach();
      final TranscriptSegmentEntity failed = say(
        'I am agree with you on this point.',
      );
      async.flushMicrotasks();
      llm.last.fail(const LlmUnreachableException('Claude'));
      async.flushMicrotasks();

      expect(coach.snapshot.unavailable, isTrue);
      expect(coach.coachedSegmentIds, isNot(contains(failed.id)));

      async.elapse(interval);
      final TranscriptSegmentEntity next = say(
        'He have sent the deck to the client.',
        atMs: 125000,
      );
      async.flushMicrotasks();
      llm.last.reply(
        answer(<(String, String)>[('He have sent', 'He has sent')]),
      );
      async.flushMicrotasks();

      expect(coach.snapshot.unavailable, isFalse);
      expect(coach.coachedSegmentIds, contains(next.id));
    });
  });

  test('requête sans réponse : les phrases suivantes entrent sans attendre, '
      'l\'arrêt abandonne la requête', () {
    fakeAsync((FakeAsync async) {
      setUpCoach();
      say('I am agree with you on this point.');
      async.flushMicrotasks();
      final ScriptedStream hung = llm.last;

      // `onSegmentFinalized` est synchrone : rien n'attend le modèle.
      for (int i = 0; i < 50; i++) {
        say('Line $i: we need to check the figures.', atMs: 61000 + i * 100);
      }
      async.elapse(interval * 2);

      bool stopped = false;
      coach.stop().then((_) => stopped = true);
      async.flushMicrotasks();

      expect(stopped, isTrue);
      expect(hung.cancelled, isTrue);
    });
  });

  test('après l\'arrêt : plus rien ne part, ce qui a été trouvé reste lisible '
      'jusqu\'au prochain démarrage', () {
    fakeAsync((FakeAsync async) {
      setUpCoach();
      final TranscriptSegmentEntity s = say(
        'I am agree with you on this point.',
      );
      async.flushMicrotasks();
      llm.last.reply(answer(<(String, String)>[('I am agree', 'I agree')]));
      async.flushMicrotasks();

      coach.stop();
      async.flushMicrotasks();
      say('He have sent the deck to the client.', atMs: 125000);
      async.elapse(interval * 2);

      expect(llm.streams, hasLength(1));
      expect(coach.snapshot.corrections.single.corrected, 'I agree');
      expect(coach.coachedSegmentIds, contains(s.id));

      coach.start('s2');
      expect(coach.snapshot.corrections, isEmpty);
      expect(coach.coachedSegmentIds, isEmpty);
    });
  });

  test('chaque nouveau résultat est publié', () {
    fakeAsync((FakeAsync async) {
      setUpCoach();
      final List<LiveCoachSnapshot> seen = <LiveCoachSnapshot>[];
      coach.snapshots.listen(seen.add);

      say('I am agree with you on this point.');
      async.flushMicrotasks();
      llm.last.reply(answer(<(String, String)>[('I am agree', 'I agree')]));
      async.flushMicrotasks();

      expect(seen, isNotEmpty);
      expect(seen.last.corrections.single.corrected, 'I agree');
    });
  });
}
