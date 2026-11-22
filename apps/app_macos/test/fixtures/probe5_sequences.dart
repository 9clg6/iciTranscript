// GÉNÉRÉ depuis les journaux de la sonde 5 (vrai service contre vrai
// serveur, voix de synthèse), scratchpad/probe/live5/*.jsonl et
// probe/audio/live/schedule.json. Ne pas retoucher à la main : ce sont les
// séquences réellement produites, copiées telles quelles.
//
// Pour chaque scénario : les segments de la session AVANT le rattrapage
// (liste finale moins les segments `_backfill_`, plus les repères), le
// texte que le rattrapage a rendu pour chaque repère (morceaux, heure
// depuis le début de l'intervalle retranscrit), et le texte de référence
// lu (une phrase par entrée, avec ses heures dans l'audio).

typedef ProbeSegment = ({
  String id,
  String source,
  int timestampMs,
  bool partial,
  String text,
});

typedef ProbeGap = ({
  String markerId,
  String source,
  int markerStartMs,
  int markerEndMs,
  int planStartMs,
  List<({int offsetMs, String text})> recovered,
});

typedef ProbeSentence = ({String source, int startMs, int endMs, String text});

typedef ProbeScenario = ({
  String name,
  String sessionId,
  List<ProbeSegment> segments,
  List<ProbeGap> gaps,
});

