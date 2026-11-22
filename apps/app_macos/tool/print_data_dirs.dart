// Prints the resolved directories without touching them (no app launch).
// Run: fvm flutter test --no-pub tool/print_data_dirs.dart (the resolver
// imports flutter/foundation, so plain `dart run` cannot compile it).
import 'dart:io';

import 'package:ici_transcript/core/platform/app_data_directory.dart';

void main() {
  final Map<String, String> real = Map<String, String>.of(Platform.environment)
    ..remove('FLUTTER_TEST');
  for (final Map<String, String> env in <Map<String, String>>[
    real,
    <String, String>{...real, 'OATS_DATA_DIR': '/tmp/x'},
  ]) {
    for (final AppBuildMode m in <AppBuildMode>[
      AppBuildMode.debug,
      AppBuildMode.release,
    ]) {
      stdout.writeln(
        '${env['OATS_DATA_DIR'] ?? '-'} ${m.name}: data=${resolveAppDataDirectory(env, buildMode: m)} '
        'tools=${resolveToolsDirectory(env)} logs=${resolveLogDirectory(env, buildMode: m)}',
      );
    }
  }
}
