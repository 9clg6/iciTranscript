// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session.local.data_source.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider pour [SessionLocalDataSource].
///
/// Fournit l'implementation basee sur Drift/SQLite pour la persistance
/// des sessions de transcription.

@ProviderFor(sessionLocalDataSource)
const sessionLocalDataSourceProvider = SessionLocalDataSourceProvider._();

/// Provider pour [SessionLocalDataSource].
///
/// Fournit l'implementation basee sur Drift/SQLite pour la persistance
/// des sessions de transcription.

final class SessionLocalDataSourceProvider
    extends
        $FunctionalProvider<
          SessionLocalDataSource,
          SessionLocalDataSource,
          SessionLocalDataSource
        >
    with $Provider<SessionLocalDataSource> {
  /// Provider pour [SessionLocalDataSource].
  ///
  /// Fournit l'implementation basee sur Drift/SQLite pour la persistance
  /// des sessions de transcription.
  const SessionLocalDataSourceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sessionLocalDataSourceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sessionLocalDataSourceHash();

  @$internal
  @override
  $ProviderElement<SessionLocalDataSource> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  SessionLocalDataSource create(Ref ref) {
    return sessionLocalDataSource(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SessionLocalDataSource value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SessionLocalDataSource>(value),
    );
  }
}

String _$sessionLocalDataSourceHash() =>
    r'a5afd34b2eec1abf4f85b32fc03b4e5d065a2d9a';
