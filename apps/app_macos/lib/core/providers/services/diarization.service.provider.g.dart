// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'diarization.service.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider singleton pour [DiarizationService].

@ProviderFor(diarizationService)
const diarizationServiceProvider = DiarizationServiceProvider._();

/// Provider singleton pour [DiarizationService].

final class DiarizationServiceProvider
    extends
        $FunctionalProvider<
          DiarizationService,
          DiarizationService,
          DiarizationService
        >
    with $Provider<DiarizationService> {
  /// Provider singleton pour [DiarizationService].
  const DiarizationServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'diarizationServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$diarizationServiceHash();

  @$internal
  @override
  $ProviderElement<DiarizationService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  DiarizationService create(Ref ref) {
    return diarizationService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DiarizationService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DiarizationService>(value),
    );
  }
}

String _$diarizationServiceHash() =>
    r'625dbd19ed2571b8ff89317509b5f81a2e7abae5';
