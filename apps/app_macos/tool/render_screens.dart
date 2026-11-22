// Outil (pas une spec, hors suite normale) : rend les écrans principaux en
// PNG, clair et sombre, à deux tailles, avec les vraies polices et les
// vraies traductions.
//
//   OATS_SHOTS_DIR=/chemin fvm flutter test tool/render_screens.dart
//
// Sortie : $OATS_SHOTS_DIR (défaut : /tmp/oats-shots). Données inventées,
// faux view models et base en mémoire : aucun vrai fichier de données,
// aucun serveur, aucun réseau.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:core_domain/domain/entities/audio_device.entity.dart';
import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/enum/server_state.enum.dart';
import 'package:core_domain/domain/enum/session_status.enum.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:core_data/database/app_database.dart';
import 'package:ici_transcript/application/services/documents/document_library.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/core/providers/data/database.provider.dart';
import 'package:ici_transcript/core/providers/platform/file_picker.provider.dart';
import 'package:ici_transcript/generated/translations/locale_keys.g.dart';
import 'package:ici_transcript/application/services/session_analysis.dart';
import 'package:ici_transcript/core/providers/services/api_key_store.provider.dart';
import 'package:ici_transcript/core/providers/services/llm_dio.provider.dart';
import 'package:ici_transcript/core/providers/kernel.provider.dart';
import 'package:ici_transcript/core/providers/platform/uvx_available.provider.dart';
import 'package:ici_transcript/features/history/presentation/screens/detail/session_detail.state.dart';
import 'package:ici_transcript/features/history/presentation/screens/detail/session_detail.view_model.dart';
import 'package:ici_transcript/features/history/presentation/screens/list/session_list.view_model.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.state.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.view_model.dart';
import 'package:ici_transcript/features/onboarding/presentation/ollama_setup.state.dart';
import 'package:ici_transcript/features/onboarding/presentation/ollama_setup.view_model.dart';
import 'package:ici_transcript/features/settings/presentation/screens/settings/settings.state.dart';
import 'package:ici_transcript/features/settings/presentation/screens/settings/settings.view_model.dart';
import 'package:ici_transcript/features/settings/presentation/screens/settings/settings_dictation.view_model.dart';
import 'package:ici_transcript/application/services/dictation/dictation_controller.dart';
import 'package:ici_transcript/application/services/dictation/dictation_preferences.dart';
import 'package:ici_transcript/core/providers/services/dictation.provider.dart';
import 'package:ici_transcript/presentation/app.dart';

import '../test/helpers/document_fakes.dart';
import '../test/helpers/fake_data.dart';
import '../test/helpers/fake_view_models.dart';
import '../test/helpers/local_model_fakes.dart';
import '../test/helpers/settings_fakes.dart';

final String _outDir =
    Platform.environment['OATS_SHOTS_DIR'] ?? '/tmp/oats-shots';

final DateTime _now = DateTime.now();
DateTime _at(int daysAgo, int h, int m) =>
    DateTime(_now.year, _now.month, _now.day - daysAgo, h, m);

final List<SessionEntity> _sessions = <SessionEntity>[
  _session('s1', 'Point produit hebdo', _at(0, 9, 30), 47 * 60),
  _session('s2', 'Revue de sprint 14', _at(0, 14, 0), 63 * 60),
  _session('s3', 'Entretien candidat backend', _at(1, 11, 15), 38 * 60),
  _session('s4', 'Atelier tarifs 2027', _at(3, 10, 0), 92 * 60),
  _session('s5', 'Synchro design système', _at(3, 16, 45), 25 * 60),
  _session(
    's6',
    'Préparation du comité d’investissement avec l’équipe finance et les '
        'associés, ordre du jour et chiffres du trimestre',
    _at(6, 15, 30),
    74 * 60,
  ),
  _session('s7', 'Appel rapide fournisseur', _at(6, 17, 50), 40),
  _session('s8', 'Rétrospective trimestrielle', _at(400, 10, 0), 55 * 60),
];

SessionEntity _session(String id, String title, DateTime at, int seconds) =>
    FakeData.createSession(
      id: id,
      title: title,
      createdAt: at,
      updatedAt: at,
      durationSeconds: seconds,
      status: SessionStatus.completed,
    );

