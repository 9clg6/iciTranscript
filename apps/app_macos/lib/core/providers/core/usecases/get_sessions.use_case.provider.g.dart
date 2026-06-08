// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'get_sessions.use_case.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider pour [GetSessionsUseCase].
///
/// Recupere la liste de toutes les sessions de transcription.

@ProviderFor(getSessionsUseCase)
const getSessionsUseCaseProvider = GetSessionsUseCaseProvider._();

/// Provider pour [GetSessionsUseCase].
///
/// Recupere la liste de toutes les sessions de transcription.

final class GetSessionsUseCaseProvider
    extends
        $FunctionalProvider<
          GetSessionsUseCase,
          GetSessionsUseCase,
          GetSessionsUseCase
        >
    with $Provider<GetSessionsUseCase> {
  /// Provider pour [GetSessionsUseCase].
  ///
  /// Recupere la liste de toutes les sessions de transcription.
  const GetSessionsUseCaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'getSessionsUseCaseProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$getSessionsUseCaseHash();

  @$internal
  @override
  $ProviderElement<GetSessionsUseCase> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  GetSessionsUseCase create(Ref ref) {
    return getSessionsUseCase(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GetSessionsUseCase value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GetSessionsUseCase>(value),
    );
  }
}

String _$getSessionsUseCaseHash() =>
    r'55939f2f7175bc51e82f7149eac8f09250b86a70';