const List<ProbeSentence> probeReference = <ProbeSentence>[
  (
    source: 'input',
    startMs: 0,
    endMs: 8140,
    text:
        'La gardienne a photographié le lavoir avec beaucoup de patience, puis le facteur a photographié la fontaine ronde pendant la fête du village.',
  ),
  (
    source: 'input',
    startMs: 10640,
    endMs: 17110,
    text:
        'The gardener cleaned the green bench before the evening rain, and then the painter tidied the round fountain before the evening rain.',
  ),
  (
    source: 'input',
    startMs: 20110,
    endMs: 26810,
    text:
        'La boulangère a repeint la vieille barrière avec beaucoup de patience, puis la voisine a repeint le lavoir au lever du soleil.',
  ),
  (
    source: 'input',
    startMs: 29310,
    endMs: 35570,
    text:
        'The teacher moved the garden gate despite the cold wind, and then the baker painted the stone wall without telling anyone.',
  ),
  (
    source: 'input',
    startMs: 38070,
    endMs: 44860,
    text:
        'La boulangère a décoré le portail avec beaucoup de patience, puis le maire a repeint le banc vert pendant la fête du village.',
  ),
  (
    source: 'input',
    startMs: 47360,
    endMs: 54020,
    text:
        'The postman measured the bus shelter during the village fair, and then the baker repaired the old greenhouse with a lot of patience.',
  ),
  (
    source: 'input',
    startMs: 56020,
    endMs: 62350,
    text:
        'La gardienne a rangé la cabane pour la rentrée des classes, puis la boulangère a réparé la serre au lever du soleil.',
  ),
  (
    source: 'input',
    startMs: 64350,
    endMs: 71050,
    text:
        'The gardener decorated the wooden fence for the start of school, and then the postman cleaned the old greenhouse during the village fair.',
  ),
  (
    source: 'input',
    startMs: 73050,
    endMs: 80480,
    text:
        'Le jardinier a photographié le lavoir sous un ciel gris, puis la voisine a photographié le kiosque à journaux sous un ciel gris.',
  ),
  (
    source: 'input',
    startMs: 82980,
    endMs: 89430,
    text:
        'The painter painted the bus shelter for the start of school, and then the teacher repaired the garden gate without telling anyone.',
  ),
  (
    source: 'input',
    startMs: 91430,
    endMs: 98550,
    text:
        'La voisine a nettoyé la cabane pendant la fête du village, puis le jardinier a nettoyé le kiosque à journaux malgré le vent froid.',
  ),
  (
    source: 'input',
    startMs: 101050,
    endMs: 107520,
    text:
        'The baker decorated the garden gate for the start of school, and then the postman painted the green bench with a lot of patience.',
  ),
  (
    source: 'input',
    startMs: 110520,
    endMs: 116640,
    text:
        'La voisine a repeint le portail au lever du soleil, puis la gardienne a nettoyé le lavoir sous un ciel gris.',
  ),
  (
    source: 'input',
    startMs: 119140,
    endMs: 125450,
    text:
        'My neighbour cleaned the garden gate with a lot of patience, and then the teacher moved the round fountain with a lot of patience.',
  ),
  (
    source: 'input',
    startMs: 128450,
    endMs: 135740,
    text:
        'Le libraire a photographié le banc vert pour la rentrée des classes, puis le jardinier a déplacé le banc vert avant la pluie du soir.',
  ),
  (
    source: 'input',
    startMs: 138740,
    endMs: 145050,
    text:
        'The gardener moved the bus shelter without telling anyone, and then the painter tidied the garden gate under a grey sky.',
  ),
  (
    source: 'input',
    startMs: 148050,
    endMs: 155910,
    text:
        'La boulangère a nettoyé le kiosque à journaux malgré le vent froid, puis la boulangère a décoré le kiosque à journaux avec beaucoup de patience.',
  ),
  (
    source: 'input',
    startMs: 158910,
    endMs: 164910,
    text:
        'The baker painted the garden gate for the start of school, and then the mayor moved the wooden fence before the evening rain.',
  ),
  (
    source: 'input',
    startMs: 166910,
    endMs: 173700,
    text:
        'Le maire a mesuré la fontaine ronde pendant la fête du village, puis la musicienne a nettoyé le lavoir au lever du soleil.',
  ),
  (
    source: 'input',
    startMs: 176700,
    endMs: 183350,
    text:
        'My neighbour repaired the wooden fence despite the cold wind, and then the librarian measured the wooden fence before the evening rain.',
  ),
  (
    source: 'input',
    startMs: 186350,
    endMs: 194000,
    text:
        'La boulangère a photographié le banc vert sans prévenir personne, puis la musicienne a nettoyé le banc vert pendant la fête du village.',
  ),
  (
    source: 'input',
    startMs: 196500,
    endMs: 202900,
    text:
        'The librarian repaired the round fountain at sunrise, and then the librarian painted the stone wall during the village fair.',
  ),
  (
    source: 'input',
    startMs: 205400,
    endMs: 212890,
    text:
        'Le jardinier a photographié la vieille barrière pour la rentrée des classes, puis le libraire a repeint le banc vert pendant la fête du village.',
  ),
  (
    source: 'input',
    startMs: 214890,
    endMs: 220940,
    text:
        'The postman measured the bus shelter at sunrise, and then the painter tidied the stone wall despite the cold wind.',
  ),
  (
    source: 'input',
    startMs: 223940,
    endMs: 231020,
    text:
        'La boulangère a repeint la serre pendant la fête du village, puis la gardienne a repeint le kiosque à journaux pendant la fête du village.',
  ),
  (
    source: 'input',
    startMs: 233520,
    endMs: 239390,
    text:
        'The mayor measured the wooden fence at sunrise, and then the gardener cleaned the old greenhouse under a grey sky.',
  ),
  (
    source: 'input',
    startMs: 241890,
    endMs: 249800,
    text:
        'La gardienne a photographié le kiosque à journaux au lever du soleil, puis le libraire a décoré le kiosque à journaux pour la rentrée des classes.',
  ),
  (
    source: 'input',
    startMs: 251800,
    endMs: 258250,
    text:
        'The teacher photographed the old greenhouse at sunrise, and then the teacher cleaned the round fountain despite the cold wind.',
  ),
  (
    source: 'input',
    startMs: 260750,
    endMs: 267800,
    text:
        'Le jardinier a déplacé la serre sous un ciel gris, puis la boulangère a photographié le lavoir sans prévenir personne.',
  ),
  (
    source: 'input',
    startMs: 269800,
    endMs: 275980,
    text:
        'The painter photographed the stone wall at sunrise, and then the mayor decorated the green bench before the evening rain.',
  ),
  (
    source: 'input',
    startMs: 278480,
    endMs: 285330,
    text:
        'Le jardinier a décoré le portail sans prévenir personne, puis le jardinier a nettoyé la cabane malgré le vent froid.',
  ),
  (
    source: 'input',
    startMs: 287330,
    endMs: 293570,
    text:
        'The baker measured the old greenhouse under a grey sky, and then the baker painted the stone wall during the village fair.',
  ),
  (
    source: 'input',
    startMs: 296570,
    endMs: 304690,
    text:
        'La musicienne a déplacé le kiosque à journaux avec beaucoup de patience, puis la gardienne a décoré la fontaine ronde avant la pluie du soir.',
  ),
  (
    source: 'output',
    startMs: 0,
    endMs: 7020,
    text:
        'The baker cleaned the old greenhouse without telling anyone, and then the librarian cleaned the bus shelter with a lot of patience.',
  ),
  (
    source: 'output',
    startMs: 9020,
    endMs: 15760,
    text:
        'Le libraire a rangé la fontaine ronde malgré le vent froid, puis la gardienne a réparé la vieille barrière pour la rentrée des classes.',
  ),
  (
    source: 'output',
    startMs: 18760,
    endMs: 26090,
    text:
        'The librarian tidied the small cabin with a lot of patience, and then the postman painted the old greenhouse with a lot of patience.',
  ),
  (
    source: 'output',
    startMs: 28590,
    endMs: 35200,
    text:
        'La boulangère a décoré le portail sans prévenir personne, puis le jardinier a mesuré le banc vert avant la pluie du soir.',
  ),
  (
    source: 'output',
    startMs: 37700,
    endMs: 44590,
    text:
        'The librarian photographed the garden gate despite the cold wind, and then the baker moved the green bench for the start of school.',
  ),
  (
    source: 'output',
    startMs: 46590,
    endMs: 53340,
    text:
        'Le facteur a mesuré la fontaine ronde malgré le vent froid, puis le facteur a photographié le lavoir pendant la fête du village.',
  ),
  (
    source: 'output',
    startMs: 55340,
    endMs: 62490,
    text:
        'The mayor measured the round fountain without telling anyone, and then the gardener photographed the old greenhouse without telling anyone.',
  ),
  (
    source: 'output',
    startMs: 64490,
    endMs: 71370,
    text:
        'Le maire a photographié le kiosque à journaux pour la rentrée des classes, puis la boulangère a repeint la cabane avant la pluie du soir.',
  ),
  (
    source: 'output',
    startMs: 74370,
    endMs: 81220,
    text:
        'The baker photographed the green bench despite the cold wind, and then the postman cleaned the green bench despite the cold wind.',
  ),
  (
    source: 'output',
    startMs: 83720,
    endMs: 90330,
    text:
        'Le libraire a décoré le kiosque à journaux malgré le vent froid, puis la gardienne a nettoyé le portail pour la rentrée des classes.',
  ),
  (
    source: 'output',
    startMs: 92830,
    endMs: 99990,
    text:
        'The librarian painted the old greenhouse for the start of school, and then the baker measured the round fountain before the evening rain.',
  ),
  (
    source: 'output',
    startMs: 101990,
    endMs: 108590,
    text:
        'La voisine a nettoyé le kiosque à journaux avant la pluie du soir, puis le maire a mesuré le portail avec beaucoup de patience.',
  ),
  (
    source: 'output',
    startMs: 111590,
    endMs: 118000,
    text:
        'The mayor painted the stone wall during the village fair, and then the gardener moved the bus shelter before the evening rain.',
  ),
  (
    source: 'output',
    startMs: 120500,
    endMs: 127250,
    text:
        'Le libraire a nettoyé le kiosque à journaux avec beaucoup de patience, puis la voisine a nettoyé le kiosque à journaux au lever du soleil.',
  ),
  (
    source: 'output',
    startMs: 129250,
    endMs: 136800,
    text:
        'The librarian decorated the old greenhouse with a lot of patience, and then the teacher painted the round fountain with a lot of patience.',
  ),
  (
    source: 'output',
    startMs: 138800,
    endMs: 145560,
    text:
        'La boulangère a décoré la cabane pendant la fête du village, puis le libraire a rangé la fontaine ronde avec beaucoup de patience.',
  ),
  (
    source: 'output',
    startMs: 148060,
    endMs: 154910,
    text:
        'The baker painted the old greenhouse at sunrise, and then the librarian painted the small cabin with a lot of patience.',
  ),
  (
    source: 'output',
    startMs: 156910,
    endMs: 163800,
    text:
        'La gardienne a déplacé la vieille barrière avant la pluie du soir, puis la gardienne a nettoyé le kiosque à journaux sous un ciel gris.',
  ),
  (
    source: 'output',
    startMs: 165800,
    endMs: 172790,
    text:
        'The teacher cleaned the round fountain without telling anyone, and then the postman repaired the round fountain despite the cold wind.',
  ),
  (
    source: 'output',
    startMs: 174790,
    endMs: 181140,
    text:
        'La boulangère a mesuré la cabane malgré le vent froid, puis le libraire a mesuré la cabane avec beaucoup de patience.',
  ),
  (
    source: 'output',
    startMs: 184140,
    endMs: 191090,
    text:
        'The librarian repaired the wooden fence with a lot of patience, and then my neighbour photographed the stone wall at sunrise.',
  ),
  (
    source: 'output',
    startMs: 194090,
    endMs: 200510,
    text:
        'La musicienne a rangé le kiosque à journaux sous un ciel gris, puis la boulangère a repeint le portail pendant la fête du village.',
  ),
  (
    source: 'output',
    startMs: 203510,
    endMs: 210170,
    text:
        'The painter moved the small cabin without telling anyone, and then the gardener painted the round fountain for the start of school.',
  ),
  (
    source: 'output',
    startMs: 212170,
    endMs: 218580,
    text:
        'La musicienne a mesuré la cabane sous un ciel gris, puis le libraire a réparé la fontaine ronde pendant la fête du village.',
  ),
  (
    source: 'output',
    startMs: 221080,
    endMs: 228390,
    text:
        'The gardener tidied the green bench before the evening rain, and then the librarian repaired the old greenhouse without telling anyone.',
  ),
  (
    source: 'output',
    startMs: 231390,
    endMs: 237880,
    text:
        'Le maire a mesuré le kiosque à journaux pour la rentrée des classes, puis le facteur a déplacé la cabane malgré le vent froid.',
  ),
  (
    source: 'output',
    startMs: 240880,
    endMs: 247910,
    text:
        'The teacher painted the bus shelter before the evening rain, and then the postman painted the old greenhouse without telling anyone.',
  ),
  (
    source: 'output',
    startMs: 250410,
    endMs: 257080,
    text:
        'Le libraire a repeint le kiosque à journaux pour la rentrée des classes, puis le jardinier a déplacé la serre sans prévenir personne.',
  ),
  (
    source: 'output',
    startMs: 259580,
    endMs: 266720,
    text:
        'The librarian photographed the green bench despite the cold wind, and then the postman repaired the bus shelter under a grey sky.',
  ),
  (
    source: 'output',
    startMs: 269220,
    endMs: 275800,
    text:
        'La gardienne a nettoyé le lavoir avant la pluie du soir, puis le libraire a photographié la cabane sans prévenir personne.',
  ),
  (
    source: 'output',
    startMs: 278800,
    endMs: 285260,
    text:
        'The painter measured the small cabin without telling anyone, and then the mayor measured the garden gate without telling anyone.',
  ),
  (
    source: 'output',
    startMs: 287260,
    endMs: 293520,
    text:
        'Le jardinier a réparé la vieille barrière sous un ciel gris, puis le libraire a rangé la vieille barrière au lever du soleil.',
  ),
  (
    source: 'output',
    startMs: 296520,
    endMs: 303430,
    text:
        'The painter repaired the small cabin during the village fair, and then the teacher photographed the stone wall without telling anyone.',
  ),
];

