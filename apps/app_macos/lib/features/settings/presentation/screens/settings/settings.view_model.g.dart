// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings.view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// ViewModel de l'ecran des reglages.
///
/// Gere la configuration audio, serveur ML, raccourcis, stockage et IA.

@ProviderFor(SettingsViewModel)
const settingsViewModelProvider = SettingsViewModelProvider._();

/// ViewModel de l'ecran des reglages.
///
/// Gere la configuration audio, serveur ML, raccourcis, stockage et IA.
final class SettingsViewModelProvider
    extends $NotifierProvider<SettingsViewModel, SettingsState> {
  /// ViewModel de l'ecran des reglages.
  ///
  /// Gere la configuration audio, serveur ML, raccourcis, stockage et IA.
  const SettingsViewModelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'settingsViewModelProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$settingsViewModelHash();

  @$internal
  @override
  SettingsViewModel create() => SettingsViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SettingsState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SettingsState>(value),
    );
  }
}

String _$settingsViewModelHash() => r'824b3dac18842dea15248f8d7a759c7146b462dd';

/// ViewModel de l'ecran des reglages.
///
/// Gere la configuration audio, serveur ML, raccourcis, stockage et IA.

abstract class _$SettingsViewModel extends $Notifier<SettingsState> {
  SettingsState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<SettingsState, SettingsState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SettingsState, SettingsState>,
              SettingsState,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
