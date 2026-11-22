import 'dart:async';

/// Un seul serveur de transcription, séquentiel : un 3e flux simultané fait
/// croître les délais sans borne (mesuré). Priorité : enregistrement >
/// dictée > rattrapage des pertes.
final class TranscriptionServerArbiter {
  /// Cree une instance de [TranscriptionServerArbiter].
  TranscriptionServerArbiter({required bool Function() isRecording})
    : _isRecording = isRecording;

  final bool Function() _isRecording;
  final StreamController<void> _mayResume = StreamController<void>.broadcast();
  bool _dictating = false;

  /// Une dictée tient le serveur (de l'appui à la fin de la dictée).
  void dictationStarted() => _dictating = true;

  /// Fin de la dictée : hors enregistrement, le rattrapage peut reprendre.
  void dictationEnded() {
    if (!_dictating) return;
    _dictating = false;
    if (!_isRecording()) _mayResume.add(null);
  }

  /// Enregistrement ou dictée en cours : le rattrapage cède le serveur.
  bool get backfillMustYield => _isRecording() || _dictating;

  /// Émis quand une dictée finit hors enregistrement.
  Stream<void> get backfillMayResume => _mayResume.stream;
}
