import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'now.provider.g.dart';

/// Horloge de l'agenda et de la détection de réunion (remplacée dans les
/// tests).
@Riverpod(keepAlive: true)
DateTime Function() now(Ref ref) => DateTime.now;
