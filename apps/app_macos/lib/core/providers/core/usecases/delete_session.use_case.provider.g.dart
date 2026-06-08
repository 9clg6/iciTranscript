// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'delete_session.use_case.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider pour [DeleteSessionUseCase].
///
/// Supprime une session et ses segments de transcription associes.

@ProviderFor(deleteSessionUseCase)
const deleteSessionUseCaseProvider = DeleteSessionUseCaseProvider._();

/// Provider pour [DeleteSessionUseCase].
///
/// Supprime une session et ses segments de transcription associes.

final class DeleteSessionUseCaseProvider
    extends
        $FunctionalProvider<
          DeleteSessionUseCase,
          DeleteSessionUseCase,
          DeleteSessionUseCase
        >
    with $Provider<DeleteSessionUseCase> {
  /// Provider pour [DeleteSessionUseCase].
  ///
  /// Supprime une session et ses segments de transcription associes.
  const DeleteSessionUseCaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'deleteSessionUseCaseProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$deleteSessionUseCaseHash();

  @$internal
  @override
  $ProviderElement<DeleteSessionUseCase> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  DeleteSessionUseCase create(Ref ref) {
    return deleteSessionUseCase(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DeleteSessionUseCase value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DeleteSessionUseCase>(value),
    );
  }
}

String _$deleteSessionUseCaseHash() =>
    r'e598b054c4bed915b214cc4da74813d9b01f106e';
