// GÉNÉRÉ depuis la sonde 10 (scratchpad/probe/live10 : vrai service contre
// vrai serveur ralenti 0,6× par le proxy, branche oats-reliability-6). Ne
// pas retoucher à la main.
//
// K : base telle que l'a trouvée le relancement après l'arrêt brutal à
// 300 s (svc_Krelaunch.jsonl, « relaunch_before ») : les segments, plus les
// deux seuls repères, PROVISOIRES, mic 2:37–4:59 et sys 2:16–5:00. L'audio
// jeté depuis ~202 s (dès 0:59 au micro, 0:53 au système) n'est sous aucun
// repère.

import 'probe5_sequences.dart';

const String probe10KSessionId = '1795418592874';

/// Segments rangés (hors repères), heures de réunion.
const List<ProbeSegment> probe10KSegments = <ProbeSegment>[
  (
    id: '1795418592874_output_1',
    source: 'output',
    timestampMs: 51,
    partial: false,
    text:
        'The painter decorated the old greenhouse under a grey sky, and then the mayor cleaned the green bench under a grey sky.',
  ),
  (
    id: '1795418592874_input_2',
    source: 'input',
    timestampMs: 51,
    partial: false,
    text:
        'Le maire a déplacé la vieille barrière sans prévenir personne, puis le libraire a rangé le portail sous un ciel gris.',
  ),
  (
    id: '1795418592874_output_3',
    source: 'output',
    timestampMs: 7951,
    partial: false,
    text:
        'Le libraire a basuré le barbeur malgré le vent froid, puis le facteur a rangé la cabane malgré le vent froid.',
  ),
  (
    id: '1795418592874_input_4',
    source: 'input',
    timestampMs: 12651,
    partial: false,
    text:
        'The teacher measured the stone wall before the evening rain, and then the teacher tidied the wooden fence during the village fair.',
  ),
  (
    id: '1795418592874_output_5',
    source: 'output',
    timestampMs: 19751,
    partial: false,
    text:
        'The Gagna moved the stone wall despite the cold wind, and then the painter photographed the small cabin under a grey sky.',
  ),
  (
    id: '1795418592874_input_6',
    source: 'input',
    timestampMs: 20351,
    partial: false,
    text:
        'La gardienne a rangé la vieille barrière pour la rentrée des classes, puis la musicienne a repeint le kiosque à journaux avant la pluie du soir.',
  ),
  (
    id: '1795418592874_output_7',
    source: 'output',
    timestampMs: 28351,
    partial: false,
    text:
        'Le libraire a repeint la vieille barrière malgré le vent froid, puis le facteur a repeint le banc vert sous un ciel gris.',
  ),
  (
    id: '1795418592874_input_8',
    source: 'input',
    timestampMs: 31951,
    partial: false,
    text:
        'The librarian cleaned the old greenhouse at sunrise, and then the librarian measured the small cabin during the village fair.',
  ),
  (
    id: '1795418592874_output_9',
    source: 'output',
    timestampMs: 35851,
    partial: false,
    text:
        'The librarian painted the stone wall during the village fair, and then my neighbor painted the small cabin for the start of school.',
  ),
  (
    id: '1795418592874_input_10',
    source: 'input',
    timestampMs: 41451,
    partial: false,
    text:
        'Le facteur à photographier le lavoir sous un ciel gris, puis le facteur à nettoyer le portail avec beaucoup de patience.',
  ),
  (
    id: '1795418592874_output_11',
    source: 'output',
    timestampMs: 45251,
    partial: false,
    text:
        'La gardienne a mesuré le lavoir sous un ciel gris, puis la gardienne a décoré le kiosque à journaux sans prévenir personne.',
  ),
  (
    id: '1795418592874_input_12',
    source: 'input',
    timestampMs: 52651,
    partial: false,
    text:
        'The postman painted the green bench for the start of school, and then the baker measured the garden gate at sunrise.',
  ),
  (
    id: '1795418592874_output_13',
    source: 'output',
    timestampMs: 90353,
    partial: false,
    text:
        'The mayor repaired the green bench for the start of school, and then the baker photographed the green bench',
  ),
];

