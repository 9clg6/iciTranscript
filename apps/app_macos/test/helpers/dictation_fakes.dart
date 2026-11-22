import 'dart:async';
import 'dart:typed_data';

import 'package:core_data/datasources/remote/transcription.remote.data_source.dart';
import 'package:core_data/model/audio_chunk.dart';
import 'package:core_data/model/audio_gap.dart';
import 'package:core_data/model/remote/transcript_event.remote.model.dart';
import 'package:core_data/model/utterance_window.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/enum/connection_state.enum.dart' as domain;
import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:ici_transcript/application/services/dictation/dictation_controller.dart';
import 'package:ici_transcript/application/services/dictation/dictation_preferences.dart';
import 'package:ici_transcript/application/services/transcription_server_arbiter.dart';
import 'package:ici_transcript/core/platform/global_shortcut_channel.dart';
import 'package:ici_transcript/core/platform/text_output_channel.dart';
import 'package:ici_transcript/core/providers/services/process_manager.service.provider.dart';

import 'live_service_fakes.dart';

// Faux de la dictée (T2). Les canaux plateforme sont étendus, comme dans
// live_service_fakes.dart ; la transcription propre à la dictée est jouée
// par [ScriptedTranscriptionRemote] (le test fait le serveur).

/// Raccourci global factice : le test appuie, relâche, annule.
final class FakeGlobalShortcutChannel extends GlobalShortcutChannel {
  final StreamController<ShortcutEvent> _events =
      StreamController<ShortcutEvent>.broadcast();

  /// Résultat des prochains enregistrements (faux : raccourci déjà pris).
  bool registerResult = true;

  final List<({int keyCode, int modifiers})> registered =
      <({int keyCode, int modifiers})>[];
  int unregisterCalls = 0;

  /// Armements successifs de la touche Échap (vrai = capturée).
  final List<bool> cancelKey = <bool>[];

  void emit(ShortcutEvent event) => _events.add(event);

  @override
  Stream<ShortcutEvent> get events => _events.stream;

  @override
  Future<bool> register({required int keyCode, required int modifiers}) async {
    registered.add((keyCode: keyCode, modifiers: modifiers));
    return registerResult;
  }

  @override
  Future<void> unregister() async => unregisterCalls++;

  @override
  Future<void> setCancelKeyEnabled(bool enabled) async =>
      cancelKey.add(enabled);

  /// Caractères de chaque touche dans la disposition de clavier courante
  /// (absente : le plugin ne sait pas, null).
  final Map<int, String> keyLabels = <int, String>{};

  @override
  Future<String?> keyLabel(int keyCode) async => keyLabels[keyCode];
}

/// Presse-papiers et collage factices, dans un journal ordonné :
/// `save`, `copy:<texte>`, `paste`, `restore`.
final class FakeTextOutputChannel extends TextOutputChannel {
  final List<String> log = <String>[];

  /// Permission Accessibilité accordée.
  bool trusted = true;

  /// Le ⌘V synthétique échoue.
  bool pasteFails = false;

  /// Dernier texte posé sur le presse-papiers.
  String? clipboard;

  /// Textes posés sur le presse-papiers par la dictée, dans l'ordre.
  List<String> get copies => log
      .where((String e) => e.startsWith('copy:'))
      .map((String e) => e.substring('copy:'.length))
      .toList();

  @override
  Future<bool> isAccessibilityTrusted() async => trusted;

  @override
  Future<void> copy(String text) async {
    log.add('copy:$text');
    clipboard = text;
  }

  @override
  Future<void> saveClipboard() async => log.add('save');

  @override
  Future<void> restoreClipboard() async => log.add('restore');

  @override
  Future<void> paste() async {
    log.add('paste');
    if (pasteFails) throw PlatformException(code: 'PASTE_FAILED');
  }
}

