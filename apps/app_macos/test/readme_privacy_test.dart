import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Garde structurelle sur le README (besoin B11) : la promesse « 100 %
/// local, zéro cloud » est lue par l'utilisateur, et elle devient fausse dès
/// qu'il autorise l'envoi à un fournisseur en ligne (Claude, OpenAI, Gemini).
/// Le README doit dire que ces fournisseurs sont optionnels et coupés par
/// défaut, sans promesse inconditionnelle.
void main() {
  // `flutter test` tourne dans apps/app_macos.
  final String readme = File('../../README.md').readAsStringSync();
  final String lower = readme.toLowerCase();

  for (final String claim in <String>[
    'zero cloud',
    '100% local',
    '100 % local',
    'without sending a single byte',
    'no data is sent to any external server',
  ]) {
    test('plus de promesse inconditionnelle « $claim »', () {
      expect(lower, isNot(contains(claim)));
    });
  }

  test('les fournisseurs en ligne sont cités comme optionnels', () {
    expect(lower, contains('optional'));
    for (final String provider in <String>['claude', 'openai', 'gemini']) {
      expect(lower, contains(provider), reason: provider);
    }
  });

  test('l\'envoi en ligne est dit coupé par défaut', () {
    expect(lower, contains('off by default'));
  });

  test('l\'audio reste sur le Mac', () {
    expect(lower, contains('audio never leaves your mac'));
  });
}
