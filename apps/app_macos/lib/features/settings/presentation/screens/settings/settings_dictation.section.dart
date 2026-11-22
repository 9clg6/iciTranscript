part of 'settings.screen.dart';

// Masques Carbon (HIToolbox Events.h) : controlKey, optionKey, shiftKey,
// cmdKey.
const int _carbonControl = 4096;
const int _carbonOption = 2048;
const int _carbonShift = 512;
const int _carbonCommand = 256;
const int _macSpace = 49;

/// Code de touche macOS de chaque touche physique (table de Flutter, à
/// l'envers).
final Map<PhysicalKeyboardKey, int> _macKeyCodes = <PhysicalKeyboardKey, int>{
  for (final MapEntry<int, PhysicalKeyboardKey> e
      in kMacOsToPhysicalKey.entries)
    e.value: e.key,
};

/// « ⌃⌥Espace » : modificateurs dans l'ordre d'Apple, puis la touche.
String dictationShortcutLabel(DictationShortcut shortcut) {
  final int m = shortcut.modifiers;
  final String mods = <String>[
    if (m & _carbonControl != 0) '⌃',
    if (m & _carbonOption != 0) '⌥',
    if (m & _carbonShift != 0) '⇧',
    if (m & _carbonCommand != 0) '⌘',
  ].join();
  // Espace : un seul texte traduit (« ⌃⌥Espace »), modificateurs compris.
  if (shortcut.keyCode == _macSpace) {
    return LocaleKeys.settings_dictation_shortcut_space.tr(
      args: <String>[mods],
    );
  }
  return '$mods${_keyLabel(shortcut.keyCode)}';
}

// ponytail: libellé de la position US (QWERTY) de la touche ; sur AZERTY une
// lettre peut s'afficher sous son nom QWERTY. Garder le libellé saisi si cela
// gêne.
String _keyLabel(int keyCode) {
  final PhysicalKeyboardKey? key = kMacOsToPhysicalKey[keyCode];
  final int usage = (key?.usbHidUsage ?? 0) & 0xFFFF;
  if (usage >= 0x04 && usage <= 0x1d) {
    return String.fromCharCode(0x41 + usage - 0x04); // A…Z
  }
  if (usage >= 0x1e && usage <= 0x26) {
    return String.fromCharCode(0x31 + usage - 0x1e); // 1…9
  }
  if (usage == 0x27) return '0';
  if (usage >= 0x3a && usage <= 0x45) return 'F${usage - 0x3a + 1}';
  return LocaleKeys.settings_dictation_key_code.tr(args: <String>['$keyCode']);
}

bool _isFunctionKey(PhysicalKeyboardKey key) {
  final int usage = key.usbHidUsage & 0xFFFF;
  return usage >= 0x3a && usage <= 0x45;
}

/// Section « Dictée » : interrupteur, raccourci (modifiable), sortie,
/// permission Accessibilité.
class _DictationSection extends ConsumerStatefulWidget {
  const _DictationSection();

  @override
  ConsumerState<_DictationSection> createState() => _DictationSectionState();
}

