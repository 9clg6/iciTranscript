import 'package:core_data/database/dao/detected_question.dao.dart';
import 'package:ici_transcript/application/services/live_answers/question_store.dart';
import 'package:ici_transcript/core/providers/data/database.provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'question_store.provider.g.dart';

/// Questions détectées gardées avec la note, sur la base de l'app.
@Riverpod(keepAlive: true)
QuestionStore questionStore(Ref ref) =>
    DriftQuestionStore(DetectedQuestionDao(ref.watch(databaseProvider)));