const List<String> _lines = <String>[
  'Bonjour à tous, on commence par le point sur les inscriptions.',
  'Les chiffres de la semaine sont bons, on dépasse l’objectif de huit pour '
      'cent, surtout grâce à la campagne de rentrée.',
  'Très bien. Est-ce qu’on sait d’où viennent les nouveaux comptes ?',
  'Majoritairement du parrainage, un peu du référencement.',
  'Il faudrait vérifier que le tunnel d’inscription tient la charge si la '
      'tendance continue.',
  'Je regarde avec l’équipe infra cette semaine.',
];

List<TranscriptSegmentEntity> _segments(int count) => <TranscriptSegmentEntity>[
  for (int i = 0; i < count; i++)
    TranscriptSegmentEntity(
      id: 'seg-$i',
      sessionId: 's2',
      // Deux phrases du micro, une de l'appel, et ainsi de suite.
      source: i % 3 == 2 ? AudioSource.output : AudioSource.input,
      text: _lines[i % _lines.length],
      timestampMs: i * 21000,
      createdAt: _at(0, 14, 0),
    ),
];

const String _summary = '''
Revue de fin de sprint : objectif atteint, deux sujets reportés.

## Décisions
- Le tunnel d’inscription passe en **priorité haute** pour le sprint 15.
- La campagne de parrainage est prolongée de deux semaines.

## Prochaines étapes
- Mesurer la tenue en charge du tunnel (infra).
- Préparer la démo du nouveau tableau de bord pour jeudi.
- Relancer les comptes inactifs depuis trente jours.
''';

/// fr.json lu sur disque : le cache de rootBundle ne survit pas d'un test
/// à l'autre sous l'horloge factice.
class _FrLoader extends AssetLoader {
  const _FrLoader();

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async =>
      jsonDecode(File('assets/translations/fr.json').readAsStringSync())
          as Map<String, dynamic>;
}

/// Réglages avec des micros et un long chemin de stockage.
final SettingsState _settings = SettingsState(
  availableDevices: FakeData.createAudioDeviceList()
      .where((AudioDeviceEntity d) => d.isInput)
      .toList(),
  storagePath:
      '/Users/demo/Library/Application Support/Exemple/un/chemin/assez/long',
  dbSizeMb: 182,
);

class _SettingsViewModel extends SettingsViewModel {
  _SettingsViewModel(this._state);

  final SettingsState _state;

  @override
  SettingsState build() => _state;
}

/// États de la section IA (clés inventées : seuls les 4 derniers caractères
/// existent ici).
final Map<String, SettingsState> _aiStates = <String, SettingsState>{
  'no-key': _settings,
  // Saisie puis Enregistrer pendant le rendu (offre d'autoriser l'envoi).
  'key-saved': _settings,
  'test-ok': _settings.copyWith(
    llmCloudAllowed: true,
    llmActive: LlmProviderId.anthropic,
    llmKeySuffixes: const <LlmProviderId, String>{
      LlmProviderId.anthropic: 'a1b2',
      LlmProviderId.openai: 'z9y8',
    },
    llmTests: const <LlmProviderId, LlmTestStatus>{
      LlmProviderId.anthropic: LlmTestStatus.ok,
    },
  ),
  'test-error': _settings.copyWith(
    llmCloudAllowed: true,
    llmActive: LlmProviderId.anthropic,
    llmKeySuffixes: const <LlmProviderId, String>{
      LlmProviderId.anthropic: 'a1b2',
    },
    llmTests: const <LlmProviderId, LlmTestStatus>{
      LlmProviderId.anthropic: LlmTestStatus.invalidKey,
    },
    llmModels: const <LlmProviderId, String>{
      LlmProviderId.anthropic: 'modele-exemple-long-nom-2026',
    },
  ),
  'cloud-paused': _settings.copyWith(
    llmPreferred: LlmProviderId.openai,
    llmKeySuffixes: const <LlmProviderId, String>{
      LlmProviderId.anthropic: 'a1b2',
      LlmProviderId.openai: 'z9y8',
    },
  ),
};

