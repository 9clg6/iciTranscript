import 'package:core_domain/domain/entities/english_feedback.entity.dart';
import 'package:core_domain/domain/enum/server_state.enum.dart';
import 'package:core_presentation/core_presentation.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ici_transcript/application/services/ollama.service.dart';
import 'package:ici_transcript/application/services/transcript_grouping.dart';
import 'package:ici_transcript/core/providers/services/live_answers.service.provider.dart';
import 'package:ici_transcript/features/history/presentation/screens/list/session_list.view_model.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.state.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/live_transcription.view_model.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/widgets/server_status.widget.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/widgets/finalising.widget.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/widgets/live_answers_panel.widget.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/widgets/live_coach_block.widget.dart';
import 'package:ici_transcript/core/providers/services/live_coach.service.provider.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/widgets/session_controls.widget.dart';
import 'package:ici_transcript/features/live_transcription/presentation/screens/live/widgets/transcript_line.widget.dart';
import 'package:ici_transcript/features/shared/presentation/widgets/coach_feedback.widget.dart';
import 'package:ici_transcript/features/shell/presentation/shell_view.provider.dart';
import 'package:ici_transcript/generated/translations/locale_keys.g.dart';

/// Ecran de transcription en direct.
///
/// Barre d'outils (statut serveur, minuteur, contrôles), options, bannières
/// de permission, transcription en temps réel avec défilement automatique,
/// barre d'état des sources audio.
class LiveTranscriptionScreen extends ConsumerStatefulWidget {
  /// Cree une instance de [LiveTranscriptionScreen].
  const LiveTranscriptionScreen({super.key});

  @override
  ConsumerState<LiveTranscriptionScreen> createState() =>
      _LiveTranscriptionScreenState();
}

