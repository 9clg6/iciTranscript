// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

part of 'app_router.dart';

/// generated route for
/// [LiveTranscriptionScreen]
class LiveTranscriptionRoute extends PageRouteInfo<void> {
  const LiveTranscriptionRoute({List<PageRouteInfo>? children})
    : super(LiveTranscriptionRoute.name, initialChildren: children);

  static const String name = 'LiveTranscriptionRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const LiveTranscriptionScreen();
    },
  );
}

/// generated route for
/// [MainShellScreen]
class MainShellRoute extends PageRouteInfo<void> {
  const MainShellRoute({List<PageRouteInfo>? children})
    : super(MainShellRoute.name, initialChildren: children);

  static const String name = 'MainShellRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const MainShellScreen();
    },
  );
}

/// generated route for
/// [SessionDetailScreen]
class SessionDetailRoute extends PageRouteInfo<SessionDetailRouteArgs> {
  SessionDetailRoute({
    required String sessionId,
    VoidCallback? onClose,
    Key? key,
    List<PageRouteInfo>? children,
  }) : super(
         SessionDetailRoute.name,
         args: SessionDetailRouteArgs(
           sessionId: sessionId,
           onClose: onClose,
           key: key,
         ),
         rawPathParams: {'sessionId': sessionId},
         initialChildren: children,
       );

  static const String name = 'SessionDetailRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      final pathParams = data.inheritedPathParams;
      final args = data.argsAs<SessionDetailRouteArgs>(
        orElse: () => SessionDetailRouteArgs(
          sessionId: pathParams.getString('sessionId'),
        ),
      );
      return SessionDetailScreen(
        sessionId: args.sessionId,
        onClose: args.onClose,
        key: args.key,
      );
    },
  );
}

class SessionDetailRouteArgs {
  const SessionDetailRouteArgs({
    required this.sessionId,
    this.onClose,
    this.key,
  });

  final String sessionId;

  final VoidCallback? onClose;

  final Key? key;

  @override
  String toString() {
    return 'SessionDetailRouteArgs{sessionId: $sessionId, onClose: $onClose, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SessionDetailRouteArgs) return false;
    return sessionId == other.sessionId &&
        onClose == other.onClose &&
        key == other.key;
  }

  @override
  int get hashCode => sessionId.hashCode ^ onClose.hashCode ^ key.hashCode;
}

/// generated route for
/// [SettingsScreen]
class SettingsRoute extends PageRouteInfo<void> {
  const SettingsRoute({List<PageRouteInfo>? children})
    : super(SettingsRoute.name, initialChildren: children);

  static const String name = 'SettingsRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const SettingsScreen();
    },
  );
}
