import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/generated/translations/locale_keys.g.dart';

/// Clé du message affiché pour l'échec [error] d'une requête IA. Toute
/// erreur non typée (ligne mal formée, panne inattendue) = « a échoué ».
String llmErrorKey(Object error) => switch (error) {
  LlmInvalidKeyException() => LocaleKeys.llm_error_invalid_key,
  LlmRateLimitedException() => LocaleKeys.llm_error_rate_limited,
  LlmUnreachableException() => LocaleKeys.llm_error_unreachable,
  LlmMalformedAnswerException() => LocaleKeys.llm_error_malformed,
  _ => LocaleKeys.llm_error_failed,
};
