import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/dictation/dictation_controller.dart';
import 'package:ici_transcript/application/services/dictation/dictation_preferences.dart';
import 'package:ici_transcript/core/platform/global_shortcut_channel.dart';
import 'package:ici_transcript/core/providers/services/process_manager.service.provider.dart';

import '../../../helpers/dictation_fakes.dart';
import '../../../helpers/live_service_fakes.dart';

/// Revue PR #19, point 3 : premier lancement, dictée activée (défaut),
/// modèle de transcription absent du cache. Démarrer le serveur le
/// téléchargerait (plusieurs Go) sans que l'utilisateur l'ait demandé.
///
/// API supposée sur [DictationController] :
/// - `isTranscriptionModelCached: Future<bool> Function()?` (constructeur ;
///   null : pas de vérification, le modèle est supposé là). Le provider
///   passe la vraie vérification (`isTranscriptionModelCached`, voir
///   transcription_model_cache_test) ;
/// - état `DictationModelMissing` : un appui le montre tout de suite, au
///   lieu de « démarrage… » sans fin ;
/// - `Future<void> downloadModel()` : le geste explicite de Réglages ;
///   démarre le serveur (qui télécharge le modèle).
void main() {
  const DictationSettings clipboardMode = DictationSettings(
    outputMode: DictationOutputMode.clipboard,
  );

  late DictationHarness h;
  late FakeGlobalShortcutChannel shortcuts;
  late ScriptedTranscriptionRemote remote;
  late DictationController controller;
  bool cached = false;

  void build(FakeAsync async) {
    cached = false;
    h = DictationHarness(async);
    shortcuts = FakeGlobalShortcutChannel();
    remote = ScriptedTranscriptionRemote();
    controller = DictationController(
      arbiter: h.arbiter,
      shortcuts: shortcuts,
      textOutput: h.output,
      audioCapture: h.audio,
      transcription: remote,
      processManager: ProcessManagerService(channel: h.process),
      liveTranscription: h.live.service,
      serverCommand: LiveServiceHarness.command,
      serverArgs: LiveServiceHarness.args,
      webSocketUrl: DictationHarness.webSocketUrl,
      isTranscriptionModelCached: () async => cached,
    );
    // Le serveur prêt = modèle téléchargé.
    h.process.onReady = () => cached = true;
    unawaited(controller.apply(clipboardMode));
    async.elapse(const Duration(milliseconds: 10));
  }

  test('au lancement : le serveur n est pas démarré', () {
    fakeAsync((FakeAsync async) {
      build(async);
      async.elapse(const Duration(seconds: 30));

      expect(h.process.starts, isEmpty);
      expect(controller.shortcutStatus, ShortcutStatus.registered);
    });
  });

  test('un appui montre « modèle absent » tout de suite, sans capture ni '
      'démarrage', () {
    fakeAsync((FakeAsync async) {
      build(async);

      shortcuts.emit(ShortcutEvent.pressed);
      async.elapse(const Duration(milliseconds: 50));

      expect(controller.state, isA<DictationModelMissing>());
      expect(h.audio.startCalls, 0);
      expect(h.process.starts, isEmpty);
      expect(
        shortcuts.cancelKey.isEmpty || !shortcuts.cancelKey.last,
        isTrue,
        reason: 'Échap jamais laissée capturée',
      );
      async.elapse(const Duration(minutes: 2));
      expect(controller.state, isA<DictationModelMissing>());
    });
  });

  test('télécharger le modèle (geste explicite) : serveur démarré, puis la '
      'dictée marche', () {
    fakeAsync((FakeAsync async) {
      build(async);

      unawaited(controller.downloadModel());
      async.elapse(const Duration(seconds: 1));
      expect(h.process.starts, hasLength(1));

      shortcuts.emit(ShortcutEvent.pressed);
      async.elapse(const Duration(milliseconds: 50));
      expect(controller.state, isA<DictationListening>());
    });
  });
}
