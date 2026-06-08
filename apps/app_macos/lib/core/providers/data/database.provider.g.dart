// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider singleton pour [AppDatabase] (Drift/SQLite).
///
/// Base PERSISTANTE sur disque (sinon les sessions disparaissent au
/// redémarrage). Fichier dans le dossier de l'app.

@ProviderFor(database)
const databaseProvider = DatabaseProvider._();

/// Provider singleton pour [AppDatabase] (Drift/SQLite).
///
/// Base PERSISTANTE sur disque (sinon les sessions disparaissent au
/// redémarrage). Fichier dans le dossier de l'app.

final class DatabaseProvider
    extends $FunctionalProvider<AppDatabase, AppDatabase, AppDatabase>
    with $Provider<AppDatabase> {
  /// Provider singleton pour [AppDatabase] (Drift/SQLite).
  ///
  /// Base PERSISTANTE sur disque (sinon les sessions disparaissent au
  /// redémarrage). Fichier dans le dossier de l'app.
  const DatabaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'databaseProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$databaseHash();

  @$internal
  @override
  $ProviderElement<AppDatabase> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AppDatabase create(Ref ref) {
    return database(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppDatabase value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppDatabase>(value),
    );
  }
}

String _$databaseHash() => r'a1d4f0fb1f6202aa238a230f0e7ba935025643f9';
