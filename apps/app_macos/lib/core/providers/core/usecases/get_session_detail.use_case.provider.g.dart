// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'get_session_detail.use_case.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider pour [GetSessionDetailUseCase].
///
/// Recupere le detail d'une session avec ses segments de transcription.

@ProviderFor(getSessionDetailUseCase)
const getSessionDetailUseCaseProvider = GetSessionDetailUseCaseProvider._();

/// Provider pour [GetSessionDetailUseCase].
///
/// Recupere le detail d'une session avec ses segments de transcription.

final class GetSessionDetailUseCaseProvider
    extends
        $FunctionalProvider<
          GetSessionDetailUseCase,
          GetSessionDetailUseCase,
          GetSessionDetailUseCase
        >
    with $Provider<GetSessionDetailUseCase> {
  /// Provider pour [GetSessionDetailUseCase].
  ///
  /// Recupere le detail d'une session avec ses segments de transcription.
  const GetSessionDetailUseCaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'getSessionDetailUseCaseProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$getSessionDetailUseCaseHash();

  @$internal
  @override
  $ProviderElement<GetSessionDetailUseCase> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  GetSessionDetailUseCase create(Ref ref) {
    return getSessionDetailUseCase(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GetSessionDetailUseCase value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GetSessionDetailUseCase>(value),
    );
  }
}

String _$getSessionDetailUseCaseHash() =>
    r'ed839fe667dace056fd564050fe5cfcaed216d54';
