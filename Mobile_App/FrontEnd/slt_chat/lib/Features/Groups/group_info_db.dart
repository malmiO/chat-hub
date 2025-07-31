import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class GroupInfoDB {
  static Database? _db;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  static Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'group_info.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE group_details (
            group_id TEXT PRIMARY KEY,
            name TEXT,
            description TEXT,
            profile_pic TEXT,
            created_at TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE group_members (
            id TEXT PRIMARY KEY,
            group_id TEXT,
            name TEXT,
            profile_pic TEXT,
            is_admin INTEGER
          )
        ''');
      },
    );
  }

  static Future<void> saveGroupDetails(Map<String, dynamic> group) async {
    final db = await database;
    await db.insert('group_details', {
      'group_id': group['id'],
      'name': group['name'],
      'description': group['description'],
      'profile_pic': group['profile_pic'],
      'created_at': group['created_at'],
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<Map<String, dynamic>?> getGroupDetails(String groupId) async {
    final db = await database;
    final result = await db.query('group_details', where: 'group_id = ?', whereArgs: [groupId]);
    return result.isNotEmpty ? result.first : null;
  }

  static Future<void> saveGroupMembers(String groupId, List<Map<String, dynamic>> members) async {
    final db = await database;
    await db.delete('group_members', where: 'group_id = ?', whereArgs: [groupId]);

    for (var member in members) {
      await db.insert('group_members', {
        'id': member['id'],
        'group_id': groupId,
        'name': member['name'],
        'profile_pic': member['profile_pic'],
        'is_admin': member['isAdmin'] ? 1 : 0,
      });
    }
  }

  static Future<List<Map<String, dynamic>>> getGroupMembers(String groupId) async {
    final db = await database;
    return await db.query('group_members', where: 'group_id = ?', whereArgs: [groupId]);
  }

  static Future<void> deleteGroup(String groupId) async {
    final db = await database;
    await db.delete('group_details', where: 'group_id = ?', whereArgs: [groupId]);
    await db.delete('group_members', where: 'group_id = ?', whereArgs: [groupId]);
  }
}
