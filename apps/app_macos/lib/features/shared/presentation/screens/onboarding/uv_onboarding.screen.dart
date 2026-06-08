import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ici_transcript/core/providers/platform/process_manager.provider.dart';

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

    final channel = ref.read(processManagerChannelProvider);
    final success = await channel.installUv();

    if (!success) {
      setState(() {
        _step = _Step.error;
        _errorMessage =
            "L'installation a échoué. Ouvrez un Terminal et exécutez :\n"
            'curl -LsSf https://astral.sh/uv/install.sh | sh';
      });
      return;
    }

    // Vérifier que uvx est maintenant disponible
    final available = await channel.checkUvxAvailable();
    if (available) {
      widget.onUvReady();
    } else {
      setState(() {
        _step = _Step.error;
        _errorMessage =
            'uv a été installé mais uvx est introuvable.\n'
            'Redémarrez iciTranscript ou ajoutez ~/.local/bin à votre PATH.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.memory_rounded,
                  size: 48,
                  color: colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  'Moteur ML requis',
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'iciTranscript utilise voxmlx pour la transcription vocale. '
                  'Ce moteur nécessite uv, un gestionnaire de paquets Python '
                  'ultra-rapide.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'uv sera installé dans ~/.local/bin (~5 MB). '
                  'Le modèle ML sera téléchargé au premier démarrage.',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 32),
                if (_step == _Step.error && _errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onErrorContainer,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _step == _Step.installing ? null : _install,
                    child: _step == _Step.installing
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(width: 10),
                              Text('Installation en cours…'),
                            ],
                          )
                        : const Text('Installer uv'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _Step { idle, installing, error }
