import 'package:core_domain/domain/enum/server_state.enum.dart';
import 'package:core_presentation/core_presentation.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:ici_transcript/generated/translations/locale_keys.g.dart';

/// Statut du serveur de transcription : point + libellé dans une puce bordée.
class ServerStatusWidget extends StatelessWidget {
  /// Cree une instance de [ServerStatusWidget].
  const ServerStatusWidget({
    required this.serverState,
    this.portInUse,
    super.key,
  });

  /// Etat courant du serveur.
  final ServerState serverState;

  /// Port pris par un autre programme, montré à la place de l'erreur.
  final int? portInUse;

  @override
  Widget build(BuildContext context) {
    final Oats o = context.oats;
    final (Color dot, String label) = switch (serverState) {
      ServerState.ready => (o.ink, LocaleKeys.server_state_ready.tr()),
      ServerState.starting => (o.faint, LocaleKeys.server_state_starting.tr()),
      ServerState.error => (
        o.danger,
        portInUse == null
            ? LocaleKeys.server_state_error.tr()
            : LocaleKeys.server_state_port_in_use.tr(args: <String>['$portInUse']),
      ),
      ServerState.stopped => (o.faint, LocaleKeys.server_state_stopped.tr()),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: OatsSpace.sm + 1,
        vertical: OatsSpace.xxs + 1,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: o.line),
        borderRadius: BorderRadius.circular(OatsRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: OatsSpace.xs + 2),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: o.meta.copyWith(
                color: serverState == ServerState.error ? o.danger : o.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