/// Flux de transcription propre à la dictée, au contrat du port : une
/// phrase s'ouvre sur un chunk voisé ; `sendCommit(isFinal: true)` la clôt
/// et rend `{input}` si une phrase était ouverte, `{}` sinon ;
/// [activeSources] contient `input` tant qu'une phrase est ouverte ou
/// qu'un `done` est attendu. Socket fermée : plus rien n'arrive.
final class ScriptedTranscriptionRemote
    implements TranscriptionRemoteDataSource {
  ScriptedTranscriptionRemote({List<String>? log}) : log = log ?? <String>[];

  /// Journal ordonné (`dictation.connect`, `dictation.commit`,
  /// `dictation.disconnect`), partageable avec d'autres faux.
  final List<String> log;
  final List<AudioChunk> sentAudio = <AudioChunk>[];
  final List<({String url, bool systemAudioEnabled})> connects =
      <({String url, bool systemAudioEnabled})>[];
  int disconnectCalls = 0;
  int finalCommits = 0;

  /// Sources visées par chaque commit final (null : toutes).
  final List<Set<AudioSource>?> finalCommitSources = <Set<AudioSource>?>[];
  bool connected = false;

  bool _open = false;
  int _pending = 0;
  final StreamController<TranscriptEventRemoteModel> _mic =
      StreamController<TranscriptEventRemoteModel>.broadcast();
  final StreamController<TranscriptEventRemoteModel> _system =
      StreamController<TranscriptEventRemoteModel>.broadcast();
  final StreamController<AudioGap> _gaps =
      StreamController<AudioGap>.broadcast();
  final StreamController<domain.ConnectionState> _states =
      StreamController<domain.ConnectionState>.broadcast();
  final Expando<UtteranceWindow> _windows = Expando<UtteranceWindow>();

  static bool _voiced(AudioChunk chunk) =>
      chunk.data.length > 5 &&
      ByteData.sublistView(chunk.data).getInt16(4, Endian.little) != 0;

  /// Le serveur clôt seul la phrase ouverte (pause détectée).
  void pauseDetected() {
    if (!_open) return;
    _open = false;
    _pending++;
  }

  void emitDelta(String delta) {
    if (!connected) return;
    _mic.add(
      TranscriptEventRemoteModel(
        type: 'response.audio_transcript.delta',
        delta: delta,
      ),
    );
  }

  /// `done` de la plus ancienne phrase attendue ; [hadSpeech] faux : l'audio
  /// de la phrase n'avait pas d'énergie de parole.
  void emitDone(String text, {bool hadSpeech = true}) {
    if (!connected) return;
    if (_pending > 0) _pending--;
    final TranscriptEventRemoteModel event = TranscriptEventRemoteModel(
      type: 'response.audio_transcript.done',
      text: text,
    );
    _windows[event] = UtteranceWindow(
      startMs: 0,
      endMs: 0,
      hadSpeech: hadSpeech,
    );
    _mic.add(event);
  }

  @override
  Future<void> connect({
    String url = 'ws://localhost:8000/v1/realtime',
    bool systemAudioEnabled = true,
  }) async {
    log.add('dictation.connect');
    connects.add((url: url, systemAudioEnabled: systemAudioEnabled));
    connected = true;
    _states.add(domain.ConnectionState.connected);
  }

  @override
  void sendAudio(AudioChunk chunk) {
    if (!connected) return;
    sentAudio.add(chunk);
    if (chunk.source == AudioSource.input && _voiced(chunk)) _open = true;
  }

  @override
  Set<AudioSource> sendCommit({
    bool isFinal = false,
    Set<AudioSource>? sources,
  }) {
    if (!isFinal) return <AudioSource>{};
    finalCommits++;
    finalCommitSources.add(sources);
    log.add('dictation.commit');
    if (!_open) return <AudioSource>{};
    _open = false;
    _pending++;
    return <AudioSource>{AudioSource.input};
  }

  @override
  Set<AudioSource> get activeSources => _open || _pending > 0
      ? <AudioSource>{AudioSource.input}
      : <AudioSource>{};

  @override
  Stream<TranscriptEventRemoteModel> get transcriptionStream => _mic.stream;

  @override
  Stream<TranscriptEventRemoteModel> get systemTranscriptionStream =>
      _system.stream;

  @override
  Stream<AudioGap> get audioGaps => _gaps.stream;

  @override
  UtteranceWindow? windowOf(TranscriptEventRemoteModel event) =>
      _windows[event];

  @override
  Future<void> disconnect() async {
    log.add('dictation.disconnect');
    disconnectCalls++;
    connected = false;
    _open = false;
    _pending = 0;
    _states.add(domain.ConnectionState.disconnected);
  }

  @override
  Stream<domain.ConnectionState> get connectionState => _states.stream;
}

/// Monte le vrai [DictationController] sur les faux, à côté du vrai
/// service de réunion ([LiveServiceHarness], même capture, même serveur).
final class DictationHarness {
  DictationHarness(this.async, {LiveServiceHarness? live})
    : live = live ?? LiveServiceHarness(async) {
    remote = ScriptedTranscriptionRemote(log: this.live.audio.log);
    arbiter = TranscriptionServerArbiter(
      isRecording: () => this.live.service.isRecording,
    );
    controller = DictationController(
      arbiter: arbiter,
      shortcuts: shortcuts,
      textOutput: output,
      audioCapture: this.live.audio,
      transcription: remote,
      processManager: ProcessManagerService(channel: this.live.process),
      liveTranscription: this.live.service,
      serverCommand: LiveServiceHarness.command,
      serverArgs: LiveServiceHarness.args,
      webSocketUrl: webSocketUrl,
    );
  }

  static const String webSocketUrl = 'ws://localhost:8000/v1/realtime';

  final FakeAsync async;
  final LiveServiceHarness live;
  final FakeGlobalShortcutChannel shortcuts = FakeGlobalShortcutChannel();
  final FakeTextOutputChannel output = FakeTextOutputChannel();
  late final ScriptedTranscriptionRemote remote;

  /// Arbitre du serveur unique : enregistrement > dictée > rattrapage.
  late final TranscriptionServerArbiter arbiter;
  late final DictationController controller;

  FakeProcessManagerChannel get process => live.process;
  FakeAudioCaptureChannel get audio => live.audio;
  DictationState get state => controller.state;

  /// Lancement de l'app : réglages appliqués (raccourci, serveur chaud).
  void launch([DictationSettings settings = const DictationSettings()]) {
    unawaited(controller.apply(settings));
    async.elapse(const Duration(milliseconds: 10));
  }

  void press() {
    shortcuts.emit(ShortcutEvent.pressed);
    async.elapse(Duration.zero);
  }

  void release() {
    shortcuts.emit(ShortcutEvent.released);
    async.elapse(Duration.zero);
  }

  void cancel() {
    shortcuts.emit(ShortcutEvent.cancel);
    async.elapse(Duration.zero);
  }

  int _nextId = 0;

  /// [count] chunks micro de 100 ms, voisés ou non, un toutes les 100 ms.
  void say(int count, {bool voiced = true}) {
    for (int i = 0; i < count; i++) {
      final int id = _nextId++;
      audio.emit(
        chunk(
          AudioSource.input,
          id,
          timestampMs: 1000000 + id * 100,
          voiced: voiced,
        ),
      );
      async.elapse(const Duration(milliseconds: 100));
    }
  }

  /// Appui maintenu en parlant [count] × 100 ms, puis relâchement.
  void holdAndSay(int count) {
    press();
    say(count);
    release();
  }
}
