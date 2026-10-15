import 'dart:io';

import 'package:core_foundation/logging/logger.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ici_transcript/presentation/app.dart';
import 'package:mcp_toolkit/mcp_toolkit.dart';

/// Point d'entree de l'application IciTranscript.
///
/// Le serveur ML (voxmlx-serve) est gere par un LaunchAgent.
/// L'app est sandboxee pour obtenir la permission micro automatiquement.
Future<void> main() async {
  MCPToolkitBinding.instance.initialize();
  WidgetsFlutterBinding.ensureInitialized();
  // Journaux consultables en release : ~/Library/Logs/iciTranscript/.
  final String? home = Platform.environment['HOME'];
  if (home != null) {
    Log.writeToFile('$home/Library/Logs/iciTranscript/iciTranscript.log');
  }
  await EasyLocalization.ensureInitialized();

  runApp(
    ProviderScope(
      child: EasyLocalization(
        supportedLocales: const <Locale>[Locale('fr')],
        path: 'assets/translations',
        fallbackLocale: const Locale('fr'),
        child: const RootAppWidget(),
      ),
    ),
  );
}
