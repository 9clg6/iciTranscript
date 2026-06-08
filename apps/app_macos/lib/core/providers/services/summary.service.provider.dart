import 'package:core_data/database/app_database.dart';
import 'package:core_data/database/dao/summary.dao.dart';
import 'package:ici_transcript/application/services/summary.service.dart';
import 'package:ici_transcript/core/providers/data/database.provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'summary.service.provider.g.dart';

/// Provider pour [SummaryService].
@Riverpod(keepAlive: true)
SummaryService summaryService(Ref ref) {
  final AppDatabase db = ref.watch(databaseProvider);
  final SummaryDao dao = SummaryDao(db);
  return SummaryService(summaryDao: dao);
}
