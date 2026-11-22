// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'live_answers.service.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Questions et réponses en direct ; démarré et arrêté avec chaque
/// enregistrement par le view model du direct.

@ProviderFor(liveAnswersService)
const liveAnswersServiceProvider = LiveAnswersServiceProvider._();

/// Questions et réponses en direct ; démarré et arrêté avec chaque
/// enregistrement par le view model du direct.

final class LiveAnswersServiceProvider
    extends
        $FunctionalProvider<
          LiveAnswersService,
          LiveAnswersService,
          LiveAnswersService
        >
    with $Provider<LiveAnswersService> {
  /// Questions et réponses en direct ; démarré et arrêté avec chaque
  /// enregistrement par le view model du direct.
  const LiveAnswersServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'liveAnswersServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$liveAnswersServiceHash();

  @$internal
  @override
  $ProviderElement<LiveAnswersService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  LiveAnswersService create(Ref ref) {
    return liveAnswersService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LiveAnswersService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LiveAnswersService>(value),
    );
  }
}

String _$liveAnswersServiceHash() =>
    r'452afb94ad08c7acccaaa24d7eb783f1526b9c53';
