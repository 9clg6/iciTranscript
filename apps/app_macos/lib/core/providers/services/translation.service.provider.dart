import 'package:ici_transcript/application/services/translation.service.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'translation.service.provider.g.dart';

/// Provider singleton pour [TranslationService].
@Riverpod(keepAlive: true)
TranslationService translationService(Ref ref) {
  final TranslationService service = TranslationService();
  ref.onDispose(service.dispose);
  return service;
}
