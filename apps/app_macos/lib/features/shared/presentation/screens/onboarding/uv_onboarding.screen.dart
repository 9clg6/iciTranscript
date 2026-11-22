import 'package:core_presentation/core_presentation.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ici_transcript/core/platform/process_manager_channel.dart';
import 'package:ici_transcript/core/providers/platform/process_manager.provider.dart';
import 'package:ici_transcript/generated/translations/locale_keys.g.dart';

/// Ecran d'onboarding affiché quand `uv`/`uvx` n'est pas installé.
///
/// Guide l'utilisateur pour installer `uv` via le script officiel d'Astral,
/// puis relance la vérification automatiquement.
class UvOnboardingScreen extends ConsumerStatefulWidget {
  /// Crée une instance de [UvOnboardingScreen].
  const UvOnboardingScreen({required this.onUvReady, super.key});

  /// Callback appelé quand uvx est détecté (installation réussie).
  final VoidCallback onUvReady;

  @override
  ConsumerState<UvOnboardingScreen> createState() => _UvOnboardingScreenState();
}

class _UvOnboardingScreenState extends ConsumerState<UvOnboardingScreen> {
  _Step _step = _Step.idle;
  String? _errorMessage;

  Future<void> _install() async {
    setState(() {
      _step = _Step.installing;
      _errorMessage = null;
    });

    final ProcessManagerChannel channel = ref.read(
      processManagerChannelProvider,
    );
    final bool success = await channel.installUv();

    if (!success) {
      setState(() {
        _step = _Step.error;
        _errorMessage = LocaleKeys.uv_failed.tr(
          args: <String>['curl -LsSf https://astral.sh/uv/install.sh | sh'],
        );
      });
      return;
    }

    // Vérifier que uvx est maintenant disponible
    final bool available = await channel.checkUvxAvailable();
    if (available) {
      widget.onUvReady();
    } else {
      setState(() {
        _step = _Step.error;
        _errorMessage = LocaleKeys.uv_no_uvx.tr();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final Oats o = context.oats;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(OatsSpace.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(LocaleKeys.app_name.tr(), style: o.wordmark),
              const SizedBox(height: OatsSpace.xl),
              Text(LocaleKeys.uv_title.tr(), style: o.title),
              const SizedBox(height: OatsSpace.md),
              Text(LocaleKeys.uv_body.tr(), style: o.body),
              const SizedBox(height: OatsSpace.sm),
              Text(LocaleKeys.uv_detail.tr(), style: o.small),
              const SizedBox(height: OatsSpace.xl),
              if (_step == _Step.error && _errorMessage != null) ...<Widget>[
                OatsNotice(
                  icon: Icons.error_outline,
                  danger: true,
                  message: _errorMessage!,
                ),
                const SizedBox(height: OatsSpace.lg),
              ],
              OatsPrimaryButton(
                icon: _step == _Step.installing
                    ? null
                    : Icons.download_outlined,
                label: _step == _Step.installing
                    ? LocaleKeys.uv_installing.tr()
                    : LocaleKeys.uv_install.tr(),
                onPressed: _step == _Step.installing ? null : _install,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _Step { idle, installing, error }
