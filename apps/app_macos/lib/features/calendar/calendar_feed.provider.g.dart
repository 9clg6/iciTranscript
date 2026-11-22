// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'calendar_feed.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Événements de l'agenda, relus quand l'agenda change, quand le jour change
/// et quand les réglages de l'agenda changent.

@ProviderFor(CalendarFeedController)
const calendarFeedControllerProvider = CalendarFeedControllerProvider._();

/// Événements de l'agenda, relus quand l'agenda change, quand le jour change
/// et quand les réglages de l'agenda changent.
final class CalendarFeedControllerProvider
    extends $AsyncNotifierProvider<CalendarFeedController, CalendarFeed> {
  /// Événements de l'agenda, relus quand l'agenda change, quand le jour change
  /// et quand les réglages de l'agenda changent.
  const CalendarFeedControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: _noRetry,
        name: r'calendarFeedControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$calendarFeedControllerHash();

  @$internal
  @override
  CalendarFeedController create() => CalendarFeedController();
}

String _$calendarFeedControllerHash() =>
    r'e009efcdaa6ffba0175fb493d26944e4d3268821';

/// Événements de l'agenda, relus quand l'agenda change, quand le jour change
/// et quand les réglages de l'agenda changent.

abstract class _$CalendarFeedController extends $AsyncNotifier<CalendarFeed> {
  FutureOr<CalendarFeed> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<AsyncValue<CalendarFeed>, CalendarFeed>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<CalendarFeed>, CalendarFeed>,
              AsyncValue<CalendarFeed>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// Agendas de l'utilisateur (à lire seulement une fois connecté et autorisé).

@ProviderFor(calendarList)
const calendarListProvider = CalendarListProvider._();

/// Agendas de l'utilisateur (à lire seulement une fois connecté et autorisé).

final class CalendarListProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<CalendarInfo>>,
          List<CalendarInfo>,
          FutureOr<List<CalendarInfo>>
        >
    with
        $FutureModifier<List<CalendarInfo>>,
        $FutureProvider<List<CalendarInfo>> {
  /// Agendas de l'utilisateur (à lire seulement une fois connecté et autorisé).
  const CalendarListProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'calendarListProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$calendarListHash();

  @$internal
  @override
  $FutureProviderElement<List<CalendarInfo>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<CalendarInfo>> create(Ref ref) {
    return calendarList(ref);
  }
}

String _$calendarListHash() => r'0cc352779990a5c3a302e67a28b41f8b74c591a5';
