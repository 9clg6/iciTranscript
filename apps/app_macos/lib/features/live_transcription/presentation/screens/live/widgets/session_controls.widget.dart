import 'package:core_presentation/core_presentation.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:ici_transcript/generated/translations/locale_keys.g.dart';

/// Contrôles de session : Démarrer (au repos), sinon Pause/Reprendre et
/// Arrêter. Un seul bouton plein à la fois.
class SessionControlsWidget extends StatelessWidget {
  /// Cree une instance de [SessionControlsWidget].
  const SessionControlsWidget({
    required this.isRecording,
    required this.isPaused,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    super.key,
  });

  /// Indique si un enregistrement est en cours.
  final bool isRecording;

  /// Indique si l'enregistrement est en pause.
  final bool isPaused;

  /// Callback pour demarrer l'enregistrement.
  final VoidCallback onStart;

  /// Callback pour mettre en pause l'enregistrement.
  final VoidCallback onPause;

  /// Callback pour reprendre l'enregistrement.
  final VoidCallback onResume;

  /// Callback pour arreter l'enregistrement.
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    if (!isRecording && !isPaused) {
      return OatsPrimaryButton(
        icon: Icons.fiber_manual_record_outlined,
        label: LocaleKeys.transcription_live_start.tr(),
        onPressed: onStart,
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        OatsButton(
          icon: isPaused ? Icons.play_arrow_outlined : Icons.pause_outlined,
          label: isPaused
              ? LocaleKeys.transcription_live_resume.tr()
              : LocaleKeys.transcription_live_pause.tr(),
          onPressed: isPaused ? onResume : onPause,
        ),
        const SizedBox(width: OatsSpace.sm),
        OatsPrimaryButton(
          icon: Icons.stop_outlined,
          label: LocaleKeys.transcription_live_stop.tr(),
          onPressed: onStop,
        ),
      ],
    );
  }
}
