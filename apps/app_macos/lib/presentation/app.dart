import 'package:core_presentation/core_presentation.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ici_transcript/core/providers/kernel.provider.dart';
import 'package:ici_transcript/core/providers/platform/uvx_available.provider.dart';
import 'package:ici_transcript/features/onboarding/presentation/ollama_setup.view_model.dart';
import 'package:ici_transcript/features/shared/presentation/screens/onboarding/uv_onboarding.screen.dart';
import 'package:ici_transcript/foundation/routing/app_router.dart';
import 'package:ici_transcript/generated/translations/locale_keys.g.dart';

/// Widget racine d'Oats.
///
/// Attend l'initialisation du kernel, propose l'installation de uv si besoin,
/// puis ouvre le shell. Le modèle local (Ollama) ne bloque jamais le
/// lancement : les fonctions qui en ont besoin le disent en ligne.
class RootAppWidget extends ConsumerStatefulWidget {
  /// Cree une instance de [RootAppWidget].
  const RootAppWidget({super.key});

  @override
  ConsumerState<RootAppWidget> createState() => _RootAppWidgetState();
}

class _RootAppWidgetState extends ConsumerState<RootAppWidget> {
  final AppRouter _appRouter = AppRouter();
  final ThemeData _light = buildOatsTheme(Brightness.light);
  final ThemeData _dark = buildOatsTheme(Brightness.dark);

  Widget _simple(Widget home) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: LocaleKeys.app_name.tr(),
    localizationsDelegates: context.localizationDelegates,
    supportedLocales: context.supportedLocales,
    locale: context.locale,
    theme: _light,
    darkTheme: _dark,
    home: Scaffold(body: home),
  );

  @override
  Widget build(BuildContext context) {
    final AsyncValue<void> kernelState = ref.watch(kernelProvider);
    final AsyncValue<bool> uvxState = ref.watch(uvxAvailableProvider);

    return kernelState.when(
      loading: () => _simple(const Center(child: CircularProgressIndicator())),
      error: (Object error, StackTrace stackTrace) => _simple(
        Center(
          child: Text(
            LocaleKeys.common_error_init.tr(args: <String>['$error']),
          ),
        ),
      ),
      data: (_) {
        if (!(uvxState.value ?? true)) {
          return _simple(
            UvOnboardingScreen(
              onUvReady: () => ref.invalidate(uvxAvailableProvider),
            ),
          );
        }
        // Prépare le modèle local en arrière-plan dès le lancement, sans
        // rien bloquer (keepAlive : un seul téléchargement).
        ref.read(ollamaSetupViewModelProvider);
        return MaterialApp.router(
          debugShowCheckedModeBanner: false,
          title: LocaleKeys.app_name.tr(),
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          theme: _light,
          darkTheme: _dark,
          routerConfig: _appRouter.config(),
        );
      },
    );
  }
}
