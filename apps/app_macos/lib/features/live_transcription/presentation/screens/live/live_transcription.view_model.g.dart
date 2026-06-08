// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'live_transcription.view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// ViewModel de l'ecran de transcription en direct.

@ProviderFor(LiveTranscriptionViewModel)
const liveTranscriptionViewModelProvider =
    LiveTranscriptionViewModelProvider._();

/// ViewModel de l'ecran de transcription en direct.
final class LiveTranscriptionViewModelProvider
    extends
        $NotifierProvider<LiveTranscriptionViewModel, LiveTranscriptionState> {
  /// ViewModel de l'ecran de transcription en direct.
  const LiveTranscriptionViewModelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'liveTranscriptionViewModelProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$liveTranscriptionViewModelHash();

  @$internal
  @override
  LiveTranscriptionViewModel create() => LiveTranscriptionViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LiveTranscriptionState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LiveTranscriptionState>(value),
    );
  }
}

String _$liveTranscriptionViewModelHash() =>
    r'e4c36ff2e36706c2254a9b155bfef2f482625cf6';

/// ViewModel de l'ecran de transcription en direct.

abstract class _$LiveTranscriptionViewModel
    extends $Notifier<LiveTranscriptionState> {
  LiveTranscriptionState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref =
        this.ref as $Ref<LiveTranscriptionState, LiveTranscriptionState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<LiveTranscriptionState, LiveTranscriptionState>,
              LiveTranscriptionState,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
