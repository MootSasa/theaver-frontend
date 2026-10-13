import 'package:drift/drift.dart';

QueryExecutor openConnection([String? name]) {
  throw UnsupportedError('Cannot create a database on this platform');
}

Future<void> deleteDatabaseFile(String name) async {}
