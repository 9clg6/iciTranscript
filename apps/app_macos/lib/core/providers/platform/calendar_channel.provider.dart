import 'package:ici_transcript/core/platform/calendar_channel.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'calendar_channel.provider.g.dart';

/// Agenda macOS (remplacé par un faux canal dans les tests).
@Riverpod(keepAlive: true)
CalendarChannel calendarChannel(Ref ref) => const CalendarChannel();
