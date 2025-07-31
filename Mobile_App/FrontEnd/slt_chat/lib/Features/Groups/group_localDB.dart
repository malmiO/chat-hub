import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';

class LocalDatabase {
  Database? _database;

  Future<void> initDatabase() async {
    String path = join(await getDatabasesPath(), 'group_chat.db');
    _database = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            messageId TEXT,
            tempId TEXT UNIQUE,
            groupId TEXT,
            senderId TEXT,
            type TEXT,
            content TEXT,
            filePath TEXT,
            mediaUrl TEXT,
            status TEXT,
            timestamp TEXT,
            readBy TEXT
          )
        ''');
      },
    );
  }

  Future<void> close() async {
    await _database?.close();
  }

  Future<void> insertMediaMessage({
    required String filePath,
    required String content,
    required String type,
    required int isMe,
    required String status,
    required String createdAt,
    required String tempId,
    required String groupId,
  }) async {
    await _database?.insert('messages', {
      'tempId': tempId,
      'groupId': groupId,
      'senderId': isMe == 1 ? 'me' : 'other', // Simplified for this example
      'type': type,
      'content': content,
      'filePath': filePath.isNotEmpty ? filePath : null,
      'status': status,
      'timestamp': createdAt,
      'readBy': json.encode(['me']),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateMessageStatus({
    required String tempId,
    required String status,
    String? content,
  }) async {
    await _database?.update(
      'messages',
      {
        'status': status,
        if (content != null) 'mediaUrl': content,
        if (status == 'success')
          'messageId': tempId, // Update with server ID if available
      },
      where: 'tempId = ?',
      whereArgs: [tempId],
    );
  }

  Future<void> updateMessageByGroup({
    required String tempId,
    required String groupId,
    required Map<String, dynamic> values,
  }) async {
    await _database?.update(
      'messages',
      values,
      where: 'tempId = ? AND groupId = ?',
      whereArgs: [tempId, groupId],
    );
  }

  Future<List<Map<String, dynamic>>> getMessages(String groupId) async {
    return await _database?.query(
          'messages',
          where: 'groupId = ?',
          whereArgs: [groupId],
        ) ??
        [];
  }

  Future<List<Map<String, dynamic>>> getPendingMessages() async {
    return await _database?.query(
          'messages',
          where: 'status IN (?, ?, ?)',
          whereArgs: ['pending', 'uploading', 'failed'],
        ) ??
        [];
  }

  Future<void> saveMessages(
    List<Map<String, dynamic>> messages,
    String groupId,
  ) async {
    final batch = _database?.batch();
    batch?.delete('messages', where: 'groupId = ?', whereArgs: [groupId]);

    for (var msg in messages) {
      batch?.insert('messages', {
        'messageId': msg['_id'],
        'tempId': msg['tempId'],
        'groupId': msg['group_id'],
        'senderId': msg['sender_id'],
        'type': msg['type'],
        'content': msg['type'] == 'text' ? msg['message'] : null,
        'filePath':
            msg['type'] != 'text' &&
                    (msg['status'] == 'uploading' || msg['status'] == 'pending')
                ? (msg['image_url'] ??
                    msg['voice_url'] ??
                    msg['video_url'] ??
                    msg['pdf_url'])
                : null,
        'mediaUrl':
            msg['type'] != 'text' && msg['status'] == 'success'
                ? (msg['image_url'] ??
                    msg['voice_url'] ??
                    msg['video_url'] ??
                    msg['pdf_url'])
                : null,
        'status': msg['status'],
        'timestamp': msg['timestamp'],
        'readBy': json.encode(msg['read_by']),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    await batch?.commit();
  }
}
