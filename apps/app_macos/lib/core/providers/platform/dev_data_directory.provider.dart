import 'package:ici_transcript/core/platform/app_data_directory.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'dev_data_directory.provider.g.dart';

/// Vrai quand l'app tourne sur un dossier de données de dev (debug, profile,
/// `OATS_DATA_DIR`) : la barre latérale l'affiche.
@Riverpod(keepAlive: true)
bool isDevDataDirectory(Ref ref) => runsOnDevDataDirectory();
