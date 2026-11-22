import 'package:core_domain/domain/entities/audio_device.entity.dart';
import 'package:ici_transcript/application/services/llm/api_key_store.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/application/services/llm/llm_settings.dart';
import 'package:ici_transcript/core/platform/app_data_directory.dart';
import 'package:ici_transcript/core/platform/prefs_store.dart';
import 'package:ici_transcript/core/providers/platform/audio_capture.provider.dart';
import 'package:ici_transcript/core/providers/platform/prefs_store.provider.dart';
import 'package:ici_transcript/core/providers/services/active_llm_provider.provider.dart';
import 'package:ici_transcript/core/providers/services/api_key_store.provider.dart';
import 'package:ici_transcript/core/providers/services/llm_dio.provider.dart';
import 'package:ici_transcript/features/settings/presentation/screens/settings/settings.state.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'settings.view_model.g.dart';

const String _micKey = 'selected_mic_id';
const String _systemAudioKey = 'system_audio_enabled';

/// Fournisseurs en ligne (avec clé API).
const List<LlmProviderId> kCloudLlmProviders = <LlmProviderId>[
  LlmProviderId.anthropic,
  LlmProviderId.openai,
  LlmProviderId.gemini,
];

/// ViewModel de l'ecran des reglages.
///
/// Gere la configuration audio, serveur ML, raccourcis, stockage et IA.
@Riverpod(keepAlive: true)
class SettingsViewModel extends _$SettingsViewModel {
  PrefsStore get _prefs => ref.read(prefsStoreProvider);
  ApiKeyStore get _keys => ref.read(apiKeyStoreProvider);

  @override
  SettingsState build() {
    _init();
    return SettingsState.initial();
  }

  Future<void> _init() async {
    final List<AudioDeviceEntity> devices = await ref
        .read(audioCaptureChannelProvider)
        .listDevices();
    final List<AudioDeviceEntity> inputDevices = devices
        .where((AudioDeviceEntity d) => d.isInput)
        .toList();

    final Map<String, Object?> prefs = await _prefs.read();
    final String? savedMicId = prefValue<String>(prefs, _micKey);
    final LlmSettings llm = LlmSettings.fromPrefs(prefs);

    final Map<LlmProviderId, String> suffixes = <LlmProviderId, String>{};
    final Set<LlmProviderId> keyErrors = <LlmProviderId>{};
    for (final LlmProviderId id in kCloudLlmProviders) {
      try {
        final String? key = await _keys.read(id);
        if (key != null) suffixes[id] = _last4(key);
      } on Object {
        keyErrors.add(id);
      }
    }
    final LlmProviderId active = await _resolve(llm);
    if (!ref.mounted) return;

    final String? resolvedMicId =
        savedMicId != null &&
            inputDevices.any((AudioDeviceEntity d) => d.id == savedMicId)
        ? savedMicId
        : null;

    state = state.copyWith(
      storagePath: appDataDirectory(),
      dbSizeMb: 124.0,
      systemAudioEnabled: prefValue<bool>(prefs, _systemAudioKey) ?? true,
      autoStartServer: true,
      serverPort: '8000',
      availableDevices: inputDevices,
      selectedMicId: resolvedMicId,
      llmCloudAllowed: llm.cloudAllowed,
      llmPreferred: llm.preferred,
      llmModels: llm.models,
      llmKeySuffixes: suffixes,
      llmKeyErrors: keyErrors,
      llmActive: active,
    );
  }

  /// Met a jour le microphone selectionne.
  Future<void> updateMic(String id) async {
    state = state.copyWith(selectedMicId: id);
    await _prefs.update(<String, Object?>{_micKey: id});
  }

  /// Active ou desactive la capture audio systeme.
  Future<void> toggleSystemAudio() async {
    final bool newValue = !state.systemAudioEnabled;
    state = state.copyWith(systemAudioEnabled: newValue);
    await _prefs.update(<String, Object?>{_systemAudioKey: newValue});
  }

  /// Active ou desactive le lancement automatique du serveur.
  void toggleAutoStart() {
    state = state.copyWith(autoStartServer: !state.autoStartServer);
  }

  /// Met a jour le port du serveur ML.
  void updatePort(String port) {
    state = state.copyWith(serverPort: port);
  }

  /// Range [key] au trousseau (jamais dans prefs.json) ; saisie vide = rien.
  Future<void> saveApiKey(LlmProviderId id, String key) async {
    final String trimmed = key.trim();
    if (trimmed.isEmpty) return;
    try {
      await _keys.write(id, trimmed);
    } on Object {
      // Ni l'erreur ni la clé ne sont journalisées.
      state = state.copyWith(
        llmKeyErrors: <LlmProviderId>{...state.llmKeyErrors, id},
      );
      return;
    }
    state = state.copyWith(
      llmKeySuffixes: <LlmProviderId, String>{
        ...state.llmKeySuffixes,
        id: _last4(trimmed),
      },
      llmKeyErrors: <LlmProviderId>{...state.llmKeyErrors}..remove(id),
      llmTests: <LlmProviderId, LlmTestStatus>{...state.llmTests}..remove(id),
    );
    await _llmChanged();
  }

