import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/live_answers/live_question.dart';
import 'package:ici_transcript/application/services/recording_storage.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.screen.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.state.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.view_model.dart';
import 'package:ici_transcript/features/status_panel/status_panel_snapshot.dart';

import '../../helpers/fake_view_models.dart';
import '../../helpers/localized_app.dart';

// Place disque : ce que voient l'écran de la note et le panneau de la barre
// de menus (règles : recording_storage_test.dart).
//
// API supposée :
// - `LiveTranscriptionState.storage` (`RecordingStorage`, défaut : tout va
//   bien), alimenté par `LiveTranscriptionService.storageStream` ;
// - écran de la note : `ValueKey<String>('storage-warning')` (peu de place,
//   le texte donne les minutes restantes), `'storage-critical'` (moins de
//   200 Mo), `'storage-audio-copy'` (écriture WAV ratée : le rattrapage ne
//   couvrira pas ce passage), `'storage-unsaved'` (phrases pas encore
//   rangées) ;
// - panneau : clé `storage` du `statusPanelSnapshot`, null si tout va bien,
//   sinon `{level: 'low'|'critical'|'ok', minutesLeft: int?,
//   audioCopyFailing: bool, unsavedLines: int}` (seulement des types du
//   canal).
LiveTranscriptionState _recording(RecordingStorage storage) =>
    LiveTranscriptionState.initial().copyWith(
      isRecording: true,
      storage: storage,
    );

void main() {
  group('panneau de la barre de menus', () {
    Map<String, Object?> snap(RecordingStorage storage) => statusPanelSnapshot(
      live: _recording(storage),
      questions: const <LiveQuestion>[],
      suggestion: null,
      dictating: false,
    );

    test('tout va bien : pas de clé storage', () {
      expect(snap(const RecordingStorage())['storage'], isNull);
    });

    test('peu de place : niveau et minutes restantes', () {
      expect(
        snap(
          const RecordingStorage(
            level: StorageLevel.low,
            recordingTimeLeft: Duration(minutes: 95),
          ),
        )['storage'],
        <String, Object?>{
          'level': 'low',
          'minutesLeft': 95,
          'audioCopyFailing': false,
          'unsavedLines': 0,
        },
      );
    });

    test('critique, copie audio en échec, phrases non rangées', () {
      expect(
        snap(
          const RecordingStorage(
            level: StorageLevel.critical,
            recordingTimeLeft: Duration(minutes: 40),
            audioCopyFailing: true,
            unsavedLines: 3,
          ),
        )['storage'],
        <String, Object?>{
          'level': 'critical',
          'minutesLeft': 40,
          'audioCopyFailing': true,
          'unsavedLines': 3,
        },
      );
    });
  });

  group('écran de la note', () {
    late FakeLiveTranscriptionViewModel vm;
    late List<Override> overrides;

    setUp(() {
      vm = FakeLiveTranscriptionViewModel();
      overrides = <Override>[
        liveTranscriptionViewModelProvider.overrideWith(() => vm),
      ];
    });

    Future<void> show(WidgetTester tester, RecordingStorage storage) async {
      await pumpLocalized(
        tester,
        const LiveTranscriptionScreen(),
        overrides: overrides,
        settle: false,
      );
      vm.show(_recording(storage));
      await tester.pump();
    }

    String textOf(WidgetTester tester, Finder f) => tester
        .widgetList<Text>(find.descendant(of: f, matching: find.byType(Text)))
        .map((Text t) => t.data ?? t.textSpan?.toPlainText() ?? '')
        .join(' ');

    testWidgets('peu de place : avertissement avec le temps restant', (
      WidgetTester tester,
    ) async {
      await show(
        tester,
        const RecordingStorage(
          level: StorageLevel.low,
          recordingTimeLeft: Duration(minutes: 95),
        ),
      );
      final Finder w = find.byKey(const ValueKey<String>('storage-warning'));
      expect(w, findsOneWidget);
      expect(textOf(tester, w), anyOf(contains('95'), contains('1 h 35')));
    });

    testWidgets('moins de 200 Mo : erreur claire', (WidgetTester tester) async {
      await show(
        tester,
        const RecordingStorage(
          level: StorageLevel.critical,
          recordingTimeLeft: Duration(minutes: 40),
        ),
      );
      expect(
        find.byKey(const ValueKey<String>('storage-critical')),
        findsOneWidget,
      );
    });

    testWidgets('écriture WAV ratée et phrases non rangées : dit tout de '
        'suite', (WidgetTester tester) async {
      await show(
        tester,
        const RecordingStorage(audioCopyFailing: true, unsavedLines: 2),
      );
      expect(
        find.byKey(const ValueKey<String>('storage-audio-copy')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('storage-unsaved')),
        findsOneWidget,
      );
    });

    testWidgets('la place revient : plus rien', (WidgetTester tester) async {
      await show(
        tester,
        const RecordingStorage(
          level: StorageLevel.low,
          recordingTimeLeft: Duration(minutes: 95),
        ),
      );
      vm.show(_recording(const RecordingStorage()));
      await tester.pump();
      for (final String key in <String>[
        'storage-warning',
        'storage-critical',
        'storage-audio-copy',
        'storage-unsaved',
      ]) {
        expect(find.byKey(ValueKey<String>(key)), findsNothing, reason: key);
      }
    });
  });
}
