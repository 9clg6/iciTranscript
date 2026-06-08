// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session.repository.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider pour [SessionRepository].
///
/// Fournit l'implementation [SessionRepositoryImpl] qui utilise
/// la source de donnees locale Drift pour la persistance des sessions.

@ProviderFor(sessionRepository)
const sessionRepositoryProvider = SessionRepositoryProvider._();

/// Provider pour [SessionRepository].
///
/// Fournit l'implementation [SessionRepositoryImpl] qui utilise
/// la source de donnees locale Drift pour la persistance des sessions.

final class SessionRepositoryProvider
    extends
        $FunctionalProvider<
          SessionRepository,
          SessionRepository,
          SessionRepository
        >
    with $Provider<SessionRepository> {
  /// Provider pour [SessionRepository].
  ///
  /// Fournit l'implementation [SessionRepositoryImpl] qui utilise
  /// la source de donnees locale Drift pour la persistance des sessions.
  const SessionRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sessionRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sessionRepositoryHash();

  @$internal
  @override
  $ProviderElement<SessionRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  SessionRepository create(Ref ref) {
    return sessionRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SessionRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SessionRepository>(value),
    );
  }
}

String _$sessionRepositoryHash() => r'6fd3e300359df053697cb306644e7363541ede5b';