/// Live : enregistrement en cours, quelques phrases déjà transcrites.
class _RecordingLiveViewModel extends LiveTranscriptionViewModel {
  @override
  LiveTranscriptionState build() => LiveTranscriptionState.initial();

  @override
  Future<void> startSession() async {
    state = state.copyWith(
      isRecording: true,
      duration: const Duration(minutes: 23, seconds: 41),
      serverState: ServerState.ready,
      micPermission: 'authorized',
      screenRecordingPermission: 'authorized',
      segments: _segments(7),
      speakerLabels: const <String, int>{'seg-2': 0, 'seg-5': 1},
    );
  }

  /// Arrêter : l'état « Finalisation… » (rattrapage en cours), sans
  /// quitter l'écran.
  @override
  Future<String?> stopSession() async {
    state = state.copyWith(finalisingRemaining: const Duration(seconds: 46));
    return null;
  }

  @override
  Future<void> recheckPermissions() async {}
}

class _DictationViewModel extends DictationSettingsViewModel {
  _DictationViewModel(this._state);

  final DictationSettingsState _state;

  @override
  DictationSettingsState build() => _state;
}

/// Section Dictée : état montré et état du raccourci.
typedef _Dictation = ({DictationSettingsState state, ShortcutStatus status});

const _Dictation _dictationOn = (
  state: DictationSettingsState(accessibilityTrusted: true),
  status: ShortcutStatus.registered,
);

final Map<String, _Dictation> _dictationStates = <String, _Dictation>{
  'enabled': _dictationOn,
  'disabled': (
    state: const DictationSettingsState(
      settings: DictationSettings(enabled: false),
      accessibilityTrusted: true,
    ),
    status: ShortcutStatus.disabled,
  ),
  'shortcut-error': (
    state: const DictationSettingsState(accessibilityTrusted: true),
    status: ShortcutStatus.unavailable,
  ),
  'no-accessibility': (
    state: const DictationSettingsState(),
    status: ShortcutStatus.registered,
  ),
};
/// Note en cours de résumé : début du texte reçu, la suite arrive.
SessionDetailState _streaming(SessionDetailState s) => s.copyWith(
  summary:
      'Revue de fin de sprint : objectif atteint, deux sujets reportés.\n\n'
      '## Décisions\n- Le tunnel d’inscription passe en **priorité',
  isSummaryLoading: true,
  feedback: null,
);

/// Note en erreur : résumé coupé signalé, coach en erreur.
SessionDetailState _failed(SessionDetailState s) => s.copyWith(
  summary:
      'Revue de fin de sprint : objectif atteint, deux sujets reportés.\n'
      'Les participants ont décidé que le tunnel d’inscription serait',
  summaryIncomplete: true,
  feedbackError: LocaleKeys.llm_error_unreachable,
);

List<Override> _overrides(
  List<SessionEntity> sessions, {
  required AppDatabase db,
  required FakeFilePicker picker,
  OllamaSetupState ollama = const OllamaSetupState(),
  SettingsState? settings,
  _Dictation dictation = _dictationOn,
  SessionDetailState Function(SessionDetailState)? detail,
}) => <Override>[
  dictationSettingsViewModelProvider.overrideWith(
    () => _DictationViewModel(dictation.state),
  ),
  dictationShortcutStatusProvider.overrideWith(
    (Ref ref) => Stream<ShortcutStatus>.value(dictation.status),
  ),
  kernelProvider.overrideWith((Ref ref) async {}),
  databaseProvider.overrideWithValue(db),
  filePickerProvider.overrideWithValue(picker),
  // Jamais le vrai trousseau ni le réseau.
  apiKeyStoreProvider.overrideWithValue(InMemoryApiKeyStore()),
  llmDioProvider.overrideWithValue(
    Dio()..httpClientAdapter = RecordingHttpAdapter(),
  ),
  uvxAvailableProvider.overrideWith((Ref ref) async => true),
  ollamaSetupViewModelProvider.overrideWith(
    () => FakeOllamaSetupViewModel(ollama),
  ),
  sessionListViewModelProvider.overrideWith(
    () => FakeSessionListViewModel(sessions),
  ),
  liveTranscriptionViewModelProvider.overrideWith(_RecordingLiveViewModel.new),
  settingsViewModelProvider.overrideWith(
    () => _SettingsViewModel(settings ?? _settings),
  ),
  sessionDetailViewModelProvider.overrideWith(
    () => FakeSessionDetailViewModel(
      (String id) async => (detail ?? (SessionDetailState s) => s)(
        SessionDetailState(
          session: sessions.firstWhere((SessionEntity s) => s.id == id),
          segments: _segments(60),
          summary: _summary,
          speakers: <SpeakerTurn>[
            for (int i = 0; i < 60; i++)
              SpeakerTurn(
                speaker: (i ~/ 6) % 2,
                start: i * 21.0,
                end: i * 21.0 + 21,
                text: '',
              ),
          ],
        ),
      ),
    ),
  ),
];

