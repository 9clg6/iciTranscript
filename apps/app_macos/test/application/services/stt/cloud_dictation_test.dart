import 'dart:async';
import 'dart:typed_data';

import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/dictation/dictation_controller.dart';
import 'package:ici_transcript/application/services/dictation/dictation_preferences.dart';
import 'package:ici_transcript/application/services/gap_backfill.service.dart';
import 'package:ici_transcript/application/services/transcription_server_arbiter.dart';
import 'package:ici_transcript/core/platform/global_shortcut_channel.dart';
import 'package:ici_transcript/core/providers/services/process_manager.service.provider.dart';

import '../../../helpers/dictation_fakes.dart';
import '../../../helpers/live_service_fakes.dart';

// Dictée avec le moteur en ligne (Mistral, API batch) : l'audio de l'appui
// est gardé puis envoyé une fois au relâchement ; le texte est produit une
// fois. Le serveur local n'est jamais démarré (ni chaud au lancement, ni à
// l'appui) et le flux temps réel local n'est jamais ouvert.
//
// API supposée : `DictationController(..., PcmTranscriber?
// cloudTranscriber)` ; non nul = moteur en ligne choisi (l'app le fournit
// seulement quand l'envoi en ligne est permis et la clé rangée).
final class _Batch implements PcmTranscriber {
  final List<Uint8List> calls = <Uint8List>[];
  String reply = 'Bonjour, ceci est une dictée.';

  @override
  Future<List<({int offsetMs, String text})>> transcribe(Uint8List pcm) async {
    calls.add(pcm);
    return <({int offsetMs, String text})>[(offsetMs: 0, text: reply)];
  }
}

void main() {
  test('dictée en ligne : pas de serveur local, audio de l appui envoyé une '
      'fois, texte produit une fois', () {
    fakeAsync((FakeAsync async) {
      final LiveServiceHarness live = LiveServiceHarness(async);
      final ScriptedTranscriptionRemote remote = ScriptedTranscriptionRemote(
        log: live.audio.log,
      );
      final FakeGlobalShortcutChannel shortcuts = FakeGlobalShortcutChannel();
      final FakeTextOutputChannel output = FakeTextOutputChannel();
      final _Batch batch = _Batch();
      final DictationController controller = DictationController(
        arbiter: TranscriptionServerArbiter(
          isRecording: () => live.service.isRecording,
        ),
        shortcuts: shortcuts,
        textOutput: output,
        audioCapture: live.audio,
        transcription: remote,
        processManager: ProcessManagerService(channel: live.process),
        liveTranscription: live.service,
        serverCommand: LiveServiceHarness.command,
        serverArgs: LiveServiceHarness.args,
        webSocketUrl: 'ws://localhost:8000/v1/realtime',
        cloudTranscriber: batch,
      );
      unawaited(
        controller.apply(
          const DictationSettings(outputMode: DictationOutputMode.clipboard),
        ),
      );
      async.elapse(const Duration(seconds: 5));
      expect(live.process.starts, isEmpty, reason: 'pas de serveur chaud');

      shortcuts.emit(ShortcutEvent.pressed);
      async.elapse(Duration.zero);
      for (int id = 0; id < 20; id++) {
        live.audio.emit(
          chunk(AudioSource.input, id, timestampMs: 1000000 + id * 100),
        );
        async.elapse(const Duration(milliseconds: 100));
      }
      shortcuts.emit(ShortcutEvent.released);
      async.elapse(const Duration(seconds: 2));

      expect(batch.calls, hasLength(1));
      expect(batch.calls.single.length, 20 * 3200, reason: 'tout l appui');
      expect(output.copies, <String>['Bonjour, ceci est une dictée.']);
      expect(controller.state, isA<DictationDone>());
      expect(remote.connects, isEmpty, reason: 'pas de flux local');
      expect(live.process.starts, isEmpty);
    });
  });
}
