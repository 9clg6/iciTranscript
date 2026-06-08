import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ici_transcript/core/providers/kernel.provider.dart';
import 'package:ici_transcript/core/providers/platform/uvx_available.provider.dart';
import 'package:ici_transcript/features/onboarding/presentation/ollama_setup.view_model.dart';
import 'package:ici_transcript/features/onboarding/presentation/ollama_setup.screen.dart';
import 'package:ici_transcript/features/shared/presentation/screens/onboarding/uv_onboarding.screen.dart';
import 'package:ici_transcript/foundation/routing/app_router.dart';

/// Widget racine de l'application IciTranscript.
///
/// Configure le theme macOS (accent indigo), le routeur AutoRoute
/// et attend l'initialisation du kernel avant d'afficher l'app.
class RootAppWidget extends ConsumerStatefulWidget {
  /// Cree une instance de [RootAppWidget].
  const RootAppWidget({super.key});

  @override
  ConsumerState<RootAppWidget> createState() => _RootAppWidgetState();
}

class _RootAppWidgetState extends ConsumerState<RootAppWidget> {
  late final AppRouter _appRouter;

  @override
  void initState() {
    super.initState();
    _appRouter = AppRouter();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<void> kernelState = ref.watch(kernelProvider);
    final AsyncValue<bool> uvxState = ref.watch(uvxAvailableProvider);

    return kernelState.when(
      loading: () => const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      error: (Object error, StackTrace stackTrace) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(child: Text('Erreur d\'initialisation: $error')),
        ),
      ),
      data: (_) {
        // Afficher l'onboarding si uvx n'est pas disponible
        final bool uvxAvailable = uvxState.value ?? true;
        if (!uvxAvailable) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.indigo,
                brightness: Brightness.light,
              ),
              useMaterial3: true,
            ),
            darkTheme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.indigo,
                brightness: Brightness.dark,
              ),
              useMaterial3: true,
            ),
            themeMode: ThemeMode.system,
            home: UvOnboardingScreen(
              onUvReady: () =>
                  ref.invalidate(uvxAvailableProvider),
            ),
          );
        }

        // Afficher l'écran de configuration Ollama si pas encore prêt
        final bool ollamaReady =
            ref.watch(ollamaSetupViewModelProvider).isReady;
        if (!ollamaReady) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.indigo,
                brightness: Brightness.light,
              ),
              useMaterial3: true,
            ),
            darkTheme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.indigo,
                brightness: Brightness.dark,
              ),
              useMaterial3: true,
            ),
            themeMode: ThemeMode.system,
            home: const OllamaSetupScreen(),
          );
        }

        return MaterialApp.router(
          debugShowCheckedModeBanner: false,
          title: 'iciTranscript',
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.indigo,
              brightness: Brightness.light,
            ),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.indigo,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          themeMode: ThemeMode.system,
          routerConfig: _appRouter.config(),
        );
      },
    );
  }
}
