import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/enum/session_status.enum.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/live_transcription.service.dart';
import 'package:ici_transcript/features/history/presentation/screens/detail/session_detail.screen.dart';
import 'package:ici_transcript/features/history/presentation/screens/detail/session_detail.state.dart';
import 'package:ici_transcript/features/history/presentation/screens/detail/session_detail.view_model.dart';
import 'package:ici_transcript/features/onboarding/presentation/ollama_setup.view_model.dart';

import '../../helpers/fake_data.dart';
import '../../helpers/fake_view_models.dart';
import '../../helpers/localized_app.dart';

/// Repère ouvert du relancement (revue de la PR #31) : « Rien n'a pu être
/// enregistré après hh:mm:ss (app arrêtée ou disque plein) » s'affiche dans
/// la note sous un texte localisé (`transcription.gap.not_recorded_after`,
/// `{}` = heure), comme les autres repères.
/// API : not_recorded_after_marker_test.dart.
void main() {
  final SessionEntity session = FakeData.createSession(
    id: 's1',
    title: 'Point équipe',
    createdAt: DateTime(2026, 11, 23, 9),
    updatedAt: DateTime(2026, 11, 23, 10),
    durationSeconds: 3600,
    status: SessionStatus.completed,
  );

  testWidgets('la note montre le repère ouvert, localisé, avec son heure', (
    WidgetTester tester,
  ) async {
    final SessionDetailState state = SessionDetailState(
      session: session,
      segments: <TranscriptSegmentEntity>[
        TranscriptSegmentEntity(
          id: 'a',
          sessionId: 's1',
          source: AudioSource.output,
          text: 'On commence par le budget.',
          timestampMs: 50000,
          createdAt: DateTime(2026, 11, 23, 9),
        ),
        TranscriptSegmentEntity(
          id: 'p',
          sessionId: 's1',
          source: AudioSource.output,
          text: LiveTranscriptionService.notRecordedAfterMarkerText(62000),
          timestampMs: 62000,
          createdAt: DateTime(2026, 11, 23, 9),
        ),
      ],
    );
    await pumpLocalized(
      tester,
      SessionDetailScreen(sessionId: 's1', onClose: () {}),
      overrides: <Override>[
        sessionDetailViewModelProvider.overrideWith(
          () => FakeSessionDetailViewModel((String _) async => state),
        ),
        ollamaSetupViewModelProvider.overrideWith(
          () => FakeOllamaSetupViewModel(kOllamaReady),
        ),
      ],
    );

    final String template =
        frValue('transcription.gap.not_recorded_after')! as String;
    final String shown = template.replaceFirst('{}', '00:01:02');
    expect(find.textContaining('$kOpen$shown$kClose'), findsOneWidget);
    expect(find.textContaining('On commence par le budget.'), findsOneWidget);
  });
}
