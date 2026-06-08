// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'stop_session.use_case.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider pour [StopSessionUseCase].
///
/// Arrete une session de transcription en cours et met a jour son statut.

@ProviderFor(stopSessionUseCase)
const stopSessionUseCaseProvider = StopSessionUseCaseProvider._();

/// Provider pour [StopSessionUseCase].
///
/// Arrete une session de transcription en cours et met a jour son statut.

final class StopSessionUseCaseProvider
    extends
        $FunctionalProvider<
          StopSessionUseCase,
          StopSessionUseCase,
          StopSessionUseCase
        >
    with $Provider<StopSessionUseCase> {
  /// Provider pour [StopSessionUseCase].
  ///
  /// Arrete une session de transcription en cours et met a jour son statut.
  const StopSessionUseCaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'stopSessionUseCaseProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$stopSessionUseCaseHash();

  @$internal
  @override
  $ProviderElement<StopSessionUseCase> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  StopSessionUseCase create(Ref ref) {
    return stopSessionUseCase(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(StopSessionUseCase value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<StopSessionUseCase>(value),
    );
  }
}

String _$stopSessionUseCaseHash() =>
    r'5db0cd409aeb8882bcff8ec37b11c3048f8d39e8';
