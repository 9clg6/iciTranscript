// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'audio.repository.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider pour [AudioRepository].
///
/// Fournit l'implementation [AudioRepositoryImpl] qui delegue les appels
/// au [AudioCaptureChannel] (Platform Channel Swift) pour la capture audio.

@ProviderFor(audioRepository)
const audioRepositoryProvider = AudioRepositoryProvider._();

/// Provider pour [AudioRepository].
///
/// Fournit l'implementation [AudioRepositoryImpl] qui delegue les appels
/// au [AudioCaptureChannel] (Platform Channel Swift) pour la capture audio.

final class AudioRepositoryProvider
    extends
        $FunctionalProvider<AudioRepository, AudioRepository, AudioRepository>
    with $Provider<AudioRepository> {
  /// Provider pour [AudioRepository].
  ///
  /// Fournit l'implementation [AudioRepositoryImpl] qui delegue les appels
  /// au [AudioCaptureChannel] (Platform Channel Swift) pour la capture audio.
  const AudioRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'audioRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$audioRepositoryHash();

  @$internal
  @override
  $ProviderElement<AudioRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AudioRepository create(Ref ref) {
    return audioRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AudioRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AudioRepository>(value),
    );
  }
}

String _$audioRepositoryHash() => r'12ed54af842ee9efa6bdbc7cfaef4c04832e0dde';
