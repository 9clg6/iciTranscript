import 'package:ici_transcript/application/services/diarization.service.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'diarization.service.provider.g.dart';

/// Provider singleton pour [DiarizationService].
@Riverpod(keepAlive: true)
DiarizationService diarizationService(Ref ref) {
  return DiarizationService();
}