const ProbeScenario probeD = (
  name: 'D',
  sessionId: '1795385073459',
  segments: <ProbeSegment>[
    (
      id: '1795385073459_input_1',
      source: 'input',
      timestampMs: 17,
      partial: false,
      text:
          'La gardienne a photographié le lavoir avec beaucoup de patience, puis le facteur a photographié la fontaine ronde pendant la fête du village.',
    ),
    (
      id: '1795385073459_input_4',
      source: 'input',
      timestampMs: 10617,
      partial: false,
      text:
          'The gardener cleaned the green bench before the evening rain, and then the painter tidied the round fountain before the evening rain.',
    ),
    (
      id: '1795385073459_input_6',
      source: 'input',
      timestampMs: 20117,
      partial: false,
      text:
          'La boulangère a repeint la vieille barrière avec beaucoup de patience, puis la voisine a repeint le lavoir au lever du soleil.',
    ),
    (
      id: '1795385073459_input_8',
      source: 'input',
      timestampMs: 29317,
      partial: false,
      text:
          'The teacher moved the garden gate despite the cold wind, and then the baker painted the stone wall without telling anyone.',
    ),
    (
      id: '1795385073459_input_10',
      source: 'input',
      timestampMs: 38017,
      partial: false,
      text:
          'La boulangère a décoré le portail avec beaucoup de patience, puis le maire a repeint le banc vert pendant la fête du village.',
    ),
    (
      id: '1795385073459_input_12',
      source: 'input',
      timestampMs: 47317,
      partial: false,
      text:
          'The postman measured the bus shelter during the village fair, and then the baker repaired the old greenhouse with a lot of patience.',
    ),
    (
      id: '1795385073459_input_14',
      source: 'input',
      timestampMs: 57038,
      partial: true,
      text: 'La gardienne a rangé la cabane pour la rentrée des classes',
    ),
    (
      id: '1795385073459_input_16',
      source: 'input',
      timestampMs: 73017,
      partial: false,
      text:
          'Grafie et le lavoir sous un ciel gris, puis la voisine a photographié le kiosque à journaux sous un ciel gris.',
    ),
    (
      id: '1795385073459_input_17',
      source: 'input',
      timestampMs: 82917,
      partial: false,
      text:
          'The painter painted the bus shelter for the start of school, and then the teacher repaired the garden gate without telling anyone.',
    ),
    (
      id: '1795385073459_input_19',
      source: 'input',
      timestampMs: 91417,
      partial: false,
      text:
          'La voisine a nettoyé la cabane pendant la fête du village, puis le jardinier a nettoyé le kiosque à journaux malgré le vent froid.',
    ),
    (
      id: '1795385073459_input_20',
      source: 'input',
      timestampMs: 101017,
      partial: false,
      text:
          'The baker decorated the garden gate for the start of school, and then the postman painted the green bench with a lot of patience.',
    ),
    (
      id: '1795385073459_input_23',
      source: 'input',
      timestampMs: 110517,
      partial: false,
      text:
          'La voisine a repeint le portail au lever du soleil, puis la gardienne a nettoyé le lavoir sous un ciel gris.',
    ),
    (
      id: '1795385073459_input_26',
      source: 'input',
      timestampMs: 119117,
      partial: false,
      text:
          'My neighbor cleaned the garden gate with a lot of patience, and then the teacher moved the round fountain with a lot of patience.',
    ),
    (
      id: '1795385073459_input_27',
      source: 'input',
      timestampMs: 128417,
      partial: false,
      text:
          'Le libraire a photographié le banc vert pour la rentrée des classes, puis le jardinier a déplacé le banc vert avant la pluie du soir.',
    ),
    (
      id: '1795385073459_input_29',
      source: 'input',
      timestampMs: 138717,
      partial: false,
      text:
          'The gardener moved the bus shelter without telling anyone, and then the painter tidied the garden gate under a gray sky.',
    ),
    (
      id: '1795385073459_input_31',
      source: 'input',
      timestampMs: 148017,
      partial: false,
      text:
          'La boulangère a nettoyé le kiosque à journaux malgré le vent froid, puis la boulangère a décoré le kiosque à journaux avec beaucoup de patience.',
    ),
    (
      id: '1795385073459_input_33',
      source: 'input',
      timestampMs: 158917,
      partial: false,
      text:
          'The baker painted the garden gate for the start of school, and then the mayor moved the wooden fence before the evening rain.',
    ),
    (
      id: '1795385073459_input_36',
      source: 'input',
      timestampMs: 166917,
      partial: false,
      text:
          'Le maire a mesuré la fontaine ronde pendant la fête du village, puis la musicienne a nettoyé le lavoir au lever du soleil.',
    ),
    (
      id: '1795385073459_input_38',
      source: 'input',
      timestampMs: 176717,
      partial: false,
      text:
          'My neighbor repaired the wooden fence despite the cold wind, and then the librarian measured the wooden fence before the evening rain.',
    ),
    (
      id: '1795385073459_input_39',
      source: 'input',
      timestampMs: 186317,
      partial: false,
      text:
          'La boulangère a photographié le banc vert sans prévenir personne, puis la musicienne a nettoyé le banc vert pendant la fête du village.',
    ),
    (
      id: '1795385073459_input_41',
      source: 'input',
      timestampMs: 196517,
      partial: false,
      text:
          'The librarian repaired the round fountain at sunrise, and then the librarian painted the stone wall during the village fair.',
    ),
    (
      id: '1795385073459_input_43',
      source: 'input',
      timestampMs: 205417,
      partial: false,
      text:
          'Le jardinier a photographié la vieille barrière pour la rentrée des classes, puis le libraire a repeint le banc vert pendant la fête du village.',
    ),
    (
      id: '1795385073459_input_46',
      source: 'input',
      timestampMs: 214917,
      partial: false,
      text:
          'The postman measured the bus shelter at sunrise, and then the painter tidied the stone wall despite the cold wind.',
    ),
    (
      id: '1795385073459_input_48',
      source: 'input',
      timestampMs: 223917,
      partial: false,
      text:
          'La boulangère a repeint la serre pendant la fête du village, puis la gardienne a repeint le kiosque à journaux pendant la fête du village.',
    ),
    (
      id: '1795385073459_input_50',
      source: 'input',
      timestampMs: 233517,
      partial: false,
      text:
          'The mayor measured the wooden fence at sunrise, and then the gardener cleaned the old greenhouse under a gray sky.',
    ),
    (
      id: '1795385073459_input_51',
      source: 'input',
      timestampMs: 241917,
      partial: false,
      text:
          'La gardienne a photographié le kiosque à journaux au lever du soleil, puis le libraire a décoré le kiosque à journaux pour la rentrée des classes.',
    ),
    (
      id: '1795385073459_input_54',
      source: 'input',
      timestampMs: 251817,
      partial: false,
      text:
          'The teacher photographed the old greenhouse at sunrise, and then the teacher cleaned the round fountain despite the cold wind.',
    ),
    (
      id: '1795385073459_input_56',
      source: 'input',
      timestampMs: 260717,
      partial: false,
      text:
          'Le jardinier a déplacé la serre sous un ciel gris, puis la boulangère a photographié le lavoir sans prévenir personne.',
    ),
    (
      id: '1795385073459_input_58',
      source: 'input',
      timestampMs: 269817,
      partial: false,
      text:
          'The painter photographed the stone wall at sunrise, and then the mayor decorated the green bench before the evening rain.',
    ),
    (
      id: '1795385073459_input_60',
      source: 'input',
      timestampMs: 278417,
      partial: false,
      text:
          'Le jardinier a décoré le portail sans prévenir personne, puis le jardinier a nettoyé la cabane malgré le vent froid.',
    ),
    (
      id: '1795385073459_input_63',
      source: 'input',
      timestampMs: 287317,
      partial: false,
      text:
          'The baker measured the old greenhouse under a grey sky, and then the baker painted the stone wall during the village fair.',
    ),
    (
      id: '1795385073459_input_64',
      source: 'input',
      timestampMs: 296517,
      partial: false,
      text:
          'La musicienne a déplacé le kiosque à journaux avec beaucoup de passion.',
    ),
    (
      id: '1795385073459_output_2',
      source: 'output',
      timestampMs: 17,
      partial: false,
      text:
          'The baker cleaned the old greenhouse without telling anyone, and then the librarian cleaned the bus shelter with a lot of patience.',
    ),
    (
      id: '1795385073459_output_3',
      source: 'output',
      timestampMs: 9017,
      partial: false,
      text:
          'Le libraire a rangé la fontaine ronde malgré le vent froid, puis la gardienne a réparé la vieille barrière pour la rentrée des classes.',
    ),
    (
      id: '1795385073459_output_5',
      source: 'output',
      timestampMs: 18717,
      partial: false,
      text:
          'The librarian tidied the small cabin with a lot of patience, and then the postman painted the old greenhouse with a lot of patience.',
    ),
    (
      id: '1795385073459_output_7',
      source: 'output',
      timestampMs: 28517,
      partial: false,
      text:
          'La boulangère a décoré le portail sans prévenir personne, puis le jardinier a mesuré le banc vert avant la pluie du soir.',
    ),
    (
      id: '1795385073459_output_9',
      source: 'output',
      timestampMs: 37717,
      partial: false,
      text:
          'The librarian photographed the garden gate despite the cold wind, and then the baker moved the green bench for the start of school.',
    ),
    (
      id: '1795385073459_output_11',
      source: 'output',
      timestampMs: 46517,
      partial: false,
      text:
          'Le facteur a mesuré la fontaine ronde malgré le vent froid, puis le facteur a photographié le lavoir pendant la fête du village.',
    ),
    (
      id: '1795385073459_output_13',
      source: 'output',
      timestampMs: 56258,
      partial: true,
      text:
          'The mayor measured the round fountain without telling anyone, and then the',
    ),
    (
      id: '1795385073459_output_21',
      source: 'output',
      timestampMs: 74317,
      partial: false,
      text: 'In the green bench despite the cold wind.',
    ),
    (
      id: '1795385073459_output_22',
      source: 'output',
      timestampMs: 83717,
      partial: false,
      text:
          'Le libraire a décoré le kiosque à journaux malgré le vent froid, puis la gardienne a nettoyé le portail pour la rentrée des classes.',
    ),
    (
      id: '1795385073459_output_24',
      source: 'output',
      timestampMs: 92817,
      partial: false,
      text:
          'The librarian painted the old greenhouse for the start of school, and then the baker measured the round fountain before the evening rain.',
    ),
    (
      id: '1795385073459_output_25',
      source: 'output',
      timestampMs: 101917,
      partial: false,
      text:
          'La voisine a nettoyé le kiosque à journaux avant la pluie du soir, puis le maire a mesuré le portail avec beaucoup de patience.',
    ),
    (
      id: '1795385073459_output_28',
      source: 'output',
      timestampMs: 111617,
      partial: false,
      text:
          'The mayor painted the stone wall during the village fair, and then the gardener moved the bus shelter before the evening rain.',
    ),
    (
      id: '1795385073459_output_30',
      source: 'output',
      timestampMs: 120517,
      partial: false,
      text:
          'Le libraire a nettoyé le kiosque à journaux avec beaucoup de patience, puis la voisine a nettoyé le kiosque à journaux au lever du soleil.',
    ),
    (
      id: '1795385073459_output_32',
      source: 'output',
      timestampMs: 129217,
      partial: false,
      text:
          'The librarian decorated the old greenhouse with a lot of patience, and then the teacher painted the round fountain with a lot of patience.',
    ),
    (
      id: '1795385073459_output_34',
      source: 'output',
      timestampMs: 138717,
      partial: false,
      text:
          'La boulangère a décoré la cabane pendant la fête du village, puis le libraire a rangé la fontaine ronde avec beaucoup de patience.',
    ),
    (
      id: '1795385073459_output_35',
      source: 'output',
      timestampMs: 148017,
      partial: false,
      text:
          'The baker painted the old greenhouse at sunrise, and then the librarian painted the small cabin with a lot of patience.',
    ),
    (
      id: '1795385073459_output_37',
      source: 'output',
      timestampMs: 156917,
      partial: false,
      text:
          'La gardienne a déplacé la vieille barrière avant la pluie de soir, puis la gardienne a nettoyé le kiosque à journaux sous un ciel gris.',
    ),
    (
      id: '1795385073459_output_40',
      source: 'output',
      timestampMs: 165817,
      partial: false,
      text:
          'The teacher cleaned the round fountain without telling anyone, and then the postman repaired the round fountain despite the cold wind.',
    ),
    (
      id: '1795385073459_output_42',
      source: 'output',
      timestampMs: 174717,
      partial: false,
      text:
          'La boulangère a basuré la cabane malgré le vent froid, puis le libraire a basuré la cabane avec beaucoup de patience.',
    ),
    (
      id: '1795385073459_output_44',
      source: 'output',
      timestampMs: 184117,
      partial: false,
      text:
          'The librarian repaired the wooden fence with a lot of patience, and then my neighbor photographed the stone wall at sunrise.',
    ),
    (
      id: '1795385073459_output_45',
      source: 'output',
      timestampMs: 194017,
      partial: false,
      text:
          'La musicienne a rangé le kiosque à journaux sous un ciel gris, puis la boulangère a repeint le portail pendant la fête du village.',
    ),
    (
      id: '1795385073459_output_47',
      source: 'output',
      timestampMs: 203517,
      partial: false,
      text:
          'The painter moved the small cabin without telling anyone, and then the gardener painted the round fountain for the start of school.',
    ),
    (
      id: '1795385073459_output_49',
      source: 'output',
      timestampMs: 212117,
      partial: false,
      text:
          'La musicienne a basuré la cabane sous un ciel gris, puis le libraire a réparé la fontaine ronde pendant la fête du village.',
    ),
    (
      id: '1795385073459_output_52',
      source: 'output',
      timestampMs: 221117,
      partial: false,
      text:
          'The Gognat tied the green bench before the evening rain, and then the librarian repaired the old greenhouse without telling anyone.',
    ),
    (
      id: '1795385073459_output_53',
      source: 'output',
      timestampMs: 231317,
      partial: false,
      text:
          'Le maire a basuré le kiosque à journaux pour la rentrée des classes, puis le facteur a déplacé la cabane malgré le vent froid.',
    ),
    (
      id: '1795385073459_output_55',
      source: 'output',
      timestampMs: 240817,
      partial: false,
      text:
          'The teacher painted the bus shelter before the evening rain, and then the postman painted the old greenhouse without telling anyone.',
    ),
    (
      id: '1795385073459_output_57',
      source: 'output',
      timestampMs: 250417,
      partial: false,
      text:
          'Le libraire a repeint le kiosque à journaux pour la rentrée des classes, puis le jardinier a déplacé la serre sans prévenir personne.',
    ),
    (
      id: '1795385073459_output_59',
      source: 'output',
      timestampMs: 259617,
      partial: false,
      text:
          'The librarian photographed the green bench despite the cold wind, and then the postman repaired the bus shelter under a grey sky.',
    ),
    (
      id: '1795385073459_output_61',
      source: 'output',
      timestampMs: 269217,
      partial: false,
      text:
          'La gardienne a nettoyé le lavoir avant la pluie du soir, puis le libraire a photographié la cabane sans prévenir personne.',
    ),
    (
      id: '1795385073459_output_62',
      source: 'output',
      timestampMs: 278817,
      partial: false,
      text:
          'The painter measured the small cabin without telling anyone, and then the mayor measured the garden gate without telling anyone.',
    ),
    (
      id: '1795385073459_output_65',
      source: 'output',
      timestampMs: 287217,
      partial: false,
      text:
          'Le jardinier a réparé la vieille barrière sous un ciel gris, puis le libraire a rangé la vieille barrière au lever du soleil.',
    ),
    (
      id: '1795385073459_output_66',
      source: 'output',
      timestampMs: 296517,
      partial: false,
      text: 'The painter repaired the small cabin during the village fair, and',
    ),
  ],
  gaps: <ProbeGap>[
    (
      markerId: '1795385073459_input_15',
      source: 'input',
      markerStartMs: 56017,
      markerEndMs: 74000,
      planStartMs: 55017,
      recovered: <({int offsetMs, String text})>[
        (
          offsetMs: 0,
          text:
              'La gardienne a rangé la cabane pour la rentrée des classes, puis la boulangère a réparé la serre au lever du soleil.',
        ),
        (
          offsetMs: 9300,
          text:
              'The gardener decorated the wooden fence for the start of school, and then the postman cleaned the old greenhouse during the village fair. Le jardinier a photographié le lac.',
        ),
      ],
    ),
    (
      markerId: '1795385073459_output_18',
      source: 'output',
      markerStartMs: 55317,
      markerEndMs: 79000,
      planStartMs: 54317,
      recovered: <({int offsetMs, String text})>[
        (
          offsetMs: 0,
          text:
              'The mayor measured the round fountain without telling anyone, and then the gardener photographed the old greenhouse without telling anyone.',
        ),
        (
          offsetMs: 10100,
          text:
              'La Mega Photo va frayer le kiosque à journaux pour la rentrée des classes, puis la boulangère a repeint la cabane avant la pluie du soir.',
        ),
        (
          offsetMs: 20000,
          text:
              'The baker photographed the green bench despite the cold wind, and then the postman cleaned the green bench',
        ),
      ],
    ),
  ],
);

