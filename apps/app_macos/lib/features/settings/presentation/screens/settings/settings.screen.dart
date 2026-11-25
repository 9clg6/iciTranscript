import 'dart:async';

import 'package:core_domain/domain/entities/audio_device.entity.dart';
import 'package:core_presentation/core_presentation.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ici_transcript/core/providers/services/api_key_store.provider.dart';
import 'package:ici_transcript/core/providers/platform/prefs_store.provider.dart';
import 'package:ici_transcript/application/services/stt/transcription_engine.dart';
import 'package:ici_transcript/application/services/dictation/dictation_controller.dart';
import 'package:ici_transcript/application/services/dictation/dictation_preferences.dart';
import 'package:ici_transcript/application/services/llm/llm_provider.dart';
import 'package:ici_transcript/application/services/llm/llm_settings.dart';
import 'package:ici_transcript/application/services/calendar/calendar_event.dart';
import 'package:ici_transcript/core/providers/platform/owned_processes.provider.dart';
import 'package:ici_transcript/features/calendar/calendar_feed.provider.dart';
import 'package:ici_transcript/features/calendar/calendar_prefs.provider.dart';
import 'package:ici_transcript/features/calendar/meeting_suggestion.provider.dart';
import 'package:ici_transcript/core/providers/services/dictation.provider.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.state.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.view_model.dart';
import 'package:ici_transcript/features/onboarding/presentation/ollama_setup.screen.dart';
import 'package:ici_transcript/features/settings/presentation/screens/settings/settings.state.dart';
import 'package:ici_transcript/features/settings/presentation/screens/settings/settings.view_model.dart';
import 'package:ici_transcript/features/settings/presentation/screens/settings/settings_dictation.view_model.dart';
import 'package:ici_transcript/generated/translations/locale_keys.g.dart';

part 'settings_ai.section.dart';
part 'settings_calendar.section.dart';
part 'settings_dictation.section.dart';
part 'settings_engine.section.dart';

/// Largeur de la colonne des réglages.
const double kSettingsWidth = 610;

/// Page Réglages du shell : audio, enregistrement, modèle local, agenda et
/// réunions, IA, serveur, stockage.
class SettingsScreen extends ConsumerStatefulWidget {
  /// Cree une instance de [SettingsScreen].
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final SettingsState state = ref.watch(settingsViewModelProvider);
    final SettingsViewModel vm = ref.read(settingsViewModelProvider.notifier);
    final LiveTranscriptionState live = ref.watch(
      liveTranscriptionViewModelProvider,
    );
    final LiveTranscriptionViewModel liveVm = ref.read(
      liveTranscriptionViewModelProvider.notifier,
    );
    final Oats o = context.oats;

