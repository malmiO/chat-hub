import 'dart:async';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:slt_chat/config/config.dart';
import 'package:slt_chat/service/local_db_helper.dart';
import 'package:video_player/video_player.dart';
import 'dart:convert';

class VideoModule {
  static Future<void> pickAndUploadVideo({
    required BuildContext context,
    required String userId,
    required String receiverId,
    required Function(Map<String, dynamic>) onSend,
    required Function(int) onProgress,
    required Function(String) onError,
  }) async {
    try {
      // Request permissions
      PermissionStatus status;
      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        if (androidInfo.version.sdkInt >= 33) {
          status = await Permission.videos.request();
        } else {
          status = await Permission.storage.request();
        }
      } else {
        status = await Permission.videos.request();
      }

      if (status != PermissionStatus.granted) {
        if (status == PermissionStatus.permanentlyDenied) {
          _showPermissionSettingsDialog(context, 'Videos');
        } else {
          onError('Video gallery permission denied');
        }
        return;
      }

      // Pick video
      final pickedFile = await ImagePicker().pickVideo(
        source: ImageSource.gallery,
      );

      if (pickedFile == null) {
        onError('No video selected');
        return;
      }

      final videoFile = File(pickedFile.path);
      final tempId = DateTime.now().millisecondsSinceEpoch.toString();

      // Show preview and upload
      await _showVideoPreview(
        context: context,
        videoFile: videoFile,
        userId: userId,
        receiverId: receiverId,
        tempId: tempId,
        onSend: onSend,
        onProgress: onProgress,
        onError: onError,
      );
    } catch (e) {
      onError('Error picking video: $e');
    }
  }

  static void _showPermissionSettingsDialog(
    BuildContext context,
    String permissionType,
  ) {
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

  static Future<void> _showVideoPreview({
    required BuildContext context,
    required File videoFile,
    required String userId,
    required String receiverId,
    required String tempId,
    required Function(Map<String, dynamic>) onSend,
    required Function(int) onProgress,
    required Function(String) onError,
  }) async {
    VideoPlayerController? controller;
    bool isUploading = false;
    int uploadProgress = 0;

    try {
      controller = VideoPlayerController.file(videoFile)
        ..initialize().then((_) {});

      await showModalBottomSheet(
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
                                  controller?.dispose();
                                },
                              ),
                              Spacer(),
                              Text(
                                'Video Preview',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                ),
                              ),
                              Spacer(),
                              IconButton(
                                icon: Icon(Icons.send, color: Colors.blue),
                                onPressed:
                                    isUploading
                                        ? null
                                        : () async {
                                          setModalState(
                                            () => isUploading = true,
                                          );
                                          await _uploadVideo(
                                            context: context,
                                            videoFile: videoFile,
                                            userId: userId,
                                            receiverId: receiverId,
                                            tempId: tempId,
                                            onSend: onSend,
                                            onProgress: (progress) {
                                              setModalState(
                                                () => uploadProgress = progress,
                                              );
                                              onProgress(progress);
                                            },
                                            onError: onError,
                                          );
                                          setModalState(
                                            () => isUploading = false,
                                          );
                                          if (context.mounted)
                                            Navigator.pop(context);
                                        },
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Center(
                            child:
                                controller != null &&
                                        controller!.value.isInitialized
                                    ? AspectRatio(
                                      aspectRatio:
                                          controller!.value.aspectRatio,
                                      child: VideoPlayer(controller!),
                                    )
                                    : CircularProgressIndicator(),
                          ),
                        ),
                        if (isUploading) ...[
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
                      ],
                    ),
                  ),
            ),
      );
    } finally {
      controller?.dispose();
    }
  }

  static Future<void> _uploadVideo({
    required BuildContext context,
    required File videoFile,
    required String userId,
    required String receiverId,
    required String tempId,
    required Function(Map<String, dynamic>) onSend,
    required Function(int) onProgress,
    required Function(String) onError,
  }) async {
    try {
      // Save video to local storage
      final appDir = await getApplicationDocumentsDirectory();
      final videoDir = Directory('${appDir.path}/videos');
      if (!await videoDir.exists()) await videoDir.create();
      final localPath = '${videoDir.path}/${path.basename(videoFile.path)}';
      await videoFile.copy(localPath);

      final mimeType = 'video/mp4';
      final fileName = path.basename(videoFile.path);
      final length = await videoFile.length();

      final fileStream = videoFile.openRead().cast<List<int>>();
      int bytesSent = 0;

      final streamWithProgress = fileStream.transform<List<int>>(
        StreamTransformer.fromHandlers(
          handleData: (data, sink) {
            sink.add(data);
            bytesSent += data.length;
            final progress = (bytesSent / length * 100).clamp(0, 100).toInt();
            onProgress(progress);
          },
        ),
      );

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${AppConfig.baseUrl}/upload-video'),
      );

      final multipartFile = http.MultipartFile(
        'file',
        streamWithProgress,
        length,
        filename: fileName,
        contentType: MediaType.parse(mimeType),
      );

      request.files.add(multipartFile);
      request.fields['sender_id'] = userId;
      request.fields['receiver_id'] = receiverId;
      request.fields['temp_id'] = tempId;

      final response = await request.send();
      final responseData = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final jsonData = json.decode(responseData);
        final message = {
          'sender_id': userId,
          'receiver_id': receiverId,
          'is_video': true,
          'video_id': jsonData['video_id'],
          'temp_id': tempId,
          'timestamp': DateTime.now().toIso8601String(),
          'isMe': true,
          'read': false,
          'sent': true,
          'delivered': false,
          'filename': fileName,
          'local_video_path': localPath, // Store local path
        };

        // Update database with local path
        final localDB = LocalDBHelper();
        await localDB.saveMessage(message);
        await localDB.updateLocalVideoPath(tempId, localPath);

        onSend(message);
      } else {
        throw Exception('Failed to upload video: ${response.statusCode}');
      }
    } catch (e) {
      onError('Failed to send video: $e');
    }
  }
}
