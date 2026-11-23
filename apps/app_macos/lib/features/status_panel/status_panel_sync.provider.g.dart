// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'status_panel_sync.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Tient le panneau de barre de menus à jour et exécute ses clics. Monté par
/// l'app (RootAppWidget) pour toute sa vie.

@ProviderFor(statusPanelSync)
const statusPanelSyncProvider = StatusPanelSyncProvider._();

/// Tient le panneau de barre de menus à jour et exécute ses clics. Monté par
/// l'app (RootAppWidget) pour toute sa vie.

final class StatusPanelSyncProvider
    extends
        $FunctionalProvider<StatusPanelSync, StatusPanelSync, StatusPanelSync>
    with $Provider<StatusPanelSync> {
  /// Tient le panneau de barre de menus à jour et exécute ses clics. Monté par
  /// l'app (RootAppWidget) pour toute sa vie.
  const StatusPanelSyncProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'statusPanelSyncProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$statusPanelSyncHash();

  @$internal
  @override
  $ProviderElement<StatusPanelSync> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  StatusPanelSync create(Ref ref) {
    return statusPanelSync(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(StatusPanelSync value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<StatusPanelSync>(value),
    );
  }
}

String _$statusPanelSyncHash() => r'605509fb699edaec29ff5354d41732017569295b';
