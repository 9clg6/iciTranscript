import 'dart:async';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:core_data/database/app_database.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ici_transcript/application/services/documents/document_library.dart';
import 'package:ici_transcript/application/services/llm/llm_settings.dart';
import 'package:ici_transcript/core/platform/prefs_store.dart';
import 'package:ici_transcript/core/providers/data/database.provider.dart';
import 'package:ici_transcript/core/providers/platform/file_picker.provider.dart';
import 'package:ici_transcript/features/documents/presentation/documents.screen.dart';

import '../../helpers/document_fakes.dart';
import '../../helpers/fake_view_models.dart';
import '../../helpers/local_model_fakes.dart';
import '../../helpers/localized_app.dart';
import '../../helpers/settings_fakes.dart';

/// Page Documents (besoins A5, A6) : comportement, pas pixels.
///
/// API supposée :
/// - `DocumentsScreen` (lib/features/documents/presentation/documents.screen.dart),
///   `const DocumentsScreen({super.key})`, affichée par le shell pour
///   `ShellView.documents`.
/// - Lit la bibliothèque par `documentLibraryProvider`
///   (lib/core/providers/services/document_library.provider.dart, construit
///   sur `databaseProvider`) et le sélecteur par `filePickerProvider`.
/// - Une ligne par document, clé `ValueKey<String>('document-<id>')`, avec
///   titre, type (`documents.type.<txt|md|pdf>`), date d'ajout
///   (`DateFormat('d MMM y', 'fr')`) et `documents.excerpts`.plural(n) ;
///   actions Renommer / Supprimer de la ligne : texte ou infobulle
///   `documents.rename` / `documents.delete`.
/// - L'interrupteur d'envoi est lu dans prefs.json (`llm_cloud_allowed`).
void main() {
  late AppDatabase db;
  late FakeFilePicker picker;
  late Directory dir;

  setUp(() {
    resetPrefs();
    db = memoryDatabase();
    picker = FakeFilePicker();
    dir = tempFolder();
  });
  tearDown(() => db.close());

  /// Laisse finir les E/S réelles (fichiers, base) puis redessine.
  Future<void> idle(WidgetTester tester) async {
    for (int i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await settle(tester, frames: 3);
    }
  }

  /// Attend (E/S réelles, 3 s au plus) que [done] soit vrai : une
  /// implémentation correcte peut enchaîner plus d'attentes qu'[idle].
  Future<void> until(WidgetTester tester, bool Function() done) async {
    for (int i = 0; i < 30 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await settle(tester, frames: 2);
    }
  }

  bool shown(Finder f) => f.evaluate().isNotEmpty;

  Future<LibraryDocument> seed(
    WidgetTester tester,
    String name,
    String text, {
    DateTime? at,
  }) async {
    final LibraryDocument? doc = await tester.runAsync(
      () => withClock(
        Clock.fixed(at ?? DateTime(2026, 11, 20, 14, 30)),
        () => DocumentLibrary(db).importFile(writeFile(dir, name, text)),
      ),
    );
    return doc!;
  }

  Future<void> pumpPage(WidgetTester tester) async {
    await pumpLocalized(
      tester,
      const DocumentsScreen(),
      settle: false,
      overrides: <Override>[
        databaseProvider.overrideWithValue(db),
        filePickerProvider.overrideWithValue(picker),
      ],
    );
    await idle(tester);
  }

  Finder addButton() => find.text('documents.add'.tr());

  Finder row(String id) => find.byKey(ValueKey<String>('document-$id'));

  /// Action de la ligne : bouton texte ou icône avec infobulle.
  Finder rowAction(String id, String key) {
    final Finder byText = find.descendant(
      of: row(id),
      matching: find.text(key.tr()),
    );
    return byText.evaluate().isNotEmpty
        ? byText
        : find.descendant(of: row(id), matching: find.byTooltip(key.tr()));
  }

  Future<List<LibraryDocument>> stored(WidgetTester tester) async =>
      (await tester.runAsync(() => DocumentLibrary(db).list()))!;

  group('vide', () {
    testWidgets('aucun document : état vide et action « Ajouter un document »',
        (WidgetTester tester) async {
      await pumpPage(tester);
      await until(tester, () => shown(addButton()));

      expect(find.text('documents.empty_title'.tr()), findsOneWidget);
      expect(addButton(), findsOneWidget);
    });

    testWidgets('le sélecteur est ouvert sur .txt, .md et .pdf', (
      WidgetTester tester,
    ) async {
      await pumpPage(tester);

      await tester.tap(addButton());
      await idle(tester);

      expect(picker.calls.single.toSet(), <String>{'txt', 'md', 'pdf'});
    });

    testWidgets('sélection annulée : rien ne change, aucun message d\'erreur', (
      WidgetTester tester,
    ) async {
      await pumpPage(tester);
      picker.next = <String>[];

      await tester.tap(addButton());
      await idle(tester);

      expect(find.text('documents.empty_title'.tr()), findsOneWidget);
      expect(find.textContaining('documents.error'), findsNothing);
      expect(await stored(tester), isEmpty);
    });

    testWidgets('sélecteur en panne : message, et l\'ajout reste possible', (
      WidgetTester tester,
    ) async {
      await pumpPage(tester);
      picker.error = PlatformException(code: 'panel', message: 'boom');

      await tester.tap(addButton());
      await until(tester, () => shown(find.text('documents.error.picker'.tr())));

      expect(find.text('documents.error.picker'.tr()), findsOneWidget);
      picker
        ..error = null
        ..next = <String>[writeFile(dir, 'plan.md', 'Le plan.')];
      await tester.tap(addButton());
      await until(tester, () => shown(find.text('plan')));
      expect(find.text('plan'), findsOneWidget);
    });
  });

  group('ajout', () {
    testWidgets('un fichier choisi apparaît dans la liste avec type, date et '
        'nombre d\'extraits', (WidgetTester tester) async {
      await pumpPage(tester);
      picker.next = <String>[writeFile(dir, 'Budget 2027.md', 'Le budget.')];

      await tester.tap(addButton());
      await until(tester, () => shown(find.text('Budget 2027')));

      final LibraryDocument doc = (await stored(tester)).single;
      expect(find.descendant(of: row(doc.id), matching: find.text('Budget 2027')),
          findsOneWidget);
      expect(
        find.descendant(
          of: row(doc.id),
          matching: find.textContaining('documents.type.md'.tr()),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: row(doc.id),
          matching: find.textContaining('documents.excerpts'.plural(1)),
        ),
        findsOneWidget,
      );
      expect(find.text('documents.empty_title'.tr()), findsNothing);
    });

    testWidgets('import en cours : un indicateur, puis le document', (
      WidgetTester tester,
    ) async {
      final Completer<String> extraction = Completer<String>();
      mockPdfChannel((MethodCall call) => extraction.future);
      await pumpPage(tester);
      picker.next = <String>[writeFile(dir, 'Rapport.pdf', '%PDF-1.4')];

      await tester.tap(addButton());
      await until(tester, () => shown(find.text('documents.importing'.tr())));

      expect(find.text('documents.importing'.tr()), findsOneWidget);

      extraction.complete('Le chiffre d\'affaires progresse.');
      await until(tester, () => shown(find.text('Rapport')));

      expect(find.text('documents.importing'.tr()), findsNothing);
      expect(find.text('Rapport'), findsOneWidget);
      expect(find.textContaining('documents.type.pdf'.tr()), findsOneWidget);
    });

    testWidgets('plusieurs fichiers : chaque issue est rapportée, les erreurs '
        'en ligne avec le nom du fichier', (WidgetTester tester) async {
      await pumpPage(tester);
      picker.next = <String>[
        writeFile(dir, 'plan.md', 'Le plan de la semaine.'),
        writeFile(dir, 'contrat.docx', 'binaire'),
        writeFile(dir, 'vide.txt', '   '),
        '${dir.path}/disparu.md',
      ];

      await tester.tap(addButton());
      await until(
        tester,
        () =>
            shown(find.text('plan')) &&
            shown(find.textContaining('contrat.docx')) &&
            shown(find.textContaining('vide.txt')) &&
            shown(find.textContaining('disparu.md')),
      );

      expect(find.text('plan'), findsOneWidget);
      expect(find.textContaining('contrat.docx'), findsOneWidget);
      expect(
        find.textContaining('documents.error.unsupported'.tr()),
        findsOneWidget,
      );
      expect(find.textContaining('vide.txt'), findsOneWidget);
      expect(find.textContaining('documents.error.empty'.tr()), findsOneWidget);
      expect(find.textContaining('disparu.md'), findsOneWidget);
      expect(
        find.textContaining('documents.error.unreadable'.tr()),
        findsOneWidget,
      );
      expect((await stored(tester)).map((LibraryDocument d) => d.title),
          <String>['plan']);
      expect(addButton(), findsOneWidget);
    });

    testWidgets('fichier trop volumineux : message en ligne', (
      WidgetTester tester,
    ) async {
      await pumpPage(tester);
      picker.next = <String>[
        writeFile(dir, 'enorme.txt', 'a' * (kMaxDocumentTextChars + 1)),
      ];

      await tester.tap(addButton());
      await until(tester, () => shown(find.textContaining('enorme.txt')));

      expect(find.textContaining('enorme.txt'), findsOneWidget);
      expect(
        find.textContaining('documents.error.too_large'.tr()),
        findsOneWidget,
      );
    });
  });

  group('liste', () {
    testWidgets('chaque document montre titre, type, date d\'ajout et nombre '
        'd\'extraits', (WidgetTester tester) async {
      final String long = List<String>.generate(
        3,
        (int i) => List<String>.filled(100, 'mot$i'.padRight(9)).join(' '),
      ).join('\n\n');
      final LibraryDocument doc = await seed(
        tester,
        'Plan.md',
        long,
        at: DateTime(2026, 11, 20, 14, 30),
      );

      await pumpPage(tester);
      await until(tester, () => shown(row(doc.id)));

      expect(doc.excerptCount, 3);
      for (final String text in <String>[
        'Plan',
        DateFormat('d MMM y', 'fr').format(DateTime(2026, 11, 20)),
        'documents.excerpts'.plural(3),
        'documents.type.md'.tr(),
      ]) {
        expect(
          find.descendant(of: row(doc.id), matching: find.textContaining(text)),
          findsWidgets,
          reason: text,
        );
      }
    });
  });

  group('renommer', () {
    testWidgets('Renommer puis Entrée : nouveau titre dans la liste et en base',
        (WidgetTester tester) async {
      final LibraryDocument doc = await seed(tester, 'plan.md', 'Le plan.');
      await pumpPage(tester);
      await until(tester, () => shown(row(doc.id)));

      await tester.tap(rowAction(doc.id, 'documents.rename'));
      await settle(tester, frames: 3);
      expect(find.text('documents.rename_label'.tr()), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Plan validé');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await until(tester, () => shown(find.text('Plan validé')));

      expect(find.text('Plan validé'), findsOneWidget);
      expect((await stored(tester)).single.title, 'Plan validé');
    });

    testWidgets('Renommer puis Enregistrer : nouveau titre', (
      WidgetTester tester,
    ) async {
      final LibraryDocument doc = await seed(tester, 'plan.md', 'Le plan.');
      await pumpPage(tester);
      await until(tester, () => shown(row(doc.id)));

      await tester.tap(rowAction(doc.id, 'documents.rename'));
      await settle(tester, frames: 3);
      await tester.enterText(find.byType(TextField), 'Plan 2027');
      await tester.tap(find.text('documents.save'.tr()));
      await until(tester, () => shown(find.text('Plan 2027')));

      expect((await stored(tester)).single.title, 'Plan 2027');
    });

    testWidgets('Renommer puis Annuler : titre inchangé', (
      WidgetTester tester,
    ) async {
      final LibraryDocument doc = await seed(tester, 'plan.md', 'Le plan.');
      await pumpPage(tester);
      await until(tester, () => shown(row(doc.id)));

      await tester.tap(rowAction(doc.id, 'documents.rename'));
      await settle(tester, frames: 3);
      await tester.enterText(find.byType(TextField), 'Autre titre');
      await tester.tap(find.text('documents.cancel'.tr()));
      await idle(tester);

      expect(find.text('plan'), findsOneWidget);
      expect((await stored(tester)).single.title, 'plan');
    });
  });

  group('supprimer', () {
    testWidgets('Supprimer demande confirmation ; confirmer retire le document '
        'et ses extraits', (WidgetTester tester) async {
      final LibraryDocument plan = await seed(tester, 'plan.md', 'Le plan.');
      await seed(tester, 'budget.md', 'Le budget.');
      await pumpPage(tester);
      await until(tester, () => shown(row(plan.id)));

      await tester.tap(rowAction(plan.id, 'documents.delete'));
      await settle(tester, frames: 3);

      expect(find.text('documents.delete_confirm'.tr()), findsOneWidget);
      expect((await stored(tester)), hasLength(2), reason: 'pas avant confirmation');

      await tester.tap(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('documents.delete'.tr()),
        ),
      );
      await until(tester, () => !shown(row(plan.id)));

      expect(row(plan.id), findsNothing);
      expect(find.text('budget'), findsOneWidget);
      expect((await stored(tester)).map((LibraryDocument d) => d.title),
          <String>['budget']);
      final List<DocumentExcerpt>? hits = await tester.runAsync(
        () => DocumentLibrary(db).search('plan'),
      );
      expect(hits, isEmpty);
    });

    testWidgets('Supprimer puis Annuler : le document reste', (
      WidgetTester tester,
    ) async {
      final LibraryDocument plan = await seed(tester, 'plan.md', 'Le plan.');
      await pumpPage(tester);
      await until(tester, () => shown(row(plan.id)));

      await tester.tap(rowAction(plan.id, 'documents.delete'));
      await settle(tester, frames: 3);
      await tester.tap(find.text('documents.cancel'.tr()));
      await idle(tester);

      expect(row(plan.id), findsOneWidget);
      expect(await stored(tester), hasLength(1));
    });

    testWidgets('supprimer le dernier document ramène l\'état vide', (
      WidgetTester tester,
    ) async {
      final LibraryDocument plan = await seed(tester, 'plan.md', 'Le plan.');
      await pumpPage(tester);
      await until(tester, () => shown(row(plan.id)));

      await tester.tap(rowAction(plan.id, 'documents.delete'));
      await settle(tester, frames: 3);
      await tester.tap(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('documents.delete'.tr()),
        ),
      );
      await until(tester, () => !shown(row(plan.id)));

      expect(find.text('documents.empty_title'.tr()), findsOneWidget);
      expect(addButton(), findsOneWidget);
    });
  });

  group('confidentialité', () {
    testWidgets('envoi coupé (défaut) : la page dit que les documents restent '
        'sur le Mac', (WidgetTester tester) async {
      await pumpPage(tester);
      await until(tester, () => shown(find.text('documents.privacy_local'.tr())));

      expect(find.text('documents.privacy_local'.tr()), findsOneWidget);
      expect(find.text('documents.privacy_cloud'.tr()), findsNothing);
    });

    testWidgets('envoi autorisé : la page dit que des extraits peuvent partir '
        'chez le fournisseur choisi', (WidgetTester tester) async {
      await tester.runAsync(
        () => PrefsStore().update(<String, Object?>{
          LlmSettings.cloudAllowedKey: true,
        }),
      );
      await pumpPage(tester);
      await until(tester, () => shown(find.text('documents.privacy_cloud'.tr())));

      expect(find.text('documents.privacy_cloud'.tr()), findsOneWidget);
      expect(find.text('documents.privacy_local'.tr()), findsNothing);
    });
  });
}