const ProbeScenario probeRelaunch = (
  name: 'Relaunch',
  sessionId: '1795385499416',
  segments: <ProbeSegment>[
    (
      id: '1795385499416_input_1',
      source: 'input',
      timestampMs: 28,
      partial: false,
      text:
          'La gardienne a photographié le lavoir avec beaucoup de patience, puis le facteur a photographié la fontaine ronde pendant la fête du village.',
    ),
    (
      id: '1795385499416_input_4',
      source: 'input',
      timestampMs: 10628,
      partial: false,
      text:
          'The gardener cleaned the green bench before the evening rain, and then the painter tidied the round fountain before the evening rain.',
    ),
    (
      id: '1795385499416_input_6',
      source: 'input',
      timestampMs: 20128,
      partial: false,
      text:
          'La boulangère a repeint la vieille barrière avec beaucoup de patience, puis la voisine a repeint le lavoir au lever du soleil.',
    ),
    (
      id: '1795385499416_input_8',
      source: 'input',
      timestampMs: 29328,
      partial: false,
      text:
          'The teacher moved the garden gate despite the cold wind, and then the baker painted the stone wall without telling anyone.',
    ),
    (
      id: '1795385499416_input_10',
      source: 'input',
      timestampMs: 39181,
      partial: true,
      text: 'La boulangère a',
    ),
    (
      id: '1795385499416_output_2',
      source: 'output',
      timestampMs: 28,
      partial: false,
      text:
          'The baker cleaned the old greenhouse without telling anyone, and then the librarian cleaned the bus shelter with a lot of patience.',
    ),
    (
      id: '1795385499416_output_3',
      source: 'output',
      timestampMs: 9028,
      partial: false,
      text:
          'Le libraire a rangé la fontaine ronde malgré le vent froid, puis la gardienne a réparé la vieille barrière pour la rentrée des classes.',
    ),
    (
      id: '1795385499416_output_5',
      source: 'output',
      timestampMs: 18728,
      partial: false,
      text:
          'The librarian tidied the small cabin with a lot of patience, and then the postman painted the old greenhouse with a lot of patience.',
    ),
    (
      id: '1795385499416_output_7',
      source: 'output',
      timestampMs: 28528,
      partial: false,
      text:
          'La boulangère a décoré le portail sans prévenir personne, puis le jardinier a mesuré le banc vert avant la pluie du soir.',
    ),
    (
      id: '1795385499416_output_9',
      source: 'output',
      timestampMs: 38682,
      partial: true,
      text: 'The librarian',
    ),
  ],
  gaps: <ProbeGap>[
    (
      markerId: '1795385499416_input_pending',
      source: 'input',
      markerStartMs: 38028,
      markerEndMs: 81000,
      planStartMs: 37028,
      recovered: <({int offsetMs, String text})>[
        (
          offsetMs: 0,
          text:
              'La boulangère a décoré le portail avec beaucoup de patience, puis le maire a repeint le banc vert pendant la fête du village.',
        ),
        (
          offsetMs: 10300,
          text:
              'The postman measured the bus shelter during the village fair, and then the baker repaired the old greenhouse with a lot of patience. La gardienne a rangé la cabane pour la rentrée des classes.',
        ),
        (
          offsetMs: 22300,
          text:
              'Puis la boulangère a réparé la serre au lever du soleil. The gardener decorated the wooden fence for the start of school, and then the postman cleaned the old greenhouse during the village fair.',
        ),
        (
          offsetMs: 34300,
          text:
              'Le jardinier a photographié le lavoir sous un ciel gris, puis la voisine a photographié le kiosque à journaux sous un ciel gris.',
        ),
      ],
    ),
    (
      markerId: '1795385499416_output_pending',
      source: 'output',
      markerStartMs: 37728,
      markerEndMs: 81000,
      planStartMs: 36728,
      recovered: <({int offsetMs, String text})>[
        (
          offsetMs: 0,
          text:
              'The librarian photographed the garden gate despite the cold wind, and then the baker moved the green bench for the start of school.',
        ),
        (
          offsetMs: 9800,
          text:
              'Le fighter a mesuré la fontaine ronde malgré le vent froid, puis le fighter a photographié le lavoir pendant la fête du village. The mayor measured the round fountain without telling anyone.',
        ),
        (
          offsetMs: 21800,
          text:
              'And then the gardener photographed the old greenhouse without telling anyone. La mère a photographié le kiosque ajourneau pour la rentrée des classes.',
        ),
        (
          offsetMs: 31200,
          text:
              'Puis la boulangère a repeint la cabane avant la pluie du soir. The baker photographed the green bench despite the cold wind.',
        ),
        (
          offsetMs: 41100,
          text:
              'And then the postman cleaned the green bench despite the cold wind.',
        ),
      ],
    ),
  ],
);

