import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../models/inspection_record.dart';

class DatabaseService {
  static Database? _db;

  static Future<Database> get _database async {
    _db ??= await openDatabase(
      p.join(await getDatabasesPath(), 'agrodetect.db'),
      version: 2,
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 2) {
          await db.execute('ALTER TABLE inspections ADD COLUMN video_path TEXT');
          await db.execute('ALTER TABLE inspections ADD COLUMN duration_s INTEGER');
        }
      },
      onCreate: (db, v) => db.execute(
        'CREATE TABLE inspections('
        'id INTEGER PRIMARY KEY AUTOINCREMENT,'
        'image_path TEXT NOT NULL,'
        'created_at TEXT NOT NULL,'
        'model_name TEXT NOT NULL,'
        'counts TEXT NOT NULL,'
        'latitude REAL,'
        'longitude REAL,'
        'video_path TEXT,'
        'duration_s INTEGER)',
      ),
    );
    return _db!;
  }

  static Future<int> insert(InspectionRecord r) async =>
      (await _database).insert('inspections', r.toMap());

  static Future<List<InspectionRecord>> all() async {
    final rows = await (await _database)
        .query('inspections', orderBy: 'created_at DESC');
    return rows.map(InspectionRecord.fromMap).toList();
  }

  static Future<void> delete(InspectionRecord r) async {
    await (await _database)
        .delete('inspections', where: 'id = ?', whereArgs: [r.id]);
    try {
      final f = File(r.imagePath);
      if (await f.exists()) await f.delete();
      if (r.videoPath != null) {
        final v = File(r.videoPath!);
        if (await v.exists()) await v.delete();
      }
    } catch (_) {}
  }
}
