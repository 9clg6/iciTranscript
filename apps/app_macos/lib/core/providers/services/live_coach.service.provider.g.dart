// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'live_coach.service.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Coach anglais en direct ; démarré et arrêté avec chaque enregistrement
/// (interrupteur activé) par le view model du direct. Même modèle que les
/// réponses en direct ; seul un fournisseur en ligne reçoit les phrases.

@ProviderFor(liveCoachService)
const liveCoachServiceProvider = LiveCoachServiceProvider._();

/// Coach anglais en direct ; démarré et arrêté avec chaque enregistrement
/// (interrupteur activé) par le view model du direct. Même modèle que les
/// réponses en direct ; seul un fournisseur en ligne reçoit les phrases.

final class LiveCoachServiceProvider
    extends
        $FunctionalProvider<
          LiveCoachService,
          LiveCoachService,
          LiveCoachService
        >
    with $Provider<LiveCoachService> {
  /// Coach anglais en direct ; démarré et arrêté avec chaque enregistrement
  /// (interrupteur activé) par le view model du direct. Même modèle que les
  /// réponses en direct ; seul un fournisseur en ligne reçoit les phrases.
  const LiveCoachServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'liveCoachServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$liveCoachServiceHash();

  @$internal
  @override
  $ProviderElement<LiveCoachService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  LiveCoachService create(Ref ref) {
    return liveCoachService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LiveCoachService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LiveCoachService>(value),
    );
  }
}

String _$liveCoachServiceHash() => r'522ac1272d6e0e7b863ba44b874ea4fc5c6dfee8';

/// Ce que le coach en direct a trouvé, à chaque changement.

@ProviderFor(liveCoachSnapshot)
const liveCoachSnapshotProvider = LiveCoachSnapshotProvider._();

/// Ce que le coach en direct a trouvé, à chaque changement.

final class LiveCoachSnapshotProvider
    extends
        $FunctionalProvider<
          AsyncValue<LiveCoachSnapshot>,
          LiveCoachSnapshot,
          Stream<LiveCoachSnapshot>
        >
    with
        $FutureModifier<LiveCoachSnapshot>,
        $StreamProvider<LiveCoachSnapshot> {
  /// Ce que le coach en direct a trouvé, à chaque changement.
  const LiveCoachSnapshotProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'liveCoachSnapshotProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$liveCoachSnapshotHash();

  @$internal
  @override
  $StreamProviderElement<LiveCoachSnapshot> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<LiveCoachSnapshot> create(Ref ref) {
    return liveCoachSnapshot(ref);
  }
}

String _$liveCoachSnapshotHash() => r'c7506664042b627ebc52d14b2bddc6bdb3403e58';

/// Le coach en direct peut-il partir ? Seulement vers un fournisseur en
/// ligne configuré et autorisé (même règle que le service).

@ProviderFor(liveCoachAvailable)
const liveCoachAvailableProvider = LiveCoachAvailableProvider._();

/// Le coach en direct peut-il partir ? Seulement vers un fournisseur en
/// ligne configuré et autorisé (même règle que le service).

final class LiveCoachAvailableProvider
    extends $FunctionalProvider<AsyncValue<bool>, bool, FutureOr<bool>>
    with $FutureModifier<bool>, $FutureProvider<bool> {
  /// Le coach en direct peut-il partir ? Seulement vers un fournisseur en
  /// ligne configuré et autorisé (même règle que le service).
  const LiveCoachAvailableProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'liveCoachAvailableProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$liveCoachAvailableHash();

  @$internal
  @override
  $FutureProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<bool> create(Ref ref) {
    return liveCoachAvailable(ref);
  }
}

String _$liveCoachAvailableHash() =>
    r'637690db3da42c098861a8b35df30291f6fd5655';
