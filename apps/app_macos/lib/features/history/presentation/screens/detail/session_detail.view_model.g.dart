// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session_detail.view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// ViewModel de l'ecran de detail d'une session.
///
/// Charge la session et ses segments, gere l'edition du titre,
/// la suppression, l'export, la copie, ainsi que la generation a la demande
/// du resume IA et du retour du coach d'anglais.

@ProviderFor(SessionDetailViewModel)
const sessionDetailViewModelProvider = SessionDetailViewModelFamily._();

/// ViewModel de l'ecran de detail d'une session.
///
/// Charge la session et ses segments, gere l'edition du titre,
/// la suppression, l'export, la copie, ainsi que la generation a la demande
/// du resume IA et du retour du coach d'anglais.
final class SessionDetailViewModelProvider
    extends $AsyncNotifierProvider<SessionDetailViewModel, SessionDetailState> {
  /// ViewModel de l'ecran de detail d'une session.
  ///
  /// Charge la session et ses segments, gere l'edition du titre,
  /// la suppression, l'export, la copie, ainsi que la generation a la demande
  /// du resume IA et du retour du coach d'anglais.
  const SessionDetailViewModelProvider._({
    required SessionDetailViewModelFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'sessionDetailViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$sessionDetailViewModelHash();

  @override
  String toString() {
    return r'sessionDetailViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  SessionDetailViewModel create() => SessionDetailViewModel();

  @override
  bool operator ==(Object other) {
    return other is SessionDetailViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$sessionDetailViewModelHash() =>
    r'70b88e342da19e4775a903ebb61bc87d5207a910';

/// ViewModel de l'ecran de detail d'une session.
///
/// Charge la session et ses segments, gere l'edition du titre,
/// la suppression, l'export, la copie, ainsi que la generation a la demande
/// du resume IA et du retour du coach d'anglais.

final class SessionDetailViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          SessionDetailViewModel,
          AsyncValue<SessionDetailState>,
          SessionDetailState,
          FutureOr<SessionDetailState>,
          String
        > {
  const SessionDetailViewModelFamily._()
    : super(
        retry: null,
        name: r'sessionDetailViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// ViewModel de l'ecran de detail d'une session.
  ///
  /// Charge la session et ses segments, gere l'edition du titre,
  /// la suppression, l'export, la copie, ainsi que la generation a la demande
  /// du resume IA et du retour du coach d'anglais.

  SessionDetailViewModelProvider call({required String sessionId}) =>
      SessionDetailViewModelProvider._(argument: sessionId, from: this);

  @override
  String toString() => r'sessionDetailViewModelProvider';
}

/// ViewModel de l'ecran de detail d'une session.
///
/// Charge la session et ses segments, gere l'edition du titre,
/// la suppression, l'export, la copie, ainsi que la generation a la demande
/// du resume IA et du retour du coach d'anglais.

abstract class _$SessionDetailViewModel
    extends $AsyncNotifier<SessionDetailState> {
  late final _$args = ref.$arg as String;
  String get sessionId => _$args;

  FutureOr<SessionDetailState> build({required String sessionId});
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build(sessionId: _$args);
    final ref =
        this.ref as $Ref<AsyncValue<SessionDetailState>, SessionDetailState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<SessionDetailState>, SessionDetailState>,
              AsyncValue<SessionDetailState>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
