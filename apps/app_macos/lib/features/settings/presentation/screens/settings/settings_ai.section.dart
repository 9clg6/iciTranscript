part of 'settings.screen.dart';

/// Section « Intelligence artificielle » : envoi en ligne, fournisseur
/// utilisé, puis un bloc par fournisseur (clé, test, modèle).
class _AiSection extends ConsumerWidget {
  const _AiSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SettingsState state = ref.watch(settingsViewModelProvider);
    final SettingsViewModel vm = ref.read(settingsViewModelProvider.notifier);
    final Oats o = context.oats;
    return _Section(
      title: LocaleKeys.settings_ai_title.tr(),
      rows: <Widget>[
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _Row(
              label: LocaleKeys.settings_ai_cloud_allowed.tr(),
              trailing: OatsSwitch(
                value: state.llmCloudAllowed,
                onChanged: vm.setCloudAllowed,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                OatsSpace.lg,
                0,
                OatsSpace.lg,
                OatsSpace.md,
              ),
              child: Text(
                LocaleKeys.settings_ai_privacy_notice.tr(),
                style: o.meta,
              ),
            ),
          ],
        ),
        _Row(
          label: LocaleKeys.settings_ai_active_provider.tr(),
          subtitle: _pausedHint(state),
          trailing: DropdownButton<LlmProviderId>(
            value: state.llmActive,
            underline: const SizedBox.shrink(),
            isDense: true,
            style: o.ui,
            dropdownColor: o.background,
            borderRadius: BorderRadius.circular(OatsRadius.md),
            items: <DropdownMenuItem<LlmProviderId>>[
              for (final LlmProviderId id in <LlmProviderId>[
                LlmProviderId.ollama,
                ...kCloudLlmProviders.where(state.llmKeySuffixes.containsKey),
              ])
                DropdownMenuItem<LlmProviderId>(
                  value: id,
                  enabled: id == LlmProviderId.ollama || state.llmCloudAllowed,
                  child: Text(
                    _providerName(id),
                    style: id == LlmProviderId.ollama || state.llmCloudAllowed
                        ? o.ui
                        : o.ui.copyWith(color: o.faint),
                  ),
                ),
            ],
            onChanged: (LlmProviderId? id) {
              if (id != null) vm.selectLlmProvider(id);
            },
          ),
        ),
        for (final LlmProviderId id in <LlmProviderId>[
          ...kCloudLlmProviders,
          LlmProviderId.ollama,
        ])
          _LlmProviderBlock(
            key: ValueKey<String>('llm-${id.name}'),
            id: id,
            state: state,
            vm: vm,
          ),
      ],
    );
  }

  /// Pourquoi un fournisseur en ligne n'est pas utilisé, en une ligne ; null
  /// s'il n'y a rien à dire.
  static String? _pausedHint(SettingsState state) {
    if (state.llmCloudAllowed || state.llmKeySuffixes.isEmpty) return null;
    final LlmProviderId? chosen = state.llmPreferred;
    if (chosen != null && state.llmKeySuffixes.containsKey(chosen)) {
      return LocaleKeys.settings_ai_cloud_paused.tr(
        args: <String>[_providerName(chosen)],
      );
    }
    return LocaleKeys.settings_ai_cloud_off_hint.tr();
  }
}

String _providerName(LlmProviderId id) =>
    'settings.ai.provider.${id.name}'.tr();

/// Bloc d'un fournisseur : nom, clé (saisie ou masquée), test, modèle.
class _LlmProviderBlock extends ConsumerStatefulWidget {
  const _LlmProviderBlock({
    required this.id,
    required this.state,
    required this.vm,
    super.key,
  });

  final LlmProviderId id;
  final SettingsState state;
  final SettingsViewModel vm;

  @override
  ConsumerState<_LlmProviderBlock> createState() => _LlmProviderBlockState();
}

class _LlmProviderBlockState extends ConsumerState<_LlmProviderBlock> {
  final TextEditingController _key = TextEditingController();
  final TextEditingController _model = TextEditingController();
  String _shownModel = '';
  bool _replacing = false;

  // Clé enregistrée à l'instant : l'envoi coupé est proposé à la suite.
  bool _justSaved = false;

  LlmProviderId get _id => widget.id;

  @override
  void initState() {
    super.initState();
    _syncModel();
  }

  @override
  void didUpdateWidget(covariant _LlmProviderBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncModel();
  }

  // Réglages chargés après la première image : le champ suit la valeur
  // rangée tant que l'utilisateur ne l'a pas changée.
  void _syncModel() {
    final String saved = widget.state.llmModels[_id] ?? '';
    if (saved == _shownModel) return;
    _shownModel = saved;
    _model.text = saved;
  }

