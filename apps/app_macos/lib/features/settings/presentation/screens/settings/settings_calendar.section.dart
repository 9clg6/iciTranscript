part of 'settings.screen.dart';

/// Section « Agenda et réunions » : connexion, agendas inclus, détection des
/// réunions et démarrage automatique.
class _CalendarSection extends ConsumerWidget {
  const _CalendarSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Oats o = context.oats;
    final CalendarFeed? feed = ref.watch(calendarFeedControllerProvider).value;
    final CalendarFeedController calendar = ref.read(
      calendarFeedControllerProvider.notifier,
    );
    final CalendarPrefs prefs =
        ref.watch(calendarPrefsControllerProvider).value ??
        const CalendarPrefs();
    final CalendarPrefsController prefsVm = ref.read(
      calendarPrefsControllerProvider.notifier,
    );
    final bool micSupported =
        ref.watch(meetingDetectionSupportedProvider).value ?? true;
    final List<CalendarInfo> calendars = feed is CalendarEvents
        ? ref.watch(calendarListProvider).value ?? const <CalendarInfo>[]
        : const <CalendarInfo>[];
    final List<String> allIds = <String>[
      for (final CalendarInfo c in calendars) c.id,
    ];

    return _Section(
      title: LocaleKeys.settings_calendar_title.tr(),
      rows: <Widget>[
        switch (feed) {
          CalendarDenied() => _Row(
            label: LocaleKeys.settings_calendar_denied.tr(),
            trailing: OatsButton(
              label: LocaleKeys.settings_calendar_open_settings.tr(),
              onPressed: calendar.openPrivacySettings,
            ),
          ),
          CalendarEvents() => _Row(
            label: LocaleKeys.settings_calendar_privacy.tr(),
            trailing: OatsButton(
              label: LocaleKeys.settings_calendar_disconnect.tr(),
              onPressed: calendar.disconnect,
            ),
          ),
          _ => _Row(
            label: LocaleKeys.settings_calendar_privacy.tr(),
            trailing: OatsButton(
              icon: Icons.link,
              label: LocaleKeys.settings_calendar_connect.tr(),
              onPressed: feed == null ? null : calendar.connect,
            ),
          ),
        },
        if (calendars.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              OatsSpace.lg,
              OatsSpace.md,
              OatsSpace.lg,
              OatsSpace.xs,
            ),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                LocaleKeys.settings_calendar_calendars.tr(),
                style: o.label,
              ),
            ),
          ),
        for (final CalendarInfo c in calendars)
          _Row(
            label: c.title,
            trailing: OatsSwitch(
              value: prefs.includes(c.id),
              onChanged: (bool v) =>
                  prefsVm.setIncluded(c.id, v, allIds: allIds),
            ),
          ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _Row(
              label: LocaleKeys.settings_calendar_detection.tr(),
              trailing: OatsSwitch(
                value: prefs.detectionEnabled,
                onChanged: prefsVm.setDetectionEnabled,
              ),
            ),
            if (!micSupported)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  OatsSpace.lg,
                  0,
                  OatsSpace.lg,
                  OatsSpace.md,
                ),
                child: Text(
                  LocaleKeys.settings_calendar_mic_unsupported.tr(),
                  style: o.meta,
                ),
              ),
          ],
        ),
        _Row(
          label: LocaleKeys.settings_calendar_auto_start.tr(),
          trailing: OatsSwitch(
            value: prefs.autoStart,
            onChanged: prefs.detectionEnabled ? prefsVm.setAutoStart : null,
          ),
        ),
      ],
    );
  }
}
