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

/// Tour 7, point 4 : un passage que le modèle n'a pas su transcrire (langue
/// ou écriture inattendue, avec parole) s'affiche dans la note sous un texte
/// localisé « Passage non transcrit (hh:mm:ss – hh:mm:ss) »
/// (`transcription.gap.untranscribed`), distinct du repère de coupure.
void main() {
  final SessionEntity session = FakeData.createSession(
    id: 's1',
    title: 'Point équipe',
    createdAt: DateTime(2026, 11, 23, 9),
    updatedAt: DateTime(2026, 11, 23, 10),
    durationSeconds: 3600,
    status: SessionStatus.completed,
  );

  testWidgets('la note montre le passage non transcrit, localisé, avec ses '
      'heures', (WidgetTester tester) async {
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
          text: LiveTranscriptionService.untranscribedMarkerText(62000, 68000),
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
        frValue('transcription.gap.untranscribed')! as String;
    final String shown = template
        .replaceFirst('{}', '00:01:02')
        .replaceFirst('{}', '00:01:08');
    expect(find.textContaining('$kOpen$shown$kClose'), findsOneWidget);
    expect(find.textContaining('On commence par le budget.'), findsOneWidget);
  });
}
