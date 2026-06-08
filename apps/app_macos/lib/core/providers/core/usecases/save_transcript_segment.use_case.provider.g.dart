// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'save_transcript_segment.use_case.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider pour [SaveTranscriptSegmentUseCase].
///
/// Sauvegarde un segment de transcription dans la base de donnees locale.

@ProviderFor(saveTranscriptSegmentUseCase)
const saveTranscriptSegmentUseCaseProvider =
    SaveTranscriptSegmentUseCaseProvider._();

/// Provider pour [SaveTranscriptSegmentUseCase].
///
/// Sauvegarde un segment de transcription dans la base de donnees locale.

final class SaveTranscriptSegmentUseCaseProvider
    extends
        $FunctionalProvider<
          SaveTranscriptSegmentUseCase,
          SaveTranscriptSegmentUseCase,
          SaveTranscriptSegmentUseCase
        >
    with $Provider<SaveTranscriptSegmentUseCase> {
  /// Provider pour [SaveTranscriptSegmentUseCase].
  ///
  /// Sauvegarde un segment de transcription dans la base de donnees locale.
  const SaveTranscriptSegmentUseCaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'saveTranscriptSegmentUseCaseProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$saveTranscriptSegmentUseCaseHash();

  @$internal
  @override
  $ProviderElement<SaveTranscriptSegmentUseCase> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  SaveTranscriptSegmentUseCase create(Ref ref) {
    return saveTranscriptSegmentUseCase(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SaveTranscriptSegmentUseCase value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SaveTranscriptSegmentUseCase>(value),
    );
  }
}

String _$saveTranscriptSegmentUseCaseHash() =>
    r'f88c94719e90bb2df523e29abc773a94de5a9022';