class _LiveTranscriptionScreenState
    extends ConsumerState<LiveTranscriptionScreen> {
  final ScrollController _scrollController = ScrollController();

  LiveTranscriptionViewModel get _vm =>
      ref.read(liveTranscriptionViewModelProvider.notifier);

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _formatDuration(Duration duration) {
    final String hours = duration.inHours.toString().padLeft(2, '0');
    final String minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final String seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final LiveTranscriptionState state = ref.watch(
      liveTranscriptionViewModelProvider,
    );
    final Oats o = context.oats;

    // Auto-scroll quand la transcription change : nombre de segments ET
    // longueur du dernier segment (la phrase en cours grandit en place).
    ref.listen(
      liveTranscriptionViewModelProvider.select(
        (LiveTranscriptionState s) => (
          s.segments.length,
          s.segments.isNotEmpty ? s.segments.last.text.length : 0,
        ),
      ),
      ((int, int)? previous, (int, int) next) => _scrollToBottom(),
    );

    final List<Widget> notices = <Widget>[
      if (state.micPermission == 'denied')
        _permissionNotice(
          icon: Icons.mic_off_outlined,
          message: LocaleKeys.transcription_live_mic_denied.tr(),
          danger: true,
          onOpenSettings: _vm.openMicSettings,
        ),
      if (state.screenRecordingPermission == 'denied')
        _permissionNotice(
          icon: Icons.desktop_mac_outlined,
          message: LocaleKeys.transcription_live_screen_denied.tr(),
          onOpenSettings: _vm.openScreenRecordingSettings,
        ),
      if (state.systemAudioError != null &&
          state.screenRecordingPermission != 'denied')
        _permissionNotice(
          icon: Icons.volume_off_outlined,
          message: LocaleKeys.transcription_live_system_audio_error.tr(
            args: <String>[state.systemAudioError!],
          ),
          onOpenSettings: _vm.openScreenRecordingSettings,
        ),
      if (state.ollamaSetupStage != OllamaSetupStage.idle &&
          state.ollamaSetupStage != OllamaSetupStage.ready &&
          state.ollamaSetupStage != OllamaSetupStage.error)
        _ollamaNotice(state),
    ];

    return Scaffold(
      backgroundColor: o.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildToolbar(state),
          _buildOptionsBar(state),
          ?_liveCoachReason(state),
          for (final Widget n in notices)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                OatsSpace.xl,
                OatsSpace.md,
                OatsSpace.xl,
                0,
              ),
              child: n,
            ),
          Expanded(
            child: state.isRecording
                ? _withQuestions(_buildTranscriptArea(state))
                : _buildTranscriptArea(state),
          ),
          if (state.feedback != null || state.isFeedbackLoading)
            _buildCoachPanel(state),
          _buildStatusBar(state),
        ],
      ),
    );
  }

  Widget _permissionNotice({
    required IconData icon,
    required String message,
    required VoidCallback onOpenSettings,
    bool danger = false,
  }) => OatsNotice(
    icon: icon,
    message: message,
    danger: danger,
    actions: <Widget>[
      OatsButton(
        label: LocaleKeys.common_action_open_settings.tr(),
        onPressed: onOpenSettings,
      ),
      OatsButton(
        label: LocaleKeys.common_action_recheck.tr(),
        onPressed: _vm.recheckPermissions,
      ),
    ],
  );

  Widget _ollamaNotice(LiveTranscriptionState state) {
    final String pct = (state.ollamaSetupProgress * 100).toStringAsFixed(0);
    final String label = switch (state.ollamaSetupStage) {
      OllamaSetupStage.downloadingBinary =>
        LocaleKeys.transcription_live_ollama_binary.tr(args: <String>[pct]),
      OllamaSetupStage.startingServer =>
        LocaleKeys.transcription_live_ollama_server.tr(),
      OllamaSetupStage.downloadingModel =>
        LocaleKeys.transcription_live_ollama_model.tr(args: <String>[pct]),
      _ => '',
    };
    return OatsNotice(icon: Icons.downloading_outlined, message: label);
  }

  Widget _optionLabel(IconData icon, String label) {
    final Oats o = context.oats;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: OatsIconSize.sm, color: o.muted),
        const SizedBox(width: OatsSpace.xs + 2),
        Text(label, style: o.meta),
      ],
    );
  }

  Widget _buildOptionsBar(LiveTranscriptionState state) {
    final Oats o = context.oats;
    final bool idle = !state.isRecording && !state.isPaused;
    Widget group(List<Widget> children) =>
        Row(mainAxisSize: MainAxisSize.min, children: children);
    // Options groupées : à l'étroit, elles passent à la ligne au lieu de
    // sortir de l'écran.
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.symmetric(
        horizontal: OatsSpace.xl,
        vertical: OatsSpace.xxs,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: o.line)),
      ),
      child: Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: OatsSpace.lg,
        children: <Widget>[
          if (idle) ...<Widget>[
            group(<Widget>[
              _optionLabel(
                Icons.school_outlined,
                LocaleKeys.transcription_live_coach_option.tr(),
              ),
              OatsSwitch(
                value: state.isCoachEnabled,
                onChanged: (_) => _vm.toggleCoach(),
              ),
            ]),
            _liveCoachOption(state),
            group(<Widget>[
              Tooltip(
                message: LocaleKeys.transcription_live_speakers_tooltip.tr(),
                child: _optionLabel(
                  Icons.groups_outlined,
                  LocaleKeys.transcription_live_speakers_option.tr(),
                ),
              ),
              OatsSwitch(
                value: state.isLiveSpeakersEnabled,
                onChanged: (_) => _vm.toggleLiveSpeakers(),
              ),
            ]),
          ],
          group(<Widget>[
            _optionLabel(
              Icons.translate,
              LocaleKeys.transcription_live_translation_option.tr(),
            ),
            const SizedBox(width: OatsSpace.sm),
            _langDropdown(
              state.translationFrom,
              (String v) => _vm.setTranslationLangs(from: v),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: OatsSpace.xs),
              child: Icon(Icons.arrow_forward, size: 12, color: o.faint),
            ),
            _langDropdown(
              state.translationTo,
              (String v) => _vm.setTranslationLangs(to: v),
            ),
            OatsSwitch(
              value: state.isTranslationEnabled,
              onChanged: (_) => _vm.toggleTranslation(),
            ),
          ]),
        ],
      ),
    );
  }

  /// « Coach en direct » : disponible seulement avec un fournisseur en
  /// ligne configuré et autorisé ; sinon désactivé, et la raison est dite
  /// sous les options.
  Widget _liveCoachOption(LiveTranscriptionState state) {
    final bool available =
        ref.watch(liveCoachAvailableProvider).value ?? false;
    return MergeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _optionLabel(Icons.bolt_outlined, LocaleKeys.coach_live_option.tr()),
          OatsSwitch(
            value: available && state.isLiveCoachEnabled,
            onChanged: available ? (_) => _vm.toggleLiveCoach() : null,
          ),
        ],
      ),
    );
  }

  /// Sous les options, avant de démarrer : pourquoi « Coach en direct » est
  /// désactivé (une ligne discrète, alignée comme les options).
  Widget? _liveCoachReason(LiveTranscriptionState state) {
    final AsyncValue<bool> available = ref.watch(liveCoachAvailableProvider);
    if (state.isRecording || state.isPaused || available.value != false) {
      return null;
    }
    final Oats o = context.oats;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        OatsSpace.xl,
        OatsSpace.xs + 2,
        OatsSpace.xl,
        0,
      ),
      child: Text(
        LocaleKeys.coach_live_unavailable.tr(),
        textAlign: TextAlign.right,
        style: o.meta.copyWith(color: o.faint),
      ),
    );
  }

  static const Map<String, String> _langs = <String, String>{
    'en': 'EN',
    'fr': 'FR',
    'es': 'ES',
    'de': 'DE',
    'it': 'IT',
    'pt': 'PT',
    'nl': 'NL',
  };

  Widget _langDropdown(String value, void Function(String) onChanged) {
    final Oats o = context.oats;
    return DropdownButton<String>(
      value: value,
      isDense: true,
      underline: const SizedBox.shrink(),
      icon: Icon(Icons.expand_more, size: OatsIconSize.sm, color: o.muted),
      style: o.meta.copyWith(color: o.ink, fontWeight: FontWeight.w500),
      dropdownColor: o.background,
      items: _langs.entries
          .map(
            (MapEntry<String, String> e) =>
                DropdownMenuItem<String>(value: e.key, child: Text(e.value)),
          )
          .toList(),
      onChanged: (String? v) {
        if (v != null) onChanged(v);
      },
    );
  }

  Widget _buildToolbar(LiveTranscriptionState state) {
    final Oats o = context.oats;
    // Pendant la finalisation, la capture est arrêtée : plus de pastille.
    final bool live =
        state.isRecording &&
        !state.isPaused &&
        state.finalisingRemaining == null;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: OatsSpace.lg,
        vertical: OatsSpace.sm + 2,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: o.line)),
      ),
      child: Row(
        children: <Widget>[
          // Pendant la finalisation, l'état du serveur n'apporte rien : la
          // place va au libellé de finalisation.
          if (state.finalisingRemaining == null)
            Flexible(
              child: ServerStatusWidget(
                serverState: state.serverState,
                portInUse: state.serverPortInUse,
              ),
            ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                if (live) ...<Widget>[
                  OatsLivePill(label: LocaleKeys.nav_recording.tr()),
                  const SizedBox(width: OatsSpace.md),
                ],
                Semantics(
                  label: LocaleKeys.transcription_live_recording_time.tr(),
                  child: Text(_formatDuration(state.duration), style: o.timer),
                ),
              ],
            ),
          ),
          if (state.finalisingRemaining case final Duration remaining)
            // Plus de place que le chrono : le libellé reste lisible.
            Flexible(
              flex: 3,
              child: FinalisingWidget(
                remaining: remaining,
                onSkip: _vm.skipFinalising,
              ),
            )
          else
            SessionControlsWidget(
              isRecording: state.isRecording,
              isPaused: state.isPaused,
              onStart: _vm.startSession,
              onPause: _vm.pauseSession,
              onResume: _vm.resumeSession,
              onStop: () async {
                final String? sessionId = await _vm.stopSession();
                if (sessionId != null) {
                  // Ouvrir la note dans le shell. Retour ramène à l'accueil,
                  // ou ici si le coach prépare son retour (panneau du bas).
                  ref
                      .read(shellViewControllerProvider.notifier)
                      .show(
                        state.isCoachEnabled ? ShellView.live : ShellView.home,
                      );
                  ref
                      .read(sessionListViewModelProvider.notifier)
                      .selectSession(sessionId);
                }
              },
            ),
        ],
      ),
    );
  }

  /// La transcription et, à droite, la zone « Questions ».
  Widget _withQuestions(Widget transcript) {
    final Oats o = context.oats;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(child: transcript),
          VerticalDivider(width: 1, thickness: 1, color: o.line),
          SizedBox(
            width: (c.maxWidth * 0.4).clamp(280, 400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Expanded(child: LiveAnswersPanel()),
                if (ref.watch(
                  liveTranscriptionViewModelProvider.select(
                    (LiveTranscriptionState s) => s.isLiveCoachEnabled,
                  ),
                ))
                  const LiveCoachBlock(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTranscriptArea(LiveTranscriptionState state) {
    final Oats o = context.oats;
    if (state.segments.isEmpty) {
      if (!state.isRecording) {
        return Center(
          child: Text(
            LocaleKeys.transcription_live_no_session.tr(),
            style: o.small,
          ),
        );
      }
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(
                width: OatsIconSize.lg,
                height: OatsIconSize.lg,
                child: CircularProgressIndicator(strokeWidth: 1.5),
              ),
              const SizedBox(height: OatsSpace.lg),
              Text(LocaleKeys.transcription_live_waiting.tr(), style: o.body),
              if (state.serverState == ServerState.starting) ...<Widget>[
                const SizedBox(height: OatsSpace.sm),
                Text(
                  LocaleKeys.transcription_live_first_launch.tr(),
                  textAlign: TextAlign.center,
                  style: o.small,
                ),
                if (state.serverStartupLine != null) ...<Widget>[
                  const SizedBox(height: OatsSpace.xs),
                  Text(
                    state.serverStartupLine!,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: o.meta.copyWith(fontFamily: 'Menlo'),
                  ),
                ],
              ],
            ],
          ),
        ),
      );
    }

    // Une phrase coupée par une pause reste sur un seul bloc.
    final List<TranscriptBlock> blocks = groupTranscript(
      state.segments,
      speakerLabels: state.speakerLabels,
    );
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(
        horizontal: OatsSpace.xxxl,
        vertical: OatsSpace.xl,
      ),
      itemCount: blocks.length,
      itemBuilder: (BuildContext context, int index) {
        final TranscriptBlock block = blocks[index];
        final List<String> parts = <String>[
          if (state.isTranslationEnabled)
            for (final String id in block.segmentIds)
              if (state.translations[id] case final String t) t,
        ];
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.only(bottom: OatsSpace.lg + 2),
              child: TranscriptLineWidget(
                segment: block.segment,
                translation: parts.isEmpty ? null : parts.join(' '),
                speaker: block.speaker,
                // Phrase en cours : pas encore finale.
                onAnswer: block.segment.id.startsWith('current_')
                    ? null
                    : () => ref
                          .read(liveAnswersServiceProvider)
                          .answerSegment(block.segment, speaker: block.speaker),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCoachPanel(LiveTranscriptionState state) {
    final Oats o = context.oats;
    final EnglishFeedbackEntity? feedback = state.feedback;
    return Container(
      constraints: const BoxConstraints(maxHeight: 280),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: o.line)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: OatsSpace.xxxl,
          vertical: OatsSpace.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              LocaleKeys.transcription_live_summary_title.tr(),
              style: o.heading,
            ),
            const SizedBox(height: OatsSpace.sm),
            if (state.isFeedbackLoading)
              Text(
                LocaleKeys.transcription_live_summary_loading.tr(),
                style: o.small,
              )
            else if (feedback != null)
              CoachFeedbackView(feedback: feedback),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBar(LiveTranscriptionState state) {
    final Oats o = context.oats;
    final bool micDenied = state.micPermission == 'denied';
    final bool systemOff =
        state.screenRecordingPermission == 'denied' ||
        state.systemAudioError != null;
    final String micText = LocaleKeys.transcription_status_bar_mic.tr(
      args: <String>[
        micDenied
            ? LocaleKeys.transcription_status_bar_denied.tr()
            : LocaleKeys.transcription_status_bar_active.tr(),
      ],
    );
    final String systemText = LocaleKeys.transcription_status_bar_system.tr(
      args: <String>[
        state.screenRecordingPermission == 'denied'
            ? LocaleKeys.transcription_status_bar_denied.tr()
            : state.systemAudioError != null
            ? LocaleKeys.transcription_status_bar_not_captured.tr()
            : state.screenRecordingPermission == 'authorized'
            ? LocaleKeys.transcription_status_bar_active.tr()
            : 'ScreenCaptureKit',
      ],
    );

    Widget source(IconData icon, String text, bool off) {
      final Color c = off ? o.danger : o.muted;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: OatsIconSize.sm, color: c),
          const SizedBox(width: OatsSpace.xs + 2),
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: o.meta.copyWith(color: c),
            ),
          ),
        ],
      );
    }

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: OatsSpace.xl),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: o.line)),
      ),
      child: Row(
        children: <Widget>[
          Flexible(
            child: source(
              micDenied ? Icons.mic_off_outlined : Icons.mic_none_outlined,
              micText,
              micDenied,
            ),
          ),
          const SizedBox(width: OatsSpace.xl),
          Flexible(
            child: source(Icons.desktop_mac_outlined, systemText, systemOff),
          ),
        ],
      ),
    );
  }
}
