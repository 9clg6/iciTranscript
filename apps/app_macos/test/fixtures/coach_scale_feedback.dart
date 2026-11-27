import 'package:core_domain/domain/entities/english_feedback.entity.dart';

/// Retour du coach à l'échelle d'une vraie note (2026-11-27) : 68
/// corrections, grammar 27, expression 19, vocabulary 16, conjugation 6 ;
/// 5 sans heure ; quelques longues reformulations ; vocabulaire et
/// expression mêlés aux autres types dans l'ordre de la réunion (comme le
/// modèle les rend). Phrases anglaises inventées.
///
/// Sert aux specs (`coach_rich_view_test.dart`) et au rendu de preuve
/// (`tool/coach_proof_render.dart`, hors commit).
final EnglishFeedbackEntity kCoachScaleFeedback = EnglishFeedbackEntity(
  overall:
      'Discours fluide sur une longue réunion ; les erreurs reviennent '
      'surtout sur les accords, les faux amis et quelques expressions '
      'calquées sur le français.',
  corrections: <EnglishCorrectionEntity>[
    for (int i = 0; i < _rows.length; i++)
      EnglishCorrectionEntity(
        original: _rows[i].$2,
        corrected: _rows[i].$3,
        category: _rows[i].$1,
        explanation: _rows[i].$4,
        timestampMs: _untimed.contains(i) ? null : 20000 + i * 47000,
      ),
  ],
);

/// Rangs (dans [_rows]) des corrections sans heure.
const Set<int> _untimed = <int>{24, 28, 43, 58, 67};

