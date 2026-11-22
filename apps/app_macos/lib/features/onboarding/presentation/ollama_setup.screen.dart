import 'package:core_presentation/core_presentation.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ici_transcript/application/services/ollama.service.dart';
import 'package:ici_transcript/features/onboarding/presentation/ollama_setup.state.dart';
import 'package:ici_transcript/features/onboarding/presentation/ollama_setup.view_model.dart';
import 'package:ici_transcript/generated/translations/locale_keys.g.dart';

/// Préparation du modèle local (moteur Ollama + modèle Mistral), affichée
/// dans Réglages. Le téléchargement démarre seul au lancement ; ce bloc en
/// montre l'avancement et permet de relancer après une erreur.
class OllamaSetupScreen extends ConsumerWidget {
  /// Crée le bloc.
  const OllamaSetupScreen({super.key});

  static const List<OllamaSetupStage> _order = <OllamaSetupStage>[
    OllamaSetupStage.downloadingBinary,
    OllamaSetupStage.startingServer,
    OllamaSetupStage.downloadingModel,
    OllamaSetupStage.ready,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final OllamaSetupState s = ref.watch(ollamaSetupViewModelProvider);
    final Oats o = context.oats;
    final int current = s.isReady ? _order.length : _order.indexOf(s.stage);

    Widget step(OllamaSetupStage stage, String label, String size) {
      final int me = _order.indexOf(stage);
      final bool done = current > me;
      final bool active = s.stage == stage && !s.isReady;
      final bool download = stage != OllamaSetupStage.startingServer;
      return Padding(
        padding: const EdgeInsets.only(bottom: OatsSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                SizedBox(
                  width: OatsIconSize.md,
                  height: OatsIconSize.md,
                  child: active
                      ? const CircularProgressIndicator(strokeWidth: 1.5)
                      : Icon(
                          done
                              ? Icons.check_circle_outline
                              : Icons.circle_outlined,
                          size: OatsIconSize.md,
                          color: done ? o.ink : o.faint,
                        ),
                ),
                const SizedBox(width: OatsSpace.sm + 2),
                Expanded(
                  child: Text(
                    label,
                    style: o.ui.copyWith(
                      color: done || active ? o.ink : o.muted,
                    ),
                  ),
                ),
                Text(
                  done
                      ? LocaleKeys.common_label_done.tr()
                      : active && download && s.progress > 0
                      ? '${(s.progress * 100).toStringAsFixed(0)} %'
                      : size,
                  style: o.meta,
                ),
              ],
            ),
            if (active && download) ...<Widget>[
              const SizedBox(height: OatsSpace.sm),
              Padding(
                padding: const EdgeInsets.only(left: OatsSpace.xl + 2),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(OatsRadius.pill),
                  child: LinearProgressIndicator(
                    value: s.progress > 0 ? s.progress : null,
                    minHeight: 3,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(LocaleKeys.ollama_subtitle.tr(), style: o.small),
        const SizedBox(height: OatsSpace.lg),
        step(
          OllamaSetupStage.downloadingBinary,
          LocaleKeys.ollama_step_binary.tr(),
          '~106 Mo',
        ),
        step(
          OllamaSetupStage.startingServer,
          LocaleKeys.ollama_step_server.tr(),
          '',
        ),
        step(
          OllamaSetupStage.downloadingModel,
          LocaleKeys.ollama_step_model.tr(),
          '~4 Go',
        ),
        if (s.stage == OllamaSetupStage.error) ...<Widget>[
          const SizedBox(height: OatsSpace.xs),
          OatsNotice(
            icon: Icons.error_outline,
            danger: true,
            message: s.error == null
                ? LocaleKeys.ollama_error.tr()
                : '${LocaleKeys.ollama_error.tr()} : ${s.error}',
            actions: <Widget>[
              OatsButton(
                icon: Icons.refresh,
                label: LocaleKeys.common_action_retry.tr(),
                onPressed: () =>
                    ref.read(ollamaSetupViewModelProvider.notifier).retry(),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