/// Charge les polices déclarées (FontManifest) et la police système macOS.
Future<void> _loadFonts() async {
  final List<dynamic> manifest =
      jsonDecode(await rootBundle.loadString('FontManifest.json'))
          as List<dynamic>;
  for (final dynamic entry in manifest) {
    final Map<String, dynamic> family = entry as Map<String, dynamic>;
    final FontLoader loader = FontLoader(family['family'] as String);
    for (final dynamic font in family['fonts'] as List<dynamic>) {
      loader.addFont(
        rootBundle.load((font as Map<String, dynamic>)['asset'] as String),
      );
    }
    await loader.load();
  }
  final Uint8List sf = File('/System/Library/Fonts/SFNS.ttf').readAsBytesSync();
  await (FontLoader(
    '.AppleSystemUIFont',
  )..addFont(Future<ByteData>.value(ByteData.sublistView(sf)))).load();
}

Future<void> _shot(WidgetTester tester, GlobalKey key, String name) async {
  await tester.runAsync(() async {
    final RenderRepaintBoundary boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final ui.Image image = await boundary.toImage();
    final ByteData? png = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    final File file = File('$_outDir/$name.png');
    await file.writeAsBytes(png!.buffer.asUint8List());
    debugPrint('wrote ${file.path}');
  });
}

