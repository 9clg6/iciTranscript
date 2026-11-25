part of 'settings.screen.dart';

/// Moteur de transcription : sur ce Mac ou Mistral en ligne. Le choix
/// refusé (envoi en ligne coupé, pas de clé) n'est pas rangé ; la raison
/// est dite sous la ligne.
class _SttEngineRow extends ConsumerStatefulWidget {
  const _SttEngineRow({required this.cloudAllowed});

  /// Interrupteur d'envoi en ligne de l'IA.
  final bool cloudAllowed;

  @override
  ConsumerState<_SttEngineRow> createState() => _SttEngineRowState();
}

class _SttEngineRowState extends ConsumerState<_SttEngineRow> {
  TranscriptionEngine _engine = TranscriptionEngine.local;
  TranscriptionEngineRefusal? _refusal;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final Map<String, Object?> prefs = await ref
        .read(prefsStoreProvider)
        .read();
    if (!mounted) return;
    setState(
      () => _engine = TranscriptionEngineSettings.fromPrefs(prefs).engine,
    );
  }

  Future<void> _choose(TranscriptionEngine chosen) async {
    final ({TranscriptionEngine engine, TranscriptionEngineRefusal? refusal})
    r = await TranscriptionEngineSelection(
      ref.read(apiKeyStoreProvider),
    ).resolve(chosen: chosen, cloudAllowed: widget.cloudAllowed);
    if (!mounted) return;
    if (r.refusal != null) {
      setState(() => _refusal = r.refusal);
      return;
    }
    setState(() {
      _engine = chosen;
      _refusal = null;
    });
    await ref.read(prefsStoreProvider).update(<String, Object?>{
      TranscriptionEngineSettings.engineKey: chosen.name,
    });
  }

  static String _label(TranscriptionEngine e) => switch (e) {
    TranscriptionEngine.local => LocaleKeys.settings_audio_engine_local.tr(),
    TranscriptionEngine.mistral =>
      LocaleKeys.settings_audio_engine_mistral.tr(),
  };

  @override
  Widget build(BuildContext context) {
    final Oats o = context.oats;
    final TranscriptionEngineRefusal? refusal = _refusal;
    return Column(
      key: const ValueKey<String>('stt-engine'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Row(
          label: LocaleKeys.settings_audio_engine_title.tr(),
          subtitle: LocaleKeys.settings_audio_engine_privacy.tr(),
          trailing: DropdownButton<TranscriptionEngine>(
            value: _engine,
            underline: const SizedBox.shrink(),
            isDense: true,
            style: o.ui,
            dropdownColor: o.background,
            borderRadius: BorderRadius.circular(OatsRadius.md),
            items: <DropdownMenuItem<TranscriptionEngine>>[
              for (final TranscriptionEngine e in TranscriptionEngine.values)
                DropdownMenuItem<TranscriptionEngine>(
                  value: e,
                  child: Text(_label(e)),
                ),
            ],
            onChanged: (TranscriptionEngine? e) {
              if (e != null) unawaited(_choose(e));
            },
          ),
        ),
        if (refusal != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              OatsSpace.lg,
              0,
              OatsSpace.lg,
              OatsSpace.sm,
            ),
            child: Text(
              switch (refusal) {
                TranscriptionEngineRefusal.cloudNotAllowed =>
                  LocaleKeys.settings_audio_engine_refused_cloud.tr(),
                TranscriptionEngineRefusal.missingKey =>
                  LocaleKeys.settings_audio_engine_refused_key.tr(),
              },
              key: const ValueKey<String>('stt-engine-refusal'),
              style: o.meta.copyWith(color: o.danger),
            ),
          ),
      ],
    );
  }
}
