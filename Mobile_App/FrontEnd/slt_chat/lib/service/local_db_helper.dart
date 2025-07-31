import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:async';

class LocalDBHelper {
  static final LocalDBHelper _instance = LocalDBHelper._internal();
  static Database? _database;

  factory LocalDBHelper() => _instance;

  LocalDBHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    final path = await getDatabasesPath();
    final dbPath = join(path, 'chat_app.db');

    return await openDatabase(
      dbPath,
      version: 9, // Increment version
      onCreate: (db, version) async {
        await db.execute('''
        CREATE TABLE chats (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          chat_id TEXT,
          partner_id TEXT,
          name TEXT,
          profile_pic TEXT,
          last_message TEXT,
          last_message_time TEXT,
          unread_count INTEGER,
          is_online INTEGER,
          last_seen TEXT
        )
      ''');

        await db.execute('''
        CREATE TABLE messages (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          message_id TEXT,
          temp_id TEXT,
          chat_id TEXT,
          sender_id TEXT,
          receiver_id TEXT,
          content TEXT,
          is_image INTEGER,
          image_id TEXT,
          is_pdf INTEGER,
          pdf_id TEXT,
          filename TEXT,
          voice_url TEXT, 
          is_voice INTEGER, 
          is_video INTEGER DEFAULT 0,
          video_id TEXT,
          local_video_path TEXT,
          local_pdf_path TEXT,
          timestamp TEXT,
          is_sent INTEGER DEFAULT 0,
          is_delivered INTEGER DEFAULT 0,
          is_read INTEGER DEFAULT 0,
          is_me INTEGER,
          status TEXT
        )
      ''');

        // Add indexes
        await db.execute('''
        CREATE UNIQUE INDEX idx_messages_unique_id 
        ON messages(message_id, temp_id)
      ''');
        await db.execute('''
        CREATE INDEX idx_messages_chat 
        ON messages(chat_id)
      ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
          CREATE UNIQUE INDEX idx_messages_unique_id 
          ON messages(message_id, temp_id)
        ''');
          await db.execute('''
          CREATE INDEX idx_messages_chat 
          ON messages(chat_id)
        ''');
        }

        if (oldVersion < 3) {
          await db.execute('ALTER TABLE messages ADD voice_url TEXT');
          await db.execute(
            'ALTER TABLE messages ADD is_voice INTEGER DEFAULT 0',
          );
          await db.execute('ALTER TABLE messages ADD status TEXT');
        }

        if (oldVersion < 4) {
          await db.execute('''
          CREATE TABLE IF NOT EXISTS connections (
            id TEXT PRIMARY KEY,
            name TEXT,
            email TEXT,
            profile_pic TEXT
          )
        ''');
        }

        if (oldVersion < 5) {
          // Ensure connections table exists
          await db.execute('''
          CREATE TABLE IF NOT EXISTS connections (
            id TEXT PRIMARY KEY,
            name TEXT,
            email TEXT,
            profile_pic TEXT
          )
        ''');
        }

        if (oldVersion < 6) {
          await db.execute('ALTER TABLE messages ADD is_pdf INTEGER DEFAULT 0');
          await db.execute('ALTER TABLE messages ADD pdf_id TEXT');
          await db.execute('ALTER TABLE messages ADD filename TEXT');
        }

        if (oldVersion < 7) {
          await db.execute(
            'ALTER TABLE messages ADD is_video INTEGER DEFAULT 0',
          );
          await db.execute('ALTER TABLE messages ADD video_id TEXT');
        }

        if (oldVersion < 8) {
          await db.execute('ALTER TABLE messages ADD local_video_path TEXT');
        }

        if (oldVersion < 9) {
          await db.execute('ALTER TABLE messages ADD local_pdf_path TEXT');
        }
      },
    );
  }

  // Chat methods
  Future<void> saveChats(List<Map<String, dynamic>> chats) async {
    final db = await database;
    await db.delete('chats'); // Clear existing chats

    for (var chat in chats) {
      await db.insert('chats', {
        'chat_id': chat['chat_id'],
        'partner_id': chat['partner_id'],
        'name': chat['name'],
        'profile_pic': chat['profile_pic'],
        'last_message': chat['last_message'],
        'last_message_time': chat['last_message_time'],
        'unread_count': chat['unread_count'],
        'is_online': 0, // Default offline
        'last_seen': DateTime.now().toIso8601String(),
      });
    }
  }

  Future<List<Map<String, dynamic>>> getChats() async {
    final db = await database;
    return await db.query('chats', orderBy: 'last_message_time DESC');
  }

  Future<void> deleteChat(String chatId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('chats', where: 'chat_id = ?', whereArgs: [chatId]);
      await txn.delete('messages', where: 'chat_id = ?', whereArgs: [chatId]);
    });
  }

  Future<void> updateOnlineStatus(String userId, bool isOnline) async {
    final db = await database;
    await db.update(
      'chats',
      {
        'is_online': isOnline ? 1 : 0,
        'last_seen': DateTime.now().toIso8601String(),
      },
      where: 'partner_id = ?',
      whereArgs: [userId],
    );
  }

  Future<bool> hasData() async {
    final db = await database;
    final result = await db.query('chats', limit: 1);
    return result.isNotEmpty;
  }

  // Add to LocalDBHelper class
  Future<List<Map<String, dynamic>>> getConnections() async {
    final db = await database;
    return await db.query('connections');
  }

  Future<void> saveConnections(List<Map<String, dynamic>> connections) async {
    final db = await database;
    final batch = db.batch();

    // Clear existing connections
    await db.delete('connections');

    // Insert new connections
    for (var conn in connections) {
      batch.insert('connections', {
        'id': conn['id'],
        'name': conn['name'],
        'email': conn['email'] ?? '',
        'profile_pic': conn['profile_pic'] ?? 'default.jpg',
      });
    }

    await batch.commit();
  }

  Future<void> createMessagesTable() async {
    final db = await database;
    await db.execute('''
    CREATE TABLE IF NOT EXISTS messages (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      message_id TEXT,
      temp_id TEXT,
      chat_id TEXT,
      sender_id TEXT,
      receiver_id TEXT,
      content TEXT,
      is_image INTEGER,
      image_id TEXT,
      timestamp TEXT,
      is_sent INTEGER DEFAULT 0,
      is_delivered INTEGER DEFAULT 0,
      is_read INTEGER DEFAULT 0,
      is_me INTEGER
    )
  ''');
  }

  Future<void> saveMessage(Map<String, dynamic> message) async {
    final db = await database;

    await createMessagesTable();

    final existing = await db.query(
      'messages',
      where:
          '(message_id = ? AND message_id != "") OR (temp_id = ? AND temp_id != "")',
      whereArgs: [message['id'] ?? '', message['temp_id'] ?? ''],
      limit: 1,
    );

    if (existing.isEmpty) {
      await db.insert('messages', {
        'message_id': message['id'] ?? '',
        'temp_id': message['temp_id'] ?? '',
        'chat_id': '${message['sender_id']}_${message['receiver_id']}',
        'sender_id': message['sender_id'],
        'receiver_id': message['receiver_id'],
        'content': message['message'] ?? '',
        'is_image': message['is_image'] ?? false ? 1 : 0,
        'image_id': message['image_id'] ?? '',
        'is_pdf': message['is_pdf'] ?? false ? 1 : 0,
        'pdf_id': message['pdf_id'] ?? '',
        'filename': message['filename'] ?? '',
        'voice_url': message['voice_url'] ?? '',
        'is_voice': message['is_voice'] ?? false ? 1 : 0,
        'is_video': message['is_video'] ?? false ? 1 : 0,
        'video_id': message['video_id'] ?? '',
        'local_video_path': message['local_video_path'] ?? '',
        'local_pdf_path': message['local_pdf_path'] ?? '',
        'timestamp': message['timestamp'],
        'is_sent': message['sent'] ?? false ? 1 : 0,
        'is_delivered': message['delivered'] ?? false ? 1 : 0,
        'is_read': message['read'] ?? false ? 1 : 0,
        'is_me': message['isMe'] ?? false ? 1 : 0,
        'status': message['status'] ?? 'success',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<List<Map<String, dynamic>>> getMessagesForChat(
    String userId,
    String receiverId,
  ) async {
    final db = await database;
    final chatId1 = '${userId}_$receiverId';
    final chatId2 = '${receiverId}_$userId';

    // Simplified query without window functions
    final messages = await db.query(
      'messages',
      where: 'chat_id = ? OR chat_id = ?',
      whereArgs: [chatId1, chatId2],
      orderBy: 'timestamp DESC',
    );

    // Manual deduplication
    final uniqueMessages = <String, Map<String, dynamic>>{};
    for (var msg in messages) {
      final key =
          msg['message_id']?.toString() ?? msg['temp_id']?.toString() ?? '';
      if (!uniqueMessages.containsKey(key)) {
        uniqueMessages[key] = msg;
      }
    }

    return uniqueMessages.values.map((msg) {
      return {
        'id': msg['message_id'],
        'temp_id': msg['temp_id'],
        'sender_id': msg['sender_id'],
        'receiver_id': msg['receiver_id'],
        'message': msg['content'],
        'is_image': msg['is_image'] == 1,
        'image_id': msg['image_id'],
        'is_pdf': msg['is_pdf'] == 1,
        'pdf_id': msg['pdf_id'],
        'filename': msg['filename'],
        'voice_url': msg['voice_url'],
        'is_voice': msg['is_voice'] == 1,
        'is_video': msg['is_video'] == 1,
        'video_id': msg['video_id'],
        'local_video_path': msg['local_video_path'],
        'local_pdf_path': msg['local_pdf_path'],
        'timestamp': msg['timestamp'],
        'isMe': msg['is_me'] == 1,
        'read': msg['is_read'] == 1,
        'delivered': msg['is_delivered'] == 1,
        'sent': msg['is_sent'] == 1,
        'status': msg['status'] ?? 'success',
      };
    }).toList();
  }

  // Add method to update local video path
  Future<void> updateLocalVideoPath(String tempId, String localPath) async {
    final db = await database;
    await db.update(
      'messages',
      {'local_video_path': localPath},
      where: 'temp_id = ?',
      whereArgs: [tempId],
    );
  }

  Future<void> updateLocalPdfPath(String tempId, String localPath) async {
    final db = await database;
    await db.update(
      'messages',
      {'local_pdf_path': localPath},
      where: 'temp_id = ?',
      whereArgs: [tempId],
    );
  }

  Future<void> updateMessageStatus(
    String tempId, {
    String? messageId,
    bool? isSent,
    bool? isDelivered,
    bool? isRead,
    String? status,
  }) async {
    final db = await database;
    final updates = <String, dynamic>{};

    if (messageId != null) updates['message_id'] = messageId;
    if (isSent != null) updates['is_sent'] = isSent ? 1 : 0;
    if (isDelivered != null) updates['is_delivered'] = isDelivered ? 1 : 0;
    if (isRead != null) updates['is_read'] = isRead ? 1 : 0;
    if (status != null) updates['status'] = status;

    await db.update(
      'messages',
      updates,
      where: 'temp_id = ?',
      whereArgs: [tempId],
    );
  }

  Future<List<Map<String, dynamic>>> getPendingMessages(String userId) async {
    final db = await database;
    final messages = await db.query(
      'messages',
      where: 'sender_id = ? AND is_sent = 0',
      whereArgs: [userId],
    );

    return messages.map((msg) {
      return {
        'temp_id': msg['temp_id'],
        'sender_id': msg['sender_id'],
        'receiver_id': msg['receiver_id'],
        'message': msg['content'],
        'is_image': msg['is_image'] == 1,
        'image_id': msg['image_id'],
        'is_pdf': msg['is_pdf'] == 1,
        'pdf_id': msg['pdf_id'],
        'filename': msg['filename'],
        'voice_url': msg['voice_url'],
        'is_voice': msg['is_voice'] == 1,
        'is_video': msg['is_video'] == 1,
        'video_id': msg['video_id'],
        'local_video_path': msg['local_video_path'],
        'local_pdf_path': msg['local_pdf_path'],
        'timestamp': msg['timestamp'],
        'status': msg['status'] ?? 'success',
      };
    }).toList();
  }

  Future<void> deleteMessage(String tempId) async {
    final db = await database;
    await db.delete('messages', where: 'temp_id = ?', whereArgs: [tempId]);
  }

  Future<void> syncMessagesWithServer({
    required List<Map<String, dynamic>> serverMessages,
    required String currentUserId,
  }) async {
    final db = await database;
    final batch = db.batch();

    for (var serverMsg in serverMessages) {
      // Normalize server message
      final normalizedMsg = {
        ...serverMsg,
        'id': serverMsg['id']?.toString() ?? '',
        'temp_id': serverMsg['temp_id']?.toString() ?? '',
        'message': serverMsg['message'] ?? '',
        'voice_url': serverMsg['voice_url'] ?? '',
        'is_image': serverMsg['is_image'] ?? false,
        'is_pdf': serverMsg['is_pdf'] ?? false,
        'pdf_id': serverMsg['pdf_id'] ?? '',
        'filename': serverMsg['filename'] ?? '',
        'is_voice': serverMsg['is_voice'] ?? false,
        'is_video': serverMsg['is_video'] ?? false,
        'video_id': serverMsg['video_id'] ?? '',
        'local_video_path': serverMsg['local_video_path'] ?? '',
        'local_pdf_path': serverMsg['local_pdf_path'] ?? '',
        'delivered': serverMsg['delivered'] ?? false,
        'read': serverMsg['read'] ?? false,
        'timestamp': serverMsg['timestamp'] ?? DateTime.now().toIso8601String(),
        'status': serverMsg['status'] ?? 'success',
      };

      // Try to find by server ID or temp ID
      final existing = await db.query(
        'messages',
        where:
            '(message_id = ? AND message_id != "") OR (temp_id = ? AND temp_id != "")',
        whereArgs: [normalizedMsg['id'], normalizedMsg['temp_id']],
        limit: 1,
      );

      if (existing.isEmpty) {
        // Insert new message
        batch.insert('messages', {
          'message_id': normalizedMsg['id'],
          'temp_id': normalizedMsg['temp_id'],
          'chat_id':
              '${normalizedMsg['sender_id']}_${normalizedMsg['receiver_id']}',
          'sender_id': normalizedMsg['sender_id'],
          'receiver_id': normalizedMsg['receiver_id'],
          'content': normalizedMsg['message'],
          'is_image': normalizedMsg['is_image'] ? 1 : 0,
          'image_id': normalizedMsg['image_id'] ?? '',
          'is_pdf': normalizedMsg['is_pdf'] ? 1 : 0,
          'pdf_id': normalizedMsg['pdf_id'],
          'filename': normalizedMsg['filename'],
          'voice_url': normalizedMsg['voice_url'],
          'is_voice': normalizedMsg['is_voice'] ? 1 : 0,
          'is_video': normalizedMsg['is_video'] ? 1 : 0,
          'video_id': normalizedMsg['video_id'],
          'local_video_path': normalizedMsg['local_video_path'],
          'local_pdf_path': normalizedMsg['local_pdf_path'],
          'timestamp': normalizedMsg['timestamp'],
          'is_sent': 1,
          'is_delivered': normalizedMsg['delivered'] ? 1 : 0,
          'is_read': normalizedMsg['read'] ? 1 : 0,
          'is_me': normalizedMsg['sender_id'] == currentUserId ? 1 : 0,
          'status': normalizedMsg['status'],
        });
      } else {
        // Update existing message
        batch.update(
          'messages',
          {
            'message_id': normalizedMsg['id'],
            'content': normalizedMsg['message'],
            'is_image': normalizedMsg['is_image'] ? 1 : 0,
            'image_id': normalizedMsg['image_id'] ?? existing[0]['image_id'],
            'is_pdf': normalizedMsg['is_pdf'] ? 1 : 0,
            'pdf_id': normalizedMsg['pdf_id'] ?? existing[0]['pdf_id'],
            'filename': normalizedMsg['filename'] ?? existing[0]['filename'],
            'voice_url': normalizedMsg['voice_url'] ?? existing[0]['voice_url'],
            'is_voice': normalizedMsg['is_voice'] ? 1 : 0,
            'is_video': normalizedMsg['is_video'] ? 1 : 0,
            'video_id': normalizedMsg['video_id'] ?? existing[0]['video_id'],
            'local_video_path':
                normalizedMsg['local_video_path'] ??
                existing[0]['local_video_path'],
            'local_pdf_path':
                normalizedMsg['local_pdf_path'] ??
                existing[0]['local_pdf_path'],
            'is_sent': 1,
            'is_delivered': normalizedMsg['delivered'] ? 1 : 0,
            'is_read': normalizedMsg['read'] ? 1 : 0,
            'timestamp': normalizedMsg['timestamp'],
            'status': normalizedMsg['status'],
          },
          where: 'id = ?',
          whereArgs: [existing[0]['id']],
        );
      }
    }

    await batch.commit();
  }

  // In LocalDBHelper
  Future<void> resolveConflicts(
    List<Map<String, dynamic>> serverMessages,
  ) async {
    final db = await database;

    // Get all temp IDs from server messages that might match local temp IDs
    final serverTempIds =
        serverMessages
            .where((m) => m['temp_id'] != null)
            .map((m) => m['temp_id'])
            .toList();

    if (serverTempIds.isNotEmpty) {
      // Find local messages with matching temp IDs
      final placeholders = List.filled(serverTempIds.length, '?').join(',');
      final localMatches = await db.query(
        'messages',
        where: 'temp_id IN ($placeholders)',
        whereArgs: serverTempIds,
      );

      final batch = db.batch();

      // Update local messages with server IDs
      for (var localMsg in localMatches) {
        final serverMsg = serverMessages.firstWhere(
          (m) => m['temp_id'] == localMsg['temp_id'],
          orElse: () => {},
        );

        if (serverMsg.isNotEmpty) {
          batch.update(
            'messages',
            {
              'message_id': serverMsg['id'],
              'is_sent': 1,
              'is_delivered': serverMsg['delivered'] ? 1 : 0,
              'is_read': serverMsg['read'] ? 1 : 0,
            },
            where: 'id = ?',
            whereArgs: [localMsg['id']],
          );
        }
      }

      await batch.commit();
    }
  }

  Future<void> _createAIMessagesTable(Database db) async {
    await db.execute('''
    CREATE TABLE IF NOT EXISTS ai_messages (
      id TEXT PRIMARY KEY,
      role TEXT, -- 'user' or 'ai'
      text TEXT,
      timestamp TEXT,
      status TEXT, -- 'pending', 'sent', 'delivered', 'failed', 'offline'
      related_message_id TEXT, -- for linking responses to questions
      is_cached_response INTEGER DEFAULT 0 -- for pre-cached responses
    )
  ''');

    // Add index for faster lookups
    await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_ai_messages_timestamp 
    ON ai_messages(timestamp)
  ''');

    await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_ai_messages_status 
    ON ai_messages(status)
  ''');
  }

  // Save an AI message
  Future<void> saveAIMessage(Map<String, dynamic> message) async {
    final db = await database;
    await _createAIMessagesTable(db);

    await db.insert('ai_messages', {
      'id': message['id'],
      'role': message['role'],
      'text': message['text'],
      'timestamp': message['timestamp'],
      'status': message['status'] ?? 'sent',
      'related_message_id': message['related_message_id'],
      'is_cached_response': message['is_cached_response'] ?? 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // Update message status
  Future<void> updateAIMessageStatus(String messageId, String status) async {
    final db = await database;
    await db.update(
      'ai_messages',
      {'status': status},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  // Get cached AI responses
  Future<List<Map<String, String>>> getCachedAIMessages() async {
    final db = await database;
    final results = await db.query('ai_messages', orderBy: 'timestamp ASC');

    return results.map((row) {
      return {
        'id': row['id'] as String,
        'role': row['role'] as String,
        'text': row['text'] as String,
        'status': row['status'] as String,
        'timestamp': row['timestamp'] as String? ?? '',
      };
    }).toList();
  }

  // Get pending messages
  Future<List<Map<String, String>>> getPendingAIMessages() async {
    final db = await database;
    final results = await db.query(
      'ai_messages',
      where: 'status = ? AND role = ?',
      whereArgs: ['pending', 'user'],
      orderBy: 'timestamp ASC',
    );

    return results.map((row) {
      return {
        'id': row['id'] as String,
        'role': row['role'] as String,
        'text': row['text'] as String,
      };
    }).toList();
  }

  // Pre-cache common responses
  Future<void> cacheCommonResponses() async {
    final commonResponses = [
      {
        'id': 'cache_1',
        'role': 'ai',
        'text': 'Hello! How can I assist you today?',
        'timestamp': DateTime.now().toIso8601String(),
        'status': 'delivered',
        'is_cached_response': 1,
      },
      {
        'id': 'cache_2',
        'role': 'ai',
        'text': 'I can help with general questions when you\'re offline.',
        'timestamp': DateTime.now().toIso8601String(),
        'status': 'delivered',
        'is_cached_response': 1,
      },
      // Add more common responses as needed
    ];

    for (var response in commonResponses) {
      await saveAIMessage(response);
    }
  }

  Future<String?> getOfflineResponse(String userMessage) async {
    final db = await database;
    final lowercaseMessage = userMessage.toLowerCase();

    if (lowercaseMessage.contains('hello') || lowercaseMessage.contains('hi')) {
      final response = await db.query(
        'ai_messages',
        where: 'id = ?',
        whereArgs: ['cache_1'],
      );

      if (response.isNotEmpty) {
        return response.first['text'] as String;
      }
    }
    return null;
  }

  // Add to your LocalDBHelper
  Future<void> markMessagesAsRead(String senderId, String receiverId) async {
    final db = await database;
    await db.update(
      'messages',
      {'is_read': 1, 'read_at': DateTime.now().toIso8601String()},
      where: 'sender_id = ? AND receiver_id = ? AND is_read = 0',
      whereArgs: [senderId, receiverId],
    );
  }

  Future<void> updateVoiceMessageStatus(
    String tempId,
    String status, {
    String? voiceUrl,
  }) async {
    final db = await database;
    await db.update(
      'messages',
      {'status': status, if (voiceUrl != null) 'voice_url': voiceUrl},
      where: 'temp_id = ?',
      whereArgs: [tempId],
    );
  }

  Future<void> cleanupUnusedPdfs() async {
    final db = await database;
    final messages = await db.query('messages', columns: ['local_pdf_path']);
    final validPaths =
        messages
            .where((msg) => msg['local_pdf_path'] != null)
            .map((msg) => msg['local_pdf_path'] as String)
            .toSet();

    final appDir = await getApplicationDocumentsDirectory();
    final pdfDir = Directory('${appDir.path}/pdfs');
    if (await pdfDir.exists()) {
      await for (var file in pdfDir.list(recursive: false)) {
        if (file is File && !validPaths.contains(file.path)) {
          await file.delete();
        }
      }
    }
  }
}
