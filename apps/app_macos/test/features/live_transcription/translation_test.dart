import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/translation.service.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/widgets/transcript_line.widget.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';

void main() {
  // Vérifie la VRAIE classe utilisée par l'app (spawn uv + argos) en process.
  test('TranslationService traduit EN->FR (argos réel)', () async {
    final TranslationService service = TranslationService();
    final String out = await service.translate(
      text: 'Welcome guys, it does not work again.',
      from: 'en',
      to: 'fr',
    );
    // ignore: avoid_print
    print('TRADUCTION RÉELLE: "$out"');
    expect(out.trim(), isNotEmpty,
        reason: 'argos doit renvoyer une traduction non vide');
    await service.dispose();
  }, timeout: const Timeout(Duration(minutes: 3)));

  // Vérifie que le sous-titre s'affiche sous le texte.
  testWidgets('TranscriptLineWidget affiche le sous-titre de traduction',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TranscriptLineWidget(
            segment: TranscriptSegmentEntity(
              id: 's1',
              sessionId: 'sess',
              source: AudioSource.input,
              text: 'Welcome guys, it does not work again.',
              timestampMs: 0,
              createdAt: DateTime(2026),
            ),
            translation: 'Bienvenue les gars, ça ne marche plus.',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Bienvenue les gars, ça ne marche plus.'), findsOneWidget);
    expect(find.byIcon(Icons.translate), findsOneWidget);
  });
}
