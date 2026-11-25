import 'dart:async';

import 'package:core_data/datasources/remote/impl/transcription.remote.data_source.impl.dart';
import 'package:core_foundation/logging/logger.dart';
import 'package:flutter/widgets.dart';
import 'package:ici_transcript/core/providers/services/llm_dio.provider.dart';
import 'package:ici_transcript/core/providers/services/api_key_store.provider.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/application/services/llm/api_key_store.dart';
import 'package:ici_transcript/application/services/stt/mistral_batch_transcriber.dart';
import 'package:ici_transcript/application/services/stt/transcription_engine.dart';
import 'package:ici_transcript/application/services/dictation/dictation_controller.dart';
import 'package:ici_transcript/application/services/dictation/dictation_preferences.dart';
import 'package:ici_transcript/core/platform/global_shortcut_channel.dart';
import 'package:ici_transcript/core/platform/text_output_channel.dart';
import 'package:ici_transcript/core/platform/transcription_model_cache.dart';
import 'package:ici_transcript/core/platform/voxmlx_server.dart';
import 'package:ici_transcript/core/providers/platform/audio_capture.provider.dart';
import 'package:ici_transcript/core/providers/platform/owned_processes.provider.dart';
import 'package:ici_transcript/core/providers/platform/prefs_store.provider.dart';
import 'package:ici_transcript/core/providers/services/live_transcription.service.provider.dart';
import 'package:ici_transcript/core/providers/services/process_manager.service.provider.dart';
import 'package:ici_transcript/core/providers/services/transcription_server_arbiter.provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'dictation.provider.g.dart';

/// Provider singleton pour [GlobalShortcutChannel].
@Riverpod(keepAlive: true)
GlobalShortcutChannel globalShortcutChannel(Ref ref) => GlobalShortcutChannel();

/// Provider singleton pour [TextOutputChannel].
@Riverpod(keepAlive: true)
TextOutputChannel textOutputChannel(Ref ref) => TextOutputChannel();

/// Derniers réglages de dictée enregistrés (Réglages, lancement) ; le
/// contrôleur les applique dès qu'ils changent.
@Riverpod(keepAlive: true)
class DictationSettingsApplied extends _$DictationSettingsApplied {
  @override
  DictationSettings? build() => null;

  /// Réglages à appliquer.
  void set(DictationSettings settings) => state = settings;
}

/// Une dictée est en cours ([isDictating]) : les suggestions de réunion se
/// taisent et le micro pris par Oats pour dicter ne compte jamais comme un
/// appel. Tenu à jour par [dictationController] ; lisible sans construire
/// le contrôleur (faux dans les tests : `overrideWith` ou `set`).
@Riverpod(keepAlive: true)
class DictationActive extends _$DictationActive {
  @override
  bool build() => false;

  /// Fixe l'état.
  void set(bool active) => state = active;
}

/// Démarrage, écoute ou transcription d'une dictée.
bool isDictating(DictationState s) =>
    s is DictationStarting ||
    s is DictationListening ||
    s is DictationTranscribing;

/// Appelle [onChange] avec [isDictating] à chaque changement de [states]
/// (branchement stateStream → [dictationActiveProvider]).
StreamSubscription<bool> followDictation(
  Stream<DictationState> states,
  void Function(bool dictating) onChange,
) => states.map(isDictating).distinct().listen(onChange);

/// La dictée : raccourci global, flux propre hors réunion (micro seul, sur
/// le serveur partagé), micro de la réunion pendant un enregistrement.
@Riverpod(keepAlive: true)
DictationController dictationController(Ref ref) {
  final TranscriptionRemoteDataSourceImpl remote =
      TranscriptionRemoteDataSourceImpl();
  final ApiKeyStore keys = ref.watch(apiKeyStoreProvider);
  final DictationController controller = DictationController(
    arbiter: ref.watch(transcriptionServerArbiterProvider),
    shortcuts: ref.watch(globalShortcutChannelProvider),
    textOutput: ref.watch(textOutputChannelProvider),
    audioCapture: ref.watch(audioCaptureChannelProvider),
    transcription: remote,
    processManager: ref.watch(processManagerServiceProvider),
    liveTranscription: ref.watch(liveTranscriptionServiceProvider),
    serverCommand: voxmlxCommand,
    serverArgs: voxmlxArgs(),
    prefs: ref.watch(prefsStoreProvider),
    isTranscriptionModelCached: () async => transcriptionModelCachedNow(),
    // Moteur en ligne choisi (envoi permis, clé rangée) : l'API batch de
    // Mistral au relâchement, sans serveur local.
    cloudTranscriber: MistralBatchTranscriber(
      dio: ref.watch(llmDioProvider),
      apiKey: () => keys.read(LlmProviderId.mistral),
    ),
    cloudChosen: () async =>
        await TranscriptionEngineSelection(
          keys,
        ).fromPrefs(await ref.read(prefsStoreProvider).read()) ==
        TranscriptionEngine.mistral,
    webSocketUrl: ref
        .watch(launchServerPortsProvider)
        .transcriptionWebSocket
        .toString(),
  );
  ref.listen<DictationSettings?>(dictationSettingsAppliedProvider, (
    DictationSettings? _,
    DictationSettings? next,
  ) {
    if (next == null) return;
    controller.apply(next).catchError((Object e) {
      Log.named('Dictation').warning('Réglages de dictée non appliqués: $e');
    });
  }, fireImmediately: true);
  final StreamSubscription<bool> dictating = followDictation(
    controller.stateStream,
    ref.read(dictationActiveProvider.notifier).set,
  );
  // Retour au premier plan : un raccourci refusé faute d'Accessibilité est
  // retenté, même Réglages fermés. Sans binding (tests sans widgets) : rien.
  AppLifecycleListener? lifecycle;
  try {
    lifecycle = AppLifecycleListener(
      onResume: () => unawaited(controller.retryShortcut()),
    );
  } catch (_) {
    lifecycle = null;
  }
  ref.onDispose(() async {
    lifecycle?.dispose();
    await dictating.cancel();
    await controller.dispose();
    await remote.dispose();
  });
  return controller;
}

/// État du raccourci global (Réglages : raccourci déjà pris).
@riverpod
Stream<ShortcutStatus> dictationShortcutStatus(Ref ref) =>
    ref.watch(dictationControllerProvider).shortcutStatusStream;

/// Modèle de transcription déjà dans le cache (Réglages : proposer le
/// téléchargement). Relu à chaque lecture (non gardé).
@riverpod
Future<bool> transcriptionModelCached(Ref ref) async =>
    transcriptionModelCachedNow();
