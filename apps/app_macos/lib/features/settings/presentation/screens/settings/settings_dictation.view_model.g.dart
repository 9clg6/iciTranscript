// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings_dictation.view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Section « Dictée » de Réglages : lit et écrit prefs.json par le
/// `PrefsStore` partagé, puis fait appliquer les réglages par la dictée.

@ProviderFor(DictationSettingsViewModel)
const dictationSettingsViewModelProvider =
    DictationSettingsViewModelProvider._();

/// Section « Dictée » de Réglages : lit et écrit prefs.json par le
/// `PrefsStore` partagé, puis fait appliquer les réglages par la dictée.
final class DictationSettingsViewModelProvider
    extends
        $NotifierProvider<DictationSettingsViewModel, DictationSettingsState> {
  /// Section « Dictée » de Réglages : lit et écrit prefs.json par le
  /// `PrefsStore` partagé, puis fait appliquer les réglages par la dictée.
  const DictationSettingsViewModelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'dictationSettingsViewModelProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$dictationSettingsViewModelHash();

  @$internal
  @override
  DictationSettingsViewModel create() => DictationSettingsViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DictationSettingsState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DictationSettingsState>(value),
    );
  }
}

String _$dictationSettingsViewModelHash() =>
    r'baa2d36cb0cf3d737d14eb5c700b0828e385d6ac';

/// Section « Dictée » de Réglages : lit et écrit prefs.json par le
/// `PrefsStore` partagé, puis fait appliquer les réglages par la dictée.

abstract class _$DictationSettingsViewModel
    extends $Notifier<DictationSettingsState> {
  DictationSettingsState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref =
        this.ref as $Ref<DictationSettingsState, DictationSettingsState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<DictationSettingsState, DictationSettingsState>,
              DictationSettingsState,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
