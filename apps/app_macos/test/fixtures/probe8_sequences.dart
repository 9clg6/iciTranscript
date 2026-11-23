// GÉNÉRÉ depuis la sonde 8 (scratchpad/probe/live8/svc_Dlag.jsonl : Dlag
// AVEC rattrapage, vrai service contre vrai serveur, voix de synthèse). Ne
// pas retoucher à la main : séquences réellement produites, copiées telles
// quelles. Même texte lu que la sonde 5 ([probeReference]).
//
// Segments rangés AVANT le rattrapage (dernier état de chaque id avant le
// premier plan, à 420 s ; le repère 2:24–2:30 absorbé par la fusion est
// retiré) ; pour chaque repère, le début de l'intervalle planifié et le
// texte que le rattrapage a rendu (segments `<repère>_backfill_N`, heure
// depuis le début de l'intervalle).
//
// La phrase système 11 (« La voisine a nettoyé le kiosque… », audio
// 101,99–108,59 s) est rangée à 111,615 s (`_output_16`) : son `done` a
// reçu la fenêtre de la phrase 12. Le rattrapage de 1:49–1:58 l'a remplacée
// et n'a rendu que la phrase 12 : perdue, sans repère.

import 'probe5_sequences.dart';

const ProbeScenario probe8Dlag = (
  name: 'Dlag (sonde 8)',
  sessionId: '1795404977985',
  segments: <ProbeSegment>[
    (
      id: '1795404977985_input_1',
      source: 'input',
      timestampMs: 15,
      partial: false,
      text:
          'La gardienne a photographié le lavoir avec beaucoup de patience, puis le facteur a photographié la fontaine ronde pendant la fête du village.',
    ),
    (
      id: '1795404977985_output_2',
      source: 'output',
      timestampMs: 15,
      partial: false,
      text:
          'The baker cleaned the old greenhouse without telling anyone, and then the librarian cleaned the bus shelter with a lot of patience.',
    ),
    (
      id: '1795404977985_output_3',
      source: 'output',
      timestampMs: 9015,
      partial: false,
      text:
          'Le libraire a rangé la fontaine ronde malgré le vent froid, puis la gardienne a réparé la vieille barrière pour la rentrée des classes.',
    ),
    (
      id: '1795404977985_input_4',
      source: 'input',
      timestampMs: 10615,
      partial: false,
      text:
          'The gardener cleaned the green bench before the evening rain, and then the painter tidied the round fountain before the evening rain.',
    ),
    (
      id: '1795404977985_output_5',
      source: 'output',
      timestampMs: 18715,
      partial: false,
      text: 'The',
    ),
    (
      id: '1795404977985_input_8',
      source: 'input',
      timestampMs: 73015,
      partial: false,
      text:
          'Affiez le lavoir sous un ciel gris, puis la voisine a photographié le kiosque à journaux sous un ciel gris.',
    ),
    (
      id: '1795404977985_output_11',
      source: 'output',
      timestampMs: 74315,
      partial: false,
      text:
          'Graph the green bench despite the cold wind, and then the postman cleaned the green bench despite the cold wind.',
    ),
    (
      id: '1795404977985_input_9',
      source: 'input',
      timestampMs: 82915,
      partial: false,
      text:
          'The painter painted the bus shelter for the start of school, and then the teacher repaired the garden gate without telling anyone.',
    ),
    (
      id: '1795404977985_output_12',
      source: 'output',
      timestampMs: 83715,
      partial: false,
      text:
          'Le libraire a décoré le kiosque à journaux malgré le vent froid, puis la gardienne a nettoyé le portail pour la rentrée des classes.',
    ),
    (
      id: '1795404977985_input_10',
      source: 'input',
      timestampMs: 91415,
      partial: false,
      text:
          'La voisine a nettoyé la cabane pendant la fête du village, puis le jardinier a nettoyé le kiosque à journaux malgré le vent froid.',
    ),
    (
      id: '1795404977985_output_14',
      source: 'output',
      timestampMs: 92815,
      partial: false,
      text:
          'The librarian painted the old greenhouse for the start of school, and then the baker measured the round fountain before the evening rain.',
    ),
    (
      id: '1795404977985_input_13',
      source: 'input',
      timestampMs: 101015,
      partial: false,
      text:
          'The baker decorated the garden gate for the start of school, and then the postman painted the green bench with a lot of patience.',
    ),
    (
      id: '1795404977985_output_18',
      source: 'output',
      timestampMs: 109115,
      partial: false,
      text:
          'Le libraire a nettoyé le kiosque à journaux avec beaucoup de patience, puis la voisine a nettoyé le kiosque à journaux',
    ),
    (
      id: '1795404977985_input_15',
      source: 'input',
      timestampMs: 110515,
      partial: false,
      text:
          'La voisine a repeint le portail au lever du soleil, puis la gardienne a nettoyé le lavoir sous un ciel gris.',
    ),
    (
      id: '1795404977985_output_16',
      source: 'output',
      timestampMs: 111615,
      partial: false,
      text:
          'La voisine a nettoyé le kiosque à journaux avant la pluie du soir, puis le maire a mesuré le portail avec beaucoup de patience.',
    ),
    (
      id: '1795404977985_input_17',
      source: 'input',
      timestampMs: 119115,
      partial: false,
      text:
          'My neighbor cleaned the garden gate with a lot of patience, and then the teacher moved the round fountain with a lot of',
    ),
    (
      id: '1795404977985_output_25',
      source: 'output',
      timestampMs: 156915,
      partial: false,
      text:
          'La gardienne a déplacé la vieille barrière avant la pluie de soir, puis la gardienne a nettoyé le kiosque à journaux sous un ciel gris.',
    ),
    (
      id: '1795404977985_input_23',
      source: 'input',
      timestampMs: 158915,
      partial: false,
      text:
          'school, and then the mayor moved the wooden fence before the evening rain.',
    ),
    (
      id: '1795404977985_output_26',
      source: 'output',
      timestampMs: 165815,
      partial: false,
      text: 'The teacher cleaned',
    ),
    (
      id: '1795404977985_input_24',
      source: 'input',
      timestampMs: 166915,
      partial: false,
      text:
          'Le maire a mesuré la fontaine ronde pendant la fête du village, puis la musicienne a nettoyé le lavoir au lever du soleil.',
    ),
  ],
  gaps: <ProbeGap>[
    (
      markerId: '1795404977985_output_7',
      source: 'output',
      markerStartMs: 18715,
      markerEndMs: 75000,
      planStartMs: 17715,
      recovered: <({int offsetMs, String text})>[
        (
          offsetMs: 0,
          text:
              'The librarian tidied the small cabin with a lot of patience, and then the postman painted the old greenhouse with a lot of patience.',
        ),
        (
          offsetMs: 9600,
          text:
              'La boulangère a décoré le portail sans prévenir personne, puis le jardinier a mesuré le banc vert avant la pluie du soir.',
        ),
        (
          offsetMs: 18400,
          text:
              'The librarian photographed the garden gate despite the cold wind, and then the baker moved the green bench for the start of school.',
        ),
        (
          offsetMs: 27800,
          text:
              'Le facteur a mesuré la fontaine ronde malgré le vent froid, puis le facteur a photographié le lavoir pendant la fête du village.',
        ),
        (
          offsetMs: 36400,
          text:
              'The mayor measured the round fountain without telling anyone, and then the gardener photographed the old greenhouse without telling anyone.',
        ),
        (
          offsetMs: 45700,
          text:
              'Lo veo a Photoshop vacío y el kiosque à journaux pour la rentrée des classes, puis la boulangère a repeint la cabane avant la pluie du soir.',
        ),
        (
          offsetMs: 54900,
          text:
              'The baker photographed the green bench despite the cold wind, and then the postman cleaned the green bench despite the cold wind.',
        ),
      ],
    ),
    (
      markerId: '1795404977985_input_6',
      source: 'input',
      markerStartMs: 20115,
      markerEndMs: 74000,
      planStartMs: 19115,
      recovered: <({int offsetMs, String text})>[
        (
          offsetMs: 0,
          text:
              'La boulangère a repeint la vieille barrière avec beaucoup de patience, puis la voisine a repeint le lavoir au lever du soleil.',
        ),
        (
          offsetMs: 8900,
          text:
              'The teacher moved the garden gate despite the cold wind, and then the baker painted the stone wall without telling anyone.',
        ),
        (
          offsetMs: 17600,
          text:
              'La boulangère a décoré le portail avec beaucoup de patience, puis le maire a repeint le banc vert pendant la fête du village.',
        ),
        (
          offsetMs: 26900,
          text:
              'The postman measured the bus shelter during the village fair, and then the baker repaired the old greenhouse with a lot of patience.',
        ),
        (
          offsetMs: 35900,
          text:
              'La gardienne a rangé la cabane pour la rentrée des classes, puis la boulangère a réparé la serre au lever du soleil.',
        ),
        (
          offsetMs: 44200,
          text:
              'The gardener decorated the wooden fence for the start of school, and then the postman cleaned the old greenhouse during the village fair.',
        ),
        (
          offsetMs: 52900,
          text:
              'Le jardinier a photographié le lavoir sous un ciel gris, puis la voisine a photographié le kiosque à journaux sous un ciel gris.',
        ),
      ],
    ),
    (
      markerId: '1795404977985_output_20',
      source: 'output',
      markerStartMs: 109115,
      markerEndMs: 118000,
      planStartMs: 108115,
      recovered: <({int offsetMs, String text})>[
        (
          offsetMs: 3400,
          text:
              'The mayor painted the stone wall during the village fair, and then the gardener moved the bus shelter before the evening rain.',
        ),
      ],
    ),
    (
      markerId: '1795404977985_input_19',
      source: 'input',
      markerStartMs: 119115,
      markerEndMs: 161000,
      planStartMs: 118115,
      recovered: <({int offsetMs, String text})>[
        (
          offsetMs: 0,
          text:
              'My neighbor cleaned the garden gate with a lot of patience, and then the teacher moved the round fountain with a lot of patience.',
        ),
        (
          offsetMs: 8800,
          text:
              'Le libraire a photographié le banc vert pour la rentrée des classes, puis le jardinier a déplacé le banc vert avant la pluie du soir.',
        ),
        (
          offsetMs: 19100,
          text:
              'The gardener moved the bus shelter without telling anyone, and then the painter tidied the garden gate under a grey sky.',
        ),
        (
          offsetMs: 28400,
          text:
              'La boulangère a nettoyé le kiosque à journaux malgré le vent froid, puis la boulangère a décoré le kiosque à journaux avec beaucoup de patience.',
        ),
        (
          offsetMs: 39100,
          text:
              'The baker painted the garden gate for the start of school, and then the mayor moved the wooden fence before the evening rain.',
        ),
      ],
    ),
    (
      markerId: '1795404977985_output_21',
      source: 'output',
      markerStartMs: 120515,
      markerEndMs: 155000,
      planStartMs: 119515,
      recovered: <({int offsetMs, String text})>[
        (
          offsetMs: 0,
          text:
              'Le libraire a nettoyé le kiosque à journaux avec beaucoup de patience, puis la voisine a nettoyé le kiosque à journaux au lever du soleil.',
        ),
        (
          offsetMs: 8500,
          text:
              'The librarian decorated the old greenhouse with a lot of patience, and then the teacher painted the round fountain with a lot of patience.',
        ),
        (
          offsetMs: 18200,
          text:
              'La boulangère a décoré la cabane pendant la fête du village, puis le libraire a rangé la fontaine ronde avec beaucoup de patience.',
        ),
        (
          offsetMs: 27000,
          text:
              'The baker painted the old greenhouse at sunrise, and then the librarian painted the small cabin with a lot of patience.',
        ),
        (
          offsetMs: 36300,
          text:
              'La gardienne a déplacé la vieille barrière avant la pluie du soir, puis la gardienne a nettoyé le kiosque à journaux sous un ciel gris.',
        ),
      ],
    ),
    (
      markerId: '1795404977985_output_28',
      source: 'output',
      markerStartMs: 165815,
      markerEndMs: 299000,
      planStartMs: 164815,
      recovered: <({int offsetMs, String text})>[
        (
          offsetMs: 0,
          text:
              'The teacher cleaned the round fountain without telling anyone, and then the postman repaired the round fountain despite the cold wind.',
        ),
        (
          offsetMs: 8900,
          text:
              'La boulangère a basuré la cabane malgré le vent froid, puis le libraire a basuré la cabane avec beaucoup de patience.',
        ),
        (
          offsetMs: 17600,
          text:
              'The librarian repaired the wooden fence with a lot of patience, and then my neighbor photographed the stone wall at sunrise.',
        ),
        (
          offsetMs: 27700,
          text:
              'La musicienne a rangé le kiosque à journaux sous un ciel gris, puis la boulangère a repeint le portail pendant la fête du village.',
        ),
        (
          offsetMs: 37000,
          text:
              'The painter moved the small cabin without telling anyone, and then the gardener painted the round fountain for the start of school.',
        ),
        (
          offsetMs: 46300,
          text:
              'La musicienne a basuré la cabane sous un ciel gris, puis le libraire a réparé la fontaine ronde pendant la fête du village.',
        ),
        (
          offsetMs: 54800,
          text:
              'The Gognatided the Green Bench before the evening rain, and then the librarian repaired the old greenhouse without telling anyone.',
        ),
        (
          offsetMs: 65000,
          text:
              'L\'auberge a basuré le kiosque à journaux pour la rentrée des classes, puis le facteur a déplacé la cabane malgré le vent froid.',
        ),
        (
          offsetMs: 74300,
          text:
              'The teacher painted the bus shelter before the evening rain, and then the postman painted the old greenhouse without telling anyone.',
        ),
        (
          offsetMs: 84300,
          text:
              'Le libraire a repeint le kiosque à journaux pour la rentrée des classes, puis le jardinier a déplacé la serre sans prévenir personne.',
        ),
        (
          offsetMs: 93300,
          text:
              'The librarian photographed the green bench despite the cold wind, and then the postman repaired the bus shelter under a grey sky.',
        ),
        (
          offsetMs: 103100,
          text:
              'La gardienne allait soigner le lavoir avant la pluie du soir, puis le libraire a photographié la cabane sans prévenir personne.',
        ),
        (
          offsetMs: 112200,
          text:
              'The painter measured the small cabin without telling anyone, and then the mayor measured the garden gate without telling anyone.',
        ),
        (
          offsetMs: 121400,
          text:
              'Le jardinier a réparé la vieille barrière sous un ciel gris, puis le libraire a rangé la vieille barrière au lever du soleil.',
        ),
        (
          offsetMs: 130000,
          text:
              'The painter repaired the small cabin during the village fair, and',
        ),
      ],
    ),
    (
      markerId: '1795404977985_input_27',
      source: 'input',
      markerStartMs: 176715,
      markerEndMs: 300000,
      planStartMs: 175715,
      recovered: <({int offsetMs, String text})>[
        (
          offsetMs: 0,
          text:
              'My neighbor repaired the wooden fence despite the cold wind, and then the librarian measured the wooden fence before the evening rain.',
        ),
        (
          offsetMs: 9100,
          text:
              'La boulangère a photographié le banc vert sans prévenir personne, puis la musicienne a nettoyé le banc vert pendant la fête du village.',
        ),
        (
          offsetMs: 19500,
          text:
              'The librarian repaired the round fountain at sunrise, and then the librarian painted the stone wall during the village fair.',
        ),
        (
          offsetMs: 28400,
          text:
              'Le jardinier a photographié la vieille barrière pour la rentrée des classes, puis le libraire a repeint le banc vert pendant la fête du village.',
        ),
        (
          offsetMs: 38100,
          text:
              'The postman measured the bus shelter at sunrise, and then the painter tidied the stone wall despite the cold wind.',
        ),
        (
          offsetMs: 46700,
          text:
              'La boulangère a repeint la serre pendant la fête du village, puis la gardienne a repeint le kiosque à journaux pendant la fête du village.',
        ),
        (
          offsetMs: 56500,
          text:
              'The mayor measured the wooden fence at sunrise, and then the gardener cleaned the old greenhouse under a gray sky.',
        ),
        (
          offsetMs: 64900,
          text:
              'La gardienne a photographié le kiosque à journaux au lever du soleil, puis le libraire a décoré le kiosque à journaux pour la rentrée des classes.',
        ),
        (
          offsetMs: 75000,
          text:
              'The teacher photographed the old greenhouse at sunrise, and then the teacher cleaned the round fountain despite the cold wind.',
        ),
        (
          offsetMs: 83700,
          text:
              'Le jardinier a déplacé la serre sous un ciel gris, puis la boulangère a photographié le lavoir sans prévenir personne.',
        ),
        (
          offsetMs: 93100,
          text:
              'The painter photographed the stone wall at sunrise, and then the mayor decorated the green bench before the evening rain.',
        ),
        (
          offsetMs: 101500,
          text:
              'Le jardinier a décoré le portail sans prévenir personne, puis le jardinier a nettoyé la cabane malgré le vent froid.',
        ),
        (
          offsetMs: 110600,
          text:
              'The baker measured the old greenhouse under a grey sky, and then the baker painted the stone wall during the village fair.',
        ),
        (
          offsetMs: 119300,
          text:
              'La musicienne a déplacé le kiosque à journaux avec beaucoup de passion.',
        ),
      ],
    ),
  ],
);
