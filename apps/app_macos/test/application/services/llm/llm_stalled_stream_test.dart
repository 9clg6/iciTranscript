import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/llm/anthropic_llm_provider.dart';
import 'package:ici_transcript/application/services/llm/gemini_llm_provider.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/application/services/llm/mistral_llm_provider.dart';
import 'package:ici_transcript/application/services/llm/ollama_llm_provider.dart';
import 'package:ici_transcript/application/services/llm/openai_llm_provider.dart';

import '../../../helpers/settings_fakes.dart';

/// Une requête LLM ne reste jamais pendue (besoin 5) : un serveur qui se tait
/// au milieu d'une réponse, qui ne répond jamais, ou dont le corps d'erreur
/// n'arrive jamais, finit par une erreur typée, et la connexion est fermée.
///
/// Le délai exact est une constante de llm_http.dart (voir
/// llm_timeouts_test.dart) ; ici on attend seulement « bien plus longtemps
/// que n'importe quel délai raisonnable ».
///
/// Les délais doivent tenir quel que soit le transport : le Dio du test est
/// nu (sans BaseOptions), comme le transport factice qui remplace le réseau.
const Duration _forever = Duration(minutes: 10);
const String _key = 'sk-test-SECRET-0123456789';

LlmProvider _provider(LlmProviderId id, Dio dio) => switch (id) {
  LlmProviderId.anthropic => AnthropicLlmProvider(dio: dio, apiKey: _key),
  LlmProviderId.openai => OpenAiLlmProvider(dio: dio, apiKey: _key),
  LlmProviderId.gemini => GeminiLlmProvider(dio: dio, apiKey: _key),
  LlmProviderId.mistral => MistralLlmProvider(dio: dio, apiKey: _key),
  LlmProviderId.ollama => OllamaLlmProvider(dio: dio),
};

/// Le premier événement de [kOkStream] seul (texte « OK »), sans la fin.
String _firstEvent(LlmProviderId id) {
  final String all = kOkStream[id]!;
  return id == LlmProviderId.ollama
      ? '${all.split('\n').first}\n'
      : '${all.split('\n\n').first}\n\n';
}

class _Run {
  final List<String> texts = <String>[];
  final List<Object> errors = <Object>[];
  bool done = false;
}

_Run _listen(LlmProvider provider) {
  final _Run run = _Run();
  provider
      .streamChat(kPing)
      .listen(
        run.texts.add,
        onError: run.errors.add,
        onDone: () => run.done = true,
      );
  return run;
}

void main() {
  for (final LlmProviderId id in LlmProviderId.values) {
    group(id.name, () {
      test('serveur muet au milieu de la réponse : le texte reçu est gardé, '
          'puis « injoignable », flux fermé, connexion coupée', () {
        fakeAsync((FakeAsync async) {
          final RecordingHttpAdapter adapter = RecordingHttpAdapter(
            reply: BodyReply(200, _firstEvent(id), keepOpen: true),
          );
          final _Run run = _listen(
            _provider(id, Dio()..httpClientAdapter = adapter),
          );

          async.elapse(const Duration(milliseconds: 100));
          expect(run.texts, <String>['OK']);
          expect(run.errors, isEmpty);

          async.elapse(_forever);

          expect(run.errors, hasLength(1));
          expect(run.errors.single, isA<LlmUnreachableException>());
          expect(run.errors.single.toString(), isNot(contains(_key)));
          expect(run.done, isTrue, reason: 'le flux doit se fermer');
          expect(adapter.aborts, greaterThan(0), reason: 'connexion laissée');
        });
      });

      test('aucune réponse, jamais : « injoignable », connexion coupée', () {
        fakeAsync((FakeAsync async) {
          final RecordingHttpAdapter adapter = RecordingHttpAdapter(
            reply: const HangReply(),
          );
          final _Run run = _listen(
            _provider(id, Dio()..httpClientAdapter = adapter),
          );

          async.elapse(_forever);

          expect(run.errors, hasLength(1));
          expect(run.errors.single, isA<LlmUnreachableException>());
          expect(run.done, isTrue);
          expect(adapter.aborts, greaterThan(0));
        });
      });

      test('erreur HTTP dont le corps n\'arrive jamais en entier : le flux '
          'finit en erreur au lieu d\'attendre', () {
        fakeAsync((FakeAsync async) {
          final RecordingHttpAdapter adapter = RecordingHttpAdapter(
            reply: const BodyReply(500, '{"error": {"mess', keepOpen: true),
          );
          final _Run run = _listen(
            _provider(id, Dio()..httpClientAdapter = adapter),
          );

          async.elapse(_forever);

          expect(run.errors, hasLength(1));
          expect(run.errors.single, isA<LlmException>());
          expect(run.done, isTrue);
        });
      });
    });
  }
}
