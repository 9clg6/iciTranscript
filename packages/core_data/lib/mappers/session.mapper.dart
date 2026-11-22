import 'package:core_domain/domain/entities/session.entity.dart';
import 'package:core_domain/domain/enum/session_status.enum.dart';

import 'package:core_data/model/local/session.local.model.dart';

/// Extensions de mapping pour [SessionLocalModel].
extension SessionLocalModelX on SessionLocalModel {
  /// Convertit en [SessionEntity].
  SessionEntity toEntity() => SessionEntity(
    id: id,
    title: title,
    createdAt: DateTime.parse(createdAt),
    updatedAt: DateTime.parse(updatedAt),
    durationSeconds: durationSeconds,
    // Un statut écrit par une version plus récente de l'app (base partagée)
    // ne doit pas casser la lecture : il est lu comme une session close.
    status: SessionStatus.values.asNameMap()[status] ?? SessionStatus.completed,
  );
}

/// Extensions de mapping pour [SessionEntity] vers le modele local.
extension SessionEntityToLocalX on SessionEntity {
  /// Convertit en [SessionLocalModel].
  SessionLocalModel toLocalModel() => SessionLocalModel(
    id: id,
    title: title,
    createdAt: createdAt.toIso8601String(),
    updatedAt: updatedAt.toIso8601String(),
    durationSeconds: durationSeconds,
    status: status.name,
  );
}
