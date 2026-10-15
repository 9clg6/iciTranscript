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
/// - Les interlocuteurs en direct via [LiveDiarizationService]

@ProviderFor(liveTranscriptionService)
const liveTranscriptionServiceProvider = LiveTranscriptionServiceProvider._();

/// Provider singleton pour [LiveTranscriptionService].
///
/// Orchestre la transcription en direct en coordonnant :
/// - Le serveur ML via [ProcessManagerService]
/// - La capture audio via [AudioCaptureChannel]
/// - Le WebSocket via [TranscriptionRemoteDataSource]
/// - La session et les segments via [TranscriptionService]
/// - Les interlocuteurs en direct via [LiveDiarizationService]

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
  /// - Les interlocuteurs en direct via [LiveDiarizationService]
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
    r'2c6d2d8428e764015ea6a4d5256ebd79636478ad';
