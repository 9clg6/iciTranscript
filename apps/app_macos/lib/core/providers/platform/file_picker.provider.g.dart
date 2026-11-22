// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'file_picker.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Sélecteur de fichiers natif (remplacé par un faux dans les tests).

@ProviderFor(filePicker)
const filePickerProvider = FilePickerProvider._();

/// Sélecteur de fichiers natif (remplacé par un faux dans les tests).

final class FilePickerProvider
    extends
        $FunctionalProvider<
          FilePickerChannel,
          FilePickerChannel,
          FilePickerChannel
        >
    with $Provider<FilePickerChannel> {
  /// Sélecteur de fichiers natif (remplacé par un faux dans les tests).
  const FilePickerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'filePickerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$filePickerHash();

  @$internal
  @override
  $ProviderElement<FilePickerChannel> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  FilePickerChannel create(Ref ref) {
    return filePicker(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(FilePickerChannel value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<FilePickerChannel>(value),
    );
  }
}

String _$filePickerHash() => r'06fbad86cd667c3d8e8d2e56b58c7ffbb0590941';
