// GÉNÉRÉ depuis la sonde 9 (scratchpad/probe/live9 : vrai service contre
// vrai serveur, branche oats-reliability-6 avec le départ du rattrapage
// ramené au dernier segment intact). Ne pas retoucher à la main. Même texte
// lu que la sonde 5 ([probeReference]).
//
// Segments rangés AVANT le rattrapage (dernier état de chaque id avant le
// premier plan ; repères absorbés retirés) ; pour chaque repère, le début
// de l'intervalle planifié (déjà ramené 2 s après le début du dernier
// segment intact) et le texte rendu (`<repère>_backfill_N`, heure depuis
// ce début). Doublons de fin enregistrés : A2 et D au micro vers 168,9 s,
// au système vers 11,0 s et 103,9 s ; S06 au système vers 47,3 s.

import 'probe5_sequences.dart';

const ProbeScenario probe9A2 = (
  name: 'A2 (sonde 9)',
  sessionId: '1795411095761',
  segments: <ProbeSegment>[
    (
      id: '1795411095761_input_1',
      source: 'input',
      timestampMs: 17,
      partial: false,
      text:
          'La gardienne a photographié le lavoir avec beaucoup de patience, puis le facteur a photographié la fontaine ronde pendant la fête du village.',
    ),
    (
      id: '1795411095761_output_2',
      source: 'output',
      timestampMs: 17,
      partial: false,
      text:
          'The baker cleaned the old greenhouse without telling anyone, and then the librarian cleaned the bus shelter with a lot of patience.',
    ),
    (
      id: '1795411095761_output_3',
      source: 'output',
      timestampMs: 9017,
      partial: false,
      text:
          'Le libraire a rangé la fontaine ronde malgré le vent froid, puis la gardienne a réparé la vieille barrière pour la rentrée des classes.',
    ),
    (
      id: '1795411095761_input_4',
      source: 'input',
      timestampMs: 10617,
      partial: false,
      text:
          'The gardener cleaned the green bench before the evening rain, and then the painter tidied the round fountain before the evening rain.',
    ),
    (
      id: '1795411095761_output_5',
      source: 'output',
      timestampMs: 18717,
      partial: false,
      text: 'The',
    ),
    (
      id: '1795411095761_input_8',
      source: 'input',
      timestampMs: 73017,
      partial: false,
      text:
          'Affiez le lavoir sous un ciel gris, puis la voisine a photographié le kiosque à journaux sous un ciel gris.',
    ),
    (
      id: '1795411095761_output_11',
      source: 'output',
      timestampMs: 74317,
      partial: false,
      text:
          'Graph the green bench despite the cold wind, and then the postman cleaned the green bench despite the cold wind.',
    ),
    (
      id: '1795411095761_input_9',
      source: 'input',
      timestampMs: 82917,
      partial: false,
      text:
          'The painter painted the bus shelter for the start of school, and then the teacher repaired the garden gate without telling anyone.',
    ),
    (
      id: '1795411095761_output_12',
      source: 'output',
      timestampMs: 83717,
      partial: false,
      text:
          'Le libraire a décoré le kiosque à journaux malgré le vent froid, puis la gardienne a nettoyé le portail pour la rentrée des classes.',
    ),
    (
      id: '1795411095761_input_10',
      source: 'input',
      timestampMs: 91417,
      partial: false,
      text:
          'La voisine a nettoyé la cabane pendant la fête du village, puis le jardinier a nettoyé le kiosque à journaux malgré le vent froid.',
    ),
    (
      id: '1795411095761_output_16',
      source: 'output',
      timestampMs: 92817,
      partial: false,
      text:
          'The librarian painted the old greenhouse for the start of school, and then the baker measured the round fountain before the evening rain.',
    ),
    (
      id: '1795411095761_input_13',
      source: 'input',
      timestampMs: 101017,
      partial: false,
      text:
          'The baker decorated the garden gate for the start of school, and then the postman painted the green bench with a lot of patience.',
    ),
    (
      id: '1795411095761_output_19',
      source: 'output',
      timestampMs: 101917,
      partial: false,
      text:
          'La voisine a nettoyé le kiosque à journaux avant la pluie du soir, puis le maire a mesuré le portail avec beaucoup de patience.',
    ),
    (
      id: '1795411095761_input_17',
      source: 'input',
      timestampMs: 110517,
      partial: false,
      text:
          'La voisine a repeint le portail au lever du soleil, puis la gardienne a nettoyé le lavoir sous un ciel gris.',
    ),
    (
      id: '1795411095761_output_21',
      source: 'output',
      timestampMs: 111617,
      partial: false,
      text:
          'The mayor painted the stone wall during the village fair, and then the gardener moved the bus shelter before the evening',
    ),
    (
      id: '1795411095761_input_20',
      source: 'input',
      timestampMs: 119117,
      partial: false,
      text:
          'My neighbor cleaned the garden gate with a lot of patience, and then the teacher moved the round fountain with a lot of',
    ),
    (
      id: '1795411095761_output_26',
      source: 'output',
      timestampMs: 156917,
      partial: false,
      text:
          'La gardienne a déplacé la vieille barrière avant la pluie de soir, puis la gardienne a nettoyé le kiosque à journaux sous un ciel gris.',
    ),
    (
      id: '1795411095761_input_23',
      source: 'input',
      timestampMs: 158917,
      partial: false,
      text:
          'school, and then the mayor moved the wooden fence before the evening rain.',
    ),
    (
      id: '1795411095761_output_27',
      source: 'output',
      timestampMs: 165817,
      partial: false,
      text: 'The teacher cleaned',
    ),
    (
      id: '1795411095761_input_24',
      source: 'input',
      timestampMs: 166917,
      partial: false,
      text:
          'Le maire a mesuré la fontaine ronde pendant la fête du village, puis la musicienne a nettoyé le lavoir au lever du soleil.',
    ),
    (
      id: '1795411095761_input_25',
      source: 'input',
      timestampMs: 176717,
      partial: false,
      text: 'My neighbor repaired the wooden',
    ),
  ],
  gaps: <ProbeGap>[
    (
      markerId: '1795411095761_output_7',
      source: 'output',
      markerStartMs: 18717,
      markerEndMs: 75000,
      planStartMs: 11017,
      recovered: <({int offsetMs, String text})>[
        (
          offsetMs: 0,
          text:
              'L\'Omavois, puis la gardienne a réparé la vieille barrière pour la rentrée des classes.',
        ),
        (
          offsetMs: 6000,
          text:
              'The librarian tidied the small cabin with a lot of patience, and then the postman painted the old greenhouse with a lot of patience.',
        ),
        (
          offsetMs: 16300,
          text:
              'La boulangère a décoré le portail sans prévenir personne, puis le jardinier a mesuré le banc vert avant la pluie du soir.',
        ),
        (
          offsetMs: 25100,
          text:
              'The librarian photographed the garden gate despite the cold wind, and then the baker moved the green bench for the start of school.',
        ),
        (
          offsetMs: 34500,
          text:
              'Le facteur a mesuré la fontaine ronde malgré le vent froid, puis le facteur a photographié le lavoir pendant la fête du village.',
        ),
        (
          offsetMs: 43100,
          text:
              'The mayor measured the round fountain without telling anyone, and then the gardener photographed the old greenhouse without telling anyone.',
        ),
        (
          offsetMs: 52400,
          text:
              'Lo veo a Photob vacier le kiosque à journaux pour la rentrée des classes, puis la boulangère a repeint la cabane avant la pluie du soir.',
        ),
        (
          offsetMs: 61600,
          text:
              'The baker photographed the green bench despite the cold wind, and then the postman cleaned the green bench despite the cold wind.',
        ),
      ],
    ),
    (
      markerId: '1795411095761_input_6',
      source: 'input',
      markerStartMs: 20117,
      markerEndMs: 74000,
      planStartMs: 19117,
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
      markerId: '1795411095761_output_14',
      source: 'output',
      markerStartMs: 111617,
      markerEndMs: 155000,
      planStartMs: 103917,
      recovered: <({int offsetMs, String text})>[
        (
          offsetMs: 0,
          text:
              'Dans la pluie de soir, puis le maire a mesuré le portail avec beaucoup de patience.',
        ),
        (
          offsetMs: 5900,
          text:
              'The mayor painted the stone wall during the village fair, and then the gardener moved the bus shelter before the evening rain.',
        ),
        (
          offsetMs: 15300,
          text:
              'Le libraire a nettoyé le kiosque à journaux avec beaucoup de patience, puis la voisine a nettoyé le kiosque à journaux au lever du soleil.',
        ),
        (
          offsetMs: 24100,
          text:
              'The librarian decorated the old greenhouse with a lot of patience, and then the teacher painted the round fountain with a lot of patience.',
        ),
        (
          offsetMs: 33800,
          text:
              'La boulangère a décoré la cabane pendant la fête du village, puis le libraire a rangé la fontaine ronde avec beaucoup de patience.',
        ),
        (
          offsetMs: 42600,
          text:
              'The baker painted the old greenhouse at sunrise, and then the librarian painted the small cabin with a lot of patience.',
        ),
        (
          offsetMs: 51900,
          text:
              'La gardienne a déplacé la vieille barrière avant la pluie du soir, puis la gardienne a nettoyé le kiosque à journaux sous un ciel gris.',
        ),
      ],
    ),
    (
      markerId: '1795411095761_input_22',
      source: 'input',
      markerStartMs: 119117,
      markerEndMs: 161000,
      planStartMs: 112517,
      recovered: <({int offsetMs, String text})>[
        (
          offsetMs: 5300,
          text:
              'My neighbor cleaned the garden gate with a lot of patience, and then the teacher moved the round fountain with a lot of patience.',
        ),
        (
          offsetMs: 14400,
          text:
              'Le libraire a photographié le banc vert pour la rentrée des classes, puis le jardinier a déplacé le banc vert avant la pluie du soir.',
        ),
        (
          offsetMs: 24700,
          text:
              'The gardener moved the bus shelter without telling anyone, and then the painter tidied the garden gate under a grey sky.',
        ),
        (
          offsetMs: 34000,
          text:
              'La boulangère a nettoyé le kiosque à journaux malgré le vent froid, puis la boulangère a décoré le kiosque à journaux avec beaucoup de patience.',
        ),
        (
          offsetMs: 44700,
          text:
              'The baker painted the garden gate for the start of school, and then the mayor moved the wooden fence before the evening rain.',
        ),
      ],
    ),
    (
      markerId: '1795411095761_output_29',
      source: 'output',
      markerStartMs: 165817,
      markerEndMs: 299000,
      planStartMs: 157817,
      recovered: <({int offsetMs, String text})>[
        (
          offsetMs: 7000,
          text:
              'The teacher cleaned the round fountain without telling anyone, and then the postman repaired the round fountain despite the cold wind.',
        ),
        (
          offsetMs: 15900,
          text:
              'La boulangère a basuré la cabane malgré le vent froid, puis le libraire a basuré la cabane avec beaucoup de patience.',
        ),
        (
          offsetMs: 24600,
          text:
              'The librarian repaired the wooden fence with a lot of patience, and then my neighbor photographed the stone wall at sunrise.',
        ),
        (
          offsetMs: 34700,
          text:
              'La musicienne a rangé le kiosque à journaux sous un ciel gris, puis la boulangère a repeint le portail pendant la fête du village.',
        ),
        (
          offsetMs: 44000,
          text:
              'The painter moved the small cabin without telling anyone, and then the gardener painted the round fountain for the start of school.',
        ),
        (
          offsetMs: 53300,
          text:
              'La musicienne a basuré la cabane sous un ciel gris, puis le libraire a réparé la fontaine ronde pendant la fête du village.',
        ),
        (
          offsetMs: 61800,
          text:
              'The Gognatided the Green Bench before the evening rain, and then the librarian repaired the old greenhouse without telling anyone.',
        ),
        (
          offsetMs: 72000,
          text:
              'L\'omère a basuré le kiosque à journaux pour la rentrée des classes, puis le facteur a déplacé la cabane malgré le vent froid.',
        ),
        (
          offsetMs: 81300,
          text:
              'The teacher painted the bus shelter before the evening rain, and then the postman painted the old greenhouse without telling anyone.',
        ),
        (
          offsetMs: 91300,
          text:
              'Le libraire a repeint le kiosque à journaux pour la rentrée des classes, puis le jardinier a déplacé la serre sans prévenir personne.',
        ),
        (
          offsetMs: 100300,
          text:
              'The librarian photographed the green bench despite the cold wind, and then the postman repaired the bus shelter under a grey sky.',
        ),
        (
          offsetMs: 110100,
          text:
              'La gardienne a nettoyé le lavoir avant la pluie du soir, puis le libraire a photographié la cabane sans prévenir personne.',
        ),
        (
          offsetMs: 119200,
          text:
              'The painter measured the small cabin without telling anyone, and then the mayor measured the garden gate without telling anyone.',
        ),
        (
          offsetMs: 128400,
          text:
              'Le jardinier a réparé la vieille barrière sous un ciel gris, puis le libraire a rangé la vieille barrière au lever du soleil.',
        ),
        (
          offsetMs: 137000,
          text:
              'The painter repaired the small cabin during the village fair, and',
        ),
      ],
    ),
    (
      markerId: '1795411095761_input_28',
      source: 'input',
      markerStartMs: 176717,
      markerEndMs: 300000,
      planStartMs: 168917,
      recovered: <({int offsetMs, String text})>[
        (
          offsetMs: 0,
          text:
              'Dans la fête du village, puis la musicienne a nettoyé le lavoir au lever du soleil.',
        ),
        (
          offsetMs: 6200,
          text:
              'My neighbor repaired the wooden fence despite the cold wind, and then the librarian measured the wooden fence before the evening rain.',
        ),
        (
          offsetMs: 15900,
          text:
              'La boulangère a photographié le banc vert sans prévenir personne, puis la musicienne a nettoyé le banc vert pendant la fête du village.',
        ),
        (
          offsetMs: 26300,
          text:
              'The librarian repaired the round fountain at sunrise, and then the librarian painted the stone wall during the village fair.',
        ),
        (
          offsetMs: 35200,
          text:
              'Le jardinier a photographié la vieille barrière pour la rentrée des classes, puis le libraire a repeint le banc vert pendant la fête du village.',
        ),
        (
          offsetMs: 44900,
          text:
              'The postman measured the bus shelter at sunrise, and then the painter tidied the stone wall despite the cold wind.',
        ),
        (
          offsetMs: 53500,
          text:
              'La boulangère a repeint la serre pendant la fête du village, puis la gardienne a repeint le kiosque à journaux pendant la fête du village.',
        ),
        (
          offsetMs: 63300,
          text:
              'The mayor measured the wooden fence at sunrise, and then the gardener cleaned the old greenhouse under a gray sky.',
        ),
        (
          offsetMs: 71700,
          text:
              'La gardienne a photographié le kiosque à journaux au lever du soleil, puis le libraire a décoré le kiosque à journaux pour la rentrée des classes.',
        ),
        (
          offsetMs: 81800,
          text:
              'The teacher photographed the old greenhouse at sunrise, and then the teacher cleaned the round fountain despite the cold wind.',
        ),
        (
          offsetMs: 90500,
          text:
              'Le jardinier a déplacé la serre sous un ciel gris, puis la boulangère a photographié le lavoir sans prévenir personne.',
        ),
        (
          offsetMs: 99800,
          text:
              'The painter photographed the stone wall at sunrise, and then the mayor decorated the green bench before the evening rain.',
        ),
        (
          offsetMs: 108300,
          text:
              'Le jardinier a décoré le portail sans prévenir personne, puis le jardinier a nettoyé la cabane malgré le vent froid.',
        ),
        (
          offsetMs: 117400,
          text:
              'The baker measured the old greenhouse under a grey sky, and then the baker painted the stone wall during the village fair.',
        ),
        (
          offsetMs: 126100,
          text:
              'La musicienne a déplacé le kiosque à journaux avec beaucoup de passion.',
        ),
      ],
    ),
  ],
);

