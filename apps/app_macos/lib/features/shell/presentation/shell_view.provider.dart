import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'shell_view.provider.g.dart';

/// Page affichée dans la zone de contenu du shell.
enum ShellView {
  /// Accueil agenda.
  home,

  /// Documents source.
  documents,

  /// Coach anglais.
  coach,

  /// Réglages.
  settings,

  /// Enregistrement en cours.
  live,
}

/// Page courante du shell ; une note ouverte passe par-dessus
/// (`SessionListState.selectedSessionId`).
@Riverpod(keepAlive: true)
class ShellViewController extends _$ShellViewController {
  @override
  ShellView build() => ShellView.home;

  /// Affiche [view].
  void show(ShellView view) => state = view;
}
