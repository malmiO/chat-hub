import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:dio/dio.dart' as http hide MultipartFile;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as path;
import 'package:photo_view/photo_view.dart';
import 'package:socket_io_client/socket_io_client.dart' as socket_io;
import 'package:intl/intl.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '/common/widgets/colors.dart';
import '/config/config.dart';
import '/Features/Groups/group_info_screen.dart';
import '/Features/Groups/group_localDB.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class GroupChatScreen extends StatefulWidget {
  final String userId;
  final String groupId;
  final String groupName;
  final String groupProfilePic;

  const GroupChatScreen({
    super.key,
    required this.userId,
    required this.groupId,
    required this.groupName,
    required this.groupProfilePic,
  });

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  // Constants
  static const _voiceMimeType = 'audio/aac';
  static const _voiceCodec = Codec.aacADTS;
  static const _voiceSampleRate = 44100;
  static const _voiceBitRate = 128000;
  static const _tempIdPrefix = 'temp-';
  static const _retryIdPrefix = 'retry-';

  // Controllers and state
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  final Set<String> _processedMessageIds = {};
  final LocalDatabase _localDb = LocalDatabase();

  List<Map<String, dynamic>> _messages = [];
  late socket_io.Socket _socket;
  late IOClient _httpClient;

  bool _isLoading = true;
  bool _isRecording = false;
  bool _isPlaying = false;
  bool _isRecorderInitialized = false;
  bool _isPermissionRequestInProgress = false;
  bool _isConnected = false;

  String? _typingUser;
  String? _currentlyPlayingUrl;
  String? _audioPath;
  String? _adminName;
  Map<String, dynamic>? _groupDetails;

  bool _isEmojiVisible = false;
  FocusNode _focusNode = FocusNode();
  Duration _recordingDuration = Duration.zero;
  StreamSubscription<RecordingDisposition>? _recorderSubscription;

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  List<Map<String, dynamic>> _pendingMessages = [];

  final Map<String, http.CancelToken> _uploadCancelTokens = {};

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _handleConnectivityChange,
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _checkInitialConnection(),
    );
  }

  Future<void> _initializeServices() async {
    await _localDb.initDatabase();
    _initializeHttpClient();
    _initializeRecorder();
    _initializePlayer();
    _fetchGroupDetails();
    await _loadLocalMessages(); // Load local messages first
    setState(() => _isLoading = false);
    _fetchMessages(); // Then fetch from server
    _connectSocket();
  }

  @override
  void dispose() {
    _recorderSubscription?.cancel();
    _focusNode.dispose();
    _recorder.closeRecorder();
    _player.closePlayer();
    _localDb.close();
    _httpClient.close();
    _socket.emit('leave_group', {'group_id': widget.groupId});
    _socket.disconnect();
    _socket.off('receive_group_message');
    _messageController.dispose();
    _scrollController.dispose();
    _connectivitySubscription?.cancel();

    for (var token in _uploadCancelTokens.values) {
      token.cancel();
    }
    _uploadCancelTokens.clear();

    super.dispose();
  }

  void _sortMessagesByTime() {
    _messages.sort((a, b) {
      final aTime = DateTime.tryParse(a['timestamp'] ?? '') ?? DateTime.now();
      final bTime = DateTime.tryParse(b['timestamp'] ?? '') ?? DateTime.now();
      return aTime.compareTo(bTime);
    });
  }

  void _toggleEmojiKeyboard() {
    if (_isEmojiVisible) {
      _focusNode.requestFocus();
    } else {
      _focusNode.unfocus();
    }
    setState(() => _isEmojiVisible = !_isEmojiVisible);
  }

  void _initializeHttpClient() {
    final client = HttpClient()..badCertificateCallback = (_, __, ___) => true;
    _httpClient = IOClient(client);
  }

  Future<void> _checkInitialConnection() async {
    final results = await _connectivity.checkConnectivity();
    final isConnected =
        results.isNotEmpty &&
        results.any((result) => result != ConnectivityResult.none);
    setState(() => _isConnected = isConnected);
    if (isConnected) {
      _processPendingMessages();
    }
  }

  void _handleConnectivityChange(List<ConnectivityResult> results) {
    final isConnected =
        results.isNotEmpty &&
        results.any((result) => result != ConnectivityResult.none);
    setState(() => _isConnected = isConnected);
    if (isConnected) {
      _processPendingMessages();
    }
  }

  Future<void> _processPendingMessages() async {
    try {
      _pendingMessages = await _localDb.getPendingMessages();

      for (var msg in _pendingMessages) {
        final type = msg['type'];
        final tempId = msg['tempId'];
        final filePath = msg['filePath'];
        final content = msg['content'];

        await _localDb.updateMessageStatus(tempId: tempId, status: 'sending');

        switch (type) {
          case 'text':
            await _resendTextMessage(content, tempId);
            break;
          case 'image':
            await _uploadImage(filePath, tempId);
            break;
          case 'voice':
            await _uploadVoiceMessage(filePath, tempId);
            break;
          case 'video':
            await _uploadVideo(filePath, tempId);
            break;
          case 'pdf':
            await _uploadPdf(filePath, tempId);
            break;
        }
      }
    } catch (e) {
      print('Error processing pending messages: $e');
    }
  }

  Future<void> _resendTextMessage(String message, String tempId) async {
    if (!_isConnected) return;

    try {
      _socket.emit('send_group_message', {
        'sender_id': widget.userId,
        'group_id': widget.groupId,
        'message': message,
        'type': 'text',
        'tempId': tempId,
      });
      await _fetchMessages(); // Fetch updates after sending
    } catch (e) {
      await _localDb.updateMessageStatus(tempId: tempId, status: 'failed');
    }
  }

  Future<void> _initializeRecorder() async {
    if (_isPermissionRequestInProgress) return;

    try {
      _isPermissionRequestInProgress = true;
      final status = await Permission.microphone.request();

      if (status != PermissionStatus.granted) {
        _showSnackBar('Microphone permission denied');
        return;
      }

      await _recorder.openRecorder();
      _isRecorderInitialized = true;
    } catch (e) {
      _showSnackBar('Failed to initialize recorder: $e');
    } finally {
      _isPermissionRequestInProgress = false;
    }
  }

  Future<void> _initializePlayer() async {
    try {
      await _player.openPlayer();
    } catch (e) {
      _showSnackBar('Failed to initialize player: $e');
    }
  }

  // Media handling
  Future<void> _startRecording() async {
    if (!_isRecorderInitialized) {
      await _initializeRecorder();
      if (!_isRecorderInitialized) return;
    }

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final voiceDir = Directory('${appDir.path}/voice_messages');
      if (!await voiceDir.exists()) await voiceDir.create(recursive: true);

      _audioPath =
          '${voiceDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.aac';
      await _recorder.startRecorder(
        toFile: _audioPath!,
        codec: _voiceCodec,
        sampleRate: _voiceSampleRate,
        bitRate: _voiceBitRate,
      );
      setState(() {
        _isRecording = true;
        _recordingDuration = Duration.zero;
      });
      _recorderSubscription = _recorder.onProgress!.listen((event) {
        if (mounted) {
          setState(() => _recordingDuration = event.duration);
        }
      });
    } catch (e) {
      _showSnackBar('Failed to start recording: $e');
    }
  }

  Future<void> _stopRecording() async {
    try {
      await _recorder.stopRecorder();
      if (_audioPath != null) await _saveAndSendVoiceMessage(_audioPath!);
      _recorderSubscription?.cancel();
      setState(() {
        _isRecording = false;
        _recordingDuration = Duration.zero;
      });
    } catch (e) {
      _showSnackBar('Failed to stop recording: $e');
    }
  }

  Future<void> _saveAndSendVoiceMessage(String filePath) async {
    try {
      final tempId = '$_tempIdPrefix${DateTime.now().millisecondsSinceEpoch}';
      final status = _isConnected ? 'uploading' : 'pending';

      // Save to local storage first
      await _localDb.insertMediaMessage(
        filePath: filePath,
        content: filePath,
        type: 'voice',
        isMe: 1,
        status: status,
        createdAt: DateTime.now().toIso8601String(),
        tempId: tempId,
        groupId: widget.groupId,
      );

      setState(() {
        _messages.add({
          '_id': tempId,
          'tempId': tempId,
          'sender_id': widget.userId,
          'sender': {'name': 'You', 'id': widget.userId},
          'group_id': widget.groupId,
          'voice_url': filePath,
          'type': 'voice',
          'status': status,
          'timestamp': DateTime.now().toIso8601String(),
          'read_by': [widget.userId],
        });
        _sortMessagesByTime();
      });

      _scrollToBottom();

      if (_isConnected) {
        await _uploadVoiceMessage(filePath, tempId);
      } else {
        _showSnackBar('Voice message saved offline. Will send when connected');
      }
    } catch (e) {
      _showSnackBar('Error saving voice message: $e');
    }
  }

  Future<void> _uploadVoiceMessage(String filePath, String tempId) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        await _updateVoiceMessageStatus(
          tempId: tempId,
          status: 'failed',
          error: 'File not found',
        );
        return;
      }

      final bytes = await file.readAsBytes();
      final fileName = path.basename(filePath);

      final request =
          http.MultipartRequest(
              'POST',
              Uri.parse('${AppConfig.baseUrl}/upload-group-voice'),
            )
            ..fields['sender_id'] = widget.userId
            ..fields['group_id'] = widget.groupId
            ..fields['temp_id'] = tempId
            ..files.add(
              http.MultipartFile.fromBytes(
                'file',
                bytes,
                filename: fileName,
                contentType: MediaType.parse(_voiceMimeType),
              ),
            );

      final response = await request.send();
      final responseData = await response.stream.bytesToString();
      final jsonResponse = json.decode(responseData);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        await _updateVoiceMessageStatus(
          tempId: tempId,
          status: 'success',
          voiceUrl: jsonResponse['voice_url'],
        );
        await _fetchMessages(); // Fetch updates after upload
      } else {
        throw Exception('Upload failed: ${jsonResponse['error']}');
      }
    } catch (e) {
      await _updateVoiceMessageStatus(
        tempId: tempId,
        status: 'failed',
        error: e.toString(),
      );
    }
  }

  Future<void> _updateVoiceMessageStatus({
    required String tempId,
    required String status,
    String? voiceUrl,
    String? error,
  }) async {
    try {
      await _localDb.updateMessageStatus(
        tempId: tempId,
        status: status,
        content: voiceUrl ?? '',
      );

      final index = _messages.indexWhere((msg) => msg['tempId'] == tempId);
      if (index != -1) {
        setState(() {
          _messages[index] = {
            ..._messages[index],
            'status': status,
            if (voiceUrl != null) 'voice_url': _getFullUrl(voiceUrl),
          };
        });
      }

      if (status == 'success') {
        _showSnackBar('Voice message uploaded successfully');
      } else if (status == 'failed') {
        _showSnackBar('Upload failed: ${error ?? 'Unknown error'}');
      }
    } catch (e) {
      _showSnackBar('Error updating message status: $e');
    }
  }

  Future<void> _retryVoiceMessage(String filePath, String messageId) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        _showSnackBar('Audio file no longer exists');
        return;
      }

      setState(() {
        final index = _messages.indexWhere((msg) => msg['_id'] == messageId);
        if (index != -1) {
          _messages[index]['status'] = 'uploading';
        }
      });

      final tempId = '$_retryIdPrefix${DateTime.now().millisecondsSinceEpoch}';

      await _localDb.updateMessageByGroup(
        tempId: messageId,
        groupId: widget.groupId,
        values: {'status': 'uploading', 'tempId': tempId},
      );

      setState(() {
        final index = _messages.indexWhere((msg) => msg['_id'] == messageId);
        if (index != -1) {
          _messages[index]['_id'] = tempId;
          _messages[index]['tempId'] = tempId;
        }
      });

      await _uploadVoiceMessage(filePath, tempId);
    } catch (e) {
      _showSnackBar('Error retrying voice message: $e');
    }
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(source: source);
      if (image == null) return;

      final tempId = '$_tempIdPrefix${DateTime.now().millisecondsSinceEpoch}';
      final filePath = image.path;
      final status = _isConnected ? 'uploading' : 'pending';

      // Save to local storage first
      await _localDb.insertMediaMessage(
        filePath: filePath,
        content: filePath,
        type: 'image',
        isMe: 1,
        status: status,
        createdAt: DateTime.now().toIso8601String(),
        tempId: tempId,
        groupId: widget.groupId,
      );

      setState(() {
        _messages.add({
          '_id': tempId,
          'tempId': tempId,
          'sender_id': widget.userId,
          'sender': {'name': 'You', 'id': widget.userId},
          'group_id': widget.groupId,
          'image_url': filePath,
          'type': 'image',
          'status': status,
          'timestamp': DateTime.now().toIso8601String(),
          'read_by': [widget.userId],
        });
        _sortMessagesByTime();
      });

      _scrollToBottom();

      if (_isConnected) {
        await _uploadImage(filePath, tempId);
      } else {
        _showSnackBar('Image saved offline. Will send when connected');
      }
    } catch (e) {
      _showSnackBar('Error picking image: $e');
    }
  }

  Future<void> _uploadImage(String filePath, String tempId) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        await _updateImageStatus(
          tempId: tempId,
          status: 'failed',
          error: 'File not found',
        );
        return;
      }

      final bytes = await file.readAsBytes();
      final fileName = path.basename(filePath);
      final mimeType = lookupMimeType(filePath) ?? 'image/jpeg';

      final request =
          http.MultipartRequest(
              'POST',
              Uri.parse('${AppConfig.baseUrl}/upload-group-image'),
            )
            ..fields['sender_id'] = widget.userId
            ..fields['group_id'] = widget.groupId
            ..fields['temp_id'] = tempId
            ..files.add(
              http.MultipartFile.fromBytes(
                'file',
                bytes,
                filename: fileName,
                contentType: MediaType.parse(mimeType),
              ),
            );

      final response = await request.send();
      final responseData = await response.stream.bytesToString();
      final jsonResponse = json.decode(responseData);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        await _updateImageStatus(
          tempId: tempId,
          status: 'success',
          imageUrl: jsonResponse['image_url'],
        );
        await _fetchMessages(); // Fetch updates after upload
      } else {
        throw Exception('Upload failed: ${jsonResponse['error']}');
      }
    } catch (e) {
      await _updateImageStatus(
        tempId: tempId,
        status: 'failed',
        error: e.toString(),
      );
    }
  }

  Future<void> _updateImageStatus({
    required String tempId,
    required String status,
    String? imageUrl,
    String? error,
  }) async {
    try {
      await _localDb.updateMessageStatus(
        tempId: tempId,
        status: status,
        content: imageUrl ?? '',
      );

      final index = _messages.indexWhere((msg) => msg['tempId'] == tempId);
      if (index != -1) {
        setState(() {
          _messages[index] = {
            ..._messages[index],
            'status': status,
            if (imageUrl != null) 'image_url': _getFullUrl(imageUrl),
          };
        });
      }

      if (status == 'success') {
        _showSnackBar('Image uploaded successfully');
      } else if (status == 'failed') {
        _showSnackBar('Upload failed: ${error ?? 'Unknown error'}');
      }
    } catch (e) {
      _showSnackBar('Error updating image status: $e');
    }
  }

  Future<void> _retryImage(String filePath, String messageId) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        _showSnackBar('Image file no longer exists');
        return;
      }

      setState(() {
        final index = _messages.indexWhere((msg) => msg['_id'] == messageId);
        if (index != -1) {
          _messages[index]['status'] = 'uploading';
        }
      });

      final tempId = '$_retryIdPrefix${DateTime.now().millisecondsSinceEpoch}';

      await _localDb.updateMessageByGroup(
        tempId: messageId,
        groupId: widget.groupId,
        values: {'status': 'uploading', 'tempId': tempId},
      );

      setState(() {
        final index = _messages.indexWhere((msg) => msg['_id'] == messageId);
        if (index != -1) {
          _messages[index]['_id'] = tempId;
          _messages[index]['tempId'] = tempId;
        }
      });

      await _uploadImage(filePath, tempId);
    } catch (e) {
      _showSnackBar('Error retrying image: $e');
    }
  }

  // PDF Handling
  Future<void> _pickAndSendPdf() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result == null || result.files.isEmpty) return;

      final filePath = result.files.single.path!;
      final file = File(filePath);
      final fileName = path.basename(filePath);

      final appDir = await getApplicationDocumentsDirectory();
      final pdfDir = Directory('${appDir.path}/pdfs');
      if (!await pdfDir.exists()) await pdfDir.create();
      final localPath = '${pdfDir.path}/$fileName';
      await file.copy(localPath);

      await _showPdfPreview(filePath, localPath, fileName);
    } catch (e) {
      _showSnackBar('Error picking PDF: $e');
    }
  }

  Future<void> _showPdfPreview(
    String filePath,
    String localPath,
    String fileName,
  ) async {
    bool isUploading = false;
    int uploadProgress = 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (BuildContext context) => StatefulBuilder(
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
                            bottom: BorderSide(color: Colors.grey.shade800),
                          ),
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              icon: Icon(Icons.close, color: Colors.white),
                              onPressed: () => Navigator.pop(context),
                            ),
                            Expanded(
                              child: Text(
                                'PDF Preview',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.send,
                                color: isUploading ? Colors.grey : Colors.blue,
                              ),
                              onPressed:
                                  isUploading
                                      ? null
                                      : () async {
                                        setModalState(() {
                                          isUploading = true;
                                        });
                                        Navigator.pop(context);
                                        await _uploadAndSendPdf(
                                          filePath,
                                          localPath,
                                          fileName,
                                          onProgress: (progress) {
                                            setModalState(() {
                                              uploadProgress = progress;
                                            });
                                          },
                                        );
                                      },
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: SfPdfViewer.file(
                          File(localPath),
                          controller: PdfViewerController(),
                          onDocumentLoaded: (details) {
                            print("PDF preview loaded successfully");
                          },
                          onDocumentLoadFailed: (details) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Failed to load PDF preview'),
                              ),
                            );
                          },
                        ),
                      ),
                      if (isUploading)
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Column(
                            children: [
                              LinearProgressIndicator(
                                value: uploadProgress / 100,
                                backgroundColor: Colors.grey[800],
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.blue,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Uploading ${uploadProgress.toStringAsFixed(0)}%',
                                style: TextStyle(color: Colors.white),
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

  Future<void> _uploadPdf(
    String localPath,
    String tempId, {
    Function(int)? onProgress,
  }) async {
    final cancelToken = http.CancelToken();
    _uploadCancelTokens[tempId] = cancelToken;

    try {
      final file = File(localPath);
      if (!await file.exists()) {
        await _updatePdfStatus(
          tempId: tempId,
          status: 'failed',
          error: 'File not found',
        );
        return;
      }

      final length = await file.length();
      final fileStream = file.openRead().cast<List<int>>();
      int bytesSent = 0;

      final streamWithProgress = fileStream.transform<List<int>>(
        StreamTransformer.fromHandlers(
          handleData: (data, sink) {
            sink.add(data);
            bytesSent += data.length;
            final progress = (bytesSent / length * 100).clamp(0, 100).toInt();
            if (onProgress != null) onProgress(progress);
          },
        ),
      );

      final fileName = path.basename(localPath);
      final mimeType = 'application/pdf';

      final request =
          http.MultipartRequest(
              'POST',
              Uri.parse('${AppConfig.baseUrl}/upload-group-pdf'),
            )
            ..fields['sender_id'] = widget.userId
            ..fields['group_id'] = widget.groupId
            ..fields['temp_id'] = tempId
            ..fields['create_dirs'] = 'true'
            ..files.add(
              http.MultipartFile(
                'file',
                streamWithProgress,
                length,
                filename: fileName,
                contentType: MediaType.parse(mimeType),
              ),
            );

      final response = await request.send().timeout(
        Duration(seconds: 30),
        onTimeout: () {
          cancelToken.cancel();
          throw TimeoutException('Upload timed out');
        },
      );
      final responseData = await response.stream.bytesToString();
      final jsonResponse = json.decode(responseData);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        await _updatePdfStatus(
          tempId: tempId,
          status: 'success',
          pdfUrl:
              '${AppConfig.baseUrl}/get-group-pdf/${jsonResponse['pdf_id']}',
        );
        await _fetchMessages(); // Fetch updates after upload
      } else {
        throw Exception('Upload failed: ${jsonResponse['error']}');
      }
    } catch (e) {
      await _updatePdfStatus(
        tempId: tempId,
        status: 'failed',
        error: e.toString(),
      );
    } finally {
      _uploadCancelTokens.remove(tempId);
    }
  }

  Future<void> _uploadAndSendPdf(
    String filePath,
    String localPath,
    String fileName, {
    Function(int)? onProgress,
  }) async {
    try {
      final tempId = '$_tempIdPrefix${DateTime.now().millisecondsSinceEpoch}';
      final status = _isConnected ? 'uploading' : 'pending';

      // Save to local storage first
      await _localDb.insertMediaMessage(
        filePath: localPath,
        content: '',
        type: 'pdf',
        isMe: 1,
        status: status,
        createdAt: DateTime.now().toIso8601String(),
        tempId: tempId,
        groupId: widget.groupId,
      );

      if (mounted) {
        setState(() {
          _messages.add({
            '_id': tempId,
            'tempId': tempId,
            'sender_id': widget.userId,
            'sender': {'name': 'You', 'id': widget.userId},
            'group_id': widget.groupId,
            'pdf_url': localPath,
            'type': 'pdf',
            'status': status,
            'timestamp': DateTime.now().toIso8601String(),
            'read_by': [widget.userId],
            'filename': fileName,
          });
          _sortMessagesByTime();
        });
      }

      _scrollToBottom();

      if (_isConnected) {
        await _uploadPdf(localPath, tempId, onProgress: onProgress);
      } else {
        _showSnackBar('PDF saved offline. Will send when connected');
      }
    } catch (e) {
      _showSnackBar('Error sending PDF: $e');
    }
  }

  Future<void> _updatePdfStatus({
    required String tempId,
    required String status,
    String? pdfUrl,
    String? error,
  }) async {
    try {
      await _localDb.updateMessageStatus(
        tempId: tempId,
        status: status,
        content: pdfUrl ?? '',
      );

      if (mounted) {
        setState(() {
          final index = _messages.indexWhere((msg) => msg['tempId'] == tempId);
          if (index != -1) {
            _messages[index] = {
              ..._messages[index],
              'status': status,
              if (pdfUrl != null) 'pdf_url': pdfUrl,
            };
          }
        });
      }

      if (status == 'success') {
        _showSnackBar('PDF uploaded successfully');
      } else if (status == 'failed') {
        _showSnackBar('Error uploading PDF: $error');
      }
    } catch (e) {
      _showSnackBar('Error updating PDF status: $e');
    }
  }

  Future<void> _retryPdf(String filePath, String messageId) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        _showSnackBar('PDF file no longer exists');
        return;
      }

      if (mounted) {
        setState(() {
          final index = _messages.indexWhere((msg) => msg['_id'] == messageId);
          if (index != -1) {
            _messages[index]['status'] = 'uploading';
          }
        });
      }

      final tempId = '$_retryIdPrefix${DateTime.now().millisecondsSinceEpoch}';

      await _localDb.updateMessageByGroup(
        tempId: messageId,
        groupId: widget.groupId,
        values: {'status': 'uploading', 'tempId': tempId},
      );

      if (mounted) {
        setState(() {
          final index = _messages.indexWhere((msg) => msg['_id'] == messageId);
          if (index != -1) {
            _messages[index]['_id'] = tempId;
            _messages[index]['tempId'] = tempId;
          }
        });
      }

      await _uploadPdf(filePath, tempId);
    } catch (e) {
      _showSnackBar('Error retrying PDF: $e');
    }
  }

  Future<void> _showImageSourceOptions() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder:
          (context) => Container(
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Upload media',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                  Divider(color: Colors.grey),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildMediaOption(
                          icon: Icons.insert_photo,
                          label: 'Gallery',
                          color: Colors.purple,
                          onTap: () => _pickAndSendImage(ImageSource.gallery),
                        ),
                        _buildMediaOption(
                          icon: Icons.camera_alt,
                          label: 'Camera',
                          color: Colors.red,
                          onTap: () => _pickAndSendImage(ImageSource.camera),
                        ),
                        _buildMediaOption(
                          icon: Icons.picture_as_pdf,
                          label: 'Document',
                          color: Colors.blue,
                          onTap: () => _futureimplementDocumentUpload(),
                        ),
                        _buildMediaOption(
                          icon: Icons.videocam,
                          label: 'Video',
                          color: Colors.green,
                          onTap: () => _pickAndSendVideo(ImageSource.gallery),
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

  //still need to implement document upload feature to the group chat
  Future<void> _futureimplementDocumentUpload() async {
    _showSnackBar('Document upload feature is not implemented yet.');
  }

  Widget _buildMediaOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
      child: Column(
        children: [
          Icon(icon, color: color ?? Colors.white, size: 30),
          SizedBox(height: 4),
          Text(label, style: TextStyle(color: Colors.white)),
        ],
      ),
    );
  }

  // Socket handling
  void _connectSocket() {
    try {
      _socket = socket_io.io(AppConfig.baseUrl, {
        'transports': ['websocket'],
        'autoConnect': true,
        'forceNew': true,
      });

      _socket
        ..onConnect((_) {
          setState(() => _isConnected = true);
          _joinGroup();
        })
        ..onDisconnect((_) => setState(() => _isConnected = false))
        ..on('receive_group_message', _handleIncomingMessage)
        ..on('join_confirmation', _handleJoinConfirmation)
        ..on('group_deleted', _handleGroupDeleted)
        ..on('messages_read_group', (data) {
          final messageId = data['message_id'];
          final readerId = data['reader_id'];

          setState(() {
            final index = _messages.indexWhere(
              (msg) => msg['_id'] == messageId,
            );
            if (index != -1) {
              final GroupingreadBy = List<String>.from(
                _messages[index]['read_by'] ?? [],
              )..add(readerId);
              _messages[index]['read_by'] = GroupingreadBy;
            }
          });
          _localDb.saveMessages(
            _messages,
            widget.groupId,
          ); // Save updated read status
        })
        ..connect();
    } catch (e) {
      _showSnackBar('Socket connection error: $e');
    }
  }

  void _joinGroup() {
    _socket.emit('join_group', {
      'group_id': widget.groupId,
      'user_id': widget.userId,
    });
  }

  void _handleIncomingMessage(dynamic data) {
    if (!mounted) return;

    final messageId = data['_id']?.toString();
    if (messageId == null) return;

    if (!_messages.any((msg) => msg['_id'] == messageId)) {
      setState(() {
        if (data['type'] == 'image') {
          data['image_url'] = _getFullUrl(data['image_url']);
        } else if (data['type'] == 'voice') {
          data['voice_url'] = _getFullUrl(data['voice_url']);
        } else if (data['type'] == 'video') {
          data['video_url'] = _getFullUrl(data['video_url']);
        } else if (data['type'] == 'pdf') {
          data['pdf_url'] = _getFullUrl(data['pdf_url']);
        }
        _messages.add(Map<String, dynamic>.from(data));
        _sortMessagesByTime();
      });
      _scrollToBottom();

      // Save to local storage
      _localDb.saveMessages(_messages, widget.groupId);

      if (data['sender_id'] != widget.userId &&
          !(data['read_by']?.contains(widget.userId) ?? false)) {
        _markMessagesAsRead([messageId]);
      }
    } else {
      final tempId = data['temp_id'];
      if (tempId != null) {
        final index = _messages.indexWhere((msg) => msg['tempId'] == tempId);
        if (index != -1) {
          setState(() {
            _messages[index] = Map<String, dynamic>.from(data);
            if (data['type'] == 'video') {
              _messages[index]['video_url'] = _getFullUrl(data['video_url']);
            }
          });
          _localDb.saveMessages(
            _messages,
            widget.groupId,
          ); // Update local storage
        }
      }

      if (data['type'] == 'text' && tempId != null) {
        _localDb.updateMessageStatus(
          tempId: tempId,
          status: 'success',
          content: data['message'],
        );
      }
    }
  }

  void _handleJoinConfirmation(dynamic data) {
    if (data['status'] != 'success') {
      _showSnackBar('Failed to join group: ${data['message']}');
    }
  }

  void _handleGroupDeleted(dynamic data) {
    if (data['group_id'] == widget.groupId) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      _showSnackBar(data['message']);
    }
  }

  // Message handling
  Future<void> _sendMessage() async {
    final messageText = _messageController.text.trim();
    if (messageText.isEmpty) return;

    try {
      final tempId = '$_tempIdPrefix${DateTime.now().millisecondsSinceEpoch}';
      final status = _isConnected ? 'sending' : 'pending';

      // Save to local storage first
      await _localDb.insertMediaMessage(
        filePath: '',
        content: messageText,
        type: 'text',
        isMe: 1,
        status: status,
        createdAt: DateTime.now().toIso8601String(),
        tempId: tempId,
        groupId: widget.groupId,
      );

      setState(() {
        _messages.add({
          '_id': tempId,
          'tempId': tempId,
          'sender_id': widget.userId,
          'sender': {'name': 'You', 'id': widget.userId},
          'group_id': widget.groupId,
          'message': messageText,
          'timestamp': DateTime.now().toIso8601String(),
          'read_by': [widget.userId],
          'type': 'text',
          'status': status,
        });
        _sortMessagesByTime();
      });

      _scrollToBottom();
      _messageController.clear();

      if (_isConnected) {
        _socket.emit('send_group_message', {
          'sender_id': widget.userId,
          'group_id': widget.groupId,
          'message': messageText,
          'type': 'text',
          'tempId': tempId,
        });
        await _fetchMessages(); // Fetch updates after sending
      } else {
        _showSnackBar('Message saved offline. Will send when connected');
      }
    } catch (e) {
      _showSnackBar('Error sending message: $e');
    }
  }

  // Data fetching
  Future<void> _fetchGroupDetails() async {
    try {
      final response = await _httpClient.get(
        Uri.parse('${AppConfig.baseUrl}/group/${widget.groupId}'),
      );

      if (response.statusCode == 200) {
        setState(() => _groupDetails = json.decode(response.body));
        if (_groupDetails?['admins']?.isNotEmpty == true) {
          await _fetchAdminName(_groupDetails!['admins'][0]);
        }
      }
    } catch (e) {
      _showSnackBar('Failed to fetch group details: $e');
    }
  }

  Future<void> _fetchAdminName(String adminId) async {
    try {
      final response = await _httpClient.get(
        Uri.parse('${AppConfig.baseUrl}/user/$adminId'),
      );

      setState(() {
        _adminName =
            response.statusCode == 200
                ? json.decode(response.body)['name']
                : 'Unknown';
      });
    } catch (e) {
      setState(() => _adminName = 'Unknown');
    }
  }

  Future<void> _fetchMessages() async {
    try {
      final response = await _httpClient.get(
        Uri.parse('${AppConfig.baseUrl}/group-messages/${widget.groupId}'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final serverMessages = _processServerMessages(data['messages']);
        final localMessages = await _localDb.getMessages(widget.groupId);
        final mergedMessages = _mergeMessages(serverMessages, localMessages);

        final messagesToMarkRead =
            mergedMessages
                .where(
                  (msg) =>
                      msg['sender_id'] != widget.userId &&
                      !(msg['read_by']?.contains(widget.userId) ?? false),
                )
                .map((msg) => msg['_id'].toString())
                .toList();

        setState(() {
          _messages = mergedMessages;
        });
        _scrollToBottom();

        // Save fetched data to local storage
        await _localDb.saveMessages(_messages, widget.groupId);

        await _markMessagesAsRead(messagesToMarkRead);
      } else {
        await _loadLocalMessages();
      }
    } catch (e) {
      await _loadLocalMessages();
    }
  }

  List<Map<String, dynamic>> _processServerMessages(List<dynamic> messages) {
    return messages.map((msg) {
      if (msg['type'] == 'voice' && !msg['voice_url'].startsWith('http')) {
        msg['voice_url'] = '${AppConfig.baseUrl}${msg['voice_url']}';
      }
      if (msg['type'] == 'image' && !msg['image_url'].startsWith('http')) {
        msg['image_url'] = '${AppConfig.baseUrl}${msg['image_url']}';
      }
      if (msg['type'] == 'video' && !msg['video_url'].startsWith('http')) {
        msg['video_url'] = '${AppConfig.baseUrl}${msg['video_url']}';
      }
      if (msg['type'] == 'pdf' && !msg['pdf_url'].startsWith('http')) {
        msg['pdf_url'] = '${AppConfig.baseUrl}${msg['pdf_url']}';
      }
      if (msg['type'] == 'text' && msg['content'] != null) {
        msg['message'] = msg['content'];
      }
      msg['type'] = msg['type'] ?? 'text';
      return Map<String, dynamic>.from(msg);
    }).toList();
  }

  List<Map<String, dynamic>> _mergeMessages(
    List<Map<String, dynamic>> serverMessages,
    List<Map<String, dynamic>> localMessages,
  ) {
    final mergedMessages = <Map<String, dynamic>>[];

    for (final serverMsg in serverMessages) {
      final tempId = serverMsg['temp_id']?.toString();
      final localMatch = localMessages.firstWhere(
        (localMsg) =>
            localMsg['tempId'] == tempId &&
            localMsg['groupId'] == widget.groupId,
        orElse: () => {},
      );

      if (localMatch.isNotEmpty) {
        mergedMessages.add({
          ...serverMsg,
          'status': localMatch['status'],
          'filePath': localMatch['filePath'],
        });
      } else {
        mergedMessages.add(serverMsg);
      }
    }

    for (final localMsg in localMessages) {
      if (localMsg['status'] == 'uploading' ||
          localMsg['status'] == 'failed' ||
          localMsg['status'] == 'pending') {
        final existsInServer = serverMessages.any(
          (serverMsg) => serverMsg['temp_id'] == localMsg['tempId'],
        );

        if (!existsInServer) {
          mergedMessages.add({
            '_id': localMsg['tempId'],
            'sender_id': widget.userId,
            'sender': {'name': 'You', 'id': widget.userId},
            'group_id': widget.groupId,
            'voice_url':
                localMsg['type'] == 'voice' ? localMsg['filePath'] : null,
            'image_url':
                localMsg['type'] == 'image' ? localMsg['filePath'] : null,
            'video_url':
                localMsg['type'] == 'video' ? localMsg['filePath'] : null,
            'pdf_url': localMsg['type'] == 'pdf' ? localMsg['filePath'] : null,
            'message': localMsg['type'] == 'text' ? localMsg['content'] : null,
            'timestamp': localMsg['createdAt'],
            'read_by': [widget.userId],
            'type': localMsg['type'],
            'status': localMsg['status'],
            'tempId': localMsg['tempId'],
          });
        }
      }
    }

    return mergedMessages;
  }

  Future<void> _loadLocalMessages() async {
    final localMessages = await _localDb.getMessages(widget.groupId);
    setState(() {
      _messages =
          localMessages
              .map(
                (msg) => {
                  '_id': msg['messageId'] ?? msg['tempId'],
                  'tempId': msg['tempId'],
                  'sender_id': msg['senderId'],
                  'sender': {'name': 'You', 'id': widget.userId},
                  'group_id': msg['groupId'],
                  'type': msg['type'],
                  if (msg['type'] == 'text') 'message': msg['content'],
                  if (msg['type'] == 'image')
                    'image_url': msg['mediaUrl'] ?? msg['filePath'],
                  if (msg['type'] == 'voice')
                    'voice_url': msg['mediaUrl'] ?? msg['filePath'],
                  if (msg['type'] == 'video')
                    'video_url': msg['mediaUrl'] ?? msg['filePath'],
                  if (msg['type'] == 'pdf')
                    'pdf_url': msg['mediaUrl'] ?? msg['filePath'],
                  'timestamp': msg['timestamp'],
                  'read_by': json.decode(msg['readBy'] ?? '[]'),
                  'status': msg['status'],
                },
              )
              .toList();
      _isLoading = false;
    });
  }

  // UI helpers
  String _getFullUrl(String url) {
    return url.startsWith('http')
        ? url
        : '${AppConfig.baseUrl}/${url.startsWith('/') ? url.substring(1) : url}';
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  List<Widget> _buildGroupedMessages() {
    if (_messages.isEmpty) return [Center(child: Text('No messages yet'))];

    final Map<String, List<Map<String, dynamic>>> groupedMessages = {};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(Duration(days: 1));

    for (var message in _messages) {
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
        messageGroup.map((msg) {
          final isMe = msg['sender_id'] == widget.userId;
          return _buildMessageBubble(msg, isMe);
        }).toList(),
      );
    });

    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: _buildAppBar(),
      body: SafeArea(
        child: Column(
          children: [
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
                    _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : ListView(
                          controller: _scrollController,
                          reverse: false,
                          children: [
                            _buildChatHeader(),
                            ..._buildGroupedMessages(),
                          ],
                        ),
              ),
            ),
            _buildMessageInput(),
          ],
        ),
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: backgroundColor,
      iconTheme: const IconThemeData(color: Colors.white),
      title: GestureDetector(
        onTap: _navigateToGroupInfo,
        child: Row(
          children: [
            ClipOval(
              child: CachedNetworkImage(
                imageUrl:
                    widget.groupProfilePic != "default"
                        ? widget.groupProfilePic
                        : 'assets/user-2.png',
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
                        widget.groupName[0],
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                fit: BoxFit.cover,
                width: 40,
                height: 40,
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.groupName,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  _groupDetails != null
                      ? '${_groupDetails!['members'].length} members'
                      : 'Loading...',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.info_outline, color: Colors.white),
          onPressed: _navigateToGroupInfo,
        ),
      ],
    );
  }

  ImageProvider _getGroupProfileImage() {
    return widget.groupProfilePic != "default"
        ? NetworkImage(widget.groupProfilePic)
        : const AssetImage('assets/users.png') as ImageProvider;
  }

  Future<void> _navigateToGroupInfo() async {
    if (_groupDetails == null) return;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => GroupInfoScreen(
              groupId: widget.groupId,
              userId: widget.userId,
              groupDetails: _groupDetails!,
              onGroupImageUpdated: (newImageUrl) async {
                setState(() {});
                await _fetchGroupDetails();
                EventBus().fire(
                  GroupImageUpdatedEvent(
                    groupId: widget.groupId,
                    newImageUrl: newImageUrl,
                  ),
                );
              },
            ),
      ),
    );

    if (result == true) {
      await _fetchGroupDetails();
    }
  }

  Widget _buildChatHeader() {
    if (_groupDetails == null || _adminName == null) {
      return const SizedBox.shrink();
    }

    final createdAt = DateTime.parse(_groupDetails!['created_at']).toLocal();
    final formattedDate = DateFormat('MMM d, yyyy').format(createdAt);
    final isAdmin = _groupDetails!['admins'].contains(widget.userId);
    final adminDisplayName = isAdmin ? 'You' : _adminName;

    return Container(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(radius: 40, backgroundImage: _getGroupProfileImage()),
          const SizedBox(height: 12),
          Text(
            widget.groupName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Admin: $adminDisplayName',
            style: TextStyle(color: Colors.grey[400], fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            _groupDetails!['description'] ?? 'No description provided',
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 14,
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Created on: $formattedDate',
            style: TextStyle(color: Colors.grey[400], fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Divider(color: Colors.grey[600]),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> message, bool isMe) {
    final sender = (message['sender'] ?? {}) as Map<String, dynamic>;
    final readBy = List<String>.from(message['read_by'] ?? []);
    final type = message['type'] ?? 'text';
    final isImage = type == 'image';
    final isVoice = type == 'voice';
    final isVideo = type == 'video';
    final isPdf = type == 'pdf';
    final imageUrl = message['image_url'];
    final voiceUrl = message['voice_url'];
    final videoUrl = message['video_url'];
    final pdfUrl = message['pdf_url'];
    final status = message['status'] ?? 'success';
    final fileName = message['filename'];

    return GestureDetector(
      onLongPress: () {},
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
                    if (!isMe)
                      Text(
                        sender['name']?.toString() ?? 'Unknown',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    if (isPdf)
                      Column(
                        children: [
                          GestureDetector(
                            onTap: () => _viewPdf(pdfUrl, message['filePath']),
                            child: Container(
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.6,
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
                                      fileName ?? 'document.pdf',
                                      style: TextStyle(color: Colors.black),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (status == 'uploading')
                            Text(
                              'Uploading...',
                              style: TextStyle(color: Colors.grey),
                            ),
                          if (status == 'failed' && isMe)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Failed',
                                  style: TextStyle(color: Colors.red),
                                ),
                                IconButton(
                                  icon: Icon(Icons.refresh, color: Colors.red),
                                  onPressed:
                                      () => _retryPdf(
                                        message['filePath'] ?? pdfUrl,
                                        message['_id'],
                                      ),
                                ),
                              ],
                            ),
                        ],
                      )
                    else if (isImage)
                      Stack(
                        children: [
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder:
                                      (context) => Scaffold(
                                        appBar: AppBar(
                                          backgroundColor: Colors.black,
                                          iconTheme: IconThemeData(
                                            color: Colors.white,
                                          ),
                                        ),
                                        body: Center(
                                          child: PhotoView(
                                            imageProvider:
                                                CachedNetworkImageProvider(
                                                  imageUrl,
                                                ),
                                            minScale:
                                                PhotoViewComputedScale
                                                    .contained,
                                            maxScale:
                                                PhotoViewComputedScale.covered *
                                                2,
                                          ),
                                        ),
                                      ),
                                ),
                              );
                            },
                            child: Container(
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.6,
                                maxHeight: 300,
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: _buildImageWidget(imageUrl),
                              ),
                            ),
                          ),
                          if (status == 'uploading')
                            Positioned.fill(
                              child: Center(child: CircularProgressIndicator()),
                            ),
                          if (status == 'failed' && isMe)
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: IconButton(
                                icon: Icon(Icons.refresh, color: Colors.red),
                                onPressed:
                                    () => _retryImage(
                                      message['filePath'] ?? imageUrl,
                                      message['_id'],
                                    ),
                              ),
                            ),
                        ],
                      )
                    else if (isVoice)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (status == 'uploading')
                            CircularProgressIndicator()
                          else
                            IconButton(
                              icon: Icon(
                                _isPlaying && _currentlyPlayingUrl == voiceUrl
                                    ? Icons.stop
                                    : Icons.play_arrow,
                                color: Colors.black,
                              ),
                              onPressed:
                                  status == 'success'
                                      ? () => _playVoiceMessage(voiceUrl)
                                      : null,
                            ),
                          if (status == 'failed' && isMe)
                            IconButton(
                              icon: Icon(Icons.refresh, color: Colors.red),
                              onPressed:
                                  () => _retryVoiceMessage(
                                    voiceUrl,
                                    message['_id'],
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
                      Stack(
                        children: [
                          GestureDetector(
                            onTap: () => _playVideo(videoUrl),
                            child: Container(
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.6,
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
                                      fileName ?? 'video.mp4',
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
                          ),
                          if (status == 'uploading')
                            Positioned.fill(
                              child: Center(child: CircularProgressIndicator()),
                            ),
                          if (status == 'failed' && isMe)
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: IconButton(
                                icon: Icon(Icons.refresh, color: Colors.red),
                                onPressed:
                                    () => _retryVideo(
                                      message['filePath'] ?? videoUrl,
                                      message['_id'],
                                    ),
                              ),
                            ),
                        ],
                      )
                    else
                      Text(
                        message['message'] ?? '',
                        style: TextStyle(color: Colors.black),
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
                          if (status == 'sending')
                            Icon(
                              Icons.access_time,
                              size: 12,
                              color: Colors.grey,
                            ),
                          if (status == 'failed')
                            Icon(Icons.error, size: 12, color: Colors.red),
                          if (status == 'success')
                            Icon(
                              readBy.length > 1 ? Icons.done_all : Icons.done,
                              size: 12,
                              color:
                                  readBy.length > 1 ? Colors.blue : Colors.grey,
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

  Widget _buildImageWidget(String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) {
      return const Icon(Icons.broken_image, color: Colors.red, size: 50);
    }

    if (!imageUrl.startsWith('http')) {
      final file = File(imageUrl);
      return FutureBuilder<bool>(
        future: file.exists(),
        builder: (context, snapshot) {
          if (snapshot.data == true) {
            return Image.file(
              file,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return const Icon(
                  Icons.broken_image,
                  color: Colors.red,
                  size: 50,
                );
              },
            );
          } else {
            return const Icon(Icons.file_present, color: Colors.grey, size: 50);
          }
        },
      );
    }

    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      placeholder: (context, url) => CircularProgressIndicator(),
      errorWidget:
          (context, url, error) =>
              const Icon(Icons.broken_image, color: Colors.red, size: 50),
    );
  }

  Future<Uint8List> _getVideoThumbnail(String videoUrl) async {
    final fileName = await VideoThumbnail.thumbnailFile(
      video: videoUrl,
      thumbnailPath: (await getTemporaryDirectory()).path,
      imageFormat: ImageFormat.JPEG,
      maxHeight: 100,
      quality: 75,
    );

    final file = File(fileName!);
    return file.readAsBytesSync();
  }

  Future<void> _playVoiceMessage(String url) async {
    try {
      if (_isPlaying) {
        await _player.stopPlayer();
        setState(() {
          _isPlaying = false;
          _currentlyPlayingUrl = null;
        });
        return;
      }

      await _player.startPlayer(
        fromURI: url,
        codec: Codec.aacADTS,
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
    } catch (e) {
      _showSnackBar('Failed to play voice message: $e');
    }
  }

  Future<void> _viewPdf(String? pdfUrl, String? localPath) async {
    if (pdfUrl == null && localPath == null) {
      _showSnackBar('Invalid PDF URL or path');
      return;
    }

    final effectiveUrl =
        localPath != null && File(localPath).existsSync() ? localPath : pdfUrl;

    if (effectiveUrl == null) {
      _showSnackBar('PDF not available');
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => PdfViewerScreen(
              pdfUrl: effectiveUrl.startsWith('http') ? effectiveUrl : null,
              localPdfPath:
                  effectiveUrl.startsWith('http') ? null : effectiveUrl,
            ),
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: EdgeInsets.all(8),
      color: backgroundColor,
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.add_box_outlined, color: Colors.grey),
            onPressed: _showImageSourceOptions,
          ),
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
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      focusNode: _focusNode,
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _isRecording ? Icons.stop : Icons.mic,
                      color: _isRecording ? Colors.red : Colors.grey,
                    ),
                    onPressed: _isRecording ? _stopRecording : _startRecording,
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
              onPressed: _sendMessage,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndSendVideo(ImageSource source) async {
    try {
      final XFile? video = await _picker.pickVideo(source: source);
      if (video == null) return;

      final filePath = video.path;
      final extension = path.extension(filePath).toLowerCase();

      if (extension != '.mp4' && extension != '.mov') {
        _showSnackBar('Only MP4 and MOV are supported');
        return;
      }

      final tempId = '$_tempIdPrefix${DateTime.now().millisecondsSinceEpoch}';
      final status = _isConnected ? 'uploading' : 'pending';

      // Save to local storage first
      await _localDb.insertMediaMessage(
        filePath: filePath,
        content: filePath,
        type: 'video',
        isMe: 1,
        status: status,
        createdAt: DateTime.now().toIso8601String(),
        tempId: tempId,
        groupId: widget.groupId,
      );

      setState(() {
        _messages.add({
          '_id': tempId,
          'tempId': tempId,
          'sender_id': widget.userId,
          'sender': {'name': 'You', 'id': widget.userId},
          'group_id': widget.groupId,
          'video_url': filePath,
          'type': 'video',
          'status': status,
          'timestamp': DateTime.now().toIso8601String(),
          'read_by': [widget.userId],
        });
        _sortMessagesByTime();
      });

      _scrollToBottom();

      if (_isConnected) {
        await _uploadVideo(filePath, tempId);
      } else {
        _showSnackBar('Video saved offline. Will send when connected');
      }
    } catch (e) {
      _showSnackBar('Error picking video: $e');
    }
  }

  Future<void> _uploadVideo(String filePath, String tempId) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        await _updateVideoStatus(
          tempId: tempId,
          status: 'failed',
          error: 'File not found',
        );
        return;
      }

      final bytes = await file.readAsBytes();
      final fileName = path.basename(filePath);
      final mimeType = lookupMimeType(filePath) ?? 'video/mp4';

      final request =
          http.MultipartRequest(
              'POST',
              Uri.parse('${AppConfig.baseUrl}/upload-group-video'),
            )
            ..fields['sender_id'] = widget.userId
            ..fields['group_id'] = widget.groupId
            ..fields['temp_id'] = tempId
            ..files.add(
              http.MultipartFile.fromBytes(
                'file',
                bytes,
                filename: fileName,
                contentType: MediaType.parse(mimeType),
              ),
            );

      final response = await request.send();
      final responseData = await response.stream.bytesToString();
      final jsonResponse = json.decode(responseData);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        await _updateVideoStatus(
          tempId: tempId,
          status: 'success',
          videoUrl: jsonResponse['video_url'],
        );
        await _fetchMessages(); // Fetch updates after upload
      } else {
        throw Exception('Upload failed: ${jsonResponse['error']}');
      }
    } catch (e) {
      await _updateVideoStatus(
        tempId: tempId,
        status: 'failed',
        error: e.toString(),
      );
    }
  }

  Future<void> _updateVideoStatus({
    required String tempId,
    required String status,
    String? videoUrl,
    String? error,
  }) async {
    try {
      await _localDb.updateMessageStatus(
        tempId: tempId,
        status: status,
        content: videoUrl,
      );

      final index = _messages.indexWhere((msg) => msg['tempId'] == tempId);
      if (index != -1) {
        setState(() {
          _messages[index] = {
            ..._messages[index],
            'status': status,
            if (videoUrl != null) 'video_url': _getFullUrl(videoUrl),
          };
        });
      }

      if (status == 'success') {
        _showSnackBar('Video uploaded successfully');
      } else if (status == 'failed') {
        _showSnackBar('Upload failed: ${error ?? 'Unknown error'}');
      }
    } catch (e) {
      _showSnackBar('Error updating video status: $e');
    }
  }

  Future<void> _retryVideo(String filePath, String messageId) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        _showSnackBar('Video file no longer exists');
        return;
      }

      setState(() {
        final index = _messages.indexWhere((msg) => msg['_id'] == messageId);
        if (index != -1) {
          _messages[index]['status'] = 'uploading';
        }
      });

      final tempId = '$_retryIdPrefix${DateTime.now().millisecondsSinceEpoch}';

      await _localDb.updateMessageByGroup(
        tempId: messageId,
        groupId: widget.groupId,
        values: {'status': 'uploading', 'tempId': tempId},
      );

      setState(() {
        final index = _messages.indexWhere((msg) => msg['_id'] == messageId);
        if (index != -1) {
          _messages[index]['_id'] = tempId;
          _messages[index]['tempId'] = tempId;
        }
      });

      await _uploadVideo(filePath, tempId);
    } catch (e) {
      _showSnackBar('Error retrying video: $e');
    }
  }

  Future<void> _playVideo(String? videoUrl) async {
    if (videoUrl == null || videoUrl.isEmpty) {
      _showSnackBar('Invalid video URL');
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoPlayerScreen(videoUrl: videoUrl),
      ),
    );
  }

  Future<void> _markMessagesAsRead(List<String> messageIds) async {
    try {
      final response = await _httpClient.post(
        Uri.parse(
          '${AppConfig.baseUrl}/mark-group-messages-read/${widget.groupId}/${widget.userId}',
        ),
      );

      if (response.statusCode == 200) {
        setState(() {
          for (var msg in _messages) {
            if (msg['sender_id'] != widget.userId &&
                !(msg['read_by']?.contains(widget.userId) ?? false)) {
              final readBy = List<String>.from(msg['read_by'] ?? [])
                ..add(widget.userId);
              msg['read_by'] = readBy;
            }
          }
        });
        _localDb.saveMessages(
          _messages,
          widget.groupId,
        ); // Save updated read status
      } else {
        _showSnackBar('Failed to mark messages as read');
      }
    } catch (e) {
      _showSnackBar('Error marking messages as read: $e');
    }
  }
}

