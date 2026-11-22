// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'owned_processes.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Seul registre des serveurs lancés par l'app (un seul écrivain du fichier
/// d'état).

@ProviderFor(ownedProcessRegistry)
const ownedProcessRegistryProvider = OwnedProcessRegistryProvider._();

/// Seul registre des serveurs lancés par l'app (un seul écrivain du fichier
/// d'état).

final class OwnedProcessRegistryProvider
    extends
        $FunctionalProvider<
          OwnedProcessRegistry,
          OwnedProcessRegistry,
          OwnedProcessRegistry
        >
    with $Provider<OwnedProcessRegistry> {
  /// Seul registre des serveurs lancés par l'app (un seul écrivain du fichier
  /// d'état).
  const OwnedProcessRegistryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'ownedProcessRegistryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$ownedProcessRegistryHash();

  @$internal
  @override
  $ProviderElement<OwnedProcessRegistry> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  OwnedProcessRegistry create(Ref ref) {
    return ownedProcessRegistry(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(OwnedProcessRegistry value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<OwnedProcessRegistry>(value),
    );
  }
}

String _$ownedProcessRegistryHash() =>
    r'fc61152992fda375ee9d94b1da8f76d94d5b143c';

/// Ports des serveurs pour ce lancement (8100/8101 sur données de dev).

@ProviderFor(launchServerPorts)
const launchServerPortsProvider = LaunchServerPortsProvider._();

/// Ports des serveurs pour ce lancement (8100/8101 sur données de dev).

final class LaunchServerPortsProvider
    extends $FunctionalProvider<ServerPorts, ServerPorts, ServerPorts>
    with $Provider<ServerPorts> {
  /// Ports des serveurs pour ce lancement (8100/8101 sur données de dev).
  const LaunchServerPortsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'launchServerPortsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$launchServerPortsHash();

  @$internal
  @override
  $ProviderElement<ServerPorts> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ServerPorts create(Ref ref) {
    return launchServerPorts(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ServerPorts value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ServerPorts>(value),
    );
  }
}

String _$launchServerPortsHash() => r'd280e9231801098a7f3969f278925158e27feccf';
