import 'package:auto_route/auto_route.dart';
import 'package:ici_transcript/features/shell/presentation/oats_shell.screen.dart';

part 'app_router.gr.dart';

/// Routeur d'Oats : une seule page, le shell ; il choisit lui-même la page
/// affichée (accueil, documents, coach, réglages, enregistrement, note).
@AutoRouterConfig(replaceInRouteName: 'Screen|Page,Route')
class AppRouter extends RootStackRouter {
  /// Cree une instance de [AppRouter].
  AppRouter({super.navigatorKey});

  @override
  List<AutoRoute> get routes => <AutoRoute>[
    AutoRoute(page: OatsShellRoute.page, initial: true),
  ];
}
