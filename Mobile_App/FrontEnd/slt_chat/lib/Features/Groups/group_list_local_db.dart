import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class GroupListLocalDB {
  static const _dbName = 'group_list.db';
  static const _dbVersion = 1;
  static const _tableName = 'groups';

  // Column names
  static const groupId = 'group_id';
  static const name = 'name';
  static const profilePic = 'profile_pic';
  static const memberCount = 'member_count';
  static const lastMessage = 'last_message';
  static const lastMessageTime = 'last_message_time';
  static const unreadCount = 'unread_count';

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final path = join(await getDatabasesPath(), _dbName);
    return openDatabase(path, version: _dbVersion, onCreate: _onCreate);
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_tableName (
        $groupId TEXT PRIMARY KEY,
        $name TEXT NOT NULL,
        $profilePic TEXT,
        $memberCount INTEGER NOT NULL,
        $lastMessage TEXT,
        $lastMessageTime TEXT,
        $unreadCount INTEGER NOT NULL
      )
    ''');
  }

  // Insert/update groups
  Future<void> upsertGroups(List<Map<String, dynamic>> groups) async {
    final db = await database;
    final batch = db.batch();

    for (final group in groups) {
      batch.insert(
        _tableName,
        _convertToDBFormat(group),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit();
  }

  // Fetch all groups from local DB
  Future<List<Map<String, dynamic>>> getGroups() async {
    final db = await database;
    final List<Map<String, dynamic>> dbGroups = await db.query(_tableName);
    return dbGroups.map(_convertFromDBFormat).toList();
  }

  // Convert server format to DB format
  Map<String, dynamic> _convertToDBFormat(Map<String, dynamic> group) {
    return {
      groupId: group['group_id'],
      name: group['name'],
      profilePic: group['profile_pic'],
      memberCount: (group['members'] as List).length,
      lastMessage: group['last_message'],
      lastMessageTime: group['last_message_time'],
      unreadCount: group['unread_count'],
    };
  }

  // Convert DB format to app format
  Map<String, dynamic> _convertFromDBFormat(Map<String, dynamic> dbGroup) {
    return {
      'group_id': dbGroup[groupId],
      'name': dbGroup[name],
      'profile_pic': dbGroup[profilePic],
      'member_count': dbGroup[memberCount],
      'last_message': dbGroup[lastMessage],
      'last_message_time': dbGroup[lastMessageTime],
      'unread_count': dbGroup[unreadCount],
    };
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}
