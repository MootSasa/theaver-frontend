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
    final fileName = name.endsWith('.db') ? name : '$name.db';
    final file = File(p.join(dbFolder.path, fileName));
    if (await file.exists()) {
      await file.delete();
    }
  } catch (_) {}
}
