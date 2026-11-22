// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dev_data_directory.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Vrai quand l'app tourne sur un dossier de données de dev (debug, profile,
/// `OATS_DATA_DIR`) : la barre latérale l'affiche.

@ProviderFor(isDevDataDirectory)
const isDevDataDirectoryProvider = IsDevDataDirectoryProvider._();

/// Vrai quand l'app tourne sur un dossier de données de dev (debug, profile,
/// `OATS_DATA_DIR`) : la barre latérale l'affiche.

final class IsDevDataDirectoryProvider
    extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  /// Vrai quand l'app tourne sur un dossier de données de dev (debug, profile,
  /// `OATS_DATA_DIR`) : la barre latérale l'affiche.
  const IsDevDataDirectoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'isDevDataDirectoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$isDevDataDirectoryHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return isDevDataDirectory(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$isDevDataDirectoryHash() =>
    r'9264e9e0519ced40c554cd0106602209496cd0b7';