const List<(String, String, String, String)> _rows =
    <(String, String, String, String)>[
      (
        'grammar',
        'I am agree with this plan',
        'I agree with this plan',
        '« agree » est un verbe : pas de « am ».',
      ),
      (
        'vocabulary',
        'Can you borrow me your charger',
        'Can you lend me your charger',
        '« borrow » = emprunter ; prêter se dit autrement.',
      ),
      (
        'grammar',
        'He have sent the report',
        'He has sent the report',
        'Avec « he », l\'auxiliaire est « has ».',
      ),
      (
        'expression',
        'I look forward to see you there',
        'I look forward to seeing you there',
        '« look forward to » est suivi de la forme en -ing.',
      ),
      (
        'conjugation',
        'Yesterday we decide to wait',
        'Yesterday we decided to wait',
        'Action passée : prétérit.',
      ),
      (
        'vocabulary',
        'We must take a decision today',
        'We must make a decision today',
        'Une décision se « fait » en anglais.',
      ),
      (
        'grammar',
        'She don\'t know the client yet',
        'She doesn\'t know the client yet',
        'Troisième personne : « doesn\'t ».',
      ),
      (
        'expression',
        'We discussed about the roadmap',
        'We discussed the roadmap',
        '« discuss » se construit sans « about ».',
      ),
      (
        'grammar',
        'There is many open tickets',
        'There are many open tickets',
        'Pluriel : « there are ».',
      ),
      (
        'vocabulary',
        'The workshop was funny overall',
        'The workshop was fun overall',
        '« funny » veut dire drôle, pas agréable.',
      ),
      (
        'expression',
        'Do the call now',
        'Make the call now',
        'Un appel se passe avec le même verbe qu\'une décision.',
      ),
      (
        'grammar',
        'We have less people this month',
        'We have fewer people this month',
        'Dénombrable : « fewer ».',
      ),
      (
        'vocabulary',
        'I will assist to the review',
        'I will attend the review',
        'Faux ami : « assist » veut dire aider.',
      ),
      (
        'conjugation',
        'I am working here since 2020',
        'I have been working here since 2020',
        '« since » demande le present perfect continu.',
      ),
      (
        'expression',
        'This is not my cup of coffee',
        'This is not my cup of tea',
        'L\'expression anglaise parle de thé.',
      ),
      (
        'grammar',
        'The informations are in the doc',
        'The information is in the doc',
        '« information » est indénombrable.',
      ),
      (
        'vocabulary',
        'The planning is ready for review',
        'The schedule is ready for review',
        '« planning » n\'est pas un calendrier en anglais.',
      ),
      (
        'expression',
        'Let\'s go back to our sheep',
        'Let\'s go back to business',
        'Calque de « revenons à nos moutons ».',
      ),
      (
        'grammar',
        'Everybody have access now',
        'Everybody has access now',
        '« everybody » est singulier.',
      ),
      (
        'expression',
        'We should think out of the box here',
        'We should think outside the box here',
        'L\'expression figée dit « outside ».',
      ),
      (
        'grammar',
        'I didn\'t received the invite',
        'I didn\'t receive the invite',
        'Après « didn\'t », la base verbale.',
      ),
      (
        'vocabulary',
        'I need to actualize the dashboard',
        'I need to update the dashboard',
        '« actualiser » ne se traduit pas mot à mot.',
      ),
      (
        'grammar',
        'It\'s the more important topic',
        'It\'s the most important topic',
        'Superlatif : « the most ».',
      ),
      (
        'expression',
        'On my point of view the risk is low',
        'From my point of view the risk is low',
        'On dit « from my point of view ».',
      ),
      (
        'conjugation',
        'When I will arrive, I call you',
        'When I arrive, I will call you',
        'Après « when », présent ; le futur va dans l\'autre partie.',
      ),
      (
        'vocabulary',
        'Can you control the figures again',
        'Can you check the figures again',
        'Vérifier des chiffres : pas « control ».',
      ),
      (
        'grammar',
        'We need to explain you the plan',
        'We need to explain the plan to you',
        '« explain something to someone ».',
      ),
      (
        'expression',
        'We will keep you on the loop',
        'We will keep you in the loop',
        'Tenir au courant : « in the loop ».',
      ),
      (
        'grammar',
        'Can you tell me what is the price',
        'Can you tell me what the price is',
        'Question indirecte : sujet avant le verbe.',
      ),
      (
        'vocabulary',
        'The formation starts next week',
        'The training starts next week',
        'Faux ami : « formation ».',
      ),
      (
        'expression',
        'It costs an arm and a foot',
        'It costs an arm and a leg',
        'L\'expression anglaise parle de la jambe.',
      ),
      (
        'grammar',
        'He is more faster than us',
        'He is faster than us',
        'Comparatif court : pas de « more ».',
      ),
      (
        'vocabulary',
        'We have a problematic with the API',
        'We have a problem with the API',
        '« problématique » n\'est pas un nom anglais.',
      ),
      (
        'grammar',
        'I am here since two hours',
        'I have been here for two hours',
        'Durée : present perfect et « for ».',
      ),
      (
        'expression',
        'We are on the same wave length',
        'We are on the same wavelength',
        'Un seul mot pour la longueur d\'onde.',
      ),
      (
        'conjugation',
        'Last week he go to Berlin',
        'Last week he went to Berlin',
        'Verbe irrégulier au prétérit.',
      ),
      (
        'vocabulary',
        'Please precise your question',
        'Please clarify your question',
        '« precise » est un adjectif.',
      ),
      (
        'grammar',
        'We was waiting for the green light',
        'We were waiting for the green light',
        'Pluriel : « were ».',
      ),
      (
        'expression',
        'Let me know if you have any question',
        'Let me know if you have any questions',
        '« any questions » au pluriel.',
      ),
      (
        'grammar',
        'Each teams has a lead',
        'Each team has a lead',
        '« each » est suivi du singulier.',
      ),
      (
        'vocabulary',
        'The deadline is too short for us',
        'The deadline is too tight for us',
        'Un délai serré.',
      ),
      (
        'expression',
        'To make a long story shorter we stopped',
        'To make a long story short we stopped',
        'Expression figée, sans comparatif.',
      ),
      (
        'grammar',
        'The data shows a increase',
        'The data shows an increase',
        '« an » devant une voyelle.',
      ),
      (
        'vocabulary',
        'We will realize the project in March',
        'We will carry out the project in March',
        '« realize » veut dire se rendre compte.',
      ),
      (
        'grammar',
        'She said me that it was fine',
        'She told me that it was fine',
        '« say » ne prend pas de complément de personne.',
      ),
      (
        'expression',
        'It was a piece of pie',
        'It was a piece of cake',
        'C\'est du gâteau, littéralement.',
      ),
      (
        'conjugation',
        'We have finished it last Monday',
        'We finished it last Monday',
        'Moment passé daté : prétérit.',
      ),
      (
        'vocabulary',
        'I am responsible of the budget',
        'I am responsible for the budget',
        'Responsable de : préposition « for ».',
      ),
      (
        'grammar',
        'We must to finish today',
        'We must finish today',
        'Après « must », pas de « to ».',
      ),
      (
        'expression',
        'Let\'s call it one day',
        'Let\'s call it a day',
        'S\'arrêter là pour aujourd\'hui.',
      ),
      (
        'grammar',
        'It depend on the client',
        'It depends on the client',
        'Troisième personne : -s.',
      ),
      (
        'expression',
        'I will come back to you tomorrow',
        'I will get back to you tomorrow',
        'Revenir vers quelqu\'un avec une réponse.',
      ),
      (
        'vocabulary',
        'The figures are actually wrong',
        'The figures are currently wrong',
        '« actually » veut dire en fait.',
      ),
      (
        'grammar',
        'This feature is very useful for to save time',
        'This feature is very useful to save time',
        'Pas de « for » devant l\'infinitif.',
      ),
      (
        'expression',
        'So basically what I wanted to say is that we are not really sure '
            'that the timeline that we proposed last week is still realistic',
        'What I meant is that we are no longer sure the timeline we '
            'proposed last week is realistic',
        'Phrase plus directe, sans répétitions.',
      ),
      (
        'grammar',
        'How much users do we have',
        'How many users do we have',
        'Dénombrable : « how many ».',
      ),
      (
        'vocabulary',
        'This is a very important stake for us',
        'This is a very important issue for us',
        'Un enjeu se dit autrement.',
      ),
      (
        'grammar',
        'I would like that you review it',
        'I would like you to review it',
        '« would like someone to do ».',
      ),
      (
        'expression',
        'Thanks in advance for your return',
        'Thanks in advance for your feedback',
        'Un retour sur un travail.',
      ),
      (
        'grammar',
        'The thing is that the people of the support team they don\'t have '
            'the access to the new tool since the migration',
        'The support team hasn\'t had access to the new tool since the '
            'migration',
        'Sujet unique, present perfect avec « since ».',
      ),
      (
        'vocabulary',
        'Send me the support after the call',
        'Send me the slides after the call',
        'Un support de présentation.',
      ),
      (
        'conjugation',
        'She has wrote the summary',
        'She has written the summary',
        'Participe passé de « write ».',
      ),
      (
        'grammar',
        'We are agree on the next steps',
        'We agree on the next steps',
        'Encore « agree » sans « be ».',
      ),
      (
        'expression',
        'No worries, it\'s not a big thing',
        'No worries, it\'s not a big deal',
        'Ce n\'est pas grave.',
      ),
      (
        'grammar',
        'Its a good point',
        'It\'s a good point',
        '« it\'s » = « it is ».',
      ),
      (
        'expression',
        'It goes without saying it',
        'It goes without saying',
        'L\'expression se suffit.',
      ),
      (
        'grammar',
        'Neither of them have replied',
        'Neither of them has replied',
        '« neither » est singulier.',
      ),
      (
        'grammar',
        'If we would have known that before we would have planned it '
            'differently for sure',
        'If we had known that before, we would certainly have planned it '
            'differently',
        'Condition passée : plus-que-parfait après « if ».',
      ),
    ];
