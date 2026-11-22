import 'dart:async';

import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/ollama.service.dart';
import 'package:ici_transcript/core/providers/kernel.provider.dart';
import 'package:ici_transcript/core/providers/platform/uvx_available.provider.dart';
import 'package:ici_transcript/features/history/presentation/screens/detail/session_detail.state.dart';
import 'package:ici_transcript/features/history/presentation/screens/detail/session_detail.view_model.dart';
import 'package:ici_transcript/features/history/presentation/screens/list/session_list.state.dart';
import 'package:ici_transcript/features/history/presentation/screens/list/session_list.view_model.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.state.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.view_model.dart';
import 'package:ici_transcript/features/onboarding/presentation/ollama_setup.state.dart';
import 'package:ici_transcript/features/onboarding/presentation/ollama_setup.view_model.dart';
import 'package:ici_transcript/features/settings/presentation/screens/settings/settings.state.dart';
import 'package:ici_transcript/features/settings/presentation/screens/settings/settings.view_model.dart';

/// Liste de sessions figée ; select/search/clear gardent le comportement réel
/// (simple copyWith), seul le chargement depuis la base est remplacé.
class FakeSessionListViewModel extends SessionListViewModel {
  FakeSessionListViewModel(this.sessions);

  final List<SessionEntity> sessions;

  @override
  SessionListState build() => SessionListState(sessions: sessions);

  @override
  Future<void> deleteSession(String id) async {}
}

/// Transcription en direct sans serveur ni micro ; compte les démarrages.
class FakeLiveTranscriptionViewModel extends LiveTranscriptionViewModel {
  int startCalls = 0;

  @override
  LiveTranscriptionState build() => LiveTranscriptionState.initial();

  @override
  Future<void> startSession() async {
    startCalls++;
    state = state.copyWith(isRecording: true);
  }

  @override
  Future<void> recheckPermissions() async {}
}

/// Réglages sans canal audio ni prefs.json.
class FakeSettingsViewModel extends SettingsViewModel {
  @override
  SettingsState build() => SettingsState.initial();
}

/// Modèle local : état figé, jamais de téléchargement.
class FakeOllamaSetupViewModel extends OllamaSetupViewModel {
  FakeOllamaSetupViewModel(this.initial);

  final OllamaSetupState initial;

  @override
  OllamaSetupState build() => initial;

  @override
  void retry() {}
}

/// Ollama absent : l'installation a échoué, aucun modèle prêt.
const OllamaSetupState kOllamaAbsent = OllamaSetupState(
  stage: OllamaSetupStage.error,
  error: 'ollama introuvable',
);

/// Ollama et modèle prêts.
const OllamaSetupState kOllamaReady = OllamaSetupState(
  stage: OllamaSetupStage.ready,
  isReady: true,
  progress: 1,
);

/// Détail de session : état fourni par le test ; enregistre la suppression.
class FakeSessionDetailViewModel extends SessionDetailViewModel {
  FakeSessionDetailViewModel(this.load);

  /// Construit l'état (peut lever pour simuler une erreur, ou ne jamais finir).
  final Future<SessionDetailState> Function(String sessionId) load;

  int deleteCalls = 0;

  @override
  Future<SessionDetailState> build({required String sessionId}) =>
      load(sessionId);

  @override
  Future<void> deleteSession() async => deleteCalls++;

  @override
  Future<void> generateSummary() async {}

  @override
  Future<void> analyzeEnglish() async {}
}

/// Fakes réunis pour pomper l'application entière (RootAppWidget).
class AppFakes {
  AppFakes({
    this.sessions = const <SessionEntity>[],
    this.ollama = kOllamaAbsent,
    Future<SessionDetailState> Function(String sessionId)? detail,
  }) : detail = detail ?? _detailFrom(sessions);

  final List<SessionEntity> sessions;
  final FakeLiveTranscriptionViewModel live = FakeLiveTranscriptionViewModel();
  final OllamaSetupState ollama;
  final Future<SessionDetailState> Function(String sessionId) detail;

  static Future<SessionDetailState> Function(String) _detailFrom(
    List<SessionEntity> sessions,
  ) => (String id) async => SessionDetailState(
    session: sessions.firstWhere((SessionEntity s) => s.id == id),
    segments: const <TranscriptSegmentEntity>[],
  );

  List<Override> get overrides => <Override>[
    kernelProvider.overrideWith((Ref ref) async {}),
    uvxAvailableProvider.overrideWith((Ref ref) async => true),
    ollamaSetupViewModelProvider.overrideWith(
      () => FakeOllamaSetupViewModel(ollama),
    ),
    sessionListViewModelProvider.overrideWith(
      () => FakeSessionListViewModel(sessions),
    ),
    liveTranscriptionViewModelProvider.overrideWith(() => live),
    settingsViewModelProvider.overrideWith(FakeSettingsViewModel.new),
    sessionDetailViewModelProvider.overrideWith(
      () => FakeSessionDetailViewModel(detail),
    ),
  ];
}

/// Pompe quelques frames sans attendre la fin des animations infinies.
Future<void> settle(WidgetTester tester, {int frames = 10}) async {
  for (int i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Future qui ne se termine jamais (état « chargement »).
Future<T> never<T>() => Completer<T>().future;
