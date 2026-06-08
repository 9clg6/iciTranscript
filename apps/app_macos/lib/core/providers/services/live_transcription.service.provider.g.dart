// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'live_transcription.service.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider singleton pour [LiveTranscriptionService].
///
/// Orchestre la transcription en direct en coordonnant :
/// - Le serveur ML via [ProcessManagerService]
/// - La capture audio via [AudioCaptureChannel]
/// - Le WebSocket via [TranscriptionRemoteDataSource]
/// - La session et les segments via [TranscriptionService]

@ProviderFor(liveTranscriptionService)
const liveTranscriptionServiceProvider = LiveTranscriptionServiceProvider._();

/// Provider singleton pour [LiveTranscriptionService].
///
/// Orchestre la transcription en direct en coordonnant :
/// - Le serveur ML via [ProcessManagerService]
/// - La capture audio via [AudioCaptureChannel]
/// - Le WebSocket via [TranscriptionRemoteDataSource]
/// - La session et les segments via [TranscriptionService]

final class LiveTranscriptionServiceProvider
    extends
        $FunctionalProvider<
          LiveTranscriptionService,
          LiveTranscriptionService,
          LiveTranscriptionService
        >
    with $Provider<LiveTranscriptionService> {
  /// Provider singleton pour [LiveTranscriptionService].
  ///
  /// Orchestre la transcription en direct en coordonnant :
  /// - Le serveur ML via [ProcessManagerService]
  /// - La capture audio via [AudioCaptureChannel]
  /// - Le WebSocket via [TranscriptionRemoteDataSource]
  /// - La session et les segments via [TranscriptionService]
  const LiveTranscriptionServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'liveTranscriptionServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$liveTranscriptionServiceHash();

  @$internal
  @override
  $ProviderElement<LiveTranscriptionService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  LiveTranscriptionService create(Ref ref) {
    return liveTranscriptionService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LiveTranscriptionService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LiveTranscriptionService>(value),
    );
  }
}

String _$liveTranscriptionServiceHash() =>
    r'd7f9c5e5bc10092b62f6258a586b3bc1a5e0129c';
