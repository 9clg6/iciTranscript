// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'update_session_title.use_case.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider pour [UpdateSessionTitleUseCase].
///
/// Met a jour le titre d'une session de transcription.

@ProviderFor(updateSessionTitleUseCase)
const updateSessionTitleUseCaseProvider = UpdateSessionTitleUseCaseProvider._();

/// Provider pour [UpdateSessionTitleUseCase].
///
/// Met a jour le titre d'une session de transcription.

final class UpdateSessionTitleUseCaseProvider
    extends
        $FunctionalProvider<
          UpdateSessionTitleUseCase,
          UpdateSessionTitleUseCase,
          UpdateSessionTitleUseCase
        >
    with $Provider<UpdateSessionTitleUseCase> {
  /// Provider pour [UpdateSessionTitleUseCase].
  ///
  /// Met a jour le titre d'une session de transcription.
  const UpdateSessionTitleUseCaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'updateSessionTitleUseCaseProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$updateSessionTitleUseCaseHash();

  @$internal
  @override
  $ProviderElement<UpdateSessionTitleUseCase> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  UpdateSessionTitleUseCase create(Ref ref) {
    return updateSessionTitleUseCase(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(UpdateSessionTitleUseCase value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<UpdateSessionTitleUseCase>(value),
    );
  }
}

String _$updateSessionTitleUseCaseHash() =>
    r'0e4fe5e366384adfead5b14653d7c6ce03713684';
