import 'dart:typed_data';

import 'package:ici_transcript/application/services/gap_backfill.service.dart';
import 'package:ici_transcript/application/services/llm/api_key_store.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/application/services/llm/llm_settings.dart';
import 'package:ici_transcript/core/platform/prefs_store.dart';

/// Moteur de transcription : sur ce Mac (voxmlx local) ou Mistral en ligne.
enum TranscriptionEngine {
  /// voxmlx sur ce Mac (serveur local).
  local,

  /// Mistral Voxtral en ligne : aucun serveur local.
  mistral,
}

/// Pourquoi le moteur en ligne choisi n'est pas utilisé.
enum TranscriptionEngineRefusal {
  /// L'envoi à un service en ligne est coupé (interrupteur de l'IA).
  cloudNotAllowed,

  /// Pas de clé Mistral au trousseau.
  missingKey,
}

/// Choix du moteur, lu dans prefs.json.
class TranscriptionEngineSettings {
  /// Cree une instance de [TranscriptionEngineSettings].
  const TranscriptionEngineSettings({this.engine = TranscriptionEngine.local});

  /// Lit [engineKey] ; absent ou inattendu : [TranscriptionEngine.local].
  factory TranscriptionEngineSettings.fromPrefs(Map<String, Object?> prefs) =>
      TranscriptionEngineSettings(
        engine:
            TranscriptionEngine.values.asNameMap()[prefValue<String>(
              prefs,
              engineKey,
            )] ??
            TranscriptionEngine.local,
      );

  /// Clé dans prefs.json : `local` | `mistral`.
  static const String engineKey = 'transcription_engine';

  /// Moteur choisi.
  final TranscriptionEngine engine;
}

/// Seule décision du moteur utilisé : Mistral seulement si l'envoi en ligne
/// est permis ET la clé Mistral rangée ; sinon sur ce Mac, avec la raison.
class TranscriptionEngineSelection {
  /// Cree une instance de [TranscriptionEngineSelection].
  TranscriptionEngineSelection(this._keys);

  final ApiKeyStore _keys;

  /// Moteur utilisé pour [chosen], et pourquoi pas celui choisi.
  Future<({TranscriptionEngine engine, TranscriptionEngineRefusal? refusal})>
  resolve({
    required TranscriptionEngine chosen,
    required bool cloudAllowed,
  }) async {
    if (chosen == TranscriptionEngine.local) {
      return (engine: TranscriptionEngine.local, refusal: null);
    }
    if (!cloudAllowed) {
      return (
        engine: TranscriptionEngine.local,
        refusal: TranscriptionEngineRefusal.cloudNotAllowed,
      );
    }
    final String? key = await _keys.read(LlmProviderId.mistral);
    if (key == null || key.isEmpty) {
      return (
        engine: TranscriptionEngine.local,
        refusal: TranscriptionEngineRefusal.missingKey,
      );
    }
    return (engine: TranscriptionEngine.mistral, refusal: null);
  }

  /// Moteur utilisé d'après prefs.json : le choix, l'interrupteur d'envoi
  /// en ligne de l'IA et la clé.
  Future<TranscriptionEngine> fromPrefs(Map<String, Object?> prefs) async =>
      (await resolve(
        chosen: TranscriptionEngineSettings.fromPrefs(prefs).engine,
        cloudAllowed: LlmSettings.fromPrefs(prefs).cloudAllowed,
      )).engine;
}

/// Transcription d'un fichier (rattrapage, dictée) par le moteur utilisé au
/// moment de l'appel : [cloud] (Mistral batch) ou [local] (voxmlx).
final class EngineTranscriber implements PcmTranscriber {
  /// Cree une instance de [EngineTranscriber].
  EngineTranscriber({
    required this.local,
    required this.cloud,
    required this.engine,
  });

  /// voxmlx sur ce Mac.
  final PcmTranscriber local;

  /// Mistral en ligne.
  final PcmTranscriber cloud;

  /// Moteur utilisé maintenant.
  final Future<TranscriptionEngine> Function() engine;

  @override
  Future<List<({int offsetMs, String text})>> transcribe(Uint8List pcm) async =>
      (await engine() == TranscriptionEngine.mistral ? cloud : local)
          .transcribe(pcm);
}
