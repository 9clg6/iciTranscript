import 'dart:convert';

import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/live_answers/answer_prompt.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/core/providers/services/active_llm_provider.provider.dart';

import '../../../helpers/live_answers_fakes.dart';
import '../../../helpers/probe_outputs.dart';
import '../../../helpers/settings_fakes.dart';

/// Requête de réponse, construite à UN endroit (`buildLiveAnswerRequest`,
/// answer_prompt.dart) pour tous les fournisseurs.
///
/// 5. Langue : 30 des 36 questions françaises de la sonde ont reçu une
///    réponse en anglais avec la consigne générique « Answer in the language
///    of the question ». La requête nomme la langue de la question :
///    « French »/« français » pour une question française, « English » pour
///    une question anglaise (et pas l'autre langue comme langue de réponse).
/// 7. Sans document et sans réponse dans la réunion, 3 réponses sur 16 ont
///    inventé une procédure (« Open the shared folder… ») : la requête
///    interdit les conseils, étapes ou procédures tirés de connaissances
///    générales présentés comme des faits.
///
/// Les paramètres propres à un fournisseur (effort, max_tokens) ne sont pas
/// fixés ici.
void main() {
  LlmChatRequest build(String question, {bool withExcerpts = false}) =>
      buildLiveAnswerRequest(
        question: question,
        asked: (
          source: AudioSource.output,
          speaker: 0,
          timestampMs: 169000,
          text: question,
        ),
        context: <ContextLine>[
          (
            source: AudioSource.input,
            speaker: null,
            timestampMs: 0,
            text: 'Hi everyone, thanks for joining.',
          ),
        ],
        excerpts: withExcerpts
            ? probe('contract/en1-a1#0').excerpts
            : const <Never>[],
      );

  final RegExp french = RegExp(
    r'\b(in French|en français)\b',
    caseSensitive: false,
  );
  final RegExp english = RegExp(r'\bin English\b', caseSensitive: false);

  // Questions réelles de la sonde.
  final List<String> frenchQuestions = <String>[
    for (final String key in <String>[
      'contract/fr1-a1#0',
      'contract/fr1-a2#0',
      'contract/fr2-a#0',
      'contract/fr3-b#0',
      'contract/fr3-d#0',
    ])
      probe(key).question,
  ];
  final List<String> englishQuestions = <String>[
    for (final String key in <String>[
      'contract/en1-a1#0',
      'contract/en1-c#0',
      'contract/en2-d#0',
      'contract/en3-a#0',
    ])
      probe(key).question,
  ];

  group('5. langue de la réponse = langue de la question', () {
    for (final String q in frenchQuestions) {
      test('« $q » : la requête demande une réponse en français', () {
        final String text = requestText(build(q));
        expect(text, matches(french));
        expect(text, isNot(matches(english)));
      });
    }

    for (final String q in englishQuestions) {
      test('« $q » : la requête demande une réponse en anglais', () {
        final String text = requestText(build(q));
        expect(text, matches(english));
        expect(text, isNot(matches(french)));
      });
    }

    for (final LlmProviderId id in LlmProviderId.values) {
      test(
        '${id.name} : la consigne de langue part dans la requête HTTP',
        () async {
          final RecordingHttpAdapter http = RecordingHttpAdapter(
            reply: BodyReply(200, kOkStream[id]!),
          );
          final LlmProvider provider = buildLlmProvider(
            id,
            dio: Dio()..httpClientAdapter = http,
            apiKey: 'sk-test-SECRET-0123456789',
            model: 'model-under-test',
          );

          await provider.streamChat(build(frenchQuestions.first)).drain<void>();

          expect(jsonEncode(http.bodies.single), matches(french));
        },
      );
    }
  });

  group('7. pas de conseil tiré de connaissances générales', () {
    test('sans extrait : la requête interdit conseils et procédures tirés de '
        'connaissances générales', () {
      final String text = requestText(build(englishQuestions[2]));
      expect(
        text,
        matches(RegExp(r'(general|outside) knowledge', caseSensitive: false)),
      );
      expect(
        text,
        matches(
          RegExp(r'\b(advice|steps|procedures?)\b', caseSensitive: false),
        ),
      );
    });

    test('avec extraits : la même interdiction reste', () {
      final String text = requestText(
        build(englishQuestions.first, withExcerpts: true),
      );
      expect(
        text,
        matches(
          RegExp(r'\b(advice|steps|procedures?)\b', caseSensitive: false),
        ),
      );
    });
  });
}
