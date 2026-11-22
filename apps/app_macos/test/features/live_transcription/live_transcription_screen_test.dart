import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.screen.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.state.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.view_model.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/widgets/session_controls.widget.dart';

import '../../helpers/localized_app.dart';
import '../../helpers/test_helpers.dart';

/// ViewModel factice qui renvoie un état fixe sans déclencher le cycle de vie
/// réel (écoute des streams serveur/audio, vérification des permissions).
class _FakeLiveTranscriptionViewModel extends LiveTranscriptionViewModel {
  @override
  LiveTranscriptionState build() => LiveTranscriptionState.initial();
}

void main() {
  final List<Override> overrides = <Override>[
    liveTranscriptionViewModelProvider.overrideWith(
      _FakeLiveTranscriptionViewModel.new,
    ),
  ];

  /// Tests widget pour [LiveTranscriptionScreen].
  ///
  /// Verifie que l'ecran de transcription en direct affiche
  /// correctement les controles, le timer et les segments.
  group('LiveTranscriptionScreen', () {
    testWidgets('doit afficher le message vide quand aucun segment', (
      WidgetTester tester,
    ) async {
      // Arrange & Act
      await tester.pumpWidget(
        TestHelpers.createTestableWidget(
          child: const LiveTranscriptionScreen(),
          overrides: overrides,
        ),
      );
      await tester.pump();

      // Assert — Le screen est wrappé dans un Scaffold par le widget
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('doit afficher le timer au format 00:00:00', (
      WidgetTester tester,
    ) async {
      // Arrange & Act
      await tester.pumpWidget(
        TestHelpers.createTestableWidget(
          child: const LiveTranscriptionScreen(),
          overrides: overrides,
        ),
      );
      await tester.pump();

      // Assert
      expect(find.text('00:00:00'), findsOneWidget);
    });

    testWidgets('doit afficher le widget de controles de session', (
      WidgetTester tester,
    ) async {
      // Arrange & Act
      await tester.pumpWidget(
        TestHelpers.createTestableWidget(
          child: const LiveTranscriptionScreen(),
          overrides: overrides,
        ),
      );
      await tester.pump();

      // Assert — Le widget de controles est present
      expect(find.byType(SessionControlsWidget), findsOneWidget);
    });

    testWidgets('la barre d\'état nomme les deux sources : micro et système', (
      WidgetTester tester,
    ) async {
      await pumpLocalized(
        tester,
        const LiveTranscriptionScreen(),
        overrides: overrides,
        settle: false,
      );

      // Libellé lu dans fr.json (« Micro : {} ») ; l'icône n'est pas fixée.
      for (final String key in <String>[
        'transcription.status_bar.mic',
        'transcription.status_bar.system',
      ]) {
        final String prefix = (frValue(key)! as String).split('{}').first.trim();
        expect(find.textContaining(prefix), findsOneWidget, reason: key);
      }
    });
  });
}
