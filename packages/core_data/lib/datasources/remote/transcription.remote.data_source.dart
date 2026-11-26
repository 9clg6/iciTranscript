import 'package:core_data/model/audio_chunk.dart';
import 'package:core_data/model/audio_gap.dart';
import 'package:core_data/model/remote/transcript_event.remote.model.dart';
import 'package:core_data/model/utterance_window.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/enum/connection_state.enum.dart' as domain;

/// Événement émis par la source elle-même (pas par voxmlx) sur le flux d'une
/// source quand sa socket revient : la phrase sans `done` repart en entier,
/// le serveur va la retranscrire depuis le début.
const String utteranceResentEventType = 'client.utterance_resent';

/// Idem, mais le début de l'audio sans `done` a été perdu (tampon plein) :
/// le texte déjà reçu pour cette phrase ne sera pas retranscrit.
const String utteranceLostEventType = 'client.utterance_lost';

/// Événement émis par la source quand la reconnexion d'une source échoue en
/// 401 : la clé est refusée, réessayer n'y changera rien.
const String keyRejectedEventType = 'client.key_rejected';

/// Contrat de la source de donnees distante pour la transcription via WebSocket.
abstract interface class TranscriptionRemoteDataSource {
  /// Se connecte au serveur WebSocket de transcription.
  Future<void> connect({
    String url = 'ws://localhost:8000/v1/realtime',
    bool systemAudioEnabled = true,
  });

  /// Envoie un chunk audio au serveur pour transcription.
  void sendAudio(AudioChunk chunk);

  /// Stream des evenements de transcription du MICRO (MOI).
  Stream<TranscriptEventRemoteModel> get transcriptionStream;

  /// Stream des evenements de transcription de l'audio SYSTEME (interlocuteurs).
  Stream<TranscriptEventRemoteModel> get systemTranscriptionStream;

  /// Audio jamais transcrit (coupure plus longue que le tampon, ou session
  /// close avant la reconnexion) : une perte par coupure et par source.
  Stream<AudioGap> get audioGaps;

  /// Sources ayant actuellement un tour de parole non finalisé.
  Set<AudioSource> get activeSources;

  /// Intervalle de capture de la phrase terminée par l'événement `done`
  /// [event], ou null si le serveur l'a terminée de lui-même.
  UtteranceWindow? windowOf(TranscriptEventRemoteModel event);

  /// Audio envoyé à un moteur en ligne (ms, micro + système) depuis le dernier
  /// appel, puis remise à zéro des deux sockets. 0 pour un moteur local.
  int takeSentAudioMs();

  /// Deconnecte du serveur WebSocket.
  Future<void> disconnect();

  /// Finalise les buffers audio actifs.
  ///
  /// `voxmlx-serve` ne réinitialise une session que si `final` vaut true.
  /// [sources] null : toutes ; sinon seules celles-ci (la dictée finalise le
  /// micro sans toucher à l'audio système). Rend les sources dont une phrase
  /// ouverte a été finalisée (un `done` viendra).
  Set<AudioSource> sendCommit({
    bool isFinal = false,
    Set<AudioSource>? sources,
  });

  /// Stream de l'etat de la connexion WebSocket.
  Stream<domain.ConnectionState> get connectionState;
}