const ProbeScenario probeBackToBack = (
  name: 'BackToBack',
  sessionId: '1795385632867',
  segments: <ProbeSegment>[
    (
      id: '1795385632867_input_1',
      source: 'input',
      timestampMs: 21,
      partial: false,
      text:
          'La gardienne a photographié le lavoir avec beaucoup de patience, puis le facteur a photographié la fontaine ronde pendant la fête du village.',
    ),
    (
      id: '1795385632867_input_4',
      source: 'input',
      timestampMs: 10621,
      partial: false,
      text:
          'The gardener cleaned the green bench before the evening rain, and then the painter tidied the round fountain before the evening rain.',
    ),
    (
      id: '1795385632867_input_6',
      source: 'input',
      timestampMs: 20121,
      partial: false,
      text:
          'La boulangère a repeint la vieille barrière avec beaucoup de patience, puis la voisine a repeint le lavoir au lever du soleil.',
    ),
    (
      id: '1795385632867_input_8',
      source: 'input',
      timestampMs: 29321,
      partial: false,
      text:
          'The teacher moved the garden gate despite the cold wind, and then the baker painted the stone wall without telling anyone.',
    ),
    (
      id: '1795385632867_input_10',
      source: 'input',
      timestampMs: 38021,
      partial: false,
      text:
          'La boulangère a décoré le portail avec beaucoup de patience, puis le maire a repeint le banc vert pendant la fête du village.',
    ),
    (
      id: '1795385632867_input_12',
      source: 'input',
      timestampMs: 47321,
      partial: false,
      text:
          'The postman measured the bus shelter during the village fair, and then the baker repaired the old greenhouse with a lot of patience.',
    ),
    (
      id: '1795385632867_input_14',
      source: 'input',
      timestampMs: 57052,
      partial: false,
      text: 'La gardienne a rangé la cabane pour la rentrée des classes',
    ),
    (
      id: '1795385632867_output_2',
      source: 'output',
      timestampMs: 21,
      partial: false,
      text:
          'The baker cleaned the old greenhouse without telling anyone, and then the librarian cleaned the bus shelter with a lot of patience.',
    ),
    (
      id: '1795385632867_output_3',
      source: 'output',
      timestampMs: 9021,
      partial: false,
      text:
          'Le libraire a rangé la fontaine ronde malgré le vent froid, puis la gardienne a réparé la vieille barrière pour la rentrée des classes.',
    ),
    (
      id: '1795385632867_output_5',
      source: 'output',
      timestampMs: 18721,
      partial: false,
      text:
          'The librarian tidied the small cabin with a lot of patience, and then the postman painted the old greenhouse with a lot of patience.',
    ),
    (
      id: '1795385632867_output_7',
      source: 'output',
      timestampMs: 28521,
      partial: false,
      text:
          'La boulangère a décoré le portail sans prévenir personne, puis le jardinier a mesuré le banc vert avant la pluie du soir.',
    ),
    (
      id: '1795385632867_output_9',
      source: 'output',
      timestampMs: 37721,
      partial: false,
      text:
          'The librarian photographed the garden gate despite the cold wind, and then the baker moved the green bench for the start of school.',
    ),
    (
      id: '1795385632867_output_11',
      source: 'output',
      timestampMs: 46521,
      partial: false,
      text:
          'Le facteur a mesuré la fontaine ronde malgré le vent froid, puis le facteur a photographié le lavoir pendant la fête du village.',
    ),
    (
      id: '1795385632867_output_13',
      source: 'output',
      timestampMs: 56256,
      partial: false,
      text: 'The mayor measured the round fountain without',
    ),
  ],
  gaps: <ProbeGap>[
    (
      markerId: '1795385632867_input_15',
      source: 'input',
      markerStartMs: 56021,
      markerEndMs: 125000,
      planStartMs: 55021,
      recovered: <({int offsetMs, String text})>[
        (
          offsetMs: 0,
          text:
              'La gardienne a rangé la cabane pour la rentrée des classes, puis la boulangère a réparé la serre au lever du soleil.',
        ),
        (
          offsetMs: 9300,
          text:
              'The gardener decorated the wooden fence for the start of school, and then the postman cleaned the old greenhouse during the village fair.',
        ),
        (
          offsetMs: 18000,
          text:
              'Le jardinier a photographié le lavoir sous un ciel gris, puis la voisine a photographié le kiosque à journaux sous un ciel gris.',
        ),
        (
          offsetMs: 27900,
          text:
              'The painter painted the bus shelter for the start of school, and then the teacher repaired the garden gate without telling anyone. La voisine a nettoyé la cabane pendant la fête du village.',
        ),
        (
          offsetMs: 39900,
          text:
              'Puis le jardinier a nettoyé le kiosque à journaux malgré le vent froid. The baker decorated the garden gate for the start of school.',
        ),
        (
          offsetMs: 49100,
          text:
              'And then the postman painted the green bench with a lot of patience. La voisine a repeint le portail au lever du soleil.',
        ),
        (
          offsetMs: 58600,
          text:
              'Puis la gardienne a nettoyé le lavoir sous un ciel gris. My neighbor cleaned the garden gate with a lot of patience, and then the teacher moved the round fountain with a lot of patience.',
        ),
      ],
    ),
    (
      markerId: '1795385632867_output_16',
      source: 'output',
      markerStartMs: 55321,
      markerEndMs: 124000,
      planStartMs: 54321,
      recovered: <({int offsetMs, String text})>[
        (
          offsetMs: 0,
          text:
              'The mayor measured the round fountain without telling anyone, and then the gardener photographed the old greenhouse without telling anyone.',
        ),
        (
          offsetMs: 10100,
          text:
              'La Mega Follow va trier le kiosque à journaux pour la rentrée des classes, puis la boulangère a repeint la cabane avant la pluie du soir.',
        ),
        (
          offsetMs: 20000,
          text:
              'The baker photographed the green bench despite the cold wind, and then the postman cleaned the green bench despite the cold wind.',
        ),
        (
          offsetMs: 29400,
          text:
              'Le libraire a décoré le kiosque à journaux malgré le vent froid, puis la gardienne a nettoyé le portail pour la rentrée des classes.',
        ),
        (
          offsetMs: 38500,
          text:
              'The librarian painted the old greenhouse for the start of school, and then the baker measured the round fountain before the evening rain.',
        ),
        (
          offsetMs: 47600,
          text:
              'La voisine a nettoyé le kiosque à journaux avant la pluie du soir, puis le maire a mesuré le portail avec beaucoup de patience.',
        ),
        (
          offsetMs: 57200,
          text:
              'The mayor painted the stone wall during the village fair, and then the gardener moved the bus shelter before the evening rain.',
        ),
        (
          offsetMs: 66100,
          text:
              'Le libraire a nettoyé le kiosque à journaux avec beaucoup de patience, puis la voisine a nettoyé.',
        ),
      ],
    ),
  ],
);