const ProbeScenario probe9D = (
  name: 'D (sonde 9)',
  sessionId: '1795411768461',
  segments: <ProbeSegment>[
    (
      id: '1795411768461_input_2',
      source: 'input',
      timestampMs: 19,
      partial: false,
      text:
          'La gardienne a photographié le lavoir avec beaucoup de patience, puis le facteur a photographié la fontaine ronde pendant la fête du village.',
    ),
    (
      id: '1795411768461_output_1',
      source: 'output',
      timestampMs: 19,
      partial: false,
      text:
          'The baker cleaned the old greenhouse without telling anyone, and then the librarian cleaned the bus shelter with a lot of patience.',
    ),
    (
      id: '1795411768461_output_3',
      source: 'output',
      timestampMs: 9019,
      partial: false,
      text:
          'Le libraire a rangé la fontaine ronde malgré le vent froid, puis la gardienne a réparé la vieille barrière pour la rentrée des classes.',
    ),
    (
      id: '1795411768461_input_4',
      source: 'input',
      timestampMs: 10619,
      partial: false,
      text:
          'The gardener cleaned the green bench before the evening rain, and then the painter tidied the round fountain before the evening rain.',
    ),
    (
      id: '1795411768461_output_5',
      source: 'output',
      timestampMs: 18719,
      partial: false,
      text: 'The',
    ),
    (
      id: '1795411768461_input_8',
      source: 'input',
      timestampMs: 73019,
      partial: false,
      text:
          'Affiez le lavoir sous un ciel gris, puis la voisine a photographié le kiosque à journaux sous un ciel gris.',
    ),
    (
      id: '1795411768461_output_10',
      source: 'output',
      timestampMs: 74319,
      partial: false,
      text:
          'Graph the green bench despite the cold wind, and then the postman cleaned the green bench despite the cold wind.',
    ),
    (
      id: '1795411768461_input_9',
      source: 'input',
      timestampMs: 82919,
      partial: false,
      text:
          'The painter painted the bus shelter for the start of school, and then the teacher repaired the garden gate without telling anyone.',
    ),
    (
      id: '1795411768461_output_11',
      source: 'output',
      timestampMs: 83719,
      partial: false,
      text:
          'Le libraire a décoré le kiosque à journaux malgré le vent froid, puis la gardienne a nettoyé le portail pour la rentrée des classes.',
    ),
    (
      id: '1795411768461_input_12',
      source: 'input',
      timestampMs: 91419,
      partial: false,
      text:
          'La voisine a nettoyé la cabane pendant la fête du village, puis le jardinier a nettoyé le kiosque à journaux malgré le vent froid.',
    ),
    (
      id: '1795411768461_output_16',
      source: 'output',
      timestampMs: 92819,
      partial: false,
      text:
          'The librarian painted the old greenhouse for the start of school, and then the baker measured the round fountain before the evening rain.',
    ),
    (
      id: '1795411768461_input_13',
      source: 'input',
      timestampMs: 101019,
      partial: false,
      text:
          'The baker decorated the garden gate for the start of school, and then the postman painted the green bench with a lot of patience.',
    ),
    (
      id: '1795411768461_output_18',
      source: 'output',
      timestampMs: 101919,
      partial: false,
      text:
          'La voisine a nettoyé le kiosque à journaux avant la pluie du soir, puis le maire a mesuré le portail avec beaucoup de patience.',
    ),
    (
      id: '1795411768461_input_17',
      source: 'input',
      timestampMs: 110519,
      partial: false,
      text:
          'La voisine a repeint le portail au lever du soleil, puis la gardienne a nettoyé le lavoir sous un ciel gris.',
    ),
    (
      id: '1795411768461_output_20',
      source: 'output',
      timestampMs: 111619,
      partial: false,
      text:
          'The mayor painted the stone wall during the village fair, and then the gardener moved the bus shelter before the evening',
    ),
    (
      id: '1795411768461_input_19',
      source: 'input',
      timestampMs: 119119,
      partial: false,
      text:
          'My neighbor cleaned the garden gate with a lot of patience, and then the teacher moved the round fountain with a lot of',
    ),
    (
      id: '1795411768461_output_25',
      source: 'output',
      timestampMs: 156919,
      partial: false,
      text:
          'La gardienne a déplacé la vieille barrière avant la pluie de soir, puis la gardienne a nettoyé le kiosque à journaux sous un ciel gris.',
    ),
    (
      id: '1795411768461_input_22',
      source: 'input',
      timestampMs: 158919,
      partial: false,
      text:
          'school, and then the mayor moved the wooden fence before the evening rain.',
    ),
    (
      id: '1795411768461_output_26',
      source: 'output',
      timestampMs: 165819,
      partial: false,
      text: 'The teacher cleaned',
    ),
    (
      id: '1795411768461_input_23',
      source: 'input',
      timestampMs: 166919,
      partial: false,
      text:
          'Le maire a mesuré la fontaine ronde pendant la fête du village, puis la musicienne a nettoyé le lavoir au lever du soleil.',
    ),
    (
      id: '1795411768461_input_24',
      source: 'input',
      timestampMs: 176719,
      partial: false,
      text:
          'My neighbor repaired the wooden fence despite the cold wind, and then the librarian measured the',
    ),
  ],
  gaps: <ProbeGap>[
    (
      markerId: '1795411768461_output_7',
      source: 'output',
      markerStartMs: 18719,
      markerEndMs: 75000,
      planStartMs: 11019,
      recovered: <({int offsetMs, String text})>[
        (
          offsetMs: 0,
          text:
              'Bellemavois, puis la gardienne a réparé la vieille barrière pour la rentrée des classes.',
        ),
        (
          offsetMs: 6000,
          text:
              'The librarian tidied the small cabin with a lot of patience, and then the postman painted the old greenhouse with a lot of patience.',
        ),
        (
          offsetMs: 16300,
          text:
              'La boulangère a décoré le portail sans prévenir personne, puis le jardinier a mesuré le banc vert avant la pluie du soir.',
        ),
        (
          offsetMs: 25100,
          text:
              'The librarian photographed the garden gate despite the cold wind, and then the baker moved the green bench for the start of school.',
        ),
        (
          offsetMs: 34500,
          text:
              'Le facteur a mesuré la fontaine ronde malgré le vent froid, puis le facteur a photographié le lavoir pendant la fête du village.',
        ),
        (
          offsetMs: 43100,
          text:
              'The mayor measured the round fountain without telling anyone, and then the gardener photographed the old greenhouse without telling anyone.',
        ),
        (
          offsetMs: 52400,
          text:
              'La Mega Photob va frier le kiosque à journaux pour la rentrée des classes, puis la boulangère a repeint la cabane avant la pluie du soir.',
        ),
        (
          offsetMs: 61600,
          text:
              'The baker photographed the green bench despite the cold wind, and then the postman cleaned the green bench despite the cold wind.',
        ),
      ],
    ),
    (
      markerId: '1795411768461_input_6',
      source: 'input',
      markerStartMs: 20119,
      markerEndMs: 74000,
      planStartMs: 19119,
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
      markerId: '1795411768461_output_14',
      source: 'output',
      markerStartMs: 111619,
      markerEndMs: 155000,
      planStartMs: 103919,
      recovered: <({int offsetMs, String text})>[
        (
          offsetMs: 0,
          text:
              'En la pluie de soir, puis le maire a mesuré le portail avec beaucoup de patience.',
        ),
        (
          offsetMs: 5900,
          text:
              'The mayor painted the stone wall during the village fair, and then the gardener moved the bus shelter before the evening rain.',
        ),
        (
          offsetMs: 15300,
          text:
              'Le libraire a nettoyé le kiosque à journaux avec beaucoup de patience, puis la voisine a nettoyé le kiosque à journaux au lever du soleil.',
        ),
        (
          offsetMs: 24100,
          text:
              'The librarian decorated the old greenhouse with a lot of patience, and then the teacher painted the round fountain with a lot of patience.',
        ),
        (
          offsetMs: 33800,
          text:
              'La boulangère a décoré la cabane pendant la fête du village, puis le libraire a rangé la fontaine ronde avec beaucoup de patience.',
        ),
        (
          offsetMs: 42600,
          text:
              'The baker painted the old greenhouse at sunrise, and then the librarian painted the small cabin with a lot of patience.',
        ),
        (
          offsetMs: 51900,
          text:
              'La gardienne a déplacé la vieille barrière avant la pluie du soir, puis la gardienne a nettoyé le kiosque à journaux sous un ciel gris.',
        ),
      ],
    ),
    (
      markerId: '1795411768461_input_21',
      source: 'input',
      markerStartMs: 119119,
      markerEndMs: 161000,
      planStartMs: 112519,
      recovered: <({int offsetMs, String text})>[
        (
          offsetMs: 5300,
          text:
              'My neighbor cleaned the garden gate with a lot of patience, and then the teacher moved the round fountain with a lot of patience.',
        ),
        (
          offsetMs: 14400,
          text:
              'Le libraire a photographié le banc vert pour la rentrée des classes, puis le jardinier a déplacé le banc vert avant la pluie du soir.',
        ),
        (
          offsetMs: 24700,
          text:
              'The gardener moved the bus shelter without telling anyone, and then the painter tidied the garden gate under a grey sky.',
        ),
        (
          offsetMs: 34000,
          text:
              'La boulangère a nettoyé le kiosque à journaux malgré le vent froid, puis la boulangère a décoré le kiosque à journaux avec beaucoup de patience.',
        ),
        (
          offsetMs: 44700,
          text:
              'The baker painted the garden gate for the start of school, and then the mayor moved the wooden fence before the evening rain.',
        ),
      ],
    ),
    (
      markerId: '1795411768461_output_28',
      source: 'output',
      markerStartMs: 165819,
      markerEndMs: 299000,
      planStartMs: 157819,
      recovered: <({int offsetMs, String text})>[
        (
          offsetMs: 7000,
          text:
              'The teacher cleaned the round fountain without telling anyone, and then the postman repaired the round fountain despite the cold wind.',
        ),
        (
          offsetMs: 15900,
          text:
              'La boulangère a basuré la cabane malgré le vent froid, puis le libraire a basuré la cabane avec beaucoup de patience.',
        ),
        (
          offsetMs: 24600,
          text:
              'The librarian repaired the wooden fence with a lot of patience, and then my neighbor photographed the stone wall at sunrise.',
        ),
        (
          offsetMs: 34700,
          text:
              'La musicienne a rangé le kiosque à journaux sous un ciel gris, puis la boulangère a repeint le portail pendant la fête du village.',
        ),
        (
          offsetMs: 44000,
          text:
              'The painter moved the small cabin without telling anyone, and then the gardener painted the round fountain for the start of school.',
        ),
        (
          offsetMs: 53300,
          text:
              'La musicienne a basuré la cabane sous un ciel gris, puis le libraire a réparé la fontaine ronde pendant la fête du village.',
        ),
        (
          offsetMs: 61800,
          text:
              'The Gognatided the Green Bench before the evening rain, and then the librarian repaired the old greenhouse without telling anyone.',
        ),
        (
          offsetMs: 72000,
          text:
              'L\'omère a basuré le kiosque à journaux pour la rentrée des classes, puis le facteur a déplacé la cabane malgré le vent froid.',
        ),
        (
          offsetMs: 81300,
          text:
              'The teacher painted the bus shelter before the evening rain, and then the postman painted the old greenhouse without telling anyone.',
        ),
        (
          offsetMs: 91300,
          text:
              'Le libraire a repeint le kiosque à journaux pour la rentrée des classes, puis le jardinier a déplacé la serre sans prévenir personne.',
        ),
        (
          offsetMs: 100300,
          text:
              'The librarian photographed the green bench despite the cold wind, and then the postman repaired the bus shelter under a grey sky.',
        ),
        (
          offsetMs: 110100,
          text:
              'La gardienne a nettoyé le lavoir avant la pluie du soir, puis le libraire a photographié la cabane sans prévenir personne.',
        ),
        (
          offsetMs: 119200,
          text:
              'The painter measured the small cabin without telling anyone, and then the mayor measured the garden gate without telling anyone.',
        ),
        (
          offsetMs: 128400,
          text:
              'Le jardinier a réparé la vieille barrière sous un ciel gris, puis le libraire a rangé la vieille barrière au lever du soleil.',
        ),
        (
          offsetMs: 137000,
          text:
              'The painter repaired the small cabin during the village fair, and',
        ),
      ],
    ),
    (
      markerId: '1795411768461_input_27',
      source: 'input',
      markerStartMs: 176719,
      markerEndMs: 300000,
      planStartMs: 168919,
      recovered: <({int offsetMs, String text})>[
        (
          offsetMs: 0,
          text:
              'Dans la fête du village, puis la musicienne a nettoyé le lavoir au lever du soleil.',
        ),
        (
          offsetMs: 6200,
          text:
              'My neighbor repaired the wooden fence despite the cold wind, and then the librarian measured the wooden fence before the evening rain.',
        ),
        (
          offsetMs: 15900,
          text:
              'La boulangère a photographié le banc vert sans prévenir personne, puis la musicienne a nettoyé le banc vert pendant la fête du village.',
        ),
        (
          offsetMs: 26300,
          text:
              'The librarian repaired the round fountain at sunrise, and then the librarian painted the stone wall during the village fair.',
        ),
        (
          offsetMs: 35200,
          text:
              'Le jardinier a photographié la vieille barrière pour la rentrée des classes, puis le libraire a repeint le banc vert pendant la fête du village.',
        ),
        (
          offsetMs: 44900,
          text:
              'The postman measured the bus shelter at sunrise, and then the painter tidied the stone wall despite the cold wind.',
        ),
        (
          offsetMs: 53500,
          text:
              'La boulangère a repeint la serre pendant la fête du village, puis la gardienne a repeint le kiosque à journaux pendant la fête du village.',
        ),
        (
          offsetMs: 63300,
          text:
              'The mayor measured the wooden fence at sunrise, and then the gardener cleaned the old greenhouse under a gray sky.',
        ),
        (
          offsetMs: 71700,
          text:
              'La gardienne a photographié le kiosque à journaux au lever du soleil, puis le libraire a décoré le kiosque à journaux pour la rentrée des classes.',
        ),
        (
          offsetMs: 81800,
          text:
              'The teacher photographed the old greenhouse at sunrise, and then the teacher cleaned the round fountain despite the cold wind.',
        ),
        (
          offsetMs: 90500,
          text:
              'Le jardinier a déplacé la serre sous un ciel gris, puis la boulangère a photographié le lavoir sans prévenir personne.',
        ),
        (
          offsetMs: 99800,
          text:
              'The painter photographed the stone wall at sunrise, and then the mayor decorated the green bench before the evening rain.',
        ),
        (
          offsetMs: 108300,
          text:
              'Le jardinier a décoré le portail sans prévenir personne, puis le jardinier a nettoyé la cabane malgré le vent froid.',
        ),
        (
          offsetMs: 117400,
          text:
              'The baker measured the old greenhouse under a grey sky, and then the baker painted the stone wall during the village fair.',
        ),
        (
          offsetMs: 126100,
          text:
              'La musicienne a déplacé le kiosque à journaux avec beaucoup de passion.',
        ),
      ],
    ),
  ],
);

