import 'package:core_data/model/audio_chunk.dart';
import 'package:core_data/model/remote/transcript_event.remote.model.dart';
import 'package:core_domain/domain/enum/audio_source.enum.dart';
import 'package:core_domain/domain/enum/connection_state.enum.dart' as domain;

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

  /// Sources ayant actuellement un tour de parole non finalisé.
  Set<AudioSource> get activeSources;

  /// Deconnecte du serveur WebSocket.
  Future<void> disconnect();

  /// Finalise les buffers audio actifs.
  ///
  /// `voxmlx-serve` ne réinitialise une session que si `final` vaut true.
  Set<AudioSource> sendCommit({bool isFinal = false});

  /// Stream de l'etat de la connexion WebSocket.
  Stream<domain.ConnectionState> get connectionState;
}
