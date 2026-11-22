import 'package:ici_transcript/application/services/dictation/dictation_preferences.dart';
import 'package:ici_transcript/core/platform/text_output_channel.dart';
import 'package:ici_transcript/core/providers/platform/prefs_store.provider.dart';
import 'package:ici_transcript/core/providers/services/dictation.provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'settings_dictation.view_model.g.dart';

/// Réglages de la dictée montrés dans Réglages.
final class DictationSettingsState {
  /// Cree une instance de [DictationSettingsState].
  const DictationSettingsState({
    this.settings = const DictationSettings(),
    this.accessibilityTrusted = false,
    this.keyLabel,
  });

  /// Réglages enregistrés (défauts tant que prefs.json n'est pas lu).
  final DictationSettings settings;

  /// Accessibilité accordée (requise pour coller).
  final bool accessibilityTrusted;

  /// Touche du raccourci dans la disposition de clavier courante (null :
  /// inconnue).
  final String? keyLabel;

  DictationSettingsState _with({
    DictationSettings? settings,
    bool? accessibilityTrusted,
    String? Function()? keyLabel,
  }) => DictationSettingsState(
    settings: settings ?? this.settings,
    accessibilityTrusted: accessibilityTrusted ?? this.accessibilityTrusted,
    keyLabel: keyLabel != null ? keyLabel() : this.keyLabel,
  );
}

/// Section « Dictée » de Réglages : lit et écrit prefs.json par le
/// `PrefsStore` partagé, puis fait appliquer les réglages par la dictée.
@riverpod
class DictationSettingsViewModel extends _$DictationSettingsViewModel {
  DictationPreferences get _prefs =>
      DictationPreferences(ref.read(prefsStoreProvider));
  TextOutputChannel get _output => ref.read(textOutputChannelProvider);

  @override
  DictationSettingsState build() {
    _load();
    return const DictationSettingsState();
  }

  Future<void> _load() async {
    final DictationSettings settings = await _prefs.load();
    final bool trusted = await _output.isAccessibilityTrusted();
    final String? label = await _keyLabel(settings);
    if (!ref.mounted) return;
    state = state._with(
      settings: settings,
      accessibilityTrusted: trusted,
      keyLabel: () => label,
    );
  }

  /// Active ou coupe la dictée.
  Future<void> setEnabled(bool enabled) => _save(
    DictationSettings(
      enabled: enabled,
      shortcut: state.settings.shortcut,
      outputMode: state.settings.outputMode,
    ),
  );

  /// Raccourci (code de touche macOS + masque Carbon).
  Future<void> setShortcut(DictationShortcut shortcut) => _save(
    DictationSettings(
      enabled: state.settings.enabled,
      shortcut: shortcut,
      outputMode: state.settings.outputMode,
    ),
  );

  /// Coller ou presse-papiers.
  Future<void> setOutputMode(DictationOutputMode mode) => _save(
    DictationSettings(
      enabled: state.settings.enabled,
      shortcut: state.settings.shortcut,
      outputMode: mode,
    ),
  );

  /// Relit la permission Accessibilité (retour des Réglages Système).
  Future<void> refreshAccessibility() async {
    final bool trusted = await _output.isAccessibilityTrusted();
    if (ref.mounted) state = state._with(accessibilityTrusted: trusted);
  }

  /// Demande système d'Accessibilité.
  Future<void> requestAccessibility() async {
    final bool trusted = await _output.requestAccessibility();
    if (ref.mounted) state = state._with(accessibilityTrusted: trusted);
  }

  /// Ouvre le volet Accessibilité des Réglages Système.
  Future<void> openAccessibilitySettings() =>
      _output.openAccessibilitySettings();

  Future<void> _save(DictationSettings settings) async {
    final bool newKey =
        settings.shortcut.keyCode != state.settings.shortcut.keyCode;
    state = state._with(
      settings: settings,
      keyLabel: newKey ? () => null : null,
    );
    await _prefs.save(settings);
    ref.read(dictationSettingsAppliedProvider.notifier).set(settings);
    if (!newKey) return;
    final String? label = await _keyLabel(settings);
    if (ref.mounted) state = state._with(keyLabel: () => label);
  }

  Future<String?> _keyLabel(DictationSettings settings) => ref
      .read(globalShortcutChannelProvider)
      .keyLabel(settings.shortcut.keyCode);
}
