// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'process_manager.service.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider singleton pour [ProcessManagerService].
///
/// Wrape le [ProcessManagerChannel] pour fournir une API
/// de plus haut niveau pour le cycle de vie du serveur ML.

@ProviderFor(processManagerService)
const processManagerServiceProvider = ProcessManagerServiceProvider._();

/// Provider singleton pour [ProcessManagerService].
///
/// Wrape le [ProcessManagerChannel] pour fournir une API
/// de plus haut niveau pour le cycle de vie du serveur ML.

final class ProcessManagerServiceProvider
    extends
        $FunctionalProvider<
          ProcessManagerService,
          ProcessManagerService,
          ProcessManagerService
        >
    with $Provider<ProcessManagerService> {
  /// Provider singleton pour [ProcessManagerService].
  ///
  /// Wrape le [ProcessManagerChannel] pour fournir une API
  /// de plus haut niveau pour le cycle de vie du serveur ML.
  const ProcessManagerServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'processManagerServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$processManagerServiceHash();

  @$internal
  @override
  $ProviderElement<ProcessManagerService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ProcessManagerService create(Ref ref) {
    return processManagerService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ProcessManagerService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ProcessManagerService>(value),
    );
  }
}

String _$processManagerServiceHash() =>
    r'd7be5c19b5f27573d6b7412dcaa386a983e4ea46';
