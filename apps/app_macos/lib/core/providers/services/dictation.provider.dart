import 'package:core_data/datasources/remote/impl/transcription.remote.data_source.impl.dart';
import 'package:core_foundation/logging/logger.dart';
import 'package:ici_transcript/application/services/dictation/dictation_controller.dart';
import 'package:ici_transcript/application/services/dictation/dictation_preferences.dart';
import 'package:ici_transcript/core/platform/global_shortcut_channel.dart';
import 'package:ici_transcript/core/platform/text_output_channel.dart';
import 'package:ici_transcript/core/platform/voxmlx_server.dart';
import 'package:ici_transcript/core/providers/platform/audio_capture.provider.dart';
import 'package:ici_transcript/core/providers/platform/owned_processes.provider.dart';
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

/// La dictée : raccourci global, flux propre hors réunion (micro seul, sur
/// le serveur partagé), micro de la réunion pendant un enregistrement.
@Riverpod(keepAlive: true)
DictationController dictationController(Ref ref) {
  final TranscriptionRemoteDataSourceImpl remote =
      TranscriptionRemoteDataSourceImpl();
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
  ref.onDispose(() async {
    await controller.dispose();
    await remote.dispose();
  });
  return controller;
}

/// État du raccourci global (Réglages : raccourci déjà pris).
@riverpod
Stream<ShortcutStatus> dictationShortcutStatus(Ref ref) =>
    ref.watch(dictationControllerProvider).shortcutStatusStream;
