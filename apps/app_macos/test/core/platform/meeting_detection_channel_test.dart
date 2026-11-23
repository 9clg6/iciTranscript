import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/core/platform/meeting_detection_channel.dart';

import '../../helpers/calendar_fakes.dart';

// Côté Dart de la surveillance du micro (T5, besoins 5 et 7). Contrat du
// canal `com.icitranscript/meeting_detection` : voir
// test/helpers/calendar_fakes.dart. Côté Swift (macOS 14+) :
// kAudioHardwarePropertyProcessObjectList + kAudioProcessPropertyBundleID +
// kAudioProcessPropertyIsRunningInput, en excluant le processus d'Oats.
// L'app au premier plan n'est PAS utilisée.
//
// API supposée (lib/core/platform/meeting_detection_channel.dart) :
// `class MeetingDetectionChannel` (`const MeetingDetectionChannel()`),
// `Future<bool> start()` (false si non pris en charge, y compris quand le
// plugin Swift manque), `Future<void> stop()`,
// `Stream<Set<String>> get micUsers` ;
// et `meetingDetectionChannelProvider`
// (lib/core/providers/platform/meeting_detection_channel.provider.dart).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MeetingDetectionChannel channel = MeetingDetectionChannel();

  test('start : true quand la surveillance tourne (macOS 14+)', () async {
    final FakeMeetingPlatform platform = FakeMeetingPlatform()..install();

    expect(await channel.start(), isTrue);
    expect(platform.calls.single.method, 'start');
  });

  test(
    'start : false quand Swift dit non pris en charge (macOS < 14)',
    () async {
      FakeMeetingPlatform(supported: false).install();

      expect(await channel.start(), isFalse);
    },
  );

  test(
    'start : false, sans erreur, quand le plugin Swift est absent',
    () async {
      // Aucun faux installé : MissingPluginException côté Dart.
      expect(await channel.start(), isFalse);
    },
  );

  test('stop appelle Swift', () async {
    final FakeMeetingPlatform platform = FakeMeetingPlatform()..install();

    await channel.stop();

    expect(platform.calls.single.method, 'stop');
  });

  test(
    'chaque instantané « micUsers » émet l\'ensemble des bundle ids',
    () async {
      final FakeMeetingPlatform platform = FakeMeetingPlatform()..install();
      final List<Set<String>> seen = <Set<String>>[];
      final StreamSubscription<Set<String>> sub = channel.micUsers.listen(
        seen.add,
      );
      addTearDown(sub.cancel);

      await platform.micUsers(<String>['us.zoom.xos', 'com.google.Chrome']);
      await platform.micUsers(<String>[]);
      await Future<void>.delayed(Duration.zero);

      expect(seen, <Set<String>>[
        <String>{'us.zoom.xos', 'com.google.Chrome'},
        <String>{},
      ]);
    },
  );
}