Future<void> _pump(WidgetTester tester, int frames) async {
  for (int i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() async {
    Directory(_outDir).createSync(recursive: true);
    await _loadFonts();
  });

  const Map<String, Size> sizes = <String, Size>{
    '1280x800': Size(1280, 800),
    '900x600': Size(900, 600),
  };

  for (final Brightness brightness in Brightness.values) {
    for (final MapEntry<String, Size> size in sizes.entries) {
      final String suffix = '${brightness.name}-${size.key}';

      Future<GlobalKey> pumpApp(
        WidgetTester tester,
        List<SessionEntity> sessions, {
        OllamaSetupState ollama = const OllamaSetupState(),
        SettingsState? settings,
        _Dictation dictation = _dictationOn,
        SessionDetailState Function(SessionDetailState)? detail,
        AppDatabase? db,
        FakeFilePicker? picker,
      }) async {
        final AppDatabase base = db ?? memoryDatabase();
        addTearDown(base.close);
        tester.view.physicalSize = size.value;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(() {
          tester.view.reset();
          tester.platformDispatcher.clearPlatformBrightnessTestValue();
        });
        final GlobalKey key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: ProviderScope(
              overrides: _overrides(
                sessions,
                db: base,
                picker: picker ?? FakeFilePicker(),
                ollama: ollama,
                settings: settings,
                dictation: dictation,
                detail: detail,
              ),
              child: EasyLocalization(
                supportedLocales: const <Locale>[Locale('fr')],
                path: 'assets/translations',
                fallbackLocale: const Locale('fr'),
                startLocale: const Locale('fr'),
                saveLocale: false,
                assetLoader: const _FrLoader(),
                child: const RootAppWidget(),
              ),
            ),
          ),
        );
        // Les traductions se chargent hors de l'horloge factice du test.
        final Finder sidebar = find.byKey(
          const ValueKey<String>('oats-sidebar'),
        );
        for (int i = 0; i < 50 && sidebar.evaluate().isEmpty; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }
        await _pump(tester, 10);
        return key;
      }

      // Plateforme macOS pendant le rendu (interrupteurs, défilement),
      // remise à zéro avant la fin du test comme l'exige flutter_test.
      void shoot(String name, Future<void> Function(WidgetTester) body) {
        testWidgets('$name $suffix', (WidgetTester tester) async {
          debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
          try {
            await body(tester);
          } finally {
            debugDefaultTargetPlatformOverride = null;
          }
        });
      }

      shoot('home', (WidgetTester tester) async {
        final GlobalKey key = await pumpApp(tester, _sessions);
        await _shot(tester, key, 'home-$suffix');
      });

      shoot('home-empty', (WidgetTester tester) async {
        final GlobalKey key = await pumpApp(tester, <SessionEntity>[]);
        await _shot(tester, key, 'home-empty-$suffix');
      });

      shoot('detail', (WidgetTester tester) async {
        final GlobalKey key = await pumpApp(tester, _sessions);
        await tester.tap(find.text('Revue de sprint 14'));
        await _pump(tester, 10);
        await _shot(tester, key, 'detail-$suffix');
        await tester.drag(
          find.text('Revue de sprint 14'),
          const Offset(0, -900),
        );
        await _pump(tester, 10);
        await _shot(tester, key, 'detail-scrolled-$suffix');
      });

      shoot('settings', (WidgetTester tester) async {
        final GlobalKey key = await pumpApp(tester, _sessions);
        await tester.tap(find.text('Réglages'));
        await _pump(tester, 10);
        await _shot(tester, key, 'settings-$suffix');
        await tester.drag(find.text('Audio'), const Offset(0, -700));
        await _pump(tester, 10);
        await _shot(tester, key, 'settings-scrolled-$suffix');
      });

      // Modèle local : installé, puis en erreur d'installation.
      for (final MapEntry<String, OllamaSetupState> m
          in <String, OllamaSetupState>{
            'ready': kOllamaReady,
            'error': kOllamaAbsent,
          }.entries) {
        shoot('settings-${m.key}', (WidgetTester tester) async {
          final GlobalKey key = await pumpApp(
            tester,
            _sessions,
            ollama: m.value,
          );
          await tester.tap(find.text('Réglages'));
          await _pump(tester, 10);
          await tester.drag(find.text('Audio'), const Offset(0, -250));
          await _pump(tester, 10);
          await _shot(tester, key, 'settings-model-${m.key}-$suffix');
        });
      }

      // Section IA : titre en haut, puis blocs des fournisseurs.
      for (final MapEntry<String, SettingsState> ai in _aiStates.entries) {
        shoot('settings-ai-${ai.key}', (WidgetTester tester) async {
          final GlobalKey key = await pumpApp(
            tester,
            _sessions,
            settings: ai.value,
          );
          await tester.tap(find.text('Réglages'));
          await _pump(tester, 10);
          final Finder title = find.text('Intelligence artificielle');
          await tester.ensureVisible(title);
          await _pump(tester, 5);
          await tester.drag(title, Offset(0, 40 - tester.getTopLeft(title).dy));
          await _pump(tester, 10);
          if (ai.key == 'key-saved') {
            // Vraie saisie dans le trousseau factice : clé inventée.
            final Finder field = find.descendant(
              of: find.byKey(const ValueKey<String>('llm-anthropic')),
              matching: find.byType(TextField),
            );
            await tester.enterText(field.first, 'exemple-cle-inventee-a1b2');
            await tester.tap(find.text('Enregistrer').first);
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 50)),
            );
            await _pump(tester, 10);
          }
          await _shot(tester, key, 'settings-ai-${ai.key}-$suffix');
          await tester.drag(title, Offset(0, -(size.value.height - 200)));
          await _pump(tester, 10);
          await _shot(tester, key, 'settings-ai-${ai.key}-blocks-$suffix');
        });
      }

      // Section Dictée : activée, coupée, raccourci pris, sans Accessibilité.
      for (final MapEntry<String, _Dictation> dictation
          in _dictationStates.entries) {
        shoot('settings-dictation-${dictation.key}', (
          WidgetTester tester,
        ) async {
          final GlobalKey key = await pumpApp(
            tester,
            _sessions,
            dictation: dictation.value,
          );
          await tester.tap(find.text('Réglages'));
          await _pump(tester, 10);
          final Finder title = find.text('Dictée');
          await tester.ensureVisible(title);
          await _pump(tester, 5);
          await tester.drag(title, Offset(0, 40 - tester.getTopLeft(title).dy));
          await _pump(tester, 10);
          await _shot(
            tester,
            key,
            'settings-dictation-${dictation.key}-$suffix',
          );
        });
      }

      shoot('pages', (WidgetTester tester) async {
        final GlobalKey key = await pumpApp(tester, _sessions);
        await tester.enterText(find.byType(TextField), 'budget');
        await _pump(tester, 5);
        await _shot(tester, key, 'home-no-result-$suffix');
        await tester.tap(find.text('Documents'));
        await _pump(tester, 5);
        await _shot(tester, key, 'documents-$suffix');
        await tester.tap(find.text('Coach anglais'));
        await _pump(tester, 5);
        await _shot(tester, key, 'coach-$suffix');
        await tester.tap(find.text('Accueil'));
        await _pump(tester, 5);
        await _shot(tester, key, 'home-search-kept-$suffix');
        await tester.enterText(find.byType(TextField), '');
        await _pump(tester, 5);
        await tester.tap(find.text('Point produit hebdo'));
        await _pump(tester, 10);
        await tester.tap(find.text('Supprimer'));
        await _pump(tester, 10);
        await _shot(tester, key, 'delete-dialog-$suffix');
      });

      // Documents : liste (titres inventés), puis un ajout refusé.
      shoot('documents-list', (WidgetTester tester) async {
        final AppDatabase db = memoryDatabase();
        final Directory dir = tempFolder();
        final FakeFilePicker picker = FakeFilePicker();
        await tester.runAsync(() async {
          final DocumentLibrary library = DocumentLibrary(db);
          for (final String name in <String>[
            'Plan de recrutement 2027 pour les équipes produit, design, '
                'données et support client.md',
            'Tarifs.txt',
            'Compte rendu du comité.md',
          ]) {
            await library.importFile(
              writeFile(
                dir,
                name,
                List<String>.filled(40, _lines[1]).join('\n\n'),
              ),
            );
          }
        });
        final GlobalKey key = await pumpApp(
          tester,
          _sessions,
          db: db,
          picker: picker,
        );
        await tester.tap(find.text('Documents'));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await _pump(tester, 5);
        await _shot(tester, key, 'documents-list-$suffix');
        picker.next = <String>[
          writeFile(dir, 'Contrat fournisseur signé version finale.docx', 'x'),
          writeFile(dir, 'vide.txt', '  '),
        ];
        await tester.tap(find.text('Ajouter un document'));
        for (
          int i = 0;
          i < 30 &&
              (i < 3 || find.text('Import en cours…').evaluate().isNotEmpty);
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await _pump(tester, 1);
        }
        await _pump(tester, 5);
        await _shot(tester, key, 'documents-error-$suffix');
      });

      // Note : résumé au fil de l'eau, puis états d'erreur.
      for (final MapEntry<
            String,
            SessionDetailState Function(SessionDetailState)
          >
          d
          in <String, SessionDetailState Function(SessionDetailState)>{
            'streaming': _streaming,
            'error': _failed,
          }.entries) {
        shoot('detail-${d.key}', (WidgetTester tester) async {
          final GlobalKey key = await pumpApp(
            tester,
            _sessions,
            ollama: kOllamaReady,
            detail: d.value,
          );
          await tester.tap(find.text('Revue de sprint 14'));
          await _pump(tester, 10);
          await _shot(tester, key, 'detail-${d.key}-$suffix');
        });
      }

      shoot('live', (WidgetTester tester) async {
        final GlobalKey key = await pumpApp(tester, _sessions);
        await tester.tap(find.text('Nouvelle note'));
        await _pump(tester, 10);
        await _shot(tester, key, 'live-$suffix');
      });

      shoot('live-finalising', (WidgetTester tester) async {
        final GlobalKey key = await pumpApp(tester, _sessions);
        await tester.tap(find.text('Nouvelle note'));
        await _pump(tester, 10);
        await tester.tap(find.text('Arrêter'));
        await _pump(tester, 10);
        await _shot(tester, key, 'live-finalising-$suffix');
      });
    }
  }
}
