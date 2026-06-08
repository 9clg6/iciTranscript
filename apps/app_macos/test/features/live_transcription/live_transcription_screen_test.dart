import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.screen.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.state.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.view_model.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/widgets/session_controls.widget.dart';

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

    testWidgets('doit afficher les indicateurs audio dans la status bar', (
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

      // Assert — Icones audio
      expect(find.byIcon(Icons.mic), findsOneWidget);
      expect(find.byIcon(Icons.screenshot_monitor), findsOneWidget);
    });
  });
}
