import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:core_domain/domain/enum/server_state.enum.dart';
import 'package:core_foundation/logging/logger.dart';
import 'package:ici_transcript/application/services/gap_backfill.service.dart';

/// Rattrapage des repères quand le serveur de transcription n'était pas là.
///
/// Une session dont un repère n'a pas pu être retranscrit (serveur absent)
/// est réessayée dès que le serveur est prêt hors enregistrement, et au
/// lancement suivant ; au plus [maxAttempts] tentatives par session. Une
/// session dont le WAV a disparu n'est plus réessayée. Les sessions en
/// attente sont gardées dans [recordingsDirectory] (survivent au relancement).
final class GapBackfillRetry {
  /// Cree une instance de [GapBackfillRetry].
  GapBackfillRetry({
    required GapBackfillService backfill,
    required Stream<ServerState> serverStates,
    required bool Function() isRecording,
    required String recordingsDirectory,
  }) : _backfill = backfill,
       _isRecording = isRecording,
       _directory = recordingsDirectory {
    _states = serverStates.listen((ServerState state) {
      if (state == ServerState.ready) unawaited(_retryAll());
    });
  }

  /// Tentatives au plus par session, la première comprise.
  static const int maxAttempts = 3;

  final GapBackfillService _backfill;
  final bool Function() _isRecording;
  final String _directory;
  late final StreamSubscription<ServerState> _states;
  final Log _log = Log.named('GapBackfillRetry');
  Future<void> _tail = Future<void>.value();

  File get _pendingFile => File('$_directory/.backfill_pending.json');

  /// Première tentative, à la fin d'une session.
  Future<void> afterSession(String sessionId) =>
      _serialized(() => _attempt(sessionId));

  /// Au lancement : réessaie les sessions restées en attente.
  Future<void> retryPending() => _serialized(_retryAllNow);

  /// Arrête d'écouter l'état du serveur.
  Future<void> dispose() async {
    await _states.cancel();
    await _tail;
  }

  Future<void> _retryAll() => _serialized(_retryAllNow);

  Future<void> _retryAllNow() async {
    for (final String sessionId in (await _read()).keys.toList()) {
      if (_isRecording()) return;
      await _attempt(sessionId);
    }
  }

  // Une tentative à la fois : un serveur prêt plusieurs fois de suite ne
  // lance pas deux retranscriptions de la même session.
  Future<void> _serialized(Future<void> Function() action) {
    final Future<void> run = _tail
        .then((_) => action())
        .catchError(
          (Object e) => _log.warning('Rattrapage différé échoué: $e'),
        );
    _tail = run;
    return run;
  }

  Future<void> _attempt(String sessionId) async {
    if (_isRecording()) return;
    final Map<String, int> pending = await _read();
    if (!_hasRecording(sessionId)) {
      // WAV supprimé (passe post-session) : plus rien à rattraper.
      pending.remove(sessionId);
      await _write(pending);
      return;
    }
    final int attempts = (pending[sessionId] ?? 0) + 1;
    final int left = await _backfill.backfill(
      sessionId,
      recordingsDirectory: _directory,
    );
    if (left > 0 && attempts < maxAttempts) {
      pending[sessionId] = attempts;
    } else {
      if (left > 0) {
        _log.warning(
          'Session $sessionId : $attempts tentatives, repères gardés',
        );
      }
      pending.remove(sessionId);
    }
    await _write(pending);
  }

  bool _hasRecording(String sessionId) =>
      File('$_directory/${sessionId}_mic.wav').existsSync() ||
      File('$_directory/${sessionId}_system.wav').existsSync();

  Future<Map<String, int>> _read() async {
    try {
      if (!_pendingFile.existsSync()) return <String, int>{};
      final Object? json = jsonDecode(await _pendingFile.readAsString());
      return <String, int>{
        if (json is Map<String, dynamic>)
          for (final MapEntry<String, dynamic> e in json.entries)
            if (e.value is int) e.key: e.value as int,
      };
    } on FormatException {
      return <String, int>{};
    }
  }

  Future<void> _write(Map<String, int> pending) async {
    if (pending.isEmpty) {
      if (_pendingFile.existsSync()) await _pendingFile.delete();
      return;
    }
    await Directory(_directory).create(recursive: true);
    // Écriture puis renommage : un arrêt brutal ne laisse pas un fichier coupé.
    final File temp = File('${_pendingFile.path}.tmp');
    await temp.writeAsString(jsonEncode(pending), flush: true);
    await temp.rename(_pendingFile.path);
  }
}