  @override
  void dispose() {
    _key.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_key.text.trim().isEmpty) return;
    await widget.vm.saveApiKey(_id, _key.text);
    if (!mounted) return;
    if (ref.read(settingsViewModelProvider).llmKeySuffixes.containsKey(_id) &&
        !ref.read(settingsViewModelProvider).llmKeyErrors.contains(_id)) {
      _key.clear();
      setState(() {
        _replacing = false;
        _justSaved = true;
      });
    }
  }

  Future<void> _remove() async {
    _key.clear();
    setState(() {
      _replacing = false;
      _justSaved = false;
    });
    await widget.vm.removeApiKey(_id);
  }

  @override
  Widget build(BuildContext context) {
    final Oats o = context.oats;
    final SettingsState state = widget.state;
    final String? suffix = state.llmKeySuffixes[_id];
    final bool cloud = _id != LlmProviderId.ollama;
    return Padding(
      padding: const EdgeInsets.all(OatsSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(_providerName(_id), style: o.bodyStrong),
          const SizedBox(height: OatsSpace.md),
          if (cloud && suffix != null && !_replacing)
            _savedKeyRow(o, state, suffix)
          else if (cloud)
            _keyInputRow(),
          if (cloud) ..._statusLines(o, state, suffix),
          const SizedBox(height: OatsSpace.md),
          TextField(
            controller: _model,
            style: o.ui,
            decoration: _decoration(
              o,
              label: LocaleKeys.settings_ai_model_label.tr(),
              hint: LlmSettings.defaultModel(_id),
            ),
            onSubmitted: (String model) {
              _shownModel = model.trim();
              widget.vm.updateLlmModel(_id, model);
            },
          ),
        ],
      ),
    );
  }

  Widget _savedKeyRow(Oats o, SettingsState state, String suffix) => Wrap(
    spacing: OatsSpace.sm,
    runSpacing: OatsSpace.sm,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: <Widget>[
      Padding(
        padding: const EdgeInsets.only(right: OatsSpace.sm),
        child: Text(
          LocaleKeys.settings_ai_key_saved.tr(args: <String>[suffix]),
          style: o.ui.copyWith(color: o.muted),
        ),
      ),
      // Caché tant que l'envoi est coupé : rien ne partirait.
      if (state.llmCloudAllowed)
        OatsButton(
          label: LocaleKeys.settings_ai_test.tr(),
          onPressed: state.llmTests[_id] == LlmTestStatus.testing
              ? null
              : () => widget.vm.testLlmProvider(_id),
        ),
      OatsButton(
        label: LocaleKeys.settings_ai_replace.tr(),
        onPressed: () => setState(() => _replacing = true),
      ),
      OatsButton(
        label: LocaleKeys.settings_ai_remove.tr(),
        danger: true,
        onPressed: _remove,
      ),
    ],
  );

  Widget _keyInputRow() {
    final Oats o = context.oats;
    return Row(
      children: <Widget>[
        Expanded(
          child: TextField(
            controller: _key,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            style: o.ui,
            decoration: _decoration(
              o,
              label: LocaleKeys.settings_ai_api_key_label.tr(),
            ),
            onSubmitted: (_) => _save(),
          ),
        ),
        const SizedBox(width: OatsSpace.sm),
        OatsButton(label: LocaleKeys.settings_ai_save.tr(), onPressed: _save),
        if (_replacing) ...<Widget>[
          const SizedBox(width: OatsSpace.sm),
          OatsButton(
            label: LocaleKeys.settings_ai_cancel.tr(),
            onPressed: () {
              _key.clear();
              setState(() => _replacing = false);
            },
          ),
        ],
      ],
    );
  }

  List<Widget> _statusLines(Oats o, SettingsState state, String? suffix) {
    final LlmTestStatus? test = state.llmTests[_id];
    return <Widget>[
      if (state.llmKeyErrors.contains(_id))
        _line(LocaleKeys.settings_ai_key_error.tr(), o.danger),
      if (test != null)
        _line(
          switch (test) {
            LlmTestStatus.testing => LocaleKeys.settings_ai_testing.tr(),
            LlmTestStatus.ok => LocaleKeys.settings_ai_test_ok.tr(),
            LlmTestStatus.invalidKey =>
              LocaleKeys.settings_ai_test_invalid_key.tr(),
            LlmTestStatus.rateLimited =>
              LocaleKeys.settings_ai_test_rate_limited.tr(),
            LlmTestStatus.unreachable =>
              LocaleKeys.settings_ai_test_unreachable.tr(),
            LlmTestStatus.failed => LocaleKeys.settings_ai_test_failed.tr(),
          },
          switch (test) {
            LlmTestStatus.testing => o.muted,
            LlmTestStatus.ok => o.accent,
            _ => o.danger,
          },
        ),
      if (_justSaved && suffix != null && !state.llmCloudAllowed) ...<Widget>[
        const SizedBox(height: OatsSpace.sm),
        OatsNotice(
          icon: Icons.cloud_off_outlined,
          message: LocaleKeys.settings_ai_cloud_offer.tr(),
          actions: <Widget>[
            OatsButton(
              label: LocaleKeys.settings_ai_cloud_offer_action.tr(),
              onPressed: () => widget.vm.setCloudAllowed(true),
            ),
          ],
        ),
      ],
    ];
  }

  Widget _line(String text, Color color) => Padding(
    padding: const EdgeInsets.only(top: OatsSpace.sm),
    child: Text(text, style: context.oats.small.copyWith(color: color)),
  );

  static InputDecoration _decoration(
    Oats o, {
    required String label,
    String? hint,
  }) {
    final OutlineInputBorder border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(OatsRadius.sm),
      borderSide: BorderSide(color: o.line),
    );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      labelStyle: o.label,
      hintStyle: o.ui.copyWith(color: o.faint),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: OatsSpace.md,
        vertical: OatsSpace.md,
      ),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(borderSide: BorderSide(color: o.ink)),
    );
  }
}
