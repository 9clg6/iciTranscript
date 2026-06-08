// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings.view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// ViewModel de l'ecran des reglages.
///
/// Gere la configuration audio, serveur ML, raccourcis et stockage.

@ProviderFor(SettingsViewModel)
const settingsViewModelProvider = SettingsViewModelProvider._();

/// ViewModel de l'ecran des reglages.
///
/// Gere la configuration audio, serveur ML, raccourcis et stockage.
final class SettingsViewModelProvider
    extends $NotifierProvider<SettingsViewModel, SettingsState> {
  /// ViewModel de l'ecran des reglages.
  ///
  /// Gere la configuration audio, serveur ML, raccourcis et stockage.
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

String _$settingsViewModelHash() => r'66d52f3ed89b2f59f35d97686d2a6228c60697bd';

/// ViewModel de l'ecran des reglages.
///
/// Gere la configuration audio, serveur ML, raccourcis et stockage.

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