class _DictationSectionState extends ConsumerState<_DictationSection> {
  // Retour des Réglages Système : la permission a pu changer.
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onResume: () => ref
        .read(dictationSettingsViewModelProvider.notifier)
        .refreshAccessibility(),
  );
  final FocusNode _recorderFocus = FocusNode();
  bool _recording = false;

  @override
  void initState() {
    super.initState();
    _lifecycle; // créé dès l'affichage
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _recorderFocus.dispose();
    super.dispose();
  }

  void _startRecording() {
    setState(() => _recording = true);
    _recorderFocus.requestFocus();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.handled;
    final PhysicalKeyboardKey key = event.physicalKey;
    if (key == PhysicalKeyboardKey.escape) {
      setState(() => _recording = false);
      return KeyEventResult.handled;
    }
    final int? keyCode = _macKeyCodes[key];
    final HardwareKeyboard k = HardwareKeyboard.instance;
    final int modifiers =
        (k.isControlPressed ? _carbonControl : 0) |
        (k.isAltPressed ? _carbonOption : 0) |
        (k.isShiftPressed ? _carbonShift : 0) |
        (k.isMetaPressed ? _carbonCommand : 0);
    final bool modifierKey = <LogicalKeyboardKey>{
      ...LogicalKeyboardKey.expandSynonyms(<LogicalKeyboardKey>{
        LogicalKeyboardKey.control,
        LogicalKeyboardKey.alt,
        LogicalKeyboardKey.shift,
        LogicalKeyboardKey.meta,
      }),
    }.contains(event.logicalKey);
    // Une touche seule volerait la frappe à toutes les apps : il faut ⌃, ⌥
    // ou ⌘ (⇧ seul ne suffit pas), sauf pour une touche de fonction.
    final bool strongModifier =
        modifiers & (_carbonControl | _carbonOption | _carbonCommand) != 0;
    if (keyCode == null ||
        modifierKey ||
        (!strongModifier && !_isFunctionKey(key))) {
      return KeyEventResult.handled;
    }
    setState(() => _recording = false);
    ref
        .read(dictationSettingsViewModelProvider.notifier)
        .setShortcut(DictationShortcut(keyCode: keyCode, modifiers: modifiers));
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final DictationSettingsState state = ref.watch(
      dictationSettingsViewModelProvider,
    );
    final DictationSettingsViewModel vm = ref.read(
      dictationSettingsViewModelProvider.notifier,
    );
    final bool unavailable =
        ref.watch(dictationShortcutStatusProvider).value ==
        ShortcutStatus.unavailable;
    final DictationSettings settings = state.settings;
    final Oats o = context.oats;
    // Dictée coupée : réglages visibles mais estompés.
    final TextStyle value = settings.enabled
        ? o.ui
        : o.ui.copyWith(color: o.faint);
    return KeyedSubtree(
      key: const ValueKey<String>('settings-dictation'),
      child: _Section(
        title: LocaleKeys.settings_dictation_title.tr(),
        rows: <Widget>[
          _Row(
            label: LocaleKeys.settings_dictation_enabled.tr(),
            subtitle: LocaleKeys.settings_dictation_enabled_description.tr(),
            trailing: OatsSwitch(
              value: settings.enabled,
              onChanged: vm.setEnabled,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _Row(
                label: LocaleKeys.settings_dictation_shortcut.tr(),
                subtitle: _recording
                    ? LocaleKeys.settings_dictation_shortcut_recording_hint.tr()
                    : null,
                trailing: Focus(
                  focusNode: _recorderFocus,
                  onKeyEvent: _recording ? _onKey : null,
                  onFocusChange: (bool focused) {
                    if (!focused && _recording) {
                      setState(() => _recording = false);
                    }
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        _recording
                            ? LocaleKeys.settings_dictation_shortcut_recording
                                  .tr()
                            : dictationShortcutLabel(settings.shortcut),
                        style: value,
                      ),
                      const SizedBox(width: OatsSpace.md),
                      OatsButton(
                        label: LocaleKeys.settings_dictation_shortcut_change
                            .tr(),
                        onPressed: settings.enabled && !_recording
                            ? _startRecording
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
              if (unavailable && settings.enabled)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    OatsSpace.lg,
                    0,
                    OatsSpace.lg,
                    OatsSpace.md,
                  ),
                  child: Text(
                    LocaleKeys.settings_dictation_shortcut_unavailable.tr(),
                    style: o.meta.copyWith(color: o.danger),
                  ),
                ),
            ],
          ),
          _Row(
            label: LocaleKeys.settings_dictation_output.tr(),
            trailing: DropdownButton<DictationOutputMode>(
              value: settings.outputMode,
              underline: const SizedBox.shrink(),
              isDense: true,
              style: value,
              dropdownColor: o.background,
              borderRadius: BorderRadius.circular(OatsRadius.md),
              items: <DropdownMenuItem<DictationOutputMode>>[
                for (final DictationOutputMode mode
                    in DictationOutputMode.values)
                  DropdownMenuItem<DictationOutputMode>(
                    value: mode,
                    child: Text(_outputLabel(mode), style: value),
                  ),
              ],
              onChanged: settings.enabled
                  ? (DictationOutputMode? mode) {
                      if (mode != null) vm.setOutputMode(mode);
                    }
                  : null,
            ),
          ),
          _Row(
            label: LocaleKeys.settings_dictation_accessibility.tr(),
            subtitle: state.accessibilityTrusted
                ? LocaleKeys.settings_dictation_accessibility_granted.tr()
                : LocaleKeys.settings_dictation_accessibility_missing.tr(),
            trailing: state.accessibilityTrusted
                ? const SizedBox.shrink()
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      OatsButton(
                        label: LocaleKeys
                            .settings_dictation_accessibility_request
                            .tr(),
                        onPressed: vm.requestAccessibility,
                      ),
                      const SizedBox(width: OatsSpace.sm),
                      OatsButton(
                        label: LocaleKeys.settings_dictation_accessibility_open
                            .tr(),
                        onPressed: vm.openAccessibilitySettings,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  static String _outputLabel(DictationOutputMode mode) => switch (mode) {
    DictationOutputMode.paste =>
      LocaleKeys.settings_dictation_output_paste.tr(),
    DictationOutputMode.clipboard =>
      LocaleKeys.settings_dictation_output_clipboard.tr(),
  };
}
