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
  ///
  /// Si le serveur répond (ou qu'il n'y avait rien à faire), les autres
  /// sessions en attente sont reprises ensuite, en tâche de fond : le
  /// serveur vient de se libérer de l'enregistrement.
  Future<void> afterSession(String sessionId) => _serialized(() async {
    if (await _attempt(sessionId)) {
      unawaited(_serialized(() => _retryAllNow(except: sessionId)));
    }
  });

  /// Au lancement : réessaie les sessions restées en attente.
  Future<void> retryPending() => _serialized(_retryAllNow);

  /// Arrête d'écouter l'état du serveur.
  Future<void> dispose() async {
    await _states.cancel();
    await _tail;
  }

  Future<void> _retryAll() => _serialized(_retryAllNow);

  /// Une session à la fois, la plus ancienne d'abord (les ids sont des
  /// heures de création) ; on s'arrête dès que le serveur manque ou qu'un
  /// enregistrement commence.
  Future<void> _retryAllNow({String? except}) async {
    final List<String> ids =
        (await _read()).keys.where((String id) => id != except).toList()
          ..sort(_olderFirst);
    for (final String sessionId in ids) {
      if (_isRecording()) return;
      if (!await _attempt(sessionId)) return;
    }
  }

  static int _olderFirst(String a, String b) {
    final int? x = int.tryParse(a);
    final int? y = int.tryParse(b);
    return x != null && y != null ? x.compareTo(y) : a.compareTo(b);
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

  /// Met [sessionId] en attente sans tentative (ex. session tuée net,
  /// retrouvée au lancement avec ses repères).
  Future<void> enqueue(String sessionId) => _serialized(() async {
    final Map<String, int> pending = await _read();
    pending.putIfAbsent(sessionId, () => 0);
    await _write(pending);
  });

  /// Rend faux si le serveur n'a pas pu être utilisé (absent, ou un
  /// enregistrement a la priorité) : inutile alors d'essayer les autres.
  Future<bool> _attempt(String sessionId) async {
    final Map<String, int> pending = await _read();
    if (!_hasRecording(sessionId)) {
      // WAV supprimé (passe post-session) : plus rien à rattraper.
      pending.remove(sessionId);
      await _write(pending);
      return true;
    }
    if (_isRecording()) {
      // Le serveur est à l'enregistrement : plus tard, sans compter.
      pending.putIfAbsent(sessionId, () => 0);
      await _write(pending);
      return false;
    }
    final BackfillOutcome outcome = await _backfill.backfill(
      sessionId,
      recordingsDirectory: _directory,
    );
    // Seule une tentative qui a atteint le serveur compte : une panne du
    // serveur ne doit pas épuiser les reprises avant son retour.
    final int attempts =
        (pending[sessionId] ?? 0) + (outcome.reachedServer ? 1 : 0);
    if (outcome.markersLeft == 0) {
      pending.remove(sessionId);
    } else if (attempts >= maxAttempts) {
      _log.warning('Session $sessionId : $attempts tentatives, repères gardés');
      pending.remove(sessionId);
    } else {
      pending[sessionId] = attempts;
    }
    await _write(pending);
    return outcome.markersLeft == 0 || outcome.reachedServer;
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
