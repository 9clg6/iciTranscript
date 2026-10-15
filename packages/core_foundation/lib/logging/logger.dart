import 'dart:developer' as developer;
import 'dart:io';

/// Logger structure pour l'application.
class Log {
  /// Cree un logger nomme.
  Log.named(this._name);

  final String _name;

  static IOSink? _file;

  /// Écrit aussi les journaux dans [path] (en plus de la console de debug),
  /// pour qu'ils restent consultables dans une version release. Le fichier
  /// précédent est conservé en `.1` s'il dépasse [maxBytes].
  static void writeToFile(String path, {int maxBytes = 5 * 1024 * 1024}) {
    try {
      final File file = File(path);
      file.parent.createSync(recursive: true);
      if (file.existsSync() && file.lengthSync() > maxBytes) {
        file.renameSync('$path.1');
      }
      _file = file.openWrite(mode: FileMode.append);
    } on FileSystemException {
      _file = null;
    }
  }

  /// Log un message d'information.
  void info(String message) => _write('INFO', message);

  /// Log un message de debug.
  void debug(String message) => _write('DEBUG', message);

  /// Log un message d'avertissement.
  void warning(String message) => _write('WARNING', message);

  /// Log un message d'erreur.
  void error(String message, [Object? error, StackTrace? stackTrace]) {
    developer.log(
      '[$_name] ERROR: $message',
      error: error,
      stackTrace: stackTrace,
    );
    _append('ERROR', <String>[
      message,
      if (error != null) '$error',
      if (stackTrace != null) '$stackTrace',
    ].join('\n'));
  }

  void _write(String level, String message) {
    developer.log('[$_name] $level: $message');
    _append(level, message);
  }

  void _append(String level, String message) {
    _file?.writeln(
      '${DateTime.now().toIso8601String()} [$_name] $level: $message',
    );
  }
}