/// Repères rangés à l'arrêt brutal (id, source, texte).
const List<({String id, String source, String text})> probe10KMarkers =
    <({String id, String source, String text})>[
      (
        id: '1795418592874_input_pending',
        source: 'input',
        text: 'Transcription interrompue : 00:02:37 – 00:04:59',
      ),
      (
        id: '1795418592874_output_pending',
        source: 'output',
        text: 'Transcription interrompue : 00:02:16 – 00:05:00',
      ),
    ];

/// Texte lu (probe/audio/live60/schedule.json), jusqu'à 600 s.
const List<ProbeSentence> probe10Live60Reference = <ProbeSentence>[
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
  (
    source: 'input',
    startMs: 430620,
    endMs: 437490,
    text:
        'The librarian photographed the stone wall with a lot of patience, and then my neighbour moved the small cabin before the evening rain.',
  ),
  (
    source: 'output',
    startMs: 437340,
    endMs: 443790,
    text:
        'La voisine a rangé la fontaine ronde avant la pluie du soir, puis la musicienne a rangé la cabane pendant la fête du village.',
  ),
  (
    source: 'input',
    startMs: 441490,
    endMs: 448770,
    text:
        'La boulangère a nettoyé la fontaine ronde pendant la fête du village, puis la musicienne a repeint la vieille barrière malgré le vent froid.',
  ),
  (
    source: 'output',
    startMs: 449790,
    endMs: 457340,
    text:
        'The librarian photographed the old greenhouse under a grey sky, and then the teacher decorated the old greenhouse despite the cold wind.',
  ),
  (
    source: 'input',
    startMs: 450270,
    endMs: 456700,
    text:
        'My neighbour measured the small cabin with a lot of patience, and then the mayor decorated the garden gate during the village fair.',
  ),
  (
    source: 'input',
    startMs: 459700,
    endMs: 466830,
    text:
        'La gardienne a déplacé la cabane pour la rentrée des classes, puis le libraire a repeint la fontaine ronde pendant la fête du village.',
  ),
  (
    source: 'output',
    startMs: 463340,
    endMs: 469980,
    text:
        'Le facteur a nettoyé le banc vert pour la rentrée des classes, puis le maire a mesuré le kiosque à journaux pendant la fête du village.',
  ),
  (
    source: 'input',
    startMs: 468330,
    endMs: 475390,
    text:
        'The baker decorated the round fountain during the village fair, and then the librarian photographed the round fountain for the start of school.',
  ),
  (
    source: 'output',
    startMs: 471980,
    endMs: 479110,
    text:
        'The postman painted the old greenhouse despite the cold wind, and then the librarian measured the bus shelter with a lot of patience.',
  ),
  (
    source: 'input',
    startMs: 477890,
    endMs: 483660,
    text:
        'Le facteur a décoré la cabane sous un ciel gris, puis le maire a rangé le portail sous un ciel gris.',
  ),
  (
    source: 'output',
    startMs: 481610,
    endMs: 488600,
    text:
        'La boulangère a repeint la vieille barrière avant la pluie du soir, puis la musicienne a décoré le portail avec beaucoup de patience.',
  ),
  (
    source: 'input',
    startMs: 485160,
    endMs: 491620,
    text:
        'The librarian measured the green bench despite the cold wind, and then the mayor decorated the wooden fence for the start of school.',
  ),
  (
    source: 'output',
    startMs: 490600,
    endMs: 497630,
    text:
        'The postman decorated the round fountain under a grey sky, and then my neighbour cleaned the old greenhouse without telling anyone.',
  ),
  (
    source: 'input',
    startMs: 497620,
    endMs: 505040,
    text:
        'La boulangère a décoré la fontaine ronde pendant la fête du village, puis le jardinier a réparé le portail pour la rentrée des classes.',
  ),
  (
    source: 'output',
    startMs: 499630,
    endMs: 506590,
    text:
        'Le libraire a décoré le kiosque à journaux avec beaucoup de patience, puis le jardinier a nettoyé la vieille barrière sous un ciel gris.',
  ),
  (
    source: 'input',
    startMs: 507040,
    endMs: 513530,
    text:
        'The postman measured the garden gate with a lot of patience, and then the teacher cleaned the round fountain despite the cold wind.',
  ),
  (
    source: 'output',
    startMs: 508590,
    endMs: 514920,
    text:
        'The painter moved the round fountain despite the cold wind, and then my neighbour moved the old greenhouse at sunrise.',
  ),
  (
    source: 'output',
    startMs: 518920,
    endMs: 525310,
    text:
        'La musicienne a nettoyé le kiosque à journaux avec beaucoup de patience, puis la voisine a rangé le banc vert au lever du soleil.',
  ),
  (
    source: 'input',
    startMs: 519530,
    endMs: 526420,
    text:
        'La musicienne a rangé le portail au lever du soleil, puis la voisine a rangé la vieille barrière pour la rentrée des classes.',
  ),
  (
    source: 'input',
    startMs: 528920,
    endMs: 535190,
    text:
        'The postman painted the wooden fence under a grey sky, and then the postman cleaned the green bench for the start of school.',
  ),
  (
    source: 'output',
    startMs: 531310,
    endMs: 537700,
    text:
        'The gardener measured the bus shelter before the evening rain, and then the teacher moved the old greenhouse at sunrise.',
  ),
  (
    source: 'input',
    startMs: 537690,
    endMs: 544500,
    text:
        'Le facteur a mesuré la fontaine ronde pendant la fête du village, puis la musicienne a mesuré la serre malgré le vent froid.',
  ),
  (
    source: 'output',
    startMs: 543700,
    endMs: 549390,
    text:
        'La gardienne a réparé la serre sous un ciel gris, puis le maire a repeint la cabane avec beaucoup de patience.',
  ),
  (
    source: 'input',
    startMs: 550500,
    endMs: 557000,
    text:
        'The teacher photographed the garden gate before the evening rain, and then my neighbour repaired the stone wall for the start of school.',
  ),
  (
    source: 'output',
    startMs: 551890,
    endMs: 558880,
    text:
        'The postman repaired the round fountain before the evening rain, and then my neighbour tidied the green bench despite the cold wind.',
  ),
  (
    source: 'output',
    startMs: 561380,
    endMs: 568530,
    text:
        'La boulangère a réparé la serre pour la rentrée des classes, puis la gardienne a photographié le kiosque à journaux pour la rentrée des classes.',
  ),
  (
    source: 'input',
    startMs: 563000,
    endMs: 570510,
    text:
        'Le jardinier a nettoyé le lavoir avant la pluie du soir, puis la musicienne a photographié le kiosque à journaux sous un ciel gris.',
  ),
  (
    source: 'output',
    startMs: 571030,
    endMs: 577120,
    text:
        'My neighbour measured the garden gate under a grey sky, and then the gardener moved the wooden fence under a grey sky.',
  ),
  (
    source: 'input',
    startMs: 576510,
    endMs: 582980,
    text:
        'The teacher repaired the garden gate with a lot of patience, and then the postman measured the stone wall before the evening rain.',
  ),
  (
    source: 'output',
    startMs: 579120,
    endMs: 585400,
    text:
        'Le facteur a mesuré la serre avant la pluie du soir, puis le facteur a mesuré la cabane pendant la fête du village.',
  ),
  (
    source: 'input',
    startMs: 585480,
    endMs: 592430,
    text:
        'Le maire a photographié le lavoir sous un ciel gris, puis le libraire a rangé le kiosque à journaux pendant la fête du village.',
  ),
  (
    source: 'output',
    startMs: 588400,
    endMs: 595150,
    text:
        'The postman tidied the bus shelter without telling anyone, and then the painter cleaned the small cabin with a lot of patience.',
  ),
  (
    source: 'output',
    startMs: 596650,
    endMs: 603430,
    text:
        'La boulangère a déplacé le kiosque à journaux pour la rentrée des classes, puis la voisine a rangé la serre pour la rentrée des classes.',
  ),
  (
    source: 'input',
    startMs: 598430,
    endMs: 605270,
    text:
        'The teacher photographed the wooden fence for the start of school, and then the postman measured the round fountain without telling anyone.',
  ),
];
