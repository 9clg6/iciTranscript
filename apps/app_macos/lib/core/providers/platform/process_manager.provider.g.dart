// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'process_manager.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider singleton pour [ProcessManagerChannel].
///
/// Gere le processus voxmlx-serve (serveur ML de transcription), lance par
/// le registre partage sur le port du lancement.

@ProviderFor(processManagerChannel)
const processManagerChannelProvider = ProcessManagerChannelProvider._();

/// Provider singleton pour [ProcessManagerChannel].
///
/// Gere le processus voxmlx-serve (serveur ML de transcription), lance par
/// le registre partage sur le port du lancement.

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
  /// Gere le processus voxmlx-serve (serveur ML de transcription), lance par
  /// le registre partage sur le port du lancement.
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
    r'b45d8e9518276d4fd03b9ecbe178126a83c96ad4';
