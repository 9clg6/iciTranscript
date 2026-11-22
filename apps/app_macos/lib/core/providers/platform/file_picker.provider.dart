import 'package:ici_transcript/core/platform/file_picker_channel.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'file_picker.provider.g.dart';

/// Sélecteur de fichiers natif (remplacé par un faux dans les tests).
@Riverpod(keepAlive: true)
FilePickerChannel filePicker(Ref ref) => const FilePickerChannel();
