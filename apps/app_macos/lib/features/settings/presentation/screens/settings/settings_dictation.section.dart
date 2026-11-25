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

/// « ⌃⌥Espace » : modificateurs dans l'ordre d'Apple (U+2303 ⌃, U+2325 ⌥,
/// U+21E7 ⇧, U+2318 ⌘), puis la touche telle que la disposition de clavier
/// courante l'écrit ([keyLabel], du plugin ; null : son code).
String dictationShortcutLabel(DictationShortcut shortcut, String? keyLabel) {
  final int m = shortcut.modifiers;
  final String mods = <String>[
    if (m & _carbonControl != 0) '\u2303',
    if (m & _carbonOption != 0) '\u2325',
    if (m & _carbonShift != 0) '\u21E7',
    if (m & _carbonCommand != 0) '\u2318',
  ].join();
  final int? keyCode = shortcut.keyCode;
  if (keyCode == null) return mods; // modificateurs seuls : « ⌥⌘ »
  // Espace : un seul texte traduit (« ⌃⌥Espace »), modificateurs compris.
  if (keyCode == _macSpace) {
    return LocaleKeys.settings_dictation_shortcut_space.tr(
      args: <String>[mods],
    );
  }
  return '$mods${keyLabel ?? LocaleKeys.settings_dictation_key_code.tr(args: <String>['${shortcut.keyCode}'])}';
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
  // Modificateurs tenus ensemble depuis le dernier « tout relâché », et si
  // une autre touche est venue (alors ce n'est pas un raccourci
  // modificateurs seuls).
  int _chord = 0;
  bool _chordHadKey = false;
  // Un seul modificateur relâché : refusé, message affiché.
  bool _needsTwo = false;

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
    _chord = 0;
    _chordHadKey = false;
    setState(() {
      _recording = true;
      _needsTwo = false;
    });
    _recorderFocus.requestFocus();
  }

  static final Set<LogicalKeyboardKey> _modifierKeys =
      LogicalKeyboardKey.expandSynonyms(<LogicalKeyboardKey>{
        LogicalKeyboardKey.control,
        LogicalKeyboardKey.alt,
        LogicalKeyboardKey.shift,
        LogicalKeyboardKey.meta,
      });

  static int _heldModifiers() {
    final HardwareKeyboard k = HardwareKeyboard.instance;
    return (k.isControlPressed ? _carbonControl : 0) |
        (k.isAltPressed ? _carbonOption : 0) |
        (k.isShiftPressed ? _carbonShift : 0) |
        (k.isMetaPressed ? _carbonCommand : 0);
  }

  /// Modificateurs relâchés sans autre touche : raccourci « modificateurs
  /// seuls » (au moins deux, dont ⌃, ⌥ ou ⌘), sinon refusé avec un message.
  void _onModifiersReleased() {
    final int chord = _chord;
    final bool hadKey = _chordHadKey;
    _chord = 0;
    _chordHadKey = false;
    if (hadKey || chord == 0) return;
    if (!DictationShortcut.isValidModifiersOnly(chord)) {
      setState(() => _needsTwo = true);
      return;
    }
    setState(() {
      _recording = false;
      _needsTwo = false;
    });
    ref
        .read(dictationSettingsViewModelProvider.notifier)
        .setShortcut(DictationShortcut(keyCode: null, modifiers: chord));
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    final bool modifierKey = _modifierKeys.contains(event.logicalKey);
    if (event is KeyUpEvent) {
      if (modifierKey && _heldModifiers() == 0) _onModifiersReleased();
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent) return KeyEventResult.handled;
    if (modifierKey) {
      _chord |= _heldModifiers();
      if (_needsTwo) setState(() => _needsTwo = false);
      return KeyEventResult.handled;
    }
    _chordHadKey = true;
    final PhysicalKeyboardKey key = event.physicalKey;
    if (key == PhysicalKeyboardKey.escape) {
      setState(() {
        _recording = false;
        _needsTwo = false;
      });
      return KeyEventResult.handled;
    }
    final int? keyCode = _macKeyCodes[key];
    final int modifiers = _heldModifiers();
    // Une touche seule volerait la frappe à toutes les apps : il faut ⌃, ⌥
    // ou ⌘ (⇧ seul ne suffit pas), sauf pour une touche de fonction.
    final bool strongModifier =
        modifiers & (_carbonControl | _carbonOption | _carbonCommand) != 0;
    if (keyCode == null ||
        modifierKey ||
        (!strongModifier && !_isFunctionKey(key))) {
      return KeyEventResult.handled;
    }
    setState(() {
      _recording = false;
      _needsTwo = false;
    });
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
    final ShortcutStatus? status = ref
        .watch(dictationShortcutStatusProvider)
        .value;
    final bool unavailable = status == ShortcutStatus.unavailable;
    final DictationSettings settings = state.settings;
    final bool needsAccessibility =
        settings.enabled &&
        settings.shortcut.keyCode == null &&
        status == ShortcutStatus.needsAccessibility;
    final bool modelMissing =
        settings.enabled &&
        ref.watch(transcriptionModelCachedProvider).value == false;
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
          if (modelMissing)
            Padding(
              padding: const EdgeInsets.all(OatsSpace.lg),
              child: _ModelDownloadNotice(download: state.download, vm: vm),
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
                            : dictationShortcutLabel(
                                settings.shortcut,
                                state.keyLabel,
                              ),
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
              if (_recording && _needsTwo)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    OatsSpace.lg,
                    0,
                    OatsSpace.lg,
                    OatsSpace.md,
                  ),
                  child: Text(
                    LocaleKeys.settings_dictation_shortcut_needs_two_modifiers
                        .tr(),
                    style: o.meta.copyWith(color: o.danger),
                  ),
                ),
              if (needsAccessibility)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    OatsSpace.lg,
                    0,
                    OatsSpace.lg,
                    OatsSpace.md,
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          LocaleKeys
                              .settings_dictation_shortcut_needs_accessibility
                              .tr(),
                          style: o.meta.copyWith(color: o.danger),
                        ),
                      ),
                      const SizedBox(width: OatsSpace.md),
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

/// Modèle absent : jamais téléchargé sans ce geste (plusieurs Go).
class _ModelDownloadNotice extends StatelessWidget {
  const _ModelDownloadNotice({required this.download, required this.vm});

  final ModelDownload download;
  final DictationSettingsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final Oats o = context.oats;
    return switch (download) {
      ModelDownload.running => OatsNotice(
        icon: Icons.downloading_outlined,
        message: LocaleKeys.settings_dictation_model_downloading.tr(),
        actions: <Widget>[
          SizedBox.square(
            dimension: OatsIconSize.md,
            child: CircularProgressIndicator(strokeWidth: 2, color: o.muted),
          ),
        ],
      ),
      ModelDownload.idle || ModelDownload.failed => OatsNotice(
        icon: download == ModelDownload.failed
            ? Icons.error_outline
            : Icons.download_outlined,
        danger: download == ModelDownload.failed,
        message: download == ModelDownload.failed
            ? LocaleKeys.settings_dictation_model_download_failed.tr()
            : LocaleKeys.settings_dictation_model_missing.tr(),
        actions: <Widget>[
          OatsButton(
            label: LocaleKeys.settings_dictation_download_model.tr(),
            onPressed: vm.downloadModel,
          ),
        ],
      ),
    };
  }
}
