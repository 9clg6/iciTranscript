import 'package:flutter_test/flutter_test.dart';

import '../../helpers/localized_app.dart';

/// Textes de la page Documents et des états IA de la note : tous dans
/// fr.json. Indispensable : une clé absente est rendue telle quelle par
/// `.tr()`, des deux côtés (code et test), et les tests d'écran passeraient
/// à tort.
///
/// Valeurs françaises proposées à l'implémenteur (libres sauf mention) :
/// - documents.add : « Ajouter un document » (imposée)
/// - documents.empty : « Les documents que vous ajoutez servent de source
///   aux réponses pendant vos réunions. Formats acceptés : .txt, .md, .pdf. »
/// - documents.importing : « Import en cours… »
/// - documents.rename : « Renommer » ; documents.rename_label : « Titre »
/// - documents.save : « Enregistrer » ; documents.cancel : « Annuler »
/// - documents.delete : « Supprimer »
/// - documents.delete_confirm : « Supprimer ce document ? Ses extraits ne
///   serviront plus aux réponses. »
/// - documents.excerpts : {one: « {} extrait », other: « {} extraits »}
/// - documents.type.txt « Texte », .md « Markdown », .pdf « PDF »
/// - documents.error.unsupported : « Format non pris en charge. Formats
///   acceptés : .txt, .md, .pdf. »
/// - documents.error.empty : « Document vide : aucun texte à indexer. »
/// - documents.error.too_large : « Document trop volumineux (plus de 5 Mo de
///   texte). Découpez-le en plusieurs fichiers. »
/// - documents.error.unreadable : « Lecture impossible. Vérifiez que le
///   fichier existe et n'est pas protégé par un mot de passe. »
/// - documents.error.picker : « Impossible d'ouvrir le sélecteur de
///   fichiers. Réessayez. »
/// - documents.privacy_local : « L'envoi à un service en ligne est coupé :
///   ces documents et leurs extraits restent sur votre Mac. »
/// - documents.privacy_cloud : « L'envoi à un service en ligne est autorisé :
///   des extraits utiles à une réponse peuvent partir chez le fournisseur
///   choisi. »
/// - llm.error.invalid_key : « Clé API refusée par le fournisseur. Vérifiez-la
///   dans Réglages. »
/// - llm.error.rate_limited : « Limite du fournisseur atteinte. Réessayez
///   dans quelques minutes. »
/// - llm.error.unreachable : « Fournisseur injoignable. Vérifiez votre
///   connexion ou le modèle local. »
/// - llm.error.failed : « La génération a échoué. Réessayez. »
/// - llm.error.malformed : « Réponse du modèle illisible. Réessayez. »
/// - llm.incomplete : « Réponse incomplète : le modèle s'est arrêté avant la
///   fin. Relancez pour un résumé complet. »
void main() {
  test('documents.add = « Ajouter un document »', () {
    expect(frValue('documents.add'), 'Ajouter un document');
  });

  test('documents.empty n\'annonce plus une page « à venir »', () {
    expect(frValue('documents.empty'), isA<String>());
    expect(frValue('documents.empty')! as String, isNot(contains('bientôt')));
  });

  group('clés présentes et non vides', () {
    const List<String> keys = <String>[
      'documents.empty_title',
      'documents.empty',
      'documents.importing',
      'documents.rename',
      'documents.rename_label',
      'documents.save',
      'documents.cancel',
      'documents.delete',
      'documents.delete_confirm',
      'documents.excerpts.one',
      'documents.excerpts.other',
      'documents.type.txt',
      'documents.type.md',
      'documents.type.pdf',
      'documents.error.unsupported',
      'documents.error.empty',
      'documents.error.too_large',
      'documents.error.unreadable',
      'documents.error.picker',
      'documents.privacy_local',
      'documents.privacy_cloud',
      'llm.error.invalid_key',
      'llm.error.rate_limited',
      'llm.error.unreachable',
      'llm.error.failed',
      'llm.error.malformed',
      'llm.incomplete',
    ];
    for (final String key in keys) {
      test(key, () {
        final Object? v = frValue(key);
        expect(v, isA<String>(), reason: key);
        expect((v! as String).trim(), isNotEmpty, reason: key);
      });
    }
  });

  test('les deux lignes de confidentialité disent des choses différentes', () {
    expect(
      frValue('documents.privacy_local'),
      isNot(frValue('documents.privacy_cloud')),
    );
  });

  test('le nombre d\'extraits a un singulier et un pluriel avec le nombre', () {
    expect(frValue('documents.excerpts.one'), contains('{}'));
    expect(frValue('documents.excerpts.other'), contains('{}'));
  });
}
