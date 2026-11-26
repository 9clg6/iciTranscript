import 'package:core_domain/domain/services/cloud_transcription_cost.dart';
import 'package:test/test.dart';

/// Prix estimé de la transcription Mistral d'une note (USD), d'après
/// docs.mistral.ai/inference/pricing (lu le 2026-11-26) :
/// voxtral-mini-transcribe-realtime 3-0 = 0,008 $ / min d'audio,
/// voxtral-mini-transcribe 3-0 (batch, rattrapage) = 0,0035 $ / min.
///
/// API supposée : `double? cloudTranscriptionCostUsd({required int
/// realtimeMs, required int batchMs})` dans
/// `package:core_domain/domain/services/cloud_transcription_cost.dart` ;
/// null quand rien n'a été envoyé (note locale : pas de prix).
void main() {
  test('une minute en temps réel coûte 0,008 \$', () {
    expect(
      cloudTranscriptionCostUsd(realtimeMs: 60000, batchMs: 0),
      closeTo(0.008, 1e-9),
    );
  });

  test('une minute de rattrapage (batch) coûte 0,0035 \$', () {
    expect(
      cloudTranscriptionCostUsd(realtimeMs: 0, batchMs: 60000),
      closeTo(0.0035, 1e-9),
    );
  });

  test('les deux modes s additionnent, à la seconde près (pas de minute '
      'entamée)', () {
    // 30 min de réunion + 5 min 30 s de rattrapage.
    expect(
      cloudTranscriptionCostUsd(realtimeMs: 1800000, batchMs: 330000),
      closeTo(30 * 0.008 + 5.5 * 0.0035, 1e-9),
    );
    // 100 ms de maintien seulement.
    expect(
      cloudTranscriptionCostUsd(realtimeMs: 100, batchMs: 0),
      closeTo(0.008 / 600, 1e-12),
    );
  });

  test('rien envoyé : pas de prix', () {
    expect(cloudTranscriptionCostUsd(realtimeMs: 0, batchMs: 0), isNull);
  });
}
