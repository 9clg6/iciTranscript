// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'transcription.service.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider singleton pour [TranscriptionService].
///
/// Orchestre le cycle de vie d'une session de transcription :
/// demarrage, arret, sauvegarde des segments.
/// Maintient un etat reactif via [BehaviorSubject].

@ProviderFor(transcriptionService)
const transcriptionServiceProvider = TranscriptionServiceProvider._();

/// Provider singleton pour [TranscriptionService].
///
/// Orchestre le cycle de vie d'une session de transcription :
/// demarrage, arret, sauvegarde des segments.
/// Maintient un etat reactif via [BehaviorSubject].

final class TranscriptionServiceProvider
    extends
        $FunctionalProvider<
          TranscriptionService,
          TranscriptionService,
          TranscriptionService
        >
    with $Provider<TranscriptionService> {
  /// Provider singleton pour [TranscriptionService].
  ///
  /// Orchestre le cycle de vie d'une session de transcription :
  /// demarrage, arret, sauvegarde des segments.
  /// Maintient un etat reactif via [BehaviorSubject].
  const TranscriptionServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'transcriptionServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$transcriptionServiceHash();

  @$internal
  @override
  $ProviderElement<TranscriptionService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  TranscriptionService create(Ref ref) {
    return transcriptionService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TranscriptionService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TranscriptionService>(value),
    );
  }
}

String _$transcriptionServiceHash() =>
    r'8d205d12e856b9f6bea2bb3928c1f8ecba6a8c48';
