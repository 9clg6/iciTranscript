import 'package:core_data/database/app_database.dart';
import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_domain/domain/enum/session_status.enum.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/session_analysis.dart';
import 'package:ici_transcript/core/providers/core/repositories/session.repository.provider.dart';
import 'package:ici_transcript/core/providers/services/summary.service.provider.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.state.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.view_model.dart';

import '../../helpers/local_model_fakes.dart';

/// Seul build() est remplacé (pas de serveur, micro ni permissions) ;
/// le coach de fin d'appel testé est le vrai code du view model.
class _LiveVm extends LiveTranscriptionViewModel {
  @override
  LiveTranscriptionState build() => LiveTranscriptionState.initial();
}

/// Coach de fin d'enregistrement (interrupteur coach activé).
///
/// API supposée : `LiveTranscriptionViewModel.coachAfterCall(micTranscript,
/// sessionId:)`, l'étape coach de `stopSession` rendue publique
/// (@visibleForTesting) — aujourd'hui `_analyzeEnglish`.
void main() {
  late AppDatabase db;
  late InstantOllamaService ollama;
  late ProviderContainer c;

  Future<void> setUpWith({required bool installed}) async {
    db = memoryDatabase();
    ollama = InstantOllamaService(installed: installed);
    c = ProviderContainer(
      overrides: <Override>[
        ...localModelOverrides(db, ollama),
        liveTranscriptionViewModelProvider.overrideWith(_LiveVm.new),
      ],
    );
    addTearDown(() async {
      c.dispose();
      await db.close();
    });
    final DateTime start = DateTime(2026, 11, 20, 9);
    await c.read(sessionRepositoryProvider).create(
      SessionEntity(
        id: 's1',
        title: 'Appel client',
        createdAt: start,
        updatedAt: start,
        durationSeconds: 900,
        status: SessionStatus.completed,
      ),
    );
  }

  Future<SessionAnalysis> stored() async => SessionAnalysis.fromStored(
    await c.read(summaryServiceProvider).getSummaryForSession('s1'),
  );

  test('modèle non installé : aucun téléchargement, note gardée, '
      'pas de retour coach ni de faux message d\'erreur', () async {
    await setUpWith(installed: false);

    await c
        .read(liveTranscriptionViewModelProvider.notifier)
        .coachAfterCall('I am agree with you.', sessionId: 's1');

    expect(ollama.ensureReadyCalls, 0, reason: 'téléchargement silencieux');
    expect(ollama.analyzeCalls, 0);
    final LiveTranscriptionState s = c.read(liveTranscriptionViewModelProvider);
    expect(s.isFeedbackLoading, isFalse);
    expect(s.feedback, isNull);
    expect((await stored()).feedback, isNull);
    expect(await c.read(sessionRepositoryProvider).getById('s1'), isNotNull);
  });

  test('modèle installé : le retour du coach est produit et sauvegardé', () async {
    await setUpWith(installed: true);

    await c
        .read(liveTranscriptionViewModelProvider.notifier)
        .coachAfterCall('I am agree with you.', sessionId: 's1');

    expect(ollama.analyzeCalls, 1);
    expect(c.read(liveTranscriptionViewModelProvider).feedback, isNotNull);
    expect(
      (await stored()).feedback?.corrections.single.corrected,
      'I agree',
    );
  });
}
