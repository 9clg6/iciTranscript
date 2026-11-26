/// Prix de la transcription Mistral, USD par minute d'audio.
/// Source : docs.mistral.ai/inference/pricing, lu le 2026-11-26
/// (voxtral-mini-transcribe-realtime 3-0 et voxtral-mini-transcribe 3-0).
const double _realtimeUsdPerMin = 0.008;
const double _batchUsdPerMin = 0.0035;

/// Prix estime (USD) de l'audio envoye a Mistral, ou null si rien n'a ete
/// envoye (note locale : pas de prix).
double? cloudTranscriptionCostUsd({
  required int realtimeMs,
  required int batchMs,
}) {
  if (realtimeMs <= 0 && batchMs <= 0) return null;
  return (realtimeMs * _realtimeUsdPerMin + batchMs * _batchUsdPerMin) / 60000;
}
