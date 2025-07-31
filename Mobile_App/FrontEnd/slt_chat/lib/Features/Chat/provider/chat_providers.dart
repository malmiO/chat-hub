import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slt_chat/service/local_db_helper.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:http/io_client.dart';
import 'package:slt_chat/config/config.dart';

final chatRepositoryProvider = Provider((ref) => ChatRepository());

final chatSocketProvider = Provider<IO.Socket>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  final socket = IO.io(AppConfig.baseUrl, <String, dynamic>{
    'transports': ['websocket'],
    'autoConnect': true,
    'secure': true,
    'rejectUnauthorized': false,
    'reconnection': true,
    'reconnectionAttempts': 10,
    'reconnectionDelay': 1000,
    'reconnectionDelayMax': 10000,
    'query': {'user_id': userId},
  });
  ref.onDispose(() {
    socket.disconnect();
    socket.close();
  });
  return socket;
});

final currentUserIdProvider = StateProvider<String>((ref) => '');

final chatStateNotifierProvider =
    StateNotifierProvider<ChatNotifier, ChatState>((ref) {
      final repository = ref.watch(chatRepositoryProvider);
      final socket = ref.watch(chatSocketProvider);
      return ChatNotifier(repository, socket);
    });

class ChatRepository {
  final LocalDBHelper _localDB = LocalDBHelper();

  Future<List<Map<String, dynamic>>> getMessages(
    String userId,
    String receiverId,
  ) async {
    return await _localDB.getMessagesForChat(userId, receiverId);
  }

  Future<void> saveMessage(Map<String, dynamic> message) async {
    await _localDB.saveMessage(message);
  }

  Future<void> updateMessageStatus(
    String tempId, {
    String? messageId,
    bool? isSent,
    bool? isDelivered,
    bool? isRead,
  }) async {
    await _localDB.updateMessageStatus(
      tempId,
      messageId: messageId,
      isSent: isSent,
      isDelivered: isDelivered,
      isRead: isRead,
    );
  }

  Future<List<Map<String, dynamic>>> getPendingMessages(String userId) async {
    return await _localDB.getPendingMessages(userId);
  }
}

class ChatState {
  final List<Map<String, dynamic>> messages;
  final bool isLoading;
  final bool isTyping;
  final bool isOnline;
  final bool isConnected;
  final String lastSeen;
  final bool isUploading;
  final int uploadProgress;

  ChatState({
    this.messages = const [],
    this.isLoading = true,
    this.isTyping = false,
    this.isOnline = false,
    this.isConnected = false,
    this.lastSeen = '',
    this.isUploading = false,
    this.uploadProgress = 0,
  });

  ChatState copyWith({
    List<Map<String, dynamic>>? messages,
    bool? isLoading,
    bool? isTyping,
    bool? isOnline,
    bool? isConnected,
    String? lastSeen,
    bool? isUploading,
    int? uploadProgress,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      isTyping: isTyping ?? this.isTyping,
      isOnline: isOnline ?? this.isOnline,
      isConnected: isConnected ?? this.isConnected,
      lastSeen: lastSeen ?? this.lastSeen,
      isUploading: isUploading ?? this.isUploading,
      uploadProgress: uploadProgress ?? this.uploadProgress,
    );
  }
}

class ChatNotifier extends StateNotifier<ChatState> {
  final ChatRepository _repository;
  final IO.Socket _socket;
  Timer? _typingTimer;
  Timer? _statusTimer;
  IOClient? _secureClient;

  ChatNotifier(this._repository, this._socket) : super(ChatState()) {
    _initializeSocket();
  }

  void _initializeSocket() {
    _socket.onConnect((_) {
      state = state.copyWith(isConnected: true);
    });

    _socket.onDisconnect((_) {
      state = state.copyWith(isConnected: false);
    });

    _socket.on('message_sent', (data) {
      state = state.copyWith(
        messages:
            state.messages.map((msg) {
              if (msg['temp_id'] == data['temp_id']) {
                return {...msg, 'id': data['message_id'], 'sent': true};
              }
              return msg;
            }).toList(),
      );
      _repository.updateMessageStatus(
        data['temp_id'],
        messageId: data['message_id'],
        isSent: true,
      );
    });

    _socket.on('message_delivered', (data) {
      state = state.copyWith(
        messages:
            state.messages.map((msg) {
              if (msg['id'] == data['message_id']) {
                return {...msg, 'delivered': true};
              }
              return msg;
            }).toList(),
      );
      _repository.updateMessageStatus(data['temp_id'], isDelivered: true);
    });

    _socket.on('message_read', (data) {
      state = state.copyWith(
        messages:
            state.messages.map((msg) {
              if (msg['id'] == data['message_id']) {
                return {...msg, 'read': true};
              }
              return msg;
            }).toList(),
      );
      _repository.updateMessageStatus(data['temp_id'], isRead: true);
    });

    _socket.on('message_received', (data) {
      state = state.copyWith(
        messages: [
          {
            'sender_id': data['sender_id'],
            'receiver_id': data['receiver_id'],
            'message': data['message'],
            'id': data['message_id'],
            'isMe': false,
            'timestamp': data['timestamp'],
            'read': false,
            'sent': true,
            'delivered': true,
          },
          ...state.messages,
        ],
      );
    });

    _socket.on('typing', (data) {
      state = state.copyWith(isTyping: data['is_typing']);
      if (data['is_typing']) {
        _typingTimer?.cancel();
        _typingTimer = Timer(Duration(seconds: 3), () {
          state = state.copyWith(isTyping: false);
        });
      }
    });
  }

  Future<void> loadMessages(String userId, String receiverId) async {
    state = state.copyWith(isLoading: true);
    try {
      final localMessages = await _repository.getMessages(userId, receiverId);
      state = state.copyWith(messages: localMessages, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> sendMessage({
    required String userId,
    required String receiverId,
    required String message,
  }) async {
    if (message.trim().isEmpty) return;

    final tempId = DateTime.now().millisecondsSinceEpoch.toString();
    final newMessage = {
      'sender_id': userId,
      'receiver_id': receiverId,
      'message': message,
      'temp_id': tempId,
      'timestamp': DateTime.now().toIso8601String(),
      'isMe': true,
      'read': false,
      'sent': false,
      'delivered': false,
    };

    state = state.copyWith(messages: [newMessage, ...state.messages]);

    await _repository.saveMessage(newMessage);

    if (state.isConnected) {
      _socket.emit('send_message', {
        'sender_id': userId,
        'receiver_id': receiverId,
        'message': message,
        'temp_id': tempId,
        'time_current': newMessage['timestamp'],
      });
    }
  }

  void handleTyping(bool typing) {
    _socket.emit('typing', {
      'sender_id':
          state.messages.isNotEmpty ? state.messages.first['sender_id'] : '',
      'receiver_id':
          state.messages.isNotEmpty ? state.messages.first['receiver_id'] : '',
      'is_typing': typing,
    });
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _statusTimer?.cancel();
    super.dispose();
  }
}