/// RMS par pas de 100 ms du micro sur l'intervalle retranscrit après le
/// relancement (37,028 s → 82,0 s de la réunion), lu dans le vrai WAV.
const int probeRelaunchMicStartMs = 37028;
const List<int> probeRelaunchMicRms = <int>[
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  5294,
  8565,
  3601,
  7983,
  7753,
  5156,
  7201,
  6014,
  6299,
  6874,
  1890,
  7557,
  5983,
  7088,
  5221,
  6101,
  3227,
  4108,
  7074,
  7658,
  5902,
  4044,
  7223,
  2258,
  4410,
  5580,
  6312,
  6514,
  5098,
  2945,
  6748,
  5942,
  6602,
  3269,
  3020,
  442,
  1,
  2,
  402,
  5708,
  7192,
  7774,
  8653,
  7540,
  6068,
  5819,
  5149,
  5721,
  7286,
  6036,
  7846,
  5100,
  7297,
  2499,
  4100,
  7003,
  7850,
  7871,
  2899,
  5911,
  4193,
  5213,
  4951,
  6392,
  7209,
  5705,
  3951,
  1956,
  16,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  4358,
  852,
  6427,
  5872,
  1716,
  7097,
  8070,
  7686,
  4471,
  5812,
  3785,
  4667,
  5838,
  3896,
  3237,
  6974,
  4211,
  5172,
  4276,
  6675,
  7044,
  8233,
  5299,
  6190,
  6539,
  2307,
  221,
  5924,
  5002,
  2020,
  3,
  1295,
  7418,
  6940,
  7465,
  4987,
  5765,
  5023,
  5097,
  6329,
  5491,
  3755,
  6903,
  5151,
  6555,
  6868,
  6926,
  5661,
  1168,
  7521,
  8277,
  6638,
  6356,
  1685,
  5800,
  3298,
  6226,
  6818,
  5910,
  2585,
  2782,
  6933,
  3750,
  5038,
  3830,
  409,
  206,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  22,
  7617,
  7091,
  6927,
  5808,
  3259,
  8076,
  7358,
  7781,
  5537,
  6715,
  5252,
  7316,
  6434,
  5105,
  5659,
  8221,
  6555,
  1025,
  7131,
  7347,
  5232,
  6891,
  934,
  7283,
  5344,
  3870,
  4417,
  7243,
  5672,
  3022,
  2724,
  139,
  1,
  3,
  563,
  6626,
  7115,
  6031,
  6555,
  7898,
  6674,
  5142,
  7569,
  6417,
  5684,
  3851,
  7123,
  5680,
  7071,
  6500,
  3247,
  7112,
  6929,
  7477,
  6738,
  7550,
  4195,
  5907,
  4565,
  7412,
  7464,
  5237,
  2861,
  1,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  4793,
  3128,
  6619,
  5057,
  7612,
  5645,
  5337,
  4485,
  5524,
  6697,
  5983,
  5606,
  5482,
  6546,
  6000,
  7191,
  781,
  6850,
  5015,
  636,
  5315,
  5198,
  893,
  5736,
  5711,
  5435,
  713,
  2146,
  6845,
  4921,
  1345,
  3,
  2477,
  7466,
  6898,
  7506,
  3888,
  4881,
  6844,
  2497,
  6124,
  6956,
  3298,
  5926,
  8104,
  6362,
  7648,
  6774,
  6790,
  4072,
  4460,
  7782,
  7911,
  6609,
  5130,
  580,
  6104,
  7058,
  8272,
  5736,
  5812,
  6701,
  2740,
  352,
  5700,
  5140,
  2292,
  1,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  7011,
  8541,
  5163,
  6337,
  3908,
  8125,
  8670,
  8176,
  7690,
  3221,
  5472,
  3679,
  7183,
  5634,
  5911,
  3079,
  8086,
  7012,
  7852,
  8024,
  3323,
  8502,
  4139,
  2279,
  5826,
  5788,
  6711,
  3338,
  7073,
  6149,
  5054,
  5183,
  6261,
  2525,
  1,
  1,
  92,
  3506,
  7890,
  7369,
  3995,
  8328,
  4452,
  8141,
  8136,
  5402,
  2189,
  6050,
  7063,
  4802,
  6831,
  1335,
  7315,
  7610,
  7129,
  1239,
  6943,
  6341,
  1919,
  6697,
  4686,
  7324,
  7991,
  8354,
  3262,
  4905,
  5949,
  7222,
  3462,
  6129,
  6838,
  4873,
  4990,
  5199,
  170,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
];