    return Scaffold(
      backgroundColor: o.background,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          OatsSpace.xxxl,
          OatsSpace.xl,
          OatsSpace.xxxl,
          OatsSpace.xxxl,
        ),
        children: <Widget>[
          _Column(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                OatsPageHeader(title: LocaleKeys.settings_title.tr()),
                const SizedBox(height: OatsSpace.xl),
                _Section(
                  title: LocaleKeys.settings_audio_title.tr(),
                  rows: <Widget>[
                    _Row(
                      label: LocaleKeys.settings_audio_microphone.tr(),
                      trailing: state.availableDevices.isEmpty
                          ? Text('…', style: o.small)
                          : DropdownButton<String>(
                              value:
                                  state.selectedMicId ??
                                  state.availableDevices.first.id,
                              underline: const SizedBox.shrink(),
                              isDense: true,
                              style: o.ui,
                              dropdownColor: o.background,
                              borderRadius: BorderRadius.circular(
                                OatsRadius.md,
                              ),
                              items: <DropdownMenuItem<String>>[
                                for (final AudioDeviceEntity d
                                    in state.availableDevices)
                                  DropdownMenuItem<String>(
                                    value: d.id,
                                    child: Text(d.name),
                                  ),
                              ],
                              onChanged: (String? id) {
                                if (id != null) vm.updateMic(id);
                              },
                            ),
                    ),
                    _SttEngineRow(cloudAllowed: state.llmCloudAllowed),
                    _Row(
                      label: LocaleKeys.settings_audio_system_audio.tr(),
                      subtitle: LocaleKeys
                          .settings_audio_system_audio_description
                          .tr(),
                      trailing: OatsSwitch(
                        value: state.systemAudioEnabled,
                        onChanged: (_) => vm.toggleSystemAudio(),
                      ),
                    ),
                  ],
                ),
                _Section(
                  title: LocaleKeys.settings_recording_title.tr(),
                  rows: <Widget>[
                    _Row(
                      label: LocaleKeys.settings_recording_coach.tr(),
                      subtitle: LocaleKeys.settings_recording_coach_description
                          .tr(),
                      trailing: OatsSwitch(
                        value: live.isCoachEnabled,
                        onChanged: live.isRecording
                            ? null
                            : (_) => liveVm.toggleCoach(),
                      ),
                    ),
                    // En ligne seulement : en local, la transcription
                    // ralentirait (rien n'est envoyé pendant la réunion).
                    _Row(
                      label: LocaleKeys.coach_live_option.tr(),
                      subtitle: state.llmActive == LlmProviderId.ollama
                          ? LocaleKeys.coach_live_unavailable.tr()
                          : LocaleKeys.coach_live_description.tr(),
                      trailing: OatsSwitch(
                        value:
                            live.isLiveCoachEnabled &&
                            state.llmActive != LlmProviderId.ollama,
                        onChanged:
                            live.isRecording ||
                                state.llmActive == LlmProviderId.ollama
                            ? null
                            : (_) => liveVm.toggleLiveCoach(),
                      ),
                    ),
                    _Row(
                      label: LocaleKeys.settings_recording_speakers.tr(),
                      subtitle: LocaleKeys
                          .settings_recording_speakers_description
                          .tr(),
                      trailing: OatsSwitch(
                        value: live.isLiveSpeakersEnabled,
                        onChanged: live.isRecording
                            ? null
                            : (_) => liveVm.toggleLiveSpeakers(),
                      ),
                    ),
                  ],
                ),
                _Section(
                  title: LocaleKeys.settings_model_title.tr(),
                  rows: const <Widget>[
                    Padding(
                      padding: EdgeInsets.all(OatsSpace.lg),
                      child: OllamaSetupScreen(),
                    ),
                  ],
                ),
                const _CalendarSection(),
                const _AiSection(),
                const _DictationSection(),
                _Section(
                  title: LocaleKeys.settings_server_title.tr(),
                  rows: <Widget>[
                    _Row(
                      label: LocaleKeys.settings_server_model.tr(),
                      trailing: Text(
                        'Voxtral-Mini-4B-Realtime',
                        style: o.small,
                      ),
                    ),
                    // Lecture seule : le port suit le dossier de données.
                    _Row(
                      label: LocaleKeys.settings_server_port.tr(),
                      trailing: Text(
                        '${ref.watch(launchServerPortsProvider).transcription}',
                        style: o.small,
                      ),
                    ),
                    _Row(
                      label: LocaleKeys.settings_server_auto_launch.tr(),
                      trailing: OatsSwitch(
                        value: state.autoStartServer,
                        onChanged: (_) => vm.toggleAutoStart(),
                      ),
                    ),
                  ],
                ),
                _Section(
                  title: LocaleKeys.settings_storage_title.tr(),
                  rows: <Widget>[
                    _Row(
                      label: LocaleKeys.settings_storage_location.tr(),
                      subtitle: state.storagePath,
                      trailing: const SizedBox.shrink(),
                    ),
                    _Row(
                      label: LocaleKeys.settings_storage_database_size.tr(),
                      trailing: Text(
                        LocaleKeys.settings_storage_size_mb.tr(
                          args: <String>[state.dbSizeMb.toStringAsFixed(0)],
                        ),
                        style: o.small,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: kSettingsWidth),
      child: child,
    ),
  );
}

/// Section : intertitre gris puis carte bordée de lignes à filets.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.rows});

  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final Oats o = context.oats;
    return Padding(
      padding: const EdgeInsets.only(bottom: OatsSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          OatsSectionHeader(title),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: o.line),
              borderRadius: BorderRadius.circular(OatsRadius.lg),
            ),
            child: Column(
              children: <Widget>[
                for (int i = 0; i < rows.length; i++) ...<Widget>[
                  if (i > 0) const Divider(indent: OatsSpace.lg),
                  rows[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.trailing, this.subtitle});

  final String label;
  final String? subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final Oats o = context.oats;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: OatsSpace.lg,
          vertical: OatsSpace.sm,
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(label, style: o.ui),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Text(
                      subtitle!,
                      style: o.meta,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(width: OatsSpace.lg),
            trailing,
          ],
        ),
      ),
    );
  }
}
