import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

QueryExecutor openConnection([String? name]) {
  return LazyDatabase(() async {
    final dbName = (name != null && name.isNotEmpty) ? name : 'theaver_db';
    final result = await WasmDatabase.open(
      databaseName: dbName,
      sqlite3Uri: Uri.parse('sqlite3.wasm'),
      driftWorkerUri: Uri.parse('drift_worker.js'),
    );
    return result.resolvedExecutor;
  });
}

Future<void> deleteDatabaseFile(String name) async {
  // Web does not delete files directly
}

Future<void> deleteAllDatabaseFiles() async {
  // Web does not delete files directly
}