  /// Retire la clé de [id] du trousseau, sans confirmation.
  Future<void> removeApiKey(LlmProviderId id) async {
    try {
      await _keys.delete(id);
    } on Object {
      state = state.copyWith(
        llmKeyErrors: <LlmProviderId>{...state.llmKeyErrors, id},
      );
      return;
    }
    state = state.copyWith(
      llmKeySuffixes: <LlmProviderId, String>{...state.llmKeySuffixes}
        ..remove(id),
      llmKeyErrors: <LlmProviderId>{...state.llmKeyErrors}..remove(id),
      llmTests: <LlmProviderId, LlmTestStatus>{...state.llmTests}..remove(id),
    );
    await _llmChanged();
  }

  /// Choisit le fournisseur ; un fournisseur en ligne n'est pas retenu tant
  /// que l'envoi en ligne est coupé.
  Future<void> selectLlmProvider(LlmProviderId id) async {
    if (id != LlmProviderId.ollama && !state.llmCloudAllowed) return;
    state = state.copyWith(llmPreferred: id);
    await _prefs.update(<String, Object?>{LlmSettings.providerKey: id.name});
    await _llmChanged();
  }

  /// Modèle de [id] ; vide = modèle par défaut.
  Future<void> updateLlmModel(LlmProviderId id, String model) async {
    final String trimmed = model.trim();
    final Map<LlmProviderId, String> models = <LlmProviderId, String>{
      ...state.llmModels,
    }..remove(id);
    if (trimmed.isNotEmpty) models[id] = trimmed;
    state = state.copyWith(llmModels: models);
    await _prefs.update(<String, Object?>{
      LlmSettings.modelsKey: <String, String>{
        for (final MapEntry<LlmProviderId, String> e in models.entries)
          e.key.name: e.value,
      },
    });
    await _llmChanged();
  }

  /// Autorise ou coupe l'envoi à un service en ligne.
  Future<void> setCloudAllowed(bool allowed) async {
    state = state.copyWith(llmCloudAllowed: allowed);
    await _prefs.update(<String, Object?>{
      LlmSettings.cloudAllowedKey: allowed,
    });
    await _llmChanged();
  }

  /// Envoie une requête minimale à [id] avec sa clé rangée et range le
  /// résultat. Rien ne part sans autorisation d'envoi ni sans clé.
  Future<void> testLlmProvider(LlmProviderId id) async {
    if (id == LlmProviderId.ollama || !state.llmCloudAllowed) return;
    final String? key;
    try {
      key = await _keys.read(id);
    } on Object {
      state = state.copyWith(
        llmKeyErrors: <LlmProviderId>{...state.llmKeyErrors, id},
      );
      return;
    }
    if (key == null) return;
    _setTest(id, LlmTestStatus.testing);
    try {
      await buildLlmProvider(
        id,
        dio: ref.read(llmDioProvider),
        apiKey: key,
        model: _settings.modelFor(id),
      ).streamChat(_ping).drain<void>();
      _setTest(id, LlmTestStatus.ok);
    } on LlmInvalidKeyException {
      _setTest(id, LlmTestStatus.invalidKey);
    } on LlmRateLimitedException {
      _setTest(id, LlmTestStatus.rateLimited);
    } on LlmUnreachableException {
      _setTest(id, LlmTestStatus.unreachable);
    } on Object {
      _setTest(id, LlmTestStatus.failed);
    }
  }

  static const LlmChatRequest _ping = LlmChatRequest(
    systemPrompt: 'Réponds seulement « OK ».',
    messages: <LlmMessage>[LlmMessage(role: LlmRole.user, content: 'Test')],
    maxTokens: 16,
  );

  void _setTest(LlmProviderId id, LlmTestStatus status) {
    if (!ref.mounted) return;
    state = state.copyWith(
      llmTests: <LlmProviderId, LlmTestStatus>{...state.llmTests, id: status},
    );
  }

  LlmSettings get _settings => LlmSettings(
    cloudAllowed: state.llmCloudAllowed,
    preferred: state.llmPreferred,
    models: state.llmModels,
  );

  /// Le fournisseur actif relit ses choix à la prochaine requête ; le menu
  /// montre celui réellement utilisé.
  Future<void> _llmChanged() async {
    ref.invalidate(activeLlmProviderProvider);
    final LlmProviderId active = await _resolve(_settings);
    if (ref.mounted) state = state.copyWith(llmActive: active);
  }

  Future<LlmProviderId> _resolve(LlmSettings settings) =>
      resolveActiveLlmProvider(_keys, settings);

  // Une clé trop courte n'est jamais montrée, même en partie.
  static String _last4(String key) =>
      key.length < 8 ? '' : key.substring(key.length - 4);
}
