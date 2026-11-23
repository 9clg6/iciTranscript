import 'dart:convert';

import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/calendar/calendar_event.dart';
import 'package:ici_transcript/application/services/live_answers/live_question.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/application/services/meeting/meeting_rules.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.state.dart';
import 'package:ici_transcript/features/status_panel/status_panel_snapshot.dart';

import '../../helpers/localized_app.dart';

// Panneau de barre de menus (T3) : ce que le panneau natif reçoit.
//
// Le panneau (NSStatusItem + NSPanel non activant, Swift) ne lit RIEN
// d'autre que le canal `com.icitranscript/status_panel`. Contrat :
//
// Dart → Swift
// - `update` {instantané} : état complet du panneau (voir ci-dessous) ;
//   envoyé au lancement, à chaque changement (au plus ~4 par seconde
//   pendant un flux de texte, le dernier état toujours envoyé), et en
//   entier en réponse à `ready` ;
// - `showWindow` : montrer la fenêtre principale (au premier plan) ;
// - `terminate` : quitter l'app (après l'arrêt d'une note en cours).
//
// Swift → Dart (clics du panneau, sans argument sauf mention)
// - `ready` : le panneau vient de s'ouvrir, renvoyer l'instantané entier ;
// - `start` : « Nouvelle note » (même chemin : `startOrShowNote`) ;
// - `stop` : arrêter la note ; `pauseResume` : pause ou reprise ;
// - `skipFinalising` : ne plus attendre la fin de la transcription ;
// - `acceptSuggestion` / `dismissSuggestion` : comme l'invite du shell ;
// - `answerNow` {questionId: String} : proposer une réponse à la question
//   affichée (modèle local, à la demande) ;
// - `openWindow` : Dart répond par `showWindow` ;
// - `quit` : Dart arrête la note en cours (sauvée), puis `terminate`.
//
// Instantané (Map JSON, uniquement String, int, bool, null, List, Map) :
// - `status` : `idle` | `recording` | `paused` | `finalising` (après
//   Arrêter, pendant que le reste de l'audio se transcrit) ;
// - `elapsedSeconds` : int, durée de la note (0 au repos) ;
// - `finalisingSeconds` : int, audio restant à transcrire, null hors
//   finalisation ;
// - `title` : titre de la note en cours, null au repos ;
// - `transcript` : List des 3 dernières phrases FINIES, la plus ancienne
//   d'abord, chacune {`speaker`: String affichable (« Vous »,
//   « Interlocuteur 2 », « Interlocuteur »), `source`: `input` | `output`,
//   `text`: String} ; jamais un repère de perte ni de passage non
//   transcrit, jamais la phrase en cours (`current_*`), jamais une dictée ;
// - `question` : la plus récente question détectée, ou null :
//   {`id`: String, `text`: String, `state`: `detected` | `answering` |
//   `answered` | `declined` | `failed` | `needsModel` (noms de
//   LiveQuestionStatus ; `detected` = à demander, `declined` = pas de
//   réponse utile, `needsModel` = aucun modèle prêt), `answer`: String,
//   texte affiché sans repères `[S1]`, `truncated`: bool, `sources`:
//   List<String> titres des documents cités, dans l'ordre} ;
// - `suggestion` : la suggestion du shell, ou null : {`kind`: `calendar` |
//   `call`, `title`: String (titre de l'événement ou « Appel détecté »),
//   `detail`: String (« 10:00–10:30 » ou nom de l'app d'appel)} ;
// - `dictating` : bool, une dictée est en cours.
// Les textes affichables arrivent déjà en français (fr.json) ; Swift
// n'a que ses propres libellés de boutons.
//
// API supposée (lib/features/status_panel/status_panel_snapshot.dart) :
// `Map<String, Object?> statusPanelSnapshot({required LiveTranscriptionState
// live, required List<LiveQuestion> questions, required MeetingSuggestion?
// suggestion, required bool dictating})`, fonction pure.
void main() {
  // Traductions marquées ⟦…⟧ : un libellé vient de fr.json.
  Future<void> loadFrench(WidgetTester tester) =>
      pumpLocalized(tester, const SizedBox.shrink());

  String fr(String key, [String? arg]) {
    final String value = frValue(key)! as String;
    return '$kOpen${arg == null ? value : value.replaceFirst('{}', arg)}$kClose';
  }

  int n = 0;
  TranscriptSegmentEntity line(
    String text, {
    AudioSource source = AudioSource.output,
    String? id,
    int? atMs,
  }) {
    n++;
    return TranscriptSegmentEntity(
      id: id ?? 'note-1_${source.name}_$n',
      sessionId: 'note-1',
      source: source,
      text: text,
      timestampMs: atMs ?? n * 1000,
      createdAt: DateTime(2026, 11, 23, 10),
    );
  }

  LiveTranscriptionState recording({
    List<TranscriptSegmentEntity> segments = const <TranscriptSegmentEntity>[],
    Map<String, int> speakers = const <String, int>{},
  }) => LiveTranscriptionState.initial().copyWith(
    isRecording: true,
    duration: const Duration(minutes: 1, seconds: 15),
    sessionTitle: 'Revue de sprint',
    segments: segments,
    speakerLabels: speakers,
  );

  LiveQuestion question(
    String id, {
    String text = 'Quel est le délai de livraison prévu ?',
    LiveQuestionStatus status = LiveQuestionStatus.detected,
    String answer = '',
    bool truncated = false,
    List<AnswerSource> sources = const <AnswerSource>[],
    bool onDemand = false,
  }) => LiveQuestion(
    id: id,
    sessionId: 'note-1',
    text: text,
    timestampMs: 60000,
    status: status,
    answer: answer,
    truncated: truncated,
    sources: sources,
    onDemand: onDemand,
  );

  Map<String, Object?> snap({
    LiveTranscriptionState? live,
    List<LiveQuestion> questions = const <LiveQuestion>[],
    MeetingSuggestion? suggestion,
    bool dictating = false,
  }) => statusPanelSnapshot(
    live: live ?? LiveTranscriptionState.initial(),
    questions: questions,
    suggestion: suggestion,
    dictating: dictating,
  );

  List<Object?> texts(Map<String, Object?> s) =>
      (s['transcript']! as List<Object?>)
          .map((Object? l) => (l! as Map<Object?, Object?>)['text'])
          .toList();

  group('état de la note', () {
    test('au repos : toutes les clés du contrat, rien en cours', () {
      expect(snap(), <String, Object?>{
        'status': 'idle',
        'elapsedSeconds': 0,
        'finalisingSeconds': null,
        'title': null,
        'transcript': <Object?>[],
        'question': null,
        'suggestion': null,
        'dictating': false,
      });
    });

    test('une note enregistre : statut, durée en secondes, titre', () {
      final Map<String, Object?> s = snap(live: recording());

      expect(s['status'], 'recording');
      expect(s['elapsedSeconds'], 75);
      expect(s['title'], 'Revue de sprint');
      expect(s['finalisingSeconds'], isNull);
    });

    test('en pause', () {
      final Map<String, Object?> s = snap(
        live: recording().copyWith(isPaused: true),
      );

      expect(s['status'], 'paused');
      expect(s['elapsedSeconds'], 75);
    });

    test('après Arrêter, pendant la transcription du reste : finalising, '
        'même si l\'enregistrement n\'est pas encore marqué fini', () {
      final Map<String, Object?> s = snap(
        live: recording().copyWith(
          finalisingRemaining: const Duration(seconds: 12),
        ),
      );

      expect(s['status'], 'finalising');
      expect(s['finalisingSeconds'], 12);
    });

    test('finalisation terminée (plus d\'audio restant) : retour au repos', () {
      final Map<String, Object?> s = snap(
        live: LiveTranscriptionState.initial().copyWith(
          finalisingRemaining: null,
        ),
      );

      expect(s['status'], 'idle');
      expect(s['title'], isNull);
    });

    test('une dictée en cours est signalée', () {
      expect(snap(dictating: true)['dictating'], isTrue);
      expect(snap(live: recording(), dictating: true)['dictating'], isTrue);
    });
  });

  group('fin de la transcription', () {
    testWidgets('les 3 dernières phrases finies, la plus ancienne d\'abord, '
        'avec qui parle', (WidgetTester tester) async {
      await loadFrench(tester);
      final TranscriptSegmentEntity a = line('Bonjour à tous.');
      final TranscriptSegmentEntity b = line(
        'On commence par le budget.',
        source: AudioSource.input,
      );
      final TranscriptSegmentEntity c = line('Les chiffres sont prêts.');
      final TranscriptSegmentEntity d = line('Je partage mon écran.');

      final Map<String, Object?> s = snap(
        live: recording(
          segments: <TranscriptSegmentEntity>[a, b, c, d],
          speakers: <String, int>{c.id: 1},
        ),
      );

      expect(s['transcript'], <Object?>[
        <String, Object?>{
          'speaker': fr('transcription.live.speaker_me'),
          'source': 'input',
          'text': 'On commence par le budget.',
        },
        <String, Object?>{
          'speaker': fr('transcription.live.speaker_n', '2'),
          'source': 'output',
          'text': 'Les chiffres sont prêts.',
        },
        <String, Object?>{
          'speaker': fr('transcription.live.speaker_system'),
          'source': 'output',
          'text': 'Je partage mon écran.',
        },
      ]);
    });

    test('moins de 3 phrases : seulement celles-là', () {
      final Map<String, Object?> s = snap(
        live: recording(segments: <TranscriptSegmentEntity>[line('Bonjour.')]),
      );

      expect(texts(s), <Object?>['Bonjour.']);
    });

    test('jamais la phrase en cours : elle ne prend pas de place', () {
      final Map<String, Object?> s = snap(
        live: recording(
          segments: <TranscriptSegmentEntity>[
            line('Un.'),
            line('Deux.'),
            line('Trois.'),
            line('Quatre.'),
            line('et donc on va', id: 'current_output'),
            line(
              'je pense que',
              id: 'current_input',
              source: AudioSource.input,
            ),
          ],
        ),
      );

      expect(texts(s), <Object?>['Deux.', 'Trois.', 'Quatre.']);
    });

    test('jamais un repère de perte « Transcription interrompue… » : '
        'il ne prend pas de place', () {
      final Map<String, Object?> s = snap(
        live: recording(
          segments: <TranscriptSegmentEntity>[
            line('Un.'),
            line('Deux.'),
            line('Trois.'),
            line(LiveTranscriptionService.gapMarkerText(61000, 83000)),
          ],
        ),
      );

      expect(texts(s), <Object?>['Un.', 'Deux.', 'Trois.']);
    });

    test(
      'jamais le repère d\'un passage pas encore transcrit (provisoire)',
      () {
        final Map<String, Object?> s = snap(
          live: recording(
            segments: <TranscriptSegmentEntity>[
              line('Un.'),
              line('Deux.'),
              line('Trois.'),
              line(
                LiveTranscriptionService.gapMarkerText(90000, 95000),
                id: 'note-1_input_pending',
                source: AudioSource.input,
              ),
            ],
          ),
        );

        expect(texts(s), <Object?>['Un.', 'Deux.', 'Trois.']);
      },
    );

    test('rien que des repères : transcription vide', () {
      final Map<String, Object?> s = snap(
        live: recording(
          segments: <TranscriptSegmentEntity>[
            line(LiveTranscriptionService.gapMarkerText(0, 20000)),
          ],
        ),
      );

      expect(s['transcript'], isEmpty);
    });
  });

  group('question en direct', () {
    test('aucune question détectée : null', () {
      expect(snap(live: recording())['question'], isNull);
    });

    test('réponse en cours : état answering et texte partiel', () {
      final Map<String, Object?> s = snap(
        live: recording(),
        questions: <LiveQuestion>[
          question(
            'q1',
            status: LiveQuestionStatus.answering,
            answer: 'La livraison est prévue',
          ),
        ],
      );

      expect(s['question'], <String, Object?>{
        'id': 'q1',
        'text': 'Quel est le délai de livraison prévu ?',
        'state': 'answering',
        'answer': 'La livraison est prévue',
        'truncated': false,
        'sources': <Object?>[],
      });
    });

    test('réponse reçue : le texte affiché par le direct, sans repères de '
        'citation, et les titres des sources dans l\'ordre', () {
      final Map<String, Object?> s = snap(
        live: recording(),
        questions: <LiveQuestion>[
          question(
            'q1',
            status: LiveQuestionStatus.answered,
            answer:
                'Livraison sous six semaines [S1].\n'
                '- Pénalités au-delà de huit semaines [S2]',
            truncated: true,
            sources: const <AnswerSource>[
              AnswerSource(
                documentId: 'd1',
                title: 'Contrat cadre fictif',
                excerpt: 'délai de six semaines',
              ),
              AnswerSource(
                documentId: 'd2',
                title: 'Annexe tarifaire',
                excerpt: 'pénalités',
              ),
            ],
          ),
        ],
      );

      final Map<Object?, Object?> q = s['question']! as Map<Object?, Object?>;
      expect(q['state'], 'answered');
      expect(
        q['answer'],
        'Livraison sous six semaines.\n'
        '- Pénalités au-delà de huit semaines',
      );
      expect(q['answer'], isNot(contains('[S')));
      expect(q['truncated'], isTrue);
      expect(q['sources'], <Object?>[
        'Contrat cadre fictif',
        'Annexe tarifaire',
      ]);
    });

    for (final (LiveQuestionStatus status, String name)
        in <(LiveQuestionStatus, String)>[
          (LiveQuestionStatus.declined, 'declined'),
          (LiveQuestionStatus.needsModel, 'needsModel'),
          (LiveQuestionStatus.failed, 'failed'),
        ]) {
      test('$name : état transmis, pas de réponse', () {
        final Map<String, Object?> s = snap(
          live: recording(),
          questions: <LiveQuestion>[question('q1', status: status)],
        );

        final Map<Object?, Object?> q = s['question']! as Map<Object?, Object?>;
        expect(q['state'], name);
        expect(q['answer'], '');
      });
    }

    test('modèle local, réponse à demander : detected', () {
      final Map<String, Object?> s = snap(
        live: recording(),
        questions: <LiveQuestion>[question('q1', onDemand: true)],
      );

      expect((s['question']! as Map<Object?, Object?>)['state'], 'detected');
    });

    test('plusieurs questions réglées : la plus récente', () {
      final Map<String, Object?> s = snap(
        live: recording(),
        questions: <LiveQuestion>[
          question('q1', status: LiveQuestionStatus.answered, answer: 'Oui.'),
          question(
            'q2',
            text: 'Qui valide le budget ?',
            status: LiveQuestionStatus.declined,
          ),
        ],
      );

      final Map<Object?, Object?> q = s['question']! as Map<Object?, Object?>;
      expect(q['id'], 'q2');
      expect(q['text'], 'Qui valide le budget ?');
    });
  });

  group('suggestion de réunion', () {
    testWidgets('événement d\'agenda : titre et horaires', (
      WidgetTester tester,
    ) async {
      await loadFrench(tester);
      final Map<String, Object?> s = snap(
        suggestion: MeetingSuggestion(
          source: MeetingSource.calendar,
          key: 'event:evt-1',
          event: CalendarEvent(
            id: 'evt-1',
            title: 'Atelier roadmap',
            start: DateTime(2026, 11, 23, 10),
            end: DateTime(2026, 11, 23, 10, 30),
            attendeeCount: 3,
          ),
        ),
      );

      expect(s['suggestion'], <String, Object?>{
        'kind': 'calendar',
        'title': 'Atelier roadmap',
        'detail': '10:00–10:30',
      });
    });

    testWidgets('appel détecté : « Appel détecté » et le nom de l\'app', (
      WidgetTester tester,
    ) async {
      await loadFrench(tester);
      final Map<String, Object?> s = snap(
        suggestion: const MeetingSuggestion(
          source: MeetingSource.call,
          key: 'call:us.zoom.xos',
          appName: 'Zoom',
          bundleId: 'us.zoom.xos',
        ),
      );

      expect(s['suggestion'], <String, Object?>{
        'kind': 'call',
        'title': fr('meeting.suggestion.call_title'),
        'detail': 'Zoom',
      });
    });
  });

  test('l\'instantané passe par le canal et en JSON tel quel', () {
    final Map<String, Object?> s = snap(
      live: recording(
        segments: <TranscriptSegmentEntity>[line('Bonjour.')],
      ).copyWith(finalisingRemaining: const Duration(seconds: 3)),
      questions: <LiveQuestion>[
        question(
          'q1',
          status: LiveQuestionStatus.answered,
          answer: 'Oui [S1].',
          sources: const <AnswerSource>[
            AnswerSource(documentId: 'd1', title: 'Note', excerpt: 'oui'),
          ],
        ),
      ],
      suggestion: const MeetingSuggestion(
        source: MeetingSource.call,
        key: 'call:us.zoom.xos',
        appName: 'Zoom',
      ),
      dictating: true,
    );

    expect(jsonDecode(jsonEncode(s)), s);
    const StandardMethodCodec codec = StandardMethodCodec();
    final MethodCall decoded = codec.decodeMethodCall(
      codec.encodeMethodCall(MethodCall('update', s)),
    );
    expect(decoded.arguments, s);
  });
}
