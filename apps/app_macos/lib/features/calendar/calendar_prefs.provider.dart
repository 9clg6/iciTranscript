import 'package:ici_transcript/core/platform/prefs_store.dart';
import 'package:ici_transcript/core/providers/platform/prefs_store.provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'calendar_prefs.provider.g.dart';

/// Réglages de l'agenda et de la détection de réunion (prefs.json).
class CalendarPrefs {
  /// Crée les réglages.
  const CalendarPrefs({
    this.connected = false,
    this.calendarIds,
    this.detectionEnabled = true,
    this.autoStart = false,
  });

  /// L'utilisateur a connecté l'agenda dans Oats.
  final bool connected;

  /// Agendas inclus ; null = tous (un agenda ajouté plus tard est inclus).
  final List<String>? calendarIds;

  /// Détection des réunions active.
  final bool detectionEnabled;

  /// Un événement de l'agenda démarre la note sans demander.
  final bool autoStart;

  /// Copie ; [calendarIds] reste celui-ci.
  CalendarPrefs copyWith({
    bool? connected,
    bool? detectionEnabled,
    bool? autoStart,
  }) => CalendarPrefs(
    connected: connected ?? this.connected,
    calendarIds: calendarIds,
    detectionEnabled: detectionEnabled ?? this.detectionEnabled,
    autoStart: autoStart ?? this.autoStart,
  );

  /// [id] fait partie des agendas lus.
  bool includes(String id) => calendarIds?.contains(id) ?? true;
}

const String _connectedKey = 'calendar_connected';
const String _idsKey = 'calendar_ids';
const String _detectionKey = 'meeting_detection_enabled';
const String _modeKey = 'meeting_detection_mode';

/// Lit et range [CalendarPrefs].
@Riverpod(keepAlive: true)
class CalendarPrefsController extends _$CalendarPrefsController {
  PrefsStore get _store => ref.read(prefsStoreProvider);

  @override
  Future<CalendarPrefs> build() async {
    final Map<String, Object?> json = await ref
        .watch(prefsStoreProvider)
        .read();
    return CalendarPrefs(
      connected: prefValue<bool>(json, _connectedKey) ?? false,
      calendarIds: prefValue<List<Object?>>(
        json,
        _idsKey,
      )?.whereType<String>().toList(),
      detectionEnabled: prefValue<bool>(json, _detectionKey) ?? true,
      autoStart: prefValue<String>(json, _modeKey) == 'auto',
    );
  }

  Future<CalendarPrefs> _current() => future;

  Future<void> _save(Map<String, Object?> values, CalendarPrefs next) async {
    await _store.update(values);
    state = AsyncData<CalendarPrefs>(next);
  }

  /// Connecte ou déconnecte l'agenda.
  Future<void> setConnected(bool connected) async {
    final CalendarPrefs p = await _current();
    await _save(<String, Object?>{
      _connectedKey: connected,
    }, p.copyWith(connected: connected));
  }

  /// Inclut ou exclut l'agenda [id] parmi [allIds] ; tout inclus = liste
  /// retirée.
  Future<void> setIncluded(
    String id,
    bool included, {
    required List<String> allIds,
  }) async {
    final CalendarPrefs p = await _current();
    final Set<String> ids = <String>{...p.calendarIds ?? allIds};
    included ? ids.add(id) : ids.remove(id);
    final bool all = allIds.every(ids.contains);
    final List<String>? next = all ? null : allIds.where(ids.contains).toList();
    await _save(
      <String, Object?>{_idsKey: next},
      CalendarPrefs(
        connected: p.connected,
        calendarIds: next,
        detectionEnabled: p.detectionEnabled,
        autoStart: p.autoStart,
      ),
    );
  }

  /// Active ou coupe la détection des réunions.
  Future<void> setDetectionEnabled(bool enabled) async {
    final CalendarPrefs p = await _current();
    await _save(<String, Object?>{
      _detectionKey: enabled,
    }, p.copyWith(detectionEnabled: enabled));
  }

  /// Démarrer automatiquement (`auto`) ou demander (`ask`).
  Future<void> setAutoStart(bool auto) async {
    final CalendarPrefs p = await _current();
    await _save(<String, Object?>{
      _modeKey: auto ? 'auto' : 'ask',
    }, p.copyWith(autoStart: auto));
  }
}
