import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:core_data/database/app_database.dart';
import 'package:core_domain/domain/entities/english_feedback.entity.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/live_coach/live_coach.service.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/core/providers/services/api_key_store.provider.dart';
import 'package:ici_transcript/core/providers/services/live_answers.service.provider.dart';
import 'package:ici_transcript/core/providers/services/live_coach.service.provider.dart';
import 'package:ici_transcript/core/providers/services/llm_dio.provider.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.screen.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.state.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.view_model.dart';

import '../../helpers/fake_view_models.dart' show settle;
import '../../helpers/live_answers_fakes.dart' show LiveAnswersHarness;
import '../../helpers/llm_fakes.dart' show writeLlmPrefs;
import '../../helpers/local_model_fakes.dart';
import '../../helpers/localized_app.dart';
import '../../helpers/settings_fakes.dart';

/// Écran du direct dans l'état donné ; l'interrupteur garde le vrai code.
class _ShownLive extends LiveTranscriptionViewModel {
  _ShownLive(this.initial);

  final LiveTranscriptionState initial;

  @override
  LiveTranscriptionState build() => initial;

  @override
  Future<void> recheckPermissions() async {}
}

/// Coach en direct dont le test choisit ce qu'il a trouvé.
class _ShownCoach extends LiveCoachService {
  _ShownCoach(this.current) : super(resolveModel: () async => null);

  LiveCoachSnapshot current;
  final StreamController<LiveCoachSnapshot> _changes =
      StreamController<LiveCoachSnapshot>.broadcast();

  @override
  LiveCoachSnapshot get snapshot => current;

  @override
  Stream<LiveCoachSnapshot> get snapshots async* {
    yield current;
    yield* _changes.stream;
  }

  void show(LiveCoachSnapshot next) {
    current = next;
    _changes.add(next);
  }
}

