import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/core/platform/global_shortcut_channel.dart';

/// Côté Dart du raccourci global de la dictée (T2). Les noms de méthodes et
/// les charges utiles ci-dessous sont le contrat du plugin Swift :
///
/// MethodChannel `com.icitranscript/global_shortcut`
/// - `register` {keyCode: int (code de touche macOS), modifiers: int (masque
///   Carbon : cmd 256, shift 512, option 2048, control 4096)} → null ; lève
///   PlatformException `SHORTCUT_UNAVAILABLE` si le raccourci est déjà pris.
/// - `unregister` → null.
/// - `setCancelKeyEnabled` {enabled: bool} : Échap n'est capturée que
///   pendant une dictée, sinon elle serait volée à toutes les apps.
///
/// - `keyLabel` : voir global_shortcut_key_label_test.dart.
///
/// EventChannel `com.icitranscript/global_shortcut_events`
/// - {type: 'pressed' | 'released' | 'cancel'} ; tout autre type est ignoré.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel method = MethodChannel(
    'com.icitranscript/global_shortcut',
  );
  const EventChannel events = EventChannel(
    'com.icitranscript/global_shortcut_events',
  );
  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final List<MethodCall> calls = <MethodCall>[];

  void answer(Object? Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(method, (MethodCall call) async {
      calls.add(call);
      return handler(call);
    });
  }

  setUp(calls.clear);
  tearDown(() {
    messenger.setMockMethodCallHandler(method, null);
    messenger.setMockStreamHandler(events, null);
  });

  test('register envoie le code de touche et les modificateurs, vrai si '
      'enregistré', () async {
    answer((_) => null);

    final bool ok = await GlobalShortcutChannel().register(
      keyCode: 49,
      modifiers: 2048,
    );

    expect(ok, isTrue);
    expect(calls.single.method, 'register');
    expect(calls.single.arguments, <String, Object>{
      'keyCode': 49,
      'modifiers': 2048,
    });
  });

  test('raccourci déjà pris : faux, sans lever', () async {
    answer((_) => throw PlatformException(code: 'SHORTCUT_UNAVAILABLE'));

    final bool ok = await GlobalShortcutChannel().register(
      keyCode: 49,
      modifiers: 2048,
    );

    expect(ok, isFalse);
  });

  test(
    'plugin absent : faux, sans lever (jamais un succès silencieux)',
    () async {
      final bool ok = await GlobalShortcutChannel().register(
        keyCode: 49,
        modifiers: 2048,
      );

      expect(ok, isFalse);
    },
  );

  test('unregister et armement d Échap', () async {
    answer((_) => null);
    final GlobalShortcutChannel channel = GlobalShortcutChannel();

    await channel.setCancelKeyEnabled(true);
    await channel.setCancelKeyEnabled(false);
    await channel.unregister();

    expect(
      calls.map((MethodCall c) => '${c.method} ${c.arguments}').toList(),
      <String>[
        'setCancelKeyEnabled {enabled: true}',
        'setCancelKeyEnabled {enabled: false}',
        'unregister null',
      ],
    );
  });

  test(
    'événements : appui, relâchement, annulation ; type inconnu ignoré',
    () async {
      messenger.setMockStreamHandler(
        events,
        MockStreamHandler.inline(
          onListen: (Object? arguments, MockStreamHandlerEventSink sink) {
            sink
              ..success(<String, Object>{'type': 'pressed'})
              ..success(<String, Object>{'type': 'released'})
              ..success(<String, Object>{'type': 'autre'})
              ..success(<String, Object>{'type': 'cancel'});
          },
        ),
      );
      final List<ShortcutEvent> seen = <ShortcutEvent>[];

      final StreamSubscription<ShortcutEvent> sub = GlobalShortcutChannel()
          .events
          .listen(seen.add);
      await pumpEventQueue();
      await sub.cancel();

      expect(seen, <ShortcutEvent>[
        ShortcutEvent.pressed,
        ShortcutEvent.released,
        ShortcutEvent.cancel,
      ]);
    },
  );
}
