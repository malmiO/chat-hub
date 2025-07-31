import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:slt_chat/Features/Chat/screens/chat_info_screen.dart';
import 'package:slt_chat/Features/Chat/screens/delete_module.dart';
import 'package:slt_chat/Features/Chat/screens/pdf_viewer_screen.dart';
import 'package:slt_chat/Features/Chat/screens/video_module.dart';
import 'package:slt_chat/service/local_db_helper.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:slt_chat/config/config.dart';
import 'package:http/io_client.dart';
import 'package:slt_chat/common/widgets/colors.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as path;
import 'package:photo_view/photo_view.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:slt_chat/Features/Chat/screens/pdf_module.dart';
import 'package:video_player/video_player.dart';

class ChatScreen extends StatefulWidget {
  final String userId;
  final String receiverId;
  final String receiverName;
  final String profileImage;

  const ChatScreen({
    Key? key,
    required this.userId,
    required this.receiverId,
    required this.receiverName,
    required this.profileImage,
  }) : super(key: key);

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;
  final String? localVideoPath;
  const VideoPlayerScreen({
    Key? key,
    required this.videoUrl,
    this.localVideoPath,
  }) : super(key: key);

  @override
  _VideoPlayerScreenState createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeController();
  }

  Future<void> _initializeController() async {
    try {
      if (widget.localVideoPath != null &&
          await File(widget.localVideoPath!).exists()) {
        _controller = VideoPlayerController.file(File(widget.localVideoPath!));
      } else {
        _controller = VideoPlayerController.network(widget.videoUrl);
      }

      await _controller.initialize();
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _controller.play();
      }
    } catch (e) {
      print('Error initializing video: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _isLoading
        ? Center(child: CircularProgressIndicator())
        : _controller.value.isInitialized
        ? AspectRatio(
          aspectRatio: _controller.value.aspectRatio,
          child: VideoPlayer(_controller),
        )
        : Center(
          child: Text(
            'Error loading video',
            style: TextStyle(color: Colors.white),
          ),
        );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

const _initialReconnectDelay = 1000; // 1 second
const _maxReconnectDelay = 10000; // 10 seconds
const _reconnectDelayMultiplier = 1.5;

class _ChatScreenState extends State<ChatScreen> {
  late ScrollController _scrollController;
  late IO.Socket socket;
  final TextEditingController _messageController = TextEditingController();
  List<Map<String, dynamic>> messages = [];
  bool isLoading = true;
  bool isTyping = false;
  bool isOnline = false;
  bool isConnected = false;
  String lastSeen = '';
  Timer? _typingTimer;
  Timer? _statusTimer;
  bool _isEmojiVisible = false;
  late FocusNode _focusNode;
  late IOClient _secureClient;
  int _reconnectAttempts = 0;
  int _currentReconnectDelay = _initialReconnectDelay;
  bool _manualDisconnect = false;
  Timer? _reconnectTimer;
  File? _selectedImage;
  bool _isUploading = false;
  int _uploadProgress = 0;
  late StreamController<int> _progressStreamController;
  String? _imageCaption;

  // Voice message variables
  late FlutterSoundRecorder _recorder;
  late FlutterSoundPlayer _player;
  bool _isRecorderInitialized = false;
  bool _isPlayerInitialized = false;
  bool _isRecording = false;
  bool _isPlaying = false;
  String? _audioPath;
  String? _currentlyPlayingUrl;
  bool _isUploadingVoice = false;
  final String _sendSoundPath = 'assets/chat_send.mp3';
  final LocalDBHelper _localDB = LocalDBHelper();
  List<Map<String, dynamic>> _pendingMessages = [];
  Duration _recordingDuration = Duration.zero;
  StreamSubscription<RecordingDisposition>? _recorderSubscription;

  // PDF Sending
  File? _selectedPdf;
  bool _isUploadingPdf = false;
  int _pdfUploadProgress = 0;

  @override
  void initState() {
    super.initState();
    _loadLocalMessages();
    _scrollController = ScrollController();
    _focusNode = FocusNode();
    _progressStreamController = StreamController<int>();
    _initializeSecureClient();
    _initializeSocket();
    startStatusUpdates();
    _setupReadReceipts();
    _recorder = FlutterSoundRecorder();
    _player = FlutterSoundPlayer();
    _initializeRecorder();
    _initializePlayer();
    _localDB.cleanupUnusedPdfs(); // Clean up unused PDFs on init
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        final position = _scrollController.position;
        if (position.pixels < position.maxScrollExtent - 50) {
          _scrollController.animateTo(
            position.maxScrollExtent,
            duration: Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      }
    });
  }

  Future<void> _initializeRecorder() async {
    try {
      final status = await Permission.microphone.request();
      if (status != PermissionStatus.granted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission denied')),
        );
        return;
      }

      await _recorder.openRecorder();
      // Set subscription duration for frequent updates
      await _recorder.setSubscriptionDuration(Duration(milliseconds: 100));
      setState(() => _isRecorderInitialized = true);
      print('Recorder initialized successfully');
    } catch (e) {
      print('Recorder init error: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Recorder init failed: $e')));
    }
  }

  Future<void> _initializePlayer() async {
    if (_isPlayerInitialized) return;
    try {
      await _player.openPlayer();
      await _player.setSubscriptionDuration(const Duration(milliseconds: 10));
      setState(() => _isPlayerInitialized = true);
      print('Player initialized successfully');
    } catch (e, stack) {
      print('Player init error: $e');
      print('Stack trace: $stack');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Audio player initialization failed: ${e.toString()}'),
        ),
      );
    }
  }

  Future<void> _playSendSound() async {
    try {
      if (!_isPlayerInitialized) {
        await _initializePlayer();
        if (!_isPlayerInitialized) return;
      }

      final ByteData data = await rootBundle.load('assets/chat_send.mp3');
      final Uint8List bytes = data.buffer.asUint8List();

      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/chat_send_temp.mp3');
      await tempFile.writeAsBytes(bytes);

      await _player.startPlayer(
        fromURI: tempFile.path,
        codec: Codec.mp3,
        whenFinished: () async {
          await tempFile.delete();
        },
      );
    } catch (e, stack) {
      print('Error playing send sound: $e');
      print('Stack trace: $stack');
    }
  }

  Future<void> _playReceiveSound() async {
    try {
      if (!_isPlayerInitialized) {
        await _initializePlayer();
        if (!_isPlayerInitialized) return;
      }

      final ByteData data = await rootBundle.load('assets/upcomming.mp3');
      final Uint8List bytes = data.buffer.asUint8List();

      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/upcomming_temp.mp3');
      await tempFile.writeAsBytes(bytes);

      await _player.startPlayer(
        fromURI: tempFile.path,
        codec: Codec.mp3,
        whenFinished: () async {
          await tempFile.delete();
        },
      );
    } catch (e, stack) {
      print('Error playing receive sound: $e');
      print('Stack trace: $stack');
    }
  }

  Future<void> _startRecording() async {
    if (!_isRecorderInitialized) {
      await _initializeRecorder();
      if (!_isRecorderInitialized) return;
    }

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final voiceDir = Directory('${appDir.path}/voice_messages');
      if (!await voiceDir.exists()) await voiceDir.create();

      _audioPath =
          '${voiceDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.aac';

      print('Starting recording to: $_audioPath');
      await _recorder.startRecorder(toFile: _audioPath, codec: Codec.aacADTS);

      // Listen to recording progress for live duration updates
      _recorderSubscription?.cancel(); // Cancel any existing subscription
      _recorderSubscription = _recorder.onProgress!.listen(
        (event) {
          if (mounted) {
            setState(() {
              _recordingDuration = event.duration;
            });
            print('Recording duration: ${_recordingDuration.inSeconds}s');
          }
        },
        onError: (error) {
          print('Recorder progress error: $error');
        },
      );

      setState(() {
        _isRecording = true;
        _recordingDuration = Duration.zero;
      });
    } catch (e, stack) {
      print('Recording start error: $e');
      print('Stack trace: $stack');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Recording failed: $e')));
    }
  }

  Future<void> _stopRecording() async {
    try {
      print('Stopping recording');
      await _recorder.stopRecorder();
      _recorderSubscription?.cancel();
      _recorderSubscription = null;
      setState(() {
        _isRecording = false;
        _recordingDuration = Duration.zero;
      });
      if (_audioPath != null && await File(_audioPath!).exists()) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Voice message saved locally")));
        await _saveAndSendVoiceMessage(_audioPath!);
      } else {
        print('Audio file not found at: $_audioPath');
      }
    } catch (e, stack) {
      print('Recording stop error: $e');
      print('Stack trace: $stack');
      _recorderSubscription?.cancel();
      _recorderSubscription = null;
      setState(() {
        _isRecording = false;
        _recordingDuration = Duration.zero;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Failed to save recording: $e")));
    }
  }

  Future<void> _saveAndSendVoiceMessage(String filePath) async {
    final tempId = 'temp-${DateTime.now().millisecondsSinceEpoch}';

    final message = {
      'sender_id': widget.userId,
      'receiver_id': widget.receiverId,
      'voice_url': filePath,
      'is_voice': true,
      'temp_id': tempId,
      'timestamp': DateTime.now().toIso8601String(),
      'isMe': true,
      'status': 'uploading',
    };
    _scrollToBottom();

    await _localDB.saveMessage(message);
    setState(() => messages.insert(0, message));

    _uploadVoiceMessage(filePath, tempId);
  }

  Future<void> _uploadVoiceMessage(String filePath, String tempId) async {
    try {
      setState(() => _isUploadingVoice = true);
      final file = File(filePath);
      final bytes = await file.readAsBytes();

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${AppConfig.baseUrl}/upload-voice'),
      );
      request.fields.addAll({
        'sender_id': widget.userId,
        'receiver_id': widget.receiverId,
        'temp_id': tempId,
      });
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: path.basename(filePath),
        ),
      );

      final response = await request.send();
      final responseData = await response.stream.bytesToString();
      final jsonResponse = json.decode(responseData);

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Voice message uploaded to server!")),
        );
        _updateVoiceMessageStatus(
          tempId: tempId,
          voiceUrl: jsonResponse['voice_url'],
          status: 'success',
        );
      } else {
        throw Exception('Upload failed: ${jsonResponse['error']}');
      }
    } catch (e) {
      print('Upload error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to upload. Tap to retry.")),
      );
    } finally {
      setState(() => _isUploadingVoice = false);
    }
  }

  Future<void> _updateVoiceMessageStatus({
    required String tempId,
    String? voiceUrl,
    required String status,
    String? error,
  }) async {
    if (voiceUrl != null && voiceUrl.startsWith('/')) {
      voiceUrl = '${AppConfig.baseUrl}$voiceUrl';
    }

    await _localDB.updateVoiceMessageStatus(tempId, status, voiceUrl: voiceUrl);

    setState(() {
      final index = messages.indexWhere((msg) => msg['temp_id'] == tempId);
      if (index != -1) {
        messages[index] = {
          ...messages[index],
          'status': status,
          if (voiceUrl != null) 'voice_url': voiceUrl,
        };
      }
    });

    if (status == 'success' && voiceUrl != null && isConnected) {
      socket.emit('send_message', {
        'sender_id': widget.userId,
        'receiver_id': widget.receiverId,
        'voice_url': voiceUrl.replaceFirst(AppConfig.baseUrl, ''),
        'is_voice': true,
        'temp_id': tempId,
      });
    }
  }

  Future<void> _retryVoiceMessage(String filePath, String tempId) async {
    final file = File(filePath);
    if (await file.exists()) {
      await _uploadVoiceMessage(filePath, tempId);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Audio file missing')));
      await _localDB.deleteMessage(tempId);
      setState(() => messages.removeWhere((m) => m['temp_id'] == tempId));
    }
  }

  Future<void> _sendVoiceMessage(
    String? voiceUrl,
    String filePath,
    String tempId, {
    required String status,
  }) async {
    final message = {
      'sender_id': widget.userId,
      'receiver_id': widget.receiverId,
      'voice_url': voiceUrl ?? filePath,
      'is_voice': true,
      'temp_id': tempId,
      'timestamp': DateTime.now().toIso8601String(),
      'isMe': true,
      'read': false,
      'sent': status == 'success',
      'delivered': false,
      'status': status,
    };

    await _localDB.saveMessage(message);
    if (mounted) {
      setState(() {
        messages.insert(0, message);
      });
    }

    if (status == 'success' && isConnected) {
      socket.emit('send_message', {
        'sender_id': widget.userId,
        'receiver_id': widget.receiverId,
        'voice_url': voiceUrl,
        'is_voice': true,
        'temp_id': tempId,
        'time_current': message['timestamp'],
      });
    } else {
      _pendingMessages.add(message);
    }
  }

  Future<void> _playVoiceMessage(String url) async {
    if (_player.isPlaying) {
      await _player.stopPlayer();
    }
    if (!_isPlayerInitialized) {
      await _initializePlayer();
      if (!_isPlayerInitialized) return;
    }

    try {
      print('Attempting to play voice message from: $url');
      if (_isPlaying && _currentlyPlayingUrl == url) {
        await _player.stopPlayer();
        setState(() {
          _isPlaying = false;
          _currentlyPlayingUrl = null;
        });
        return;
      }

      if (url.startsWith('/') || url.startsWith('file://')) {
        final file = File(url.replaceFirst('file://', ''));
        if (!await file.exists()) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Audio file not found')));
          return;
        }
      }

      Codec codec;
      if (url.toLowerCase().endsWith('.aac')) {
        codec = Codec.aacADTS;
      } else if (url.toLowerCase().endsWith('.mp3')) {
        codec = Codec.mp3;
      } else {
        codec = Codec.defaultCodec;
      }

      await _player.startPlayer(
        fromURI: url,
        codec: codec,
        whenFinished: () {
          if (mounted) {
            setState(() {
              _isPlaying = false;
              _currentlyPlayingUrl = null;
            });
          }
        },
      );

      setState(() {
        _isPlaying = true;
        _currentlyPlayingUrl = url;
      });
    } catch (e, stack) {
      print('Error playing voice message: $e');
      print('Stack trace: $stack');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to play audio: ${e.toString()}')),
      );
    }
  }

  Future<void> _loadLocalMessages() async {
    try {
      final localMessages = await _localDB.getMessagesForChat(
        widget.userId,
        widget.receiverId,
      );

      if (mounted) {
        setState(() {
          messages = localMessages;
          isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading local messages: $e');
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _initializeSecureClient() async {
    try {
      final httpClient =
          HttpClient()
            ..badCertificateCallback =
                (X509Certificate cert, String host, int port) => true;

      _secureClient = IOClient(httpClient);
    } catch (e) {
      print('Error initializing secure client: $e');
      _secureClient = IOClient(HttpClient());
    }
  }

  void _setupReadReceipts() {
    _markMessagesAsRead();

    _scrollController.addListener(() {
      if (_scrollController.position.pixels ==
          _scrollController.position.maxScrollExtent) {
        _markMessagesAsRead();
      }
    });
  }

  Future<void> _markMessagesAsRead() async {
    final unreadMessages =
        messages.where((msg) => !msg['isMe'] && !msg['read']).toList();

    if (unreadMessages.isNotEmpty) {
      socket.emit('message_read', {
        'sender_id': widget.userId,
        'receiver_id': widget.receiverId,
      });

      setState(() {
        messages =
            messages
                .map(
                  (msg) =>
                      !msg['isMe'] && !msg['read']
                          ? {...msg, 'read': true}
                          : msg,
                )
                .toList();
      });

      await _localDB.markMessagesAsRead(widget.receiverId, widget.userId);
    }
  }

  void _showChatInfo() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => ChatInfoScreen(
              userId: widget.userId,
              receiverId: widget.receiverId,
              receiverName: widget.receiverName,
              isOnline: isOnline,
              lastSeen: lastSeen,
              profile: widget.profileImage,
            ),
      ),
    );
  }

  Future<void> _pickPdf() async {
    await PdfModule.pickAndUploadPdf(
      context: context,
      userId: widget.userId,
      receiverId: widget.receiverId,
      onSend: (message) async {
        await _localDB.saveMessage(message);
        setState(() {
          messages.insert(0, message);
          _scrollToBottom();
          _isUploadingPdf = false;
          _selectedPdf = null;
        });
        await _playSendSound();
        if (isConnected) {
          socket.emit('send_message', {
            'sender_id': widget.userId,
            'receiver_id': widget.receiverId,
            'is_pdf': true,
            'pdf_id': message['pdf_id'],
            'temp_id': message['temp_id'],
            'time_current': message['timestamp'],
            'filename': message['filename'],
          });
        } else {
          _pendingMessages.add(message);
        }
      },
      onProgress: (progress) {
        setState(() {
          _pdfUploadProgress = progress;
        });
      },
      onError: (error) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error)));
        setState(() {
          _isUploadingPdf = false;
        });
      },
    );
  }

  Future<void> _pickVideo() async {
    await VideoModule.pickAndUploadVideo(
      context: context,
      userId: widget.userId,
      receiverId: widget.receiverId,
      onSend: (message) async {
        await _localDB.saveMessage(message);
        setState(() {
          messages.insert(0, message);
          _scrollToBottom();
        });
        await _playSendSound();
        if (isConnected) {
          socket.emit('send_message', {
            'sender_id': widget.userId,
            'receiver_id': widget.receiverId,
            'is_video': true,
            'video_id': message['video_id'],
            'temp_id': message['temp_id'],
            'time_current': message['timestamp'],
            'filename': message['filename'],
          });
        } else {
          _pendingMessages.add(message);
        }
      },
      onProgress: (progress) {
        setState(() {
          // You can store video upload progress if needed
        });
      },
      onError: (error) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error)));
      },
    );
  }

  Future<void> _downloadAndCacheVideo(
    String videoUrl,
    String tempId,
    String filename,
  ) async {
    try {
      final response = await http.get(Uri.parse(videoUrl));
      if (response.statusCode == 200) {
        final appDir = await getApplicationDocumentsDirectory();
        final videoDir = Directory('${appDir.path}/videos');
        if (!await videoDir.exists()) await videoDir.create();
        final localPath = '${videoDir.path}/$filename';
        final file = File(localPath);
        await file.writeAsBytes(response.bodyBytes);

        await _localDB.updateLocalVideoPath(tempId, localPath);

        setState(() {
          final index = messages.indexWhere((msg) => msg['temp_id'] == tempId);
          if (index != -1) {
            messages[index]['local_video_path'] = localPath;
          }
        });
      }
    } catch (e) {
      print('Error downloading video: $e');
    }
  }

  Future<void> _downloadAndCachePdf(
    String pdfId,
    String tempId,
    String filename,
  ) async {
    try {
      final pdfUrl = '${AppConfig.baseUrl}/get-pdf/$pdfId';
      final response = await http.get(Uri.parse(pdfUrl));
      if (response.statusCode == 200) {
        final appDir = await getApplicationDocumentsDirectory();
        final pdfDir = Directory('${appDir.path}/pdfs');
        if (!await pdfDir.exists()) await pdfDir.create();
        final localPath = '${pdfDir.path}/$filename';
        final file = File(localPath);
        if (!await file.exists()) {
          await file.writeAsBytes(response.bodyBytes);
        }
        await _localDB.updateLocalPdfPath(tempId, localPath);
        setState(() {
          final index = messages.indexWhere((msg) => msg['temp_id'] == tempId);
          if (index != -1) {
            messages[index]['local_pdf_path'] = localPath;
          }
        });
      } else {
        print('Failed to download PDF: ${response.statusCode}');
      }
    } catch (e) {
      print('Error downloading PDF: $e');
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();

    if (_reconnectAttempts < 10) {
      _reconnectAttempts++;
      _currentReconnectDelay =
          (_currentReconnectDelay * _reconnectDelayMultiplier)
              .clamp(_initialReconnectDelay, _maxReconnectDelay)
              .toInt();

      print('Scheduling reconnect in ${_currentReconnectDelay}ms');

      _reconnectTimer = Timer(
        Duration(milliseconds: _currentReconnectDelay),
        () {
          if (!_manualDisconnect && mounted) {
            print('Attempting reconnect...');
            socket.connect();
          }
        },
      );
    } else {
      print('Max reconnect attempts reached');
    }
  }

  void _initializeSocket() {
    socket = IO.io(AppConfig.baseUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
      'secure': true,
      'rejectUnauthorized': false,
      'reconnection': true,
      'reconnectionAttempts': 10,
      'reconnectionDelay': _initialReconnectDelay,
      'reconnectionDelayMax': _maxReconnectDelay,
      'query': {'user_id': widget.userId},
    });

    socket.onConnect((_) {
      print('Socket connected: ${socket.id}');
      if (mounted) {
        setState(() {
          isConnected = true;
          _reconnectAttempts = 0;
          _currentReconnectDelay = _initialReconnectDelay;
        });
      }
      _joinRoom();
      updateUserStatus(true);
      _sendPendingMessages();
      _syncMessagesOnReconnect();
    });

    socket.on('message_sent', (data) {
      if (mounted) {
        setState(() {
          messages =
              messages.map((msg) {
                if (msg['temp_id'] == data['temp_id']) {
                  return {...msg, 'id': data['message_id'], 'sent': true};
                }
                return msg;
              }).toList();
        });
      }

      _localDB.updateMessageStatus(
        data['temp_id'],
        messageId: data['message_id'],
        isSent: true,
      );

      socket.emit('message_delivered', {
        'message_id': data['message_id'],
        'temp_id': data['temp_id'],
        'sender_id': widget.userId,
        'receiver_id': widget.receiverId,
      });
    });

    socket.on('message_delivered', (data) {
      if (mounted) {
        setState(() {
          messages =
              messages.map((msg) {
                if ((msg['id'] != null && msg['id'] == data['message_id']) ||
                    (msg['temp_id'] != null &&
                        msg['temp_id'] == data['temp_id'])) {
                  return {...msg, 'delivered': true};
                }
                return msg;
              }).toList();
        });
      }
      _localDB.updateMessageStatus(data['temp_id'], isDelivered: true);
    });

    socket.on('message_deleted', (data) {
      if (mounted) {
        setState(() {
          messages.removeWhere(
            (msg) =>
                msg['id'] == data['message_id'] ||
                msg['temp_id'] == data['temp_id'],
          );
        });
      }
      _localDB.deleteMessage(data['temp_id']);
    });

    socket.on('message_read', (data) {
      if (mounted) {
        setState(() {
          messages =
              messages.map((msg) {
                if (msg['id'] == data['message_id']) {
                  return {...msg, 'read': true};
                }
                return msg;
              }).toList();
        });
      }

      _localDB.updateMessageStatus(data['temp_id'], isRead: true);
    });

    socket.on('receive_message', (data) async {
      String? videoUrl =
          data['is_video'] == true
              ? '${AppConfig.baseUrl}/get-video/${data['video_id']}'
              : null;
      String? pdfUrl =
          data['is_pdf'] == true
              ? '${AppConfig.baseUrl}/get-pdf/${data['pdf_id']}'
              : null;
      String? voiceUrl = data['is_voice'] == true ? data['voice_url'] : null;
      if (voiceUrl != null && voiceUrl.startsWith('/')) {
        voiceUrl = '${AppConfig.baseUrl}$voiceUrl';
      }

      final isMe = data['sender_id'] == widget.userId;
      final String? tempId = data['temp_id'];

      // Check if message already exists
      bool messageExists = false;
      if (data['id'] != null) {
        messageExists = messages.any((msg) => msg['id'] == data['id']);
      }
      if (!messageExists && tempId != null) {
        messageExists = messages.any((msg) => msg['temp_id'] == tempId);
      }

      if (messageExists) {
        setState(() {
          messages =
              messages.map((msg) {
                final match =
                    (msg['id'] != null && msg['id'] == data['id']) ||
                    (tempId != null && msg['temp_id'] == tempId);
                return match
                    ? {
                      ...msg,
                      'id': data['id'] ?? msg['id'],
                      'voice_url': voiceUrl ?? msg['voice_url'],
                      'is_image': data['is_image'] ?? msg['is_image'],
                      'is_voice': data['is_voice'] ?? msg['is_voice'],
                      'is_pdf': data['is_pdf'] ?? msg['is_pdf'],
                      'pdf_id': data['pdf_id'] ?? msg['pdf_id'],
                      'is_video': data['is_video'] ?? msg['is_video'],
                      'video_id': data['video_id'] ?? msg['video_id'],
                      'filename': data['filename'] ?? msg['filename'],
                      'delivered': data['delivered'] ?? msg['delivered'],
                      'read': data['read'] ?? msg['read'],
                    }
                    : msg;
              }).toList();
        });
        return;
      }

      final newMessage = {
        'id': data['id'],
        'sender_id': data['sender_id'],
        'receiver_id': data['receiver_id'],
        'message': data['message'] ?? '',
        'voice_url': voiceUrl,
        'is_image': data['is_image'] ?? false,
        'is_pdf': data['is_pdf'] ?? false,
        'pdf_id': data['pdf_id'],
        'filename': data['filename'],
        'is_voice': data['is_voice'] ?? false,
        'is_video': data['is_video'] ?? false,
        'video_id': data['video_id'],
        'timestamp': data['timestamp'] ?? DateTime.now().toIso8601String(),
        'isMe': isMe,
        'read': data['read'] ?? false,
        'delivered': data['delivered'] ?? false,
        'sent': true,
        'temp_id': tempId,
        'local_video_path': null,
        'local_pdf_path': null,
      };

      await _localDB.saveMessage(newMessage);
      if (mounted) {
        setState(() {
          messages.insert(0, newMessage);
          _scrollToBottom();
        });
      }

      // Download media in background
      if (videoUrl != null && data['is_video'] == true) {
        _downloadAndCacheVideo(
          videoUrl,
          data['temp_id'] ?? '',
          data['filename'] ?? 'video_${data['temp_id']}.mp4',
        );
      }
      if (pdfUrl != null && data['is_pdf'] == true) {
        _downloadAndCachePdf(
          data['pdf_id'],
          data['temp_id'] ?? '',
          data['filename'] ?? 'document_${data['pdf_id']}.pdf',
        );
      }

      if (!isMe) {
        await _playReceiveSound();
        // Emit read receipt
        socket.emit('message_read', {
          'sender_id': widget.userId,
          'receiver_id': widget.receiverId,
          'message_id': data['id'],
          'temp_id': tempId,
        });
      }
    });

    socket.onDisconnect((_) {
      print('Socket disconnected');
      if (!_manualDisconnect && mounted) {
        setState(() => isConnected = false);
        _scheduleReconnect();
      }
    });

    socket.onConnectError((err) {
      print('Connect error: $err');
      if (!_manualDisconnect) {
        _scheduleReconnect();
      }
    });

    socket.onError((err) => print('Socket error: $err'));
    socket.onReconnectAttempt((attempt) => print('Reconnect attempt $attempt'));
    socket.on('typing', _handleTypingIndicator);
    socket.on('messages_read', _handleReadReceipts);
    socket.connect();
  }

  void _joinRoom() {
    final room = [widget.userId, widget.receiverId]..sort();
    final roomId = room.join('_');
    print('Joining room: $roomId');
    socket.emit('join_room', {
      'user_id': widget.userId,
      'receiver_id': widget.receiverId,
    });
  }

  Future<void> updateUserStatus(bool online) async {
    try {
      await _secureClient.post(
        Uri.parse('${AppConfig.baseUrl}/update-status/${widget.userId}'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'is_online': online}),
      );
    } catch (e) {
      print('Error updating status: $e');
    }
  }

  Future<void> _syncMessagesOnReconnect() async {
    try {
      // Use the oldest message timestamp or 30 days ago
      final lastMessageTime =
          messages.isNotEmpty
              ? DateTime.parse(messages.first['timestamp'])
              : DateTime.now().subtract(Duration(days: 30));

      // Avoid truncating milliseconds to ensure precision
      final syncSince = lastMessageTime.toUtc().toIso8601String();
      print('Syncing messages since: $syncSince');

      final response = await _secureClient.get(
        Uri.parse(
          '${AppConfig.baseUrl}/messages-since/${widget.userId}/${widget.receiverId}/$syncSince',
        ),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final serverMessages =
              List<Map<String, dynamic>>.from(data['messages'])
                  .map(
                    (msg) => ({
                      ...msg,
                      'isMe': msg['sender_id'] == widget.userId,
                      'sent': true,
                      'delivered': msg['delivered'] ?? false,
                      'read': msg['read'] ?? false,
                      'local_video_path': null,
                      'local_pdf_path': null,
                    }),
                  )
                  .toList();

          print('Received ${serverMessages.length} messages from server');

          // Sync messages with server
          await _localDB.syncMessagesWithServer(
            serverMessages: serverMessages,
            currentUserId: widget.userId,
          );

          // Resolve conflicts for pending messages
          await _localDB.resolveConflicts(serverMessages);

          // Reload messages from local DB
          final merged = await _localDB.getMessagesForChat(
            widget.userId,
            widget.receiverId,
          );

          if (mounted) {
            setState(() {
              messages = merged;
              _scrollToBottom();
            });
          }

          // Download media for new messages
          for (var msg in serverMessages) {
            if (msg['is_video'] == true && msg['video_id'] != null) {
              _downloadAndCacheVideo(
                '${AppConfig.baseUrl}/get-video/${msg['video_id']}',
                msg['temp_id'] ?? '',
                msg['filename'] ?? 'video_${msg['temp_id']}.mp4',
              );
            } else if (msg['is_pdf'] == true && msg['pdf_id'] != null) {
              _downloadAndCachePdf(
                msg['pdf_id'],
                msg['temp_id'] ?? '',
                msg['filename'] ?? 'document_${msg['pdf_id']}.pdf',
              );
            }
          }
        } else {
          print('Server returned error: ${data['error']}');
        }
      } else {
        print('Failed to sync messages: ${response.statusCode}');
      }
    } catch (e, stack) {
      print('Error syncing messages on reconnect: $e');
      print('Stack trace: $stack');
    }
  }

  void _toggleEmojiKeyboard() {
    if (_isEmojiVisible) {
      _focusNode.requestFocus();
    } else {
      _focusNode.unfocus();
    }
    setState(() => _isEmojiVisible = !_isEmojiVisible);
  }

  Future<void> _showImageSourceOptions() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder:
          (context) => Container(
            decoration: const BoxDecoration(
              color: Color(0xFF121212), // Dark background
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[700],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Center(
                          child: Text(
                            'Upload media',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color:
                                  Colors
                                      .white, // White text for dark background
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(color: Colors.grey, height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildOptionButton(
                          icon: Icons.insert_photo,
                          label: 'Gallery',
                          color: Colors.purple,
                          onTap: () {
                            Navigator.pop(context);
                            _pickImage(ImageSource.gallery);
                          },
                        ),
                        _buildOptionButton(
                          icon: Icons.camera_alt,
                          label: 'Camera',
                          color: Colors.red,
                          onTap: () {
                            Navigator.pop(context);
                            _pickImage(ImageSource.camera);
                          },
                        ),
                        _buildOptionButton(
                          icon: Icons.picture_as_pdf,
                          label: 'Document',
                          color: Colors.blue,
                          onTap: () {
                            Navigator.pop(context);
                            _pickPdf();
                          },
                        ),

                        _buildOptionButton(
                          icon: Icons.videocam,
                          label: 'Video',
                          color: Colors.green,
                          onTap: () {
                            Navigator.pop(context);
                            _pickVideo();
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
    );
  }

  Widget _buildOptionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 72,
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white, // White label text
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      PermissionStatus status;
      if (source == ImageSource.camera) {
        status = await Permission.camera.request();
        if (status != PermissionStatus.granted) {
          if (status == PermissionStatus.permanentlyDenied) {
            _showPermissionSettingsDialog('Camera');
          } else {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Camera permission denied')));
          }
          return;
        }
      } else {
        if (Platform.isAndroid) {
          final androidInfo = await DeviceInfoPlugin().androidInfo;
          if (androidInfo.version.sdkInt >= 33) {
            status = await Permission.photos.request();
          } else {
            status = await Permission.storage.request();
          }
        } else {
          status = await Permission.photos.request();
        }

        if (status != PermissionStatus.granted) {
          if (status == PermissionStatus.permanentlyDenied) {
            _showPermissionSettingsDialog('Photos');
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Photo gallery permission denied')),
            );
          }
          return;
        }
      }

      final pickedFile = await ImagePicker().pickImage(
        source: source,
        imageQuality: 70,
      );

      if (pickedFile != null) {
        setState(() {
          _selectedImage = File(pickedFile.path);
        });
        _showImagePreview();
      }
    } catch (e) {
      print('Error picking image: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error picking image: $e')));
    }
  }

  void _showPermissionSettingsDialog(String permissionType) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('$permissionType Permission Required'),
            content: Text(
              'Please enable $permissionType permission in app settings to use this feature.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  openAppSettings();
                },
                child: Text('Open Settings'),
              ),
            ],
          ),
    );
  }

  void _showImagePreview() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setModalState) => Container(
                  height: MediaQuery.of(context).size.height * 0.85,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: Colors.grey[800]!),
                          ),
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              icon: Icon(Icons.close, color: Colors.white),
                              onPressed: () {
                                Navigator.pop(context);
                                setState(() {
                                  _selectedImage = null;
                                  _isUploading = false;
                                });
                              },
                            ),
                            Spacer(),
                            Text(
                              'Preview',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                              ),
                            ),
                            Spacer(),
                            IconButton(
                              icon: Icon(Icons.send, color: Colors.blue),
                              onPressed: _isUploading ? null : _uploadImage,
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child:
                              _selectedImage != null
                                  ? Image.file(_selectedImage!)
                                  : Text(
                                    'No image selected',
                                    style: TextStyle(color: Colors.white),
                                  ),
                        ),
                      ),
                      if (_isUploading) ...[
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Column(
                            children: [
                              LinearProgressIndicator(
                                value: _uploadProgress / 100,
                                backgroundColor: Colors.grey[800],
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.blue,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Uploading ${_uploadProgress.toStringAsFixed(0)}%',
                                style: TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
          ),
    );
  }

  Future<void> _uploadImage() async {
    if (_selectedImage == null) return;

    setState(() {
      _isUploading = true;
      _uploadProgress = 0;
    });

    try {
      final mimeType = lookupMimeType(_selectedImage!.path) ?? 'image/jpeg';
      final fileName = path.basename(_selectedImage!.path);
      final length = await _selectedImage!.length();

      final fileStream = _selectedImage!.openRead().cast<List<int>>();
      int bytesSent = 0;

      final streamWithProgress = fileStream.transform<List<int>>(
        StreamTransformer.fromHandlers(
          handleData: (data, sink) {
            sink.add(data);
            bytesSent += data.length;
            final progress = (bytesSent / length * 100).clamp(0, 100).toInt();
            if (mounted) {
              setState(() {
                _uploadProgress = progress;
              });
            }
          },
        ),
      );

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${AppConfig.baseUrl}/upload-image'),
      );

      final multipartFile = http.MultipartFile(
        'file',
        streamWithProgress,
        length,
        filename: fileName,
        contentType: MediaType.parse(mimeType),
      );

      request.files.add(multipartFile);
      request.fields['sender_id'] = widget.userId;
      request.fields['receiver_id'] = widget.receiverId;
      if (_imageCaption != null && _imageCaption!.isNotEmpty) {
        request.fields['caption'] = _imageCaption!;
      }

      final response = await request.send();
      final responseData = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final jsonData = json.decode(responseData);
        final tempId = DateTime.now().millisecondsSinceEpoch.toString();
        if (mounted) {
          setState(() {
            messages.insert(0, {
              'sender_id': widget.userId,
              'receiver_id': widget.receiverId,
              'is_image': true,
              'id': jsonData['image_id'],
              'temp_id': tempId,
              'isMe': true,
              'timestamp': DateTime.now().toIso8601String(),
              'read': false,
              'sent': true,
              'delivered': false,
              if (_imageCaption != null) 'caption': _imageCaption,
            });
            _scrollToBottom();
            _isUploading = false;
            _selectedImage = null;
            _imageCaption = null;
          });
          Navigator.pop(context);
          await _playSendSound();

          if (isConnected) {
            socket.emit('send_message', {
              'sender_id': widget.userId,
              'receiver_id': widget.receiverId,
              'is_image': true,
              'image_id': jsonData['image_id'],
              'temp_id': tempId,
              'time_current': DateTime.now().toIso8601String(),
              if (_imageCaption != null) 'caption': _imageCaption,
            });
          } else {
            _pendingMessages.add({
              'sender_id': widget.userId,
              'receiver_id': widget.receiverId,
              'is_image': true,
              'image_id': jsonData['image_id'],
              'temp_id': tempId,
              'timestamp': DateTime.now().toIso8601String(),
              if (_imageCaption != null) 'caption': _imageCaption,
            });
          }
        }
      } else {
        throw Exception('Failed to upload image: ${response.statusCode}');
      }
    } catch (e) {
      print('Error uploading image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send image: ${e.toString()}')),
        );
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  List<Widget> _buildGroupedMessages() {
    if (messages.isEmpty) return [Center(child: Text('No messages yet'))];

    final Map<String, List<Map<String, dynamic>>> groupedMessages = {};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(Duration(days: 1));

    for (var i = messages.length - 1; i >= 0; i--) {
      final message = messages[i];
      final messageDate = DateTime.parse(message['timestamp']);
      final messageDay = DateTime(
        messageDate.year,
        messageDate.month,
        messageDate.day,
      );

      String dateLabel;
      if (messageDay == today) {
        dateLabel = 'Today';
      } else if (messageDay == yesterday) {
        dateLabel = 'Yesterday';
      } else {
        dateLabel = DateFormat('MMMM d, y').format(messageDay);
      }

      if (!groupedMessages.containsKey(dateLabel)) {
        groupedMessages[dateLabel] = [];
      }
      groupedMessages[dateLabel]!.add(message);
    }

    List<Widget> widgets = [];
    groupedMessages.forEach((dateLabel, messageGroup) {
      widgets.add(
        Padding(
          padding: EdgeInsets.only(top: 8, bottom: 4),
          child: Center(
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                dateLabel,
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              ),
            ),
          ),
        ),
      );

      widgets.addAll(
        messageGroup.map((msg) => _buildMessageBubble(msg)).toList(),
      );
    });

    return widgets;
  }

  void startStatusUpdates() {
    _statusTimer = Timer.periodic(Duration(seconds: 10), (timer) async {
      try {
        final response = await _secureClient.get(
          Uri.parse('${AppConfig.baseUrl}/status/${widget.receiverId}'),
        );
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (mounted) {
            setState(() {
              isOnline = data['is_online'] ?? false;
              lastSeen = _formatLastSeen(data['last_seen']);
            });
          }
        } else {
          print('Error fetching status: ${response.statusCode}');
        }
      } catch (e) {
        print('Error fetching status: $e');
      }
    });
  }

  String _formatLastSeen(String? timestamp) {
    if (timestamp == null) {
      return 'last seen unknown';
    }

    try {
      final dateTime = DateTime.parse(timestamp).toLocal();
      final now = DateTime.now().toLocal();
      final difference = now.difference(dateTime);

      if (difference.inSeconds < 10) return 'online';
      if (difference.inMinutes < 60) {
        return 'last seen ${difference.inMinutes} min ago';
      }
      if (difference.inHours < 24) {
        final hours = difference.inHours;
        return 'last seen $hours hour${hours == 1 ? '' : 's'} ago';
      }
      return 'last seen ${DateFormat('MMM d').format(dateTime)}';
    } catch (e) {
      print('Error formatting timestamp: $e, timestamp: $timestamp');
      return 'last seen unknown';
    }
  }

  void _handleTyping(bool typing) {
    socket.emit('typing', {
      'sender_id': widget.userId,
      'receiver_id': widget.receiverId,
      'is_typing': typing,
    });
  }

  Future<void> _showDeleteOptions(Map<String, dynamic> message) async {
    final action = await DeleteModule.showDeleteDialog(
      context: context,
      isMyMessage: message['isMe'],
      isOnline: true,
    );

    if (action != null && action != DeleteAction.cancel) {
      try {
        await DeleteModule.deleteMessage(
          messageId: message['id'] ?? '',
          tempId: message['temp_id'] ?? '',
          senderId: widget.userId,
          receiverId: widget.receiverId,
          action: action,
          localDB: _localDB,
          socket: socket,
        );

        if (mounted) {
          setState(() {
            messages.removeWhere(
              (m) =>
                  m['id'] == message['id'] ||
                  m['temp_id'] == message['temp_id'],
            );
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete message: $e')),
          );
        }
      }
    }
  }

  Future<void> fetchChatHistory() async {
    try {
      final localMessages = await _localDB.getMessagesForChat(
        widget.userId,
        widget.receiverId,
      );

      setState(() {
        messages = localMessages;
        isLoading = false;
      });

      if (isConnected) {
        final response = await _secureClient.get(
          Uri.parse(
            '${AppConfig.baseUrl}/messages/${widget.userId}/${widget.receiverId}',
          ),
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final serverMessages =
              List<Map<String, dynamic>>.from(data['messages'])
                  .map(
                    (msg) => ({
                      ...msg,
                      'isMe': msg['sender_id'] == widget.userId,
                      'sent': true,
                      'delivered':
                          msg['read'] || msg['sender_id'] != widget.userId,
                      'read': msg['read'],
                    }),
                  )
                  .toList();

          await _localDB.syncMessagesWithServer(
            serverMessages: serverMessages,
            currentUserId: widget.userId,
          );

          final merged = await _localDB.getMessagesForChat(
            widget.userId,
            widget.receiverId,
          );

          if (mounted) {
            setState(() => messages = merged);
            _scrollToBottom();
          }
        }
      }
    } catch (e) {
      print('Error fetching chat history: $e');
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _handleTypingIndicator(dynamic data) {
    if (data['sender_id'] == widget.receiverId) {
      setState(() => isTyping = data['is_typing']);
      if (data['is_typing']) {
        _typingTimer?.cancel();
        _typingTimer = Timer(Duration(seconds: 3), () {
          if (mounted) {
            setState(() => isTyping = false);
          }
        });
      }
    }
  }

  void _handleReadReceipts(dynamic data) {
    if (data['reader_id'] == widget.receiverId && mounted) {
      setState(() {
        messages =
            messages.map((msg) {
              if (msg['sender_id'] == widget.userId && !msg['read']) {
                return {...msg, 'read': true};
              }
              return msg;
            }).toList();
      });
    }
  }

  void sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty && !_isRecording) return;

    if (_messageController.text.trim().isEmpty) return;

    final tempId = DateTime.now().millisecondsSinceEpoch.toString();

    final exists = messages.any((msg) => msg['temp_id'] == tempId);
    if (exists) return;

    final message = {
      'sender_id': widget.userId,
      'receiver_id': widget.receiverId,
      'message': _messageController.text,
      'temp_id': tempId,
      'timestamp': DateTime.now().toIso8601String(),
      'isMe': true,
      'read': false,
      'sent': false,
      'delivered': false,
    };

    final messageExists = messages.any(
      (m) =>
          m['temp_id'] == tempId ||
          (m['message'] == message['message'] &&
              m['timestamp'] == message['timestamp']),
    );

    if (!messageExists) {
      _localDB.saveMessage(message).then((_) {
        if (mounted) {
          setState(() {
            messages.insert(0, message);
          });
          _scrollToBottom();
          _playSendSound();
        }
      });

      _sendViaSocket(message);
    }

    _messageController.clear();
    _handleTyping(false);
  }

  Future<void> _sendViaSocket(Map<String, dynamic> message) async {
    if (message['sent'] == true) return;
    if (isConnected) {
      try {
        socket.emit('send_message', {
          'sender_id': widget.userId,
          'receiver_id': widget.receiverId,
          'message': message['message'],
          'temp_id': message['temp_id'],
          'time_current': message['timestamp'],
        });

        await _localDB.updateMessageStatus(message['temp_id'], isSent: true);

        if (mounted) {
          setState(() {
            messages =
                messages.map((msg) {
                  if (msg['temp_id'] == message['temp_id']) {
                    return {...msg, 'sent': true};
                  }
                  return msg;
                }).toList();
          });
        }
      } catch (e) {
        print('Error sending message via socket: $e');
      }
    } else {
      _pendingMessages.add(message);
    }
  }

  Future<void> _sendPendingMessages() async {
    if (!isConnected) return;

    final pending = await _localDB.getPendingMessages(widget.userId);
    for (var msg in pending) {
      try {
        if (msg['is_voice'] == true && msg['voice_url'] != null) {
          if (msg['status'] == 'success') {
            socket.emit('send_message', {
              'sender_id': widget.userId,
              'receiver_id': widget.receiverId,
              'voice_url': msg['voice_url'].replaceFirst(AppConfig.baseUrl, ''),
              'is_voice': true,
              'temp_id': msg['temp_id'],
              'time_current': msg['timestamp'],
            });
            await _localDB.updateMessageStatus(msg['temp_id'], isSent: true);
          } else if (await File(msg['voice_url']).exists()) {
            await _uploadVoiceMessage(msg['voice_url'], msg['temp_id']);
          }
        } else if (msg['is_image'] == true && msg['image_id'] != null) {
          socket.emit('send_message', {
            'sender_id': widget.userId,
            'receiver_id': widget.receiverId,
            'is_image': true,
            'image_id': msg['image_id'],
            'temp_id': msg['temp_id'],
            'time_current': msg['timestamp'],
            if (msg['caption'] != null) 'caption': msg['caption'],
          });
          await _localDB.updateMessageStatus(msg['temp_id'], isSent: true);
        } else if (msg['is_pdf'] == true && msg['pdf_id'] != null) {
          socket.emit('send_message', {
            'sender_id': widget.userId,
            'receiver_id': widget.receiverId,
            'is_pdf': true,
            'pdf_id': msg['pdf_id'],
            'temp_id': msg['temp_id'],
            'time_current': msg['timestamp'],
            'filename': msg['filename'],
          });
          await _localDB.updateMessageStatus(msg['temp_id'], isSent: true);
        } else if (msg['is_video'] == true && msg['video_id'] != null) {
          socket.emit('send_message', {
            'sender_id': widget.userId,
            'receiver_id': widget.receiverId,
            'is_video': true,
            'video_id': msg['video_id'],
            'temp_id': msg['temp_id'],
            'time_current': msg['timestamp'],
            'filename': msg['filename'],
          });
          await _localDB.updateMessageStatus(msg['temp_id'], isSent: true);
        } else {
          socket.emit('send_message', {
            'sender_id': widget.userId,
            'receiver_id': widget.receiverId,
            'message': msg['message'],
            'temp_id': msg['temp_id'],
            'time_current': msg['timestamp'],
          });
          await _localDB.updateMessageStatus(msg['temp_id'], isSent: true);
        }
      } catch (e) {
        print('Error sending pending message: $e');
      }
    }

    // Clear pending messages list after sending
    _pendingMessages.clear();
  }

  Widget _buildMessageBubble(Map<String, dynamic> message) {
    final isMe = message['isMe'];
    final isImage = message['is_image'] ?? false;
    final isVoice = message['is_voice'] ?? false;
    final isPdf = message['is_pdf'] ?? false;
    final isVideo = message['is_video'] ?? false;
    final isSent = message['sent'] ?? true;
    final isDelivered = message['delivered'] ?? false;
    final isRead = message['read'] ?? false;
    final voiceUrl = message['voice_url'];
    final status = message['status'] ?? 'success';
    final caption = message['caption'];
    final imageUrl = '${AppConfig.baseUrl}/get-image/${message['id']}';
    final videoUrl = '${AppConfig.baseUrl}/get-video/${message['id']}';
    final localVideoPath = message['local_video_path'];

    final pdfUrl = '${AppConfig.baseUrl}/get-pdf/${message['pdf_id']}';
    final filename = message['filename'] ?? 'document_${message['pdf_id']}.pdf';
    final localPdfPath = message['local_pdf_path'];

    return GestureDetector(
      onLongPress: () => _showDeleteOptions(message),
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: Row(
          mainAxisAlignment:
              isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            Flexible(
              child: Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isMe ? Color(0xFFDCF8C6) : Color(0xFFFFFFFF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment:
                      isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    if (isPdf)
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (context) => PdfViewerScreen(
                                    pdfUrl: pdfUrl,
                                    filename: filename,
                                    localPdfPath: localPdfPath,
                                  ),
                            ),
                          );
                        },
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.6,
                          ),
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.picture_as_pdf, color: Colors.red),
                              SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  message['filename'] ?? 'document.pdf',
                                  style: TextStyle(color: Colors.black),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (isImage)
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (context) => Scaffold(
                                    appBar: AppBar(),
                                    body: Center(
                                      child: PhotoView(
                                        imageProvider:
                                            CachedNetworkImageProvider(
                                              imageUrl,
                                            ),
                                        minScale:
                                            PhotoViewComputedScale.contained,
                                        maxScale:
                                            PhotoViewComputedScale.covered * 2,
                                      ),
                                    ),
                                  ),
                            ),
                          );
                        },
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.6,
                            maxHeight: 300,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl: imageUrl,
                              fit: BoxFit.cover,
                              placeholder:
                                  (context, url) => Container(
                                    width: 200,
                                    height: 200,
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  ),
                              errorWidget:
                                  (context, url, error) => Container(
                                    width: 200,
                                    height: 200,
                                    color: Colors.grey,
                                    child: Center(child: Icon(Icons.error)),
                                  ),
                            ),
                          ),
                        ),
                      )
                    else if (isVoice)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (status == 'uploading') ...[
                            SizedBox(width: 8),
                            CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.blue,
                              ),
                            ),
                          ],
                          IconButton(
                            icon: Icon(
                              _isPlaying &&
                                      _currentlyPlayingUrl ==
                                          message['voice_url']
                                  ? Icons.stop
                                  : Icons.play_arrow,
                              color: Colors.black,
                            ),
                            onPressed:
                                status == 'success'
                                    ? () => _playVoiceMessage(voiceUrl)
                                    : null,
                          ),
                          if (status == 'uploading')
                            CircularProgressIndicator()
                          else if (status == 'failed')
                            IconButton(
                              icon: Icon(Icons.refresh, color: Colors.red),
                              onPressed:
                                  () => _retryVoiceMessage(
                                    voiceUrl,
                                    message['temp_id'],
                                  ),
                            ),
                          SizedBox(width: 8),
                          Text(
                            status == 'failed'
                                ? 'Send failed'
                                : 'Voice message',
                            style: TextStyle(color: Colors.black54),
                          ),
                        ],
                      )
                    else if (isVideo)
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (context) => Scaffold(
                                    appBar: AppBar(
                                      backgroundColor: Colors.black,
                                    ),
                                    backgroundColor: Colors.black,
                                    body: Center(
                                      child: VideoPlayerScreen(
                                        videoUrl: videoUrl,
                                        localVideoPath: localVideoPath,
                                      ),
                                    ),
                                  ),
                            ),
                          );
                        },
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.6,
                            maxHeight: 200,
                          ),
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                color: Colors.black,
                                width: double.infinity,
                                height: 150,
                              ),
                              Icon(
                                Icons.play_circle_filled,
                                color: Colors.white,
                                size: 50,
                              ),
                              Positioned(
                                bottom: 8,
                                left: 8,
                                child: Text(
                                  message['filename'] ?? 'video.mp4',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Text(
                        message['message'] ?? '',
                        style: TextStyle(color: Colors.black),
                      ),
                    if (caption != null && caption.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          caption,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                    SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          DateFormat(
                            'HH:mm',
                          ).format(DateTime.parse(message['timestamp'])),
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[600],
                          ),
                        ),
                        if (isMe) ...[
                          SizedBox(width: 4),
                          Icon(
                            isRead
                                ? Icons.done_all
                                : isDelivered
                                ? Icons.done_all
                                : Icons.done,
                            size: 12,
                            color: isRead ? Colors.blue : Colors.grey,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: backgroundColor,
        iconTheme: const IconThemeData(color: Colors.white),
        title: GestureDetector(
          onTap: () => _showChatInfo(),
          child: Row(
            children: [
              ClipOval(
                child: CachedNetworkImage(
                  imageUrl: '${AppConfig.baseUrl}/${widget.profileImage}',
                  placeholder:
                      (context, url) => CircleAvatar(
                        radius: 20,
                        backgroundColor: Colors.grey.shade300,
                        child: const CircularProgressIndicator(strokeWidth: 2),
                      ),
                  errorWidget:
                      (context, url, error) => CircleAvatar(
                        radius: 20,
                        backgroundColor: Colors.grey.shade400,
                        child: Text(
                          widget.receiverName[0],
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                  fit: BoxFit.cover,
                  width: 40,
                  height: 40,
                ),
              ),
              const SizedBox(width: 10),

              // Name and status
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.receiverName,
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    isTyping ? 'Typing...' : (isOnline ? 'Online' : lastSeen),
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: isTyping ? FontStyle.italic : FontStyle.normal,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: Container(
          color: backgroundColor,
          child: Column(
            children: [
              if (!isConnected)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  color: Colors.grey.shade800,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        height: 14,
                        width: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Reconnecting...',
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              if (_isRecording)
                Container(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  color: Colors.red.withOpacity(0.1),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.mic, color: Colors.red, size: 20),
                      SizedBox(width: 8),
                      Text(
                        "Recording...",
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(width: 16),
                      Text(
                        '${_recordingDuration.inSeconds}s',
                        style: TextStyle(color: Colors.red),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    image: DecorationImage(
                      image: AssetImage('assets/bg_4.jpg'),
                      fit: BoxFit.cover,
                      opacity: 0.3,
                    ),
                  ),
                  child:
                      isLoading
                          ? Center(child: CircularProgressIndicator())
                          : messages.isEmpty
                          ? Center(child: Text('No messages yet'))
                          : ListView(
                            controller: _scrollController,
                            reverse: false,
                            children: _buildGroupedMessages(),
                          ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(8),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.add_box_outlined, color: Colors.grey),
                      onPressed: _showImageSourceOptions,
                    ),
                    /*                     IconButton(
                      icon: Icon(Icons.camera_alt, color: Colors.grey),
                      onPressed: () => _pickImage(ImageSource.camera),
                    ), */
                    SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              icon: Icon(
                                _isEmojiVisible
                                    ? Icons.keyboard
                                    : Icons.emoji_emotions_outlined,
                                color: Colors.grey,
                              ),
                              onPressed: _toggleEmojiKeyboard,
                            ),
                            /*                             SizedBox(width: 4),
 */
                            Expanded(
                              child: TextField(
                                controller: _messageController,
                                focusNode: _focusNode,
                                decoration: InputDecoration(
                                  hintText: 'Type a message...',
                                  border: InputBorder.none,
                                ),
                                onChanged: (text) {
                                  if (text.isNotEmpty) {
                                    _handleTyping(true);
                                  } else {
                                    _handleTyping(false);
                                  }
                                },
                                onSubmitted: (_) => sendMessage(),
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                _isRecording ? Icons.stop : Icons.mic,
                                color: _isRecording ? Colors.red : Colors.grey,
                              ),
                              onPressed:
                                  _isRecording
                                      ? _stopRecording
                                      : _startRecording,
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    CircleAvatar(
                      backgroundColor: Colors.green,
                      child: IconButton(
                        icon: Icon(Icons.send, color: Colors.white),
                        onPressed: sendMessage,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _manualDisconnect = true;
    updateUserStatus(false);
    socket.off('message_sent');
    socket.off('message_delivered');
    socket.off('message_read');
    socket.off('typing');
    socket.off('messages_read');
    socket.off('connect');
    socket.off('disconnect');
    socket.off('connect_error');
    socket.off('error');
    socket.off('receive_message');
    socket.off('reconnect_attempt');
    socket.disconnect();
    socket.close();
    _reconnectTimer?.cancel();

    _messageController.dispose();
    _typingTimer?.cancel();
    _statusTimer?.cancel();
    _secureClient.close();
    _progressStreamController.close();
    _selectedImage = null;
    _imageCaption = null;
    _focusNode.dispose();

    if (_isRecording) {
      _recorder.stopRecorder();
      _recorderSubscription?.cancel();
      setState(() => _isRecording = false);
    }
    _recorder.closeRecorder();
    _player.stopPlayer();
    _player.closePlayer();
    _recorderSubscription?.cancel();
    _selectedPdf = null;
    super.dispose();
  }
}
