import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

QueryExecutor openConnection([String? name]) {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final fileName = (name != null && name.isNotEmpty)
        ? (name.endsWith('.db') ? name : '$name.db')
        : 'miptgram.db';
    final file = File(p.join(dbFolder.path, fileName));
    return NativeDatabase.createInBackground(file);
  });
}

Future<void> deleteDatabaseFile(String name) async {
  try {
    final dbFolder = await getApplicationDocumentsDirectory();
    final baseName = name.endsWith('.db') ? name.substring(0, name.length - 3) : name;
    for (final ext in ['.db', '.db-wal', '.db-shm']) {
      final file = File(p.join(dbFolder.path, '$baseName$ext'));
      if (await file.exists()) {
        await file.delete();
      }
    }
  } catch (_) {}
}

Future<void> deleteAllDatabaseFiles() async {
  try {
    final dbFolder = await getApplicationDocumentsDirectory();
    if (await dbFolder.exists()) {
      final entities = dbFolder.listSync();
      for (final entity in entities) {
        if (entity is File) {
          final filename = p.basename(entity.path);
          if (filename.startsWith('miptgram') &&
              (filename.endsWith('.db') ||
                  filename.endsWith('.db-wal') ||
                  filename.endsWith('.db-shm'))) {
            try {
              entity.deleteSync();
            } catch (_) {}
          }
        }
      }
    }
  } catch (_) {}
}

