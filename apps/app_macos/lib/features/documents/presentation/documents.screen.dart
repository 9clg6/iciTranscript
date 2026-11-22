import 'package:core_presentation/core_presentation.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ici_transcript/application/services/documents/document_library.dart';
import 'package:ici_transcript/application/services/llm/llm_settings.dart';
import 'package:ici_transcript/core/providers/platform/file_picker.provider.dart';
import 'package:ici_transcript/core/providers/platform/prefs_store.provider.dart';
import 'package:ici_transcript/core/providers/services/document_library.provider.dart';
import 'package:ici_transcript/features/home/presentation/screens/home/home.screen.dart';
import 'package:ici_transcript/generated/translations/locale_keys.g.dart';

/// Page Documents : les fichiers qui servent de source aux réponses.
///
/// Ajout par le sélecteur natif (.txt, .md, .pdf), une ligne par document
/// (titre, type, date, nombre d'extraits) avec Renommer et Supprimer, et la
/// phrase de confidentialité qui suit l'interrupteur d'envoi en ligne.
// ponytail: état local de l'écran (liste, import, erreurs), pas de view
// model : rien d'autre ne le lit.
class DocumentsScreen extends ConsumerStatefulWidget {
  /// Crée la page.
  const DocumentsScreen({super.key});

  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen> {
  List<LibraryDocument>? _docs;
  bool _importing = false;
  bool _cloudAllowed = false;

  /// Erreurs du dernier ajout, une par fichier refusé (ou le sélecteur).
  List<String> _errors = const <String>[];

  DocumentLibrary get _library => ref.read(documentLibraryProvider);

  @override
  void initState() {
    super.initState();
    _reload();
    ref.read(prefsStoreProvider).read().then((Map<String, Object?> prefs) {
      if (mounted) {
        setState(
          () => _cloudAllowed = LlmSettings.fromPrefs(prefs).cloudAllowed,
        );
      }
    });
  }

  Future<void> _reload() async {
    final List<LibraryDocument> docs = await _library.list();
    if (mounted) setState(() => _docs = docs);
  }

  Future<void> _add() async {
    final List<String> paths;
    try {
      paths = await ref
          .read(filePickerProvider)
          .pickFiles(
            extensions: DocumentType.values
                .map((DocumentType t) => t.name)
                .toList(),
          );
    } on Object {
      if (mounted) {
        setState(
          () => _errors = <String>[LocaleKeys.documents_error_picker.tr()],
        );
      }
      return;
    }
    if (paths.isEmpty || !mounted) return;
    setState(() {
      _importing = true;
      _errors = const <String>[];
    });
    final List<String> errors = <String>[];
    for (final String path in paths) {
      try {
        await _library.importFile(path);
      } on DocumentImportException catch (e) {
        errors.add('${_fileName(path)} — ${_reason(e).tr()}');
      } on Object {
        errors.add(
          '${_fileName(path)} — ${LocaleKeys.documents_error_unreadable.tr()}',
        );
      }
    }
    await _reload();
    if (mounted) {
      setState(() {
        _importing = false;
        _errors = errors;
      });
    }
  }

  static String _fileName(String path) => path.split('/').last;

  static String _reason(DocumentImportException e) => switch (e) {
    UnsupportedDocumentTypeException() =>
      LocaleKeys.documents_error_unsupported,
    EmptyDocumentException() => LocaleKeys.documents_error_empty,
    DocumentTooLargeException() => LocaleKeys.documents_error_too_large,
    UnreadableDocumentException() => LocaleKeys.documents_error_unreadable,
  };

  Future<void> _rename(LibraryDocument doc) async {
    final String? title = await showDialog<String>(
      context: context,
      builder: (BuildContext _) => _RenameDialog(initial: doc.title),
    );
    if (title == null) return;
    await _library.rename(doc.id, title);
    await _reload();
  }

  Future<void> _delete(LibraryDocument doc) async {
    final Oats o = context.oats;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        content: Text(LocaleKeys.documents_delete_confirm.tr(), style: o.body),
        actions: <Widget>[
          OatsButton(
            label: LocaleKeys.documents_cancel.tr(),
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: o.danger,
              foregroundColor: o.background,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(LocaleKeys.documents_delete.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _library.delete(doc.id);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final Oats o = context.oats;
    final List<LibraryDocument>? docs = _docs;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        OatsSpace.xxxl,
        OatsSpace.xl,
        OatsSpace.xxxl,
        OatsSpace.xl,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              OatsPageHeader(
                title: LocaleKeys.nav_documents.tr(),
                trailing: OatsPrimaryButton(
                  icon: Icons.add,
                  label: LocaleKeys.documents_add.tr(),
                  onPressed: _importing ? null : _add,
                ),
              ),
              const SizedBox(height: OatsSpace.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(top: OatsSpace.xxs),
                    child: Icon(
                      _cloudAllowed ? Icons.cloud_outlined : Icons.lock_outline,
                      size: OatsIconSize.sm,
                      color: o.muted,
                    ),
                  ),
                  const SizedBox(width: OatsSpace.sm),
                  Expanded(
                    child: Text(
                      _cloudAllowed
                          ? LocaleKeys.documents_privacy_cloud.tr()
                          : LocaleKeys.documents_privacy_local.tr(),
                      style: o.small,
                    ),
                  ),
                ],
              ),
              if (_importing) ...<Widget>[
                const SizedBox(height: OatsSpace.lg),
                Row(
                  children: <Widget>[
                    const SizedBox.square(
                      dimension: OatsIconSize.sm,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: OatsSpace.sm),
                    Text(LocaleKeys.documents_importing.tr(), style: o.small),
                  ],
                ),
              ],
              for (final String error in _errors) ...<Widget>[
                const SizedBox(height: OatsSpace.md),
                OatsNotice(
                  icon: Icons.error_outline,
                  message: error,
                  danger: true,
                ),
              ],
              const SizedBox(height: OatsSpace.lg),
              Expanded(
                child: docs == null
                    ? const SizedBox.shrink()
                    : docs.isEmpty
                    ? OatsEmptyState(
                        icon: Icons.description_outlined,
                        title: LocaleKeys.documents_empty_title.tr(),
                        message: LocaleKeys.documents_empty.tr(),
                      )
                    : ListView(
                        children: <Widget>[
                          for (final LibraryDocument d in docs)
                            _DocumentRow(
                              key: ValueKey<String>('document-${d.id}'),
                              doc: d,
                              onRename: () => _rename(d),
                              onDelete: () => _delete(d),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ligne d'un document : titre, puis type · date · extraits ; actions.
class _DocumentRow extends StatelessWidget {
  const _DocumentRow({
    required this.doc,
    required this.onRename,
    required this.onDelete,
    super.key,
  });

  final LibraryDocument doc;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final Oats o = context.oats;
    final String meta = <String>[
      'documents.type.${doc.type.name}'.tr(),
      DateFormat('d MMM y', 'fr').format(doc.addedAt),
      LocaleKeys.documents_excerpts.plural(doc.excerptCount),
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: OatsSpace.md),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: o.line)),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.description_outlined,
            size: OatsIconSize.md,
            color: o.muted,
          ),
          const SizedBox(width: OatsSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  doc.title,
                  style: o.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: OatsSpace.xxs),
                Text(
                  meta,
                  style: o.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onRename,
            tooltip: LocaleKeys.documents_rename.tr(),
            iconSize: OatsIconSize.md,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.edit_outlined, color: o.muted),
          ),
          IconButton(
            onPressed: onDelete,
            tooltip: LocaleKeys.documents_delete.tr(),
            iconSize: OatsIconSize.md,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.delete_outline, color: o.muted),
          ),
        ],
      ),
    );
  }
}

/// Renommer : champ prérempli, Entrée ou Enregistrer valide, Annuler ferme.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    final Oats o = context.oats;
    return AlertDialog(
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(LocaleKeys.documents_rename_label.tr(), style: o.label),
            const SizedBox(height: OatsSpace.xs),
            TextField(
              controller: _controller,
              autofocus: true,
              style: o.body,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        OatsButton(
          label: LocaleKeys.documents_cancel.tr(),
          onPressed: () => Navigator.of(context).pop(),
        ),
        OatsPrimaryButton(
          label: LocaleKeys.documents_save.tr(),
          onPressed: _save,
        ),
      ],
    );
  }
}