const ProbeScenario probe9S06 = (
  name: 'S06 (sonde 9)',
  sessionId: '1795410190375',
  segments: <ProbeSegment>[
    (
      id: '1795410190375_input_2',
      source: 'input',
      timestampMs: 52,
      partial: false,
      text:
          'Le maire a déplacé la vieille barrière sans prévenir personne, puis le libraire a rangé le portail sous un ciel gris.',
    ),
    (
      id: '1795410190375_output_1',
      source: 'output',
      timestampMs: 52,
      partial: false,
      text:
          'The painter decorated the old greenhouse under a grey sky, and then the mayor cleaned the green bench under a grey sky.',
    ),
    (
      id: '1795410190375_output_3',
      source: 'output',
      timestampMs: 7952,
      partial: false,
      text:
          'Le libraire a basuré le barbeur malgré le vent froid, puis le facteur a rangé la cabane malgré le vent froid.',
    ),
    (
      id: '1795410190375_input_4',
      source: 'input',
      timestampMs: 12652,
      partial: false,
      text:
          'The teacher measured the stone wall before the evening rain, and then the teacher tidied the wooden fence during the village fair.',
    ),
    (
      id: '1795410190375_output_5',
      source: 'output',
      timestampMs: 19752,
      partial: false,
      text:
          'The Gagna moved the stone wall despite the cold wind, and then the painter photographed the small cabin under a grey sky.',
    ),
    (
      id: '1795410190375_input_6',
      source: 'input',
      timestampMs: 20352,
      partial: false,
      text:
          'La gardienne a rangé la vieille barrière pour la rentrée des classes, puis la musicienne a repeint le kiosque à journaux avant la pluie du soir.',
    ),
    (
      id: '1795410190375_output_7',
      source: 'output',
      timestampMs: 28352,
      partial: false,
      text:
          'Le libraire a repeint la vieille barrière malgré le vent froid, puis le facteur a repeint le banc vert sous un ciel gris.',
    ),
    (
      id: '1795410190375_input_8',
      source: 'input',
      timestampMs: 31952,
      partial: false,
      text:
          'The librarian cleaned the old greenhouse at sunrise, and then the librarian measured the small cabin during the village fair.',
    ),
    (
      id: '1795410190375_output_9',
      source: 'output',
      timestampMs: 35852,
      partial: false,
      text:
          'The librarian painted the stone wall during the village fair, and then my neighbor painted the small cabin for the start of school.',
    ),
    (
      id: '1795410190375_input_10',
      source: 'input',
      timestampMs: 41452,
      partial: false,
      text:
          'Le facteur à photographier le lavoir sous un ciel gris, puis le facteur à nettoyer le portail avec beaucoup de patience.',
    ),
    (
      id: '1795410190375_output_11',
      source: 'output',
      timestampMs: 45252,
      partial: false,
      text:
          'La gardienne a mesuré le lavoir sous un ciel gris, puis la gardienne a décoré le kiosque à journaux sans prévenir personne.',
    ),
    (
      id: '1795410190375_input_12',
      source: 'input',
      timestampMs: 52652,
      partial: false,
      text:
          'The postman painted the green bench for the start of school, and then the baker measured the garden gate at sunrise.',
    ),
    (
      id: '1795410190375_output_13',
      source: 'output',
      timestampMs: 53652,
      partial: false,
      text:
          'The mayor repaired the green bench for the start of school, and then the baker photographed the green bench before the',
    ),
  ],
  gaps: <ProbeGap>[
    (
      markerId: '1795410190375_output_15',
      source: 'output',
      markerStartMs: 53652,
      markerEndMs: 418000,
      planStartMs: 47252,
      recovered: <({int offsetMs, String text})>[
        (
          offsetMs: 0,
          text:
              'Elbri, puis la gardienne a décoré le kiosque à journaux sans prévenir personne.',
        ),
        (
          offsetMs: 5100,
          text:
              'The mayor repaired the green bench for the start of school, and then the baker photographed the green bench before the evening rain.',
        ),
        (
          offsetMs: 14100,
          text:
              'La boulangère a réparé le lavoir avec beaucoup de patience, puis la gardienne a déplacé la cabane malgré le vent froid.',
        ),
        (
          offsetMs: 23400,
          text:
              'The librarian painted the round fountain during the village fair, and then the gardener moved the stone wall for the start of school.',
        ),
        (
          offsetMs: 33900,
          text:
              'Le facteur a nettoyé le kiosque à journaux pendant la fête du village, puis la boulangère a décoré la cabane avec beaucoup de patience.',
        ),
        (
          offsetMs: 49400,
          text:
              'The librarian moved the bus shelter under a grey sky, and then the postman photographed the garden gate with a lot of patience.',
        ),
        (
          offsetMs: 57200,
          text:
              'Le fighter a nettoyé la fontaine ronde avant la pluie du soir, puis le libraire a nettoyé le kiosque à journaux au lever du soleil.',
        ),
        (
          offsetMs: 66400,
          text:
              'The painter measured the bus shelter despite the cold wind, and then the teacher decorated the wooden fence during the village fair.',
        ),
        (
          offsetMs: 76500,
          text:
              'La musicienne a basuré le kiosque à journaux sous un ciel gris, puis la musicienne a réparé la serre pour la rentrée des classes.',
        ),
        (
          offsetMs: 85600,
          text:
              'My neighbor repaired the green bench without telling anyone. And then my neighbor painted the stone wall with a lot of patience.',
        ),
        (
          offsetMs: 95200,
          text:
              'Le libraire a réparé la fontaine ronde avant la pluie du soir, puis le maire a repeint la serre pendant la fête du village.',
        ),
        (
          offsetMs: 108700,
          text:
              'The mayor repaired the wooden fence with a lot of patience, and then the postman photographed the round fountain during the village fair.',
        ),
        (
          offsetMs: 117000,
          text:
              'La musicienne a décoré la serre pendant la fête du village, puis le facteur a décoré le lavoir sous un ciel gris.',
        ),
        (
          offsetMs: 130400,
          text:
              'The librarian photographed the small cabin before the evening rain, and then my neighbor moved the stone wall at sunrise.',
        ),
        (
          offsetMs: 143300,
          text:
              'Le jardinier a nettoyé le lavoir malgré le vent froid, puis la gardienne a rangé le banc vert au lever du soleil.',
        ),
        (
          offsetMs: 155200,
          text:
              'The mayor cleaned the wooden fence without telling anyone, and then the painter decorated the green bench despite the cold wind.',
        ),
        (
          offsetMs: 162500,
          text:
              'Le libraire a déplacé la fontaine haute pour la rentrée des classes, puis le maire a nettoyé le portail avec beaucoup de patience.',
        ),
        (
          offsetMs: 170800,
          text:
              'The painter repaired the green bench despite the cold wind, and then the postman repaired the wooden fence before the evening rain.',
        ),
        (
          offsetMs: 180300,
          text:
              'La boulangère a déplacé le kiosque à journaux avec beaucoup de patience, puis la boulangère a photographié la serre malgré le vent froid.',
        ),
        (
          offsetMs: 189500,
          text:
              'The GAGNA measured the garden gate at sunrise, and then the postman painted the bus shelter before the evening rain.',
        ),
        (
          offsetMs: 198300,
          text:
              'La gardienne a rangé la vieille barrière pour la rentrée des classes, puis le maire a décoré la fontaine ronde pendant la fête du village.',
        ),
        (
          offsetMs: 207100,
          text:
              'The baker painted the stone wall during the village fair, and then the librarian measured the bus shelter before the evening rain.',
        ),
        (
          offsetMs: 221000,
          text:
              'La boulangère a repeint le portail sans prévenir personne, puis la musicienne a décoré le banc vert pour la rentrée des classes.',
        ),
        (
          offsetMs: 233500,
          text:
              'The mayor painted the green bench despite the cold wind, and then the teacher painted the old greenhouse despite the cold wind.',
        ),
        (
          offsetMs: 246100,
          text:
              'Le facteur a déplacé le portail sous un ciel gris, puis la gardienne a rangé le bon verre avec beaucoup de patience.',
        ),
        (
          offsetMs: 253500,
          text:
              'The Gagner photographed the wooden fence without telling anyone, and then the painter tidied the round fountain for the start of school.',
        ),
        (
          offsetMs: 263900,
          text:
              'Le facteur a décoré la serre sans prévenir personne, puis la gardienne a décoré le lavoir au lever du soleil.',
        ),
        (
          offsetMs: 278100,
          text:
              'The teacher cleaned the old greenhouse before the evening rain, and then the baker painted the small cabin at sunrise.',
        ),
        (
          offsetMs: 286200,
          text:
              'La boulangère a photographié la vieille barrière pendant la fête du village, puis la gardienne a mesuré le bon verre sans prévenir personne.',
        ),
        (
          offsetMs: 295300,
          text:
              'The librarian cleaned the stone wall despite the cold wind, and then the librarian repaired the round fountain with a lot of patience.',
        ),
        (
          offsetMs: 304500,
          text:
              'Le jardinier a rangé le lavoir malgré le vent froid, puis le libraire a nettoyé le lavoir sous un ciel gris.',
        ),
        (
          offsetMs: 312700,
          text:
              'The librarian cleaned the bus shelter at sunrise, and then the baker cleaned the round fountain before the evening rain.',
        ),
        (
          offsetMs: 322100,
          text:
              'La voisine a déplacé le lavoir pendant la fête du village, puis la gardienne a photographié le portail sans prévenir personne.',
        ),
        (
          offsetMs: 331500,
          text:
              'The librarian decorated the small cabin at sunrise, and then the librarian measured the green bench despite the cold wind.',
        ),
        (
          offsetMs: 342000,
          text:
              'Le facteur a nettoyé la vieille barrière sans prévenir personne, puis le libraire a réparé le kiosque à journaux avec beaucoup de patience.',
        ),
        (
          offsetMs: 351900,
          text:
              'The mayor cleaned the round fountain for the start of school, and then the baker tidied the round fountain for the start of school.',
        ),
        (
          offsetMs: 362300,
          text:
              'Le libraire a nettoyé le banc vert pendant la fête du village, puis la gardienne a nettoyé le banc vert au lever du soleil.',
        ),
      ],
    ),
    (
      markerId: '1795410190375_input_14',
      source: 'input',
      markerStartMs: 59952,
      markerEndMs: 418000,
      planStartMs: 58952,
      recovered: <({int offsetMs, String text})>[],
    ),
  ],
);

