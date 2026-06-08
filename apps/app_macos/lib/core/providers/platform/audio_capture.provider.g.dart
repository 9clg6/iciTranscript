// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'audio_capture.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider singleton pour [AudioCaptureChannel].
///
/// Fournit le pont vers la couche plateforme Swift pour la capture audio
/// (microphone et audio systeme via ScreenCaptureKit).

@ProviderFor(audioCaptureChannel)
const audioCaptureChannelProvider = AudioCaptureChannelProvider._();

/// Provider singleton pour [AudioCaptureChannel].
///
/// Fournit le pont vers la couche plateforme Swift pour la capture audio
/// (microphone et audio systeme via ScreenCaptureKit).

final class AudioCaptureChannelProvider
    extends
        $FunctionalProvider<
          AudioCaptureChannel,
          AudioCaptureChannel,
          AudioCaptureChannel
        >
    with $Provider<AudioCaptureChannel> {
  /// Provider singleton pour [AudioCaptureChannel].
  ///
  /// Fournit le pont vers la couche plateforme Swift pour la capture audio
  /// (microphone et audio systeme via ScreenCaptureKit).
  const AudioCaptureChannelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'audioCaptureChannelProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$audioCaptureChannelHash();

  @$internal
  @override
  $ProviderElement<AudioCaptureChannel> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AudioCaptureChannel create(Ref ref) {
    return audioCaptureChannel(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AudioCaptureChannel value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AudioCaptureChannel>(value),
    );
  }
}

String _$audioCaptureChannelHash() =>
    r'2a24a25010546af10c0df13d3b83e3c5e78c6f61';
