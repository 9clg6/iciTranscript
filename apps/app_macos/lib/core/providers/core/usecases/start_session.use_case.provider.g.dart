// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'start_session.use_case.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider pour [StartSessionUseCase].
///
/// Cree une nouvelle session de transcription active.

@ProviderFor(startSessionUseCase)
const startSessionUseCaseProvider = StartSessionUseCaseProvider._();

/// Provider pour [StartSessionUseCase].
///
/// Cree une nouvelle session de transcription active.

final class StartSessionUseCaseProvider
    extends
        $FunctionalProvider<
          StartSessionUseCase,
          StartSessionUseCase,
          StartSessionUseCase
        >
    with $Provider<StartSessionUseCase> {
  /// Provider pour [StartSessionUseCase].
  ///
  /// Cree une nouvelle session de transcription active.
  const StartSessionUseCaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'startSessionUseCaseProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$startSessionUseCaseHash();

  @$internal
  @override
  $ProviderElement<StartSessionUseCase> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  StartSessionUseCase create(Ref ref) {
    return startSessionUseCase(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(StartSessionUseCase value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<StartSessionUseCase>(value),
    );
  }
}

String _$startSessionUseCaseHash() =>
    r'adb3a25c5e7656410c7ca20f5043fc1eec001db3';
