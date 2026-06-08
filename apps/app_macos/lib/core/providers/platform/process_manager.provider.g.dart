// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'process_manager.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider singleton pour [ProcessManagerChannel].
///
/// Fournit le pont vers la couche plateforme Swift pour la gestion
/// du processus voxmlx-serve (serveur ML de transcription).

@ProviderFor(processManagerChannel)
const processManagerChannelProvider = ProcessManagerChannelProvider._();

/// Provider singleton pour [ProcessManagerChannel].
///
/// Fournit le pont vers la couche plateforme Swift pour la gestion
/// du processus voxmlx-serve (serveur ML de transcription).

final class ProcessManagerChannelProvider
    extends
        $FunctionalProvider<
          ProcessManagerChannel,
          ProcessManagerChannel,
          ProcessManagerChannel
        >
    with $Provider<ProcessManagerChannel> {
  /// Provider singleton pour [ProcessManagerChannel].
  ///
  /// Fournit le pont vers la couche plateforme Swift pour la gestion
  /// du processus voxmlx-serve (serveur ML de transcription).
  const ProcessManagerChannelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'processManagerChannelProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$processManagerChannelHash();

  @$internal
  @override
  $ProviderElement<ProcessManagerChannel> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ProcessManagerChannel create(Ref ref) {
    return processManagerChannel(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ProcessManagerChannel value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ProcessManagerChannel>(value),
    );
  }
}

String _$processManagerChannelHash() =>
    r'09b739583afa5f60af6cbd64664af0c7dbbc267d';
