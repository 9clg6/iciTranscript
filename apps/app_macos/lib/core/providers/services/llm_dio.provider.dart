import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'llm_dio.provider.g.dart';

/// Client HTTP de toutes les requêtes LLM (délais : voir `postLines`).
@Riverpod(keepAlive: true)
Dio llmDio(Ref ref) {
  final Dio dio = Dio();
  ref.onDispose(dio.close);
  return dio;
}
