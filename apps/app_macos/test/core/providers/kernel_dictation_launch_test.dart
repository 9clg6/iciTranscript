import 'dart:async';
import 'dart:io';

import 'package:core_data/database/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/dictation/dictation_preferences.dart';
import 'package:ici_transcript/core/platform/app_data_directory.dart';
import 'package:ici_transcript/core/providers/data/database.provider.dart';
import 'package:ici_transcript/core/providers/kernel.provider.dart';
import 'package:ici_transcript/core/providers/platform/audio_capture.provider.dart';
import 'package:ici_transcript/core/providers/platform/process_manager.provider.dart';
import 'package:ici_transcript/core/providers/services/dictation.provider.dart';

import '../../helpers/dictation_fakes.dart';
import '../../helpers/live_service_fakes.dart';

/// Dictée (T2) au lancement : les réglages lus dans prefs.json sont
/// appliqués par le kernel ; dictée activée, le serveur est démarré tout de
/// suite (un démarrage à froid de ~10 s rendrait le premier appui
/// inutilisable), sans retarder le lancement.
///
/// API supposée, dans lib/core/providers/services/dictation.provider.dart :
/// `globalShortcutChannelProvider` et `textOutputChannelProvider`
/// (keepAlive), à côté de `dictationShortcutStatusProvider`.
void main() {
  final File prefs = File('${appDataDirectory()}/prefs.json');
  late FakeProcessManagerChannel process;
  late FakeGlobalShortcutChannel shortcuts;
  late ProviderContainer container;

  setUp(() {
    expect(prefs.path, startsWith(Directory.systemTemp.path));
    if (prefs.existsSync()) prefs.deleteSync();
    process = FakeProcessManagerChannel();
    shortcuts = FakeGlobalShortcutChannel();
    container = ProviderContainer(
      overrides: <Override>[
        databaseProvider.overrideWithValue(
          AppDatabase(NativeDatabase.memory()),
        ),
        processManagerChannelProvider.overrideWithValue(process),
        audioCaptureChannelProvider.overrideWithValue(
          FakeAudioCaptureChannel(),
        ),
        globalShortcutChannelProvider.overrideWithValue(shortcuts),
        textOutputChannelProvider.overrideWithValue(FakeTextOutputChannel()),
      ],
    );
    addTearDown(container.dispose);
  });

  /// Attend (au plus 2 s) que [done] soit vrai.
  Future<void> eventually(bool Function() done) async {
    for (int i = 0; i < 200 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test('dictée activée : le raccourci de prefs.json est enregistré et le '
      'serveur démarré, une fois', () async {
    await DictationPreferences().save(
      const DictationSettings(
        shortcut: DictationShortcut(keyCode: 2, modifiers: 4608),
      ),
    );

    await container.read(kernelProvider.future);
    await eventually(
      () => shortcuts.registered.isNotEmpty && process.starts.isNotEmpty,
    );

    expect(shortcuts.registered, <({int keyCode, int modifiers})>[
      (keyCode: 2, modifiers: 4608),
    ]);
    expect(process.starts, hasLength(1));
  });

  test('dictée désactivée : ni raccourci ni serveur au lancement', () async {
    await DictationPreferences().save(const DictationSettings(enabled: false));

    await container.read(kernelProvider.future);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(shortcuts.registered, isEmpty);
    expect(process.starts, isEmpty);
  });

  test('le lancement n attend pas que le serveur soit prêt', () async {
    process.startDuration = const Duration(seconds: 5);

    await container
        .read(kernelProvider.future)
        .timeout(const Duration(seconds: 1));
    await eventually(() => process.starts.isNotEmpty);

    expect(process.starts, hasLength(1));
  });
}