/// Texte lu dans S06 (probe/audio/live60/schedule.json), jusqu'à 425 s.
const List<ProbeSentence> probe9Live60Reference = <ProbeSentence>[
  (
    source: 'input',
    startMs: 0,
    endMs: 6640,
    text:
        'Le maire a déplacé la vieille barrière sans prévenir personne, puis le libraire a rangé le portail sous un ciel gris.',
  ),
  (
    source: 'output',
    startMs: 0,
    endMs: 6420,
    text:
        'The painter decorated the old greenhouse under a grey sky, and then the mayor cleaned the green bench under a grey sky.',
  ),
  (
    source: 'output',
    startMs: 7920,
    endMs: 13760,
    text:
        'Le libraire a mesuré le banc vert malgré le vent froid, puis le facteur a rangé la cabane malgré le vent froid.',
  ),
  (
    source: 'input',
    startMs: 12640,
    endMs: 18840,
    text:
        'The teacher measured the stone wall before the evening rain, and then the teacher tidied the wooden fence during the village fair.',
  ),
  (
    source: 'output',
    startMs: 19760,
    endMs: 26340,
    text:
        'The gardener moved the stone wall despite the cold wind, and then the painter photographed the small cabin under a grey sky.',
  ),
  (
    source: 'input',
    startMs: 20340,
    endMs: 27920,
    text:
        'La gardienne a rangé la vieille barrière pour la rentrée des classes, puis la musicienne a repeint le kiosque à journaux avant la pluie du soir.',
  ),
  (
    source: 'output',
    startMs: 28340,
    endMs: 34350,
    text:
        'Le libraire a repeint la vieille barrière malgré le vent froid, puis le facteur a repeint le banc vert sous un ciel gris.',
  ),
  (
    source: 'input',
    startMs: 31920,
    endMs: 38480,
    text:
        'The librarian cleaned the old greenhouse at sunrise, and then the librarian measured the small cabin during the village fair.',
  ),
  (
    source: 'output',
    startMs: 35850,
    endMs: 42750,
    text:
        'The librarian painted the stone wall during the village fair, and then my neighbour painted the small cabin for the start of school.',
  ),
  (
    source: 'input',
    startMs: 41480,
    endMs: 48630,
    text:
        'Le facteur a photographié le lavoir sous un ciel gris, puis le facteur a nettoyé le portail avec beaucoup de patience.',
  ),
  (
    source: 'output',
    startMs: 45250,
    endMs: 51600,
    text:
        'La gardienne a mesuré le lavoir sous un ciel gris, puis la gardienne a décoré le kiosque à journaux sans prévenir personne.',
  ),
  (
    source: 'input',
    startMs: 52630,
    endMs: 58440,
    text:
        'The postman painted the green bench for the start of school, and then the baker measured the garden gate at sunrise.',
  ),
  (
    source: 'output',
    startMs: 53600,
    endMs: 60370,
    text:
        'The mayor repaired the green bench for the start of school, and then the baker photographed the green bench before the evening rain.',
  ),
  (
    source: 'input',
    startMs: 59940,
    endMs: 66800,
    text:
        'La musicienne a décoré la serre malgré le vent froid, puis la voisine a décoré la fontaine ronde pendant la fête du village.',
  ),
  (
    source: 'output',
    startMs: 62370,
    endMs: 68890,
    text:
        'La boulangère a réparé le lavoir avec beaucoup de patience, puis la gardienne a déplacé la cabane malgré le vent froid.',
  ),
  (
    source: 'input',
    startMs: 70800,
    endMs: 77120,
    text:
        'The postman tidied the old greenhouse at sunrise, and then my neighbour painted the bus shelter under a grey sky.',
  ),
  (
    source: 'output',
    startMs: 72890,
    endMs: 79720,
    text:
        'The librarian painted the round fountain during the village fair, and then the gardener moved the stone wall for the start of school.',
  ),
  (
    source: 'input',
    startMs: 80120,
    endMs: 87440,
    text:
        'Le jardinier a repeint la cabane pour la rentrée des classes, puis le jardinier a nettoyé le kiosque à journaux avant la pluie du soir.',
  ),
  (
    source: 'output',
    startMs: 83720,
    endMs: 90690,
    text:
        'Le facteur a nettoyé le kiosque à journaux pendant la fête du village, puis la boulangère a décoré la cabane avec beaucoup de patience.',
  ),
  (
    source: 'input',
    startMs: 89440,
    endMs: 95440,
    text:
        'The baker tidied the green bench at sunrise, and then the baker photographed the stone wall with a lot of patience.',
  ),
  (
    source: 'output',
    startMs: 96690,
    endMs: 103740,
    text:
        'The librarian moved the bus shelter under a grey sky, and then the postman photographed the garden gate with a lot of patience.',
  ),
  (
    source: 'input',
    startMs: 96940,
    endMs: 104590,
    text:
        'La boulangère a décoré le lavoir avec beaucoup de patience, puis la gardienne a décoré le kiosque à journaux pendant la fête du village.',
  ),
  (
    source: 'output',
    startMs: 105240,
    endMs: 111870,
    text:
        'Le facteur a nettoyé la fontaine ronde avant la pluie du soir, puis le libraire a nettoyé le kiosque à journaux au lever du soleil.',
  ),
  (
    source: 'input',
    startMs: 106090,
    endMs: 112130,
    text:
        'My neighbour moved the garden gate during the village fair, and then the painter cleaned the wooden fence despite the cold wind.',
  ),
  (
    source: 'input',
    startMs: 114630,
    endMs: 121490,
    text:
        'Le libraire a nettoyé la cabane pendant la fête du village, puis la voisine a décoré la cabane pour la rentrée des classes.',
  ),
  (
    source: 'output',
    startMs: 115870,
    endMs: 122560,
    text:
        'The painter measured the bus shelter despite the cold wind, and then the teacher decorated the wooden fence during the village fair.',
  ),
  (
    source: 'input',
    startMs: 123990,
    endMs: 130540,
    text:
        'The baker measured the green bench before the evening rain, and then my neighbour decorated the bus shelter with a lot of patience.',
  ),
  (
    source: 'output',
    startMs: 125060,
    endMs: 131590,
    text:
        'La musicienne a mesuré le kiosque à journaux sous un ciel gris, puis la musicienne a réparé la serre pour la rentrée des classes.',
  ),
  (
    source: 'input',
    startMs: 132540,
    endMs: 139820,
    text:
        'La boulangère a mesuré le banc vert avec beaucoup de patience, puis la gardienne a photographié la serre avant la pluie du soir.',
  ),
  (
    source: 'output',
    startMs: 134590,
    endMs: 141280,
    text:
        'My neighbour repaired the green bench without telling anyone, and then my neighbour painted the stone wall with a lot of patience.',
  ),
  (
    source: 'input',
    startMs: 142320,
    endMs: 148890,
    text:
        'The painter repaired the round fountain for the start of school, and then the teacher repaired the round fountain despite the cold wind.',
  ),
  (
    source: 'output',
    startMs: 143780,
    endMs: 150010,
    text:
        'Le libraire a réparé la fontaine ronde avant la pluie du soir, puis le maire a repeint la serre pendant la fête du village.',
  ),
  (
    source: 'input',
    startMs: 154890,
    endMs: 161910,
    text:
        'Le libraire a déplacé la cabane sans prévenir personne, puis la gardienne a nettoyé la serre sans prévenir personne.',
  ),
  (
    source: 'output',
    startMs: 156010,
    endMs: 163060,
    text:
        'The mayor repaired the wooden fence with a lot of patience, and then the postman photographed the round fountain during the village fair.',
  ),
  (
    source: 'input',
    startMs: 163410,
    endMs: 169790,
    text:
        'The teacher repaired the stone wall for the start of school, and then the baker tidied the bus shelter without telling anyone.',
  ),
  (
    source: 'output',
    startMs: 165560,
    endMs: 171670,
    text:
        'La musicienne a décoré la serre pendant la fête du village, puis le facteur a décoré le lavoir sous un ciel gris.',
  ),
  (
    source: 'input',
    startMs: 175790,
    endMs: 182990,
    text:
        'La musicienne a rangé le portail sans prévenir personne, puis le maire a mesuré la fontaine ronde pour la rentrée des classes.',
  ),
  (
    source: 'output',
    startMs: 177670,
    endMs: 184600,
    text:
        'The librarian photographed the small cabin before the evening rain, and then my neighbour moved the stone wall at sunrise.',
  ),
  (
    source: 'input',
    startMs: 184490,
    endMs: 191760,
    text:
        'The painter tidied the garden gate without telling anyone, and then the postman photographed the old greenhouse without telling anyone.',
  ),
  (
    source: 'output',
    startMs: 190600,
    endMs: 196440,
    text:
        'Le jardinier a nettoyé le lavoir malgré le vent froid, puis la gardienne a rangé le banc vert au lever du soleil.',
  ),
  (
    source: 'input',
    startMs: 193760,
    endMs: 201340,
    text:
        'La musicienne a déplacé le lavoir pendant la fête du village, puis le maire a photographié la vieille barrière avant la pluie du soir.',
  ),
  (
    source: 'output',
    startMs: 202440,
    endMs: 209070,
    text:
        'The mayor cleaned the wooden fence without telling anyone, and then the painter decorated the green bench despite the cold wind.',
  ),
  (
    source: 'input',
    startMs: 203840,
    endMs: 210240,
    text:
        'The postman moved the stone wall before the evening rain, and then the painter painted the garden gate with a lot of patience.',
  ),
  (
    source: 'output',
    startMs: 210570,
    endMs: 217300,
    text:
        'Le libraire a déplacé la fontaine ronde pour la rentrée des classes, puis le maire a nettoyé le portail avec beaucoup de patience.',
  ),
  (
    source: 'input',
    startMs: 212740,
    endMs: 219780,
    text:
        'Le facteur a déplacé la fontaine ronde pour la rentrée des classes, puis la musicienne a décoré le banc vert sous un ciel gris.',
  ),
  (
    source: 'output',
    startMs: 219300,
    endMs: 226090,
    text:
        'The painter repaired the green bench despite the cold wind, and then the postman repaired the wooden fence before the evening rain.',
  ),
  (
    source: 'input',
    startMs: 221280,
    endMs: 227660,
    text:
        'The postman cleaned the wooden fence under a grey sky, and then my neighbour measured the stone wall without telling anyone.',
  ),
  (
    source: 'output',
    startMs: 229090,
    endMs: 236190,
    text:
        'La boulangère a déplacé le kiosque à journaux avec beaucoup de patience, puis la boulangère a photographié la serre malgré le vent froid.',
  ),
  (
    source: 'input',
    startMs: 231660,
    endMs: 238330,
    text:
        'Le jardinier a repeint le banc vert au lever du soleil, puis le jardinier a nettoyé le portail pendant la fête du village.',
  ),
  (
    source: 'output',
    startMs: 237690,
    endMs: 244070,
    text:
        'The gardener measured the garden gate at sunrise, and then the postman painted the bus shelter before the evening rain.',
  ),
  (
    source: 'input',
    startMs: 240330,
    endMs: 246560,
    text:
        'The teacher moved the bus shelter at sunrise, and then the teacher photographed the small cabin with a lot of patience.',
  ),
  (
    source: 'output',
    startMs: 247070,
    endMs: 253850,
    text:
        'La gardienne a rangé la vieille barrière pour la rentrée des classes, puis le maire a décoré la fontaine ronde pendant la fête du village.',
  ),
  (
    source: 'input',
    startMs: 252560,
    endMs: 259420,
    text:
        'Le maire a photographié la fontaine ronde au lever du soleil, puis le libraire a décoré la vieille barrière malgré le vent froid.',
  ),
  (
    source: 'output',
    startMs: 255350,
    endMs: 262270,
    text:
        'The baker painted the stone wall during the village fair, and then the librarian measured the bus shelter before the evening rain.',
  ),
  (
    source: 'input',
    startMs: 262420,
    endMs: 269620,
    text:
        'The librarian moved the round fountain with a lot of patience, and then the librarian photographed the bus shelter before the evening rain.',
  ),
  (
    source: 'output',
    startMs: 268270,
    endMs: 274830,
    text:
        'La boulangère a repeint le portail sans prévenir personne, puis la musicienne a décoré le banc vert pour la rentrée des classes.',
  ),
  (
    source: 'input',
    startMs: 271120,
    endMs: 277750,
    text:
        'La musicienne a rangé le lavoir sous un ciel gris, puis le libraire a mesuré le kiosque à journaux au lever du soleil.',
  ),
  (
    source: 'input',
    startMs: 279250,
    endMs: 285820,
    text:
        'The gardener tidied the round fountain for the start of school, and then the librarian tidied the wooden fence for the start of school.',
  ),
  (
    source: 'output',
    startMs: 280830,
    endMs: 287410,
    text:
        'The mayor painted the green bench despite the cold wind, and then the teacher painted the old greenhouse despite the cold wind.',
  ),
  (
    source: 'input',
    startMs: 289820,
    endMs: 298300,
    text:
        'Le facteur a photographié le kiosque à journaux pour la rentrée des classes, puis la boulangère a photographié la vieille barrière pour la rentrée des classes.',
  ),
  (
    source: 'output',
    startMs: 293410,
    endMs: 299500,
    text:
        'Le facteur a déplacé le portail sous un ciel gris, puis la gardienne a rangé le banc vert avec beaucoup de patience.',
  ),
  (
    source: 'output',
    startMs: 302500,
    endMs: 309550,
    text:
        'The gardener photographed the wooden fence without telling anyone, and then the painter tidied the round fountain for the start of school.',
  ),
  (
    source: 'input',
    startMs: 304300,
    endMs: 311220,
    text:
        'The painter measured the wooden fence before the evening rain, and then the painter photographed the small cabin without telling anyone.',
  ),
  (
    source: 'output',
    startMs: 313550,
    endMs: 319440,
    text:
        'Le facteur a décoré la serre sans prévenir personne, puis la gardienne a décoré le lavoir au lever du soleil.',
  ),
  (
    source: 'input',
    startMs: 317220,
    endMs: 323600,
    text:
        'Le facteur a nettoyé le banc vert malgré le vent froid, puis la boulangère a déplacé la cabane malgré le vent froid.',
  ),
  (
    source: 'output',
    startMs: 325440,
    endMs: 331980,
    text:
        'The teacher cleaned the old greenhouse before the evening rain, and then the baker painted the small cabin at sunrise.',
  ),
  (
    source: 'input',
    startMs: 329600,
    endMs: 336070,
    text:
        'My neighbour measured the green bench before the evening rain, and then the teacher moved the small cabin without telling anyone.',
  ),
  (
    source: 'output',
    startMs: 334980,
    endMs: 342020,
    text:
        'La boulangère a photographié la vieille barrière pendant la fête du village, puis la gardienne a mesuré le banc vert sans prévenir personne.',
  ),
  (
    source: 'input',
    startMs: 338570,
    endMs: 345310,
    text:
        'Le maire a rangé le lavoir sans prévenir personne, puis la musicienne a repeint le kiosque à journaux sous un ciel gris.',
  ),
  (
    source: 'output',
    startMs: 343520,
    endMs: 350810,
    text:
        'The librarian cleaned the stone wall despite the cold wind, and then the librarian repaired the round fountain with a lot of patience.',
  ),
  (
    source: 'input',
    startMs: 346810,
    endMs: 353410,
    text:
        'My neighbour painted the garden gate without telling anyone, and then the postman painted the green bench before the evening rain.',
  ),
  (
    source: 'output',
    startMs: 352810,
    endMs: 358680,
    text:
        'Le jardinier a rangé le lavoir malgré le vent froid, puis le libraire a nettoyé le lavoir sous un ciel gris.',
  ),
  (
    source: 'input',
    startMs: 359410,
    endMs: 366430,
    text:
        'La gardienne a repeint la serre sans prévenir personne, puis le libraire a repeint le kiosque à journaux pendant la fête du village.',
  ),
  (
    source: 'output',
    startMs: 361680,
    endMs: 368400,
    text:
        'The librarian cleaned the bus shelter at sunrise, and then the baker cleaned the round fountain before the evening rain.',
  ),
  (
    source: 'output',
    startMs: 370400,
    endMs: 377010,
    text:
        'La voisine a déplacé le lavoir pendant la fête du village, puis la gardienne a photographié le portail sans prévenir personne.',
  ),
  (
    source: 'input',
    startMs: 372430,
    endMs: 378840,
    text:
        'My neighbour cleaned the old greenhouse despite the cold wind, and then the baker cleaned the garden gate before the evening rain.',
  ),
  (
    source: 'output',
    startMs: 381010,
    endMs: 388050,
    text:
        'The librarian decorated the small cabin at sunrise, and then the librarian measured the green bench despite the cold wind.',
  ),
  (
    source: 'input',
    startMs: 382840,
    endMs: 389760,
    text:
        'Le libraire a repeint la cabane avant la pluie du soir, puis le jardinier a nettoyé la fontaine ronde avant la pluie du soir.',
  ),
  (
    source: 'output',
    startMs: 390550,
    endMs: 397620,
    text:
        'Le facteur a nettoyé la vieille barrière sans prévenir personne, puis le libraire a réparé le kiosque à journaux avec beaucoup de patience.',
  ),
  (
    source: 'input',
    startMs: 392260,
    endMs: 398600,
    text:
        'The painter repaired the stone wall during the village fair, and then the mayor decorated the garden gate before the evening rain.',
  ),
  (
    source: 'input',
    startMs: 400600,
    endMs: 407130,
    text:
        'La voisine a décoré le banc vert sous un ciel gris, puis le facteur a nettoyé le banc vert pour la rentrée des classes.',
  ),
  (
    source: 'output',
    startMs: 401620,
    endMs: 408080,
    text:
        'The mayor cleaned the round fountain for the start of school, and then the baker tidied the round fountain for the start of school.',
  ),
  (
    source: 'input',
    startMs: 411130,
    endMs: 417620,
    text:
        'The teacher cleaned the old greenhouse during the village fair, and then the gardener painted the round fountain during the village fair.',
  ),
  (
    source: 'output',
    startMs: 412080,
    endMs: 418120,
    text:
        'Le libraire a nettoyé le banc vert pendant la fête du village, puis la gardienne a nettoyé le banc vert au lever du soleil.',
  ),
  (
    source: 'input',
    startMs: 421620,
    endMs: 428620,
    text:
        'Le libraire a mesuré le banc vert avec beaucoup de patience, puis le libraire a mesuré le banc vert avec beaucoup de patience.',
  ),
  (
    source: 'output',
    startMs: 424120,
    endMs: 431340,
    text:
        'The painter photographed the green bench during the village fair, and then the painter painted the old greenhouse before the evening rain.',
  ),
];