/// Coach en direct à l'écran (interrupteur et bloc discret du panneau).
///
/// Besoin :
/// - interrupteur « Coach en direct », coupé par défaut, avant de démarrer ;
///   disponible seulement avec un fournisseur en ligne configuré ET
///   autorisé ; sinon désactivé, et l'écran dit pourquoi (le modèle local
///   ralentirait la transcription) ;
/// - pendant la réunion, coach activé : au plus les 3 corrections les plus
///   récentes (heure dans la note) dans un bloc discret ; échec : rien de
///   rouge, l'état « indisponible », la transcription reste là ; coach
///   coupé : pas de bloc.
///
/// API supposée : `LiveTranscriptionState.isLiveCoachEnabled`,
/// `toggleLiveCoach()`, `liveCoachServiceProvider` (`snapshot`,
/// `snapshots`). L'interrupteur porte le nom accessible de son libellé
/// (`coach.live.option`) ; raison : `coach.live.unavailable` ; état :
/// `coach.live.state_unavailable`.
void main() {
  late AppDatabase db;

  final DateTime t = DateTime(2026, 11, 23, 10);
  TranscriptSegmentEntity line(String text) => TranscriptSegmentEntity(
    id: 'seg-1',
    sessionId: 's1',
    source: AudioSource.input,
    text: text,
    timestampMs: 5000,
    createdAt: t,
  );

  EnglishCorrectionEntity fix(int minute) => EnglishCorrectionEntity(
    original: 'mistake number $minute',
    corrected: 'better phrasing $minute',
    category: 'grammar',
    explanation: 'Raison $minute.',
    timestampMs: minute * 60000,
  );

  Future<void> io(WidgetTester tester) async {
    for (int i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await settle(tester, frames: 2);
    }
  }

  /// [cloud] : Claude configuré et autorisé ; sinon clé présente mais envoi
  /// coupé, modèle local installé.
  Future<void> pumpLive(
    WidgetTester tester, {
    required LiveTranscriptionState state,
    required bool cloud,
    LiveCoachService? coach,
  }) async {
    await tester.runAsync(
      () => writeLlmPrefs(
        cloudAllowed: cloud,
        preferred: LlmProviderId.anthropic,
      ),
    );
    db = memoryDatabase();
    addTearDown(db.close);
    await pumpLocalized(
      tester,
      const LiveTranscriptionScreen(),
      size: const Size(1440, 900),
      settle: false,
      overrides: <Override>[
        ...localModelOverrides(db, InstantOllamaService(installed: true)),
        apiKeyStoreProvider.overrideWithValue(
          InMemoryApiKeyStore(<LlmProviderId, String>{
            LlmProviderId.anthropic: 'sk-ant-test-SECRET-0123456789',
          }),
        ),
        llmDioProvider.overrideWithValue(
          Dio()..httpClientAdapter = RecordingHttpAdapter(),
        ),
        liveTranscriptionViewModelProvider.overrideWith(
          () => _ShownLive(state),
        ),
        liveAnswersServiceProvider.overrideWithValue(
          LiveAnswersHarness().service,
        ),
        if (coach != null) liveCoachServiceProvider.overrideWithValue(coach),
      ],
    );
    await io(tester);
  }

  /// Interrupteur dont le nom accessible contient le libellé.
  SemanticsFinder liveSwitch() => find.semantics.byPredicate((SemanticsNode n) {
    final SemanticsData d = n.getSemanticsData();
    return d.label.contains('coach.live.option'.tr()) &&
        d.flagsCollection.isToggled != Tristate.none;
  });

  SemanticsData switchData() =>
      liveSwitch().evaluate().single.getSemanticsData();

  group('avant de démarrer', () {
    testWidgets('Claude configuré et autorisé : interrupteur coupé par défaut, '
        'il s\'active', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpLive(
        tester,
        state: LiveTranscriptionState.initial(),
        cloud: true,
      );

      expect(switchData().flagsCollection.isEnabled, Tristate.isTrue);
      expect(switchData().flagsCollection.isToggled, Tristate.isFalse);
      expect(find.text('coach.live.unavailable'.tr()), findsNothing);

      tester.semantics.tap(liveSwitch());
      await io(tester);

      expect(switchData().flagsCollection.isToggled, Tristate.isTrue);
      handle.dispose();
    });

    testWidgets('envoi coupé, modèle local seulement : interrupteur '
        'désactivé, l\'écran dit pourquoi', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpLive(
        tester,
        state: LiveTranscriptionState.initial(),
        cloud: false,
      );

      expect(switchData().flagsCollection.isEnabled, Tristate.isFalse);
      expect(find.text('coach.live.unavailable'.tr()), findsOneWidget);
      handle.dispose();
    });
  });

  group('pendant la réunion', () {
    final LiveTranscriptionState recording = LiveTranscriptionState(
      isRecording: true,
      isLiveCoachEnabled: true,
      segments: <TranscriptSegmentEntity>[
        line('I am agree with you on this point.'),
      ],
    );

    testWidgets('au plus les 3 corrections les plus récentes, avec leur '
        'heure', (WidgetTester tester) async {
      final _ShownCoach coach = _ShownCoach(
        LiveCoachSnapshot(
          corrections: <EnglishCorrectionEntity>[
            for (final int m in <int>[1, 2, 3, 4, 5]) fix(m),
          ],
        ),
      );
      await pumpLive(tester, state: recording, cloud: true, coach: coach);

      for (final int m in <int>[3, 4, 5]) {
        expect(find.textContaining('better phrasing $m'), findsOneWidget);
      }
      for (final int m in <int>[1, 2]) {
        expect(find.textContaining('better phrasing $m'), findsNothing);
      }
      expect(find.textContaining('05:00'), findsWidgets);
    });

    testWidgets('une nouvelle correction arrive : elle apparaît, la plus '
        'ancienne des 3 sort', (WidgetTester tester) async {
      final _ShownCoach coach = _ShownCoach(
        LiveCoachSnapshot(
          corrections: <EnglishCorrectionEntity>[fix(1), fix(2), fix(3)],
        ),
      );
      await pumpLive(tester, state: recording, cloud: true, coach: coach);

      coach.show(
        LiveCoachSnapshot(
          corrections: <EnglishCorrectionEntity>[
            fix(1),
            fix(2),
            fix(3),
            fix(4),
          ],
        ),
      );
      await io(tester);

      expect(find.textContaining('better phrasing 4'), findsOneWidget);
      expect(find.textContaining('better phrasing 1'), findsNothing);
    });

    testWidgets('coach en échec : « indisponible », rien de rouge, la '
        'transcription reste', (WidgetTester tester) async {
      await pumpLive(
        tester,
        state: recording,
        cloud: true,
        coach: _ShownCoach(const LiveCoachSnapshot(unavailable: true)),
      );

      expect(
        find.textContaining('coach.live.state_unavailable'.tr()),
        findsOneWidget,
      );
      expect(find.textContaining('I am agree with you'), findsOneWidget);
      expect(find.textContaining('llm.error'), findsNothing);
    });

    testWidgets('coach en direct coupé : pas de bloc', (
      WidgetTester tester,
    ) async {
      await pumpLive(
        tester,
        state: recording.copyWith(isLiveCoachEnabled: false),
        cloud: true,
        coach: _ShownCoach(
          LiveCoachSnapshot(corrections: <EnglishCorrectionEntity>[fix(1)]),
        ),
      );

      expect(find.textContaining('better phrasing 1'), findsNothing);
      expect(
        find.textContaining('coach.live.state_unavailable'.tr()),
        findsNothing,
      );
    });
  });
}
