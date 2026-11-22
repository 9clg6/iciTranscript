// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'prefs_store.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider singleton pour [PrefsStore] (prefs.json).

@ProviderFor(prefsStore)
const prefsStoreProvider = PrefsStoreProvider._();

/// Provider singleton pour [PrefsStore] (prefs.json).

final class PrefsStoreProvider
    extends $FunctionalProvider<PrefsStore, PrefsStore, PrefsStore>
    with $Provider<PrefsStore> {
  /// Provider singleton pour [PrefsStore] (prefs.json).
  const PrefsStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'prefsStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$prefsStoreHash();

  @$internal
  @override
  $ProviderElement<PrefsStore> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PrefsStore create(Ref ref) {
    return prefsStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PrefsStore value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PrefsStore>(value),
    );
  }
}

String _$prefsStoreHash() => r'6d94956ec29e5d4bdb6f92150fa24d2e42c0ad70';
