import 'dart:io';

/// Commande du serveur de transcription (voxmlx-serve), partagée par les
/// réunions et la dictée : un seul serveur, démarré une seule fois.
const String voxmlxCommand = 'uvx';

/// Arguments de [voxmlxCommand].
List<String> voxmlxArgs() => <String>[
  // Sans version épinglée, uv choisit le Python le plus récent (3.15+) pour
  // lequel mlx n'a pas encore de wheel : l'installation échoue et le serveur
  // ne démarre jamais.
  '--python',
  '3.12',
  '--from',
  'git+https://github.com/T0mSIlver/voxmlx.git@2ea0639570e447493d04349d96a41f71c031ae0d[server]',
  'voxmlx-serve',
  '--model',
  'T0mSIlver/Voxtral-Mini-4B-Realtime-2602-MLX-4bit',
  '--parent-pid',
  '$pid',
];