// Event Bus and other classes remain unchanged
class EventBus {
  static final EventBus _instance = EventBus._internal();
  factory EventBus() => _instance;
  EventBus._internal();

  final _controller = StreamController<dynamic>.broadcast();

  Stream<T> on<T>() {
    return _controller.stream.where((event) => event is T).cast<T>();
  }

  void fire(dynamic event) {
    _controller.add(event);
  }
}

class GroupImageUpdatedEvent {
  final String groupId;
  final String newImageUrl;

  GroupImageUpdatedEvent({required this.groupId, required this.newImageUrl});
}

class VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;

  const VideoPlayerScreen({super.key, required this.videoUrl});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _controller;
  Future<void>? _initializeVideoPlayerFuture;
  bool _isPlaying = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initializeController();
  }

  void _initializeController() {
    _controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.videoUrl),
      videoPlayerOptions: VideoPlayerOptions(
        allowBackgroundPlayback: false,
        mixWithOthers: true,
      ),
    );

    _initializeVideoPlayerFuture = _controller
        .initialize()
        .then((_) {
          if (mounted) {
            setState(() {
              _controller.addListener(_videoListener);
              _controller.setLooping(false);
            });
          }
        })
        .catchError((error) {
          if (mounted) {
            setState(() => _hasError = true);
          }
        });
  }

  void _videoListener() {
    if (mounted) {
      setState(() => _isPlaying = _controller.value.isPlaying);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child:
            _hasError
                ? _buildErrorWidget()
                : FutureBuilder(
                  future: _initializeVideoPlayerFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.done) {
                      return AspectRatio(
                        aspectRatio: _controller.value.aspectRatio,
                        child: VideoPlayer(_controller),
                      );
                    }
                    return const CircularProgressIndicator();
                  },
                ),
      ),
      floatingActionButton:
          _hasError
              ? null
              : FloatingActionButton(
                onPressed: _togglePlayPause,
                child: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
              ),
    );
  }

  Widget _buildErrorWidget() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.error_outline, color: Colors.red, size: 50),
        const SizedBox(height: 20),
        const Text(
          'Failed to load video',
          style: TextStyle(color: Colors.white),
        ),
        const SizedBox(height: 20),
        ElevatedButton(onPressed: _retryVideo, child: const Text('Retry')),
      ],
    );
  }

  void _togglePlayPause() {
    setState(() {
      if (_controller.value.isPlaying) {
        _controller.pause();
      } else {
        _controller.play();
      }
      _isPlaying = _controller.value.isPlaying;
    });
  }

  void _retryVideo() {
    setState(() {
      _hasError = false;
      _controller.dispose();
      _initializeController();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class PdfViewerScreen extends StatefulWidget {
  final String? pdfUrl;
  final String? localPdfPath;

  const PdfViewerScreen({super.key, this.pdfUrl, this.localPdfPath});

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  late PdfViewerController _pdfController;
  bool _isLoading = true;
  bool _hasError = false;
  String? _effectiveLocalPdfPath;

  @override
  void initState() {
    super.initState();
    _pdfController = PdfViewerController();
    _effectiveLocalPdfPath = widget.localPdfPath;
    _loadPdf();
  }

  Future<void> _loadPdf() async {
    try {
      if (_effectiveLocalPdfPath != null &&
          File(_effectiveLocalPdfPath!).existsSync()) {
        setState(() => _isLoading = false);
      } else if (widget.pdfUrl != null) {
        final response = await http.get(Uri.parse(widget.pdfUrl!));
        if (response.statusCode == 200) {
          final appDir = await getApplicationDocumentsDirectory();
          final pdfDir = Directory('${appDir.path}/pdfs');
          if (!await pdfDir.exists()) await pdfDir.create();
          final fileName = path.basename(widget.pdfUrl!);
          final localPath = '${pdfDir.path}/$fileName';
          await File(localPath).writeAsBytes(response.bodyBytes);
          setState(() {
            _effectiveLocalPdfPath = localPath;
            _isLoading = false;
          });
        } else {
          throw Exception('Failed to download PDF');
        }
      } else {
        throw Exception('No valid PDF source');
      }
    } catch (e) {
      setState(() {
        _hasError = true;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('PDF Viewer', style: TextStyle(color: Colors.white)),
      ),
      body: _buildPdfView(),
    );
  }

  Widget _buildPdfView() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_hasError) {
      return const Center(
        child: Text(
          'Failed to load PDF',
          style: TextStyle(color: Colors.white),
        ),
      );
    }

    return SfPdfViewer.file(
      File(_effectiveLocalPdfPath!),
      controller: _pdfController,
      onDocumentLoaded: (details) {
        print("PDF loaded successfully");
      },
      onDocumentLoadFailed: (details) {
        setState(() => _hasError = true);
      },
    );
  }

  @override
  void dispose() {
    _pdfController.dispose();
    super.dispose();
  }
}
