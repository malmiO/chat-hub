import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as path;
import 'package:slt_chat/config/config.dart';
import 'dart:convert';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:slt_chat/service/local_db_helper.dart';

class PdfModule {
  static Future<void> pickAndUploadPdf({
    required BuildContext context,
    required String userId,
    required String receiverId,
    required Function(Map<String, dynamic>) onSend,
    required Function(int) onProgress,
    required Function(String) onError,
  }) async {
    try {
      final androidInfo = await DeviceInfoPlugin().androidInfo;

      if (Platform.isAndroid && androidInfo.version.sdkInt < 33) {
        final status = await Permission.storage.request();
        if (!status.isGranted) {
          if (status.isPermanentlyDenied) {
            _showPermissionSettingsDialog(context, 'Storage');
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Storage permission denied')),
            );
          }
          return;
        }
      }

      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result != null && result.files.single.path != null) {
        File pdfFile = File(result.files.single.path!);
        await _showPdfPreview(
          context,
          pdfFile,
          userId,
          receiverId,
          onSend,
          onProgress,
          onError,
        );
      }
    } catch (e) {
      onError('Error picking PDF: $e');
    }
  }

  static Future<void> _showPdfPreview(
    BuildContext context,
    File pdfFile,
    String userId,
    String receiverId,
    Function(Map<String, dynamic>) onSend,
    Function(int) onProgress,
    Function(String) onError,
  ) async {
    bool isUploading = false;
    int uploadProgress = 0;

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
                              onPressed: () => Navigator.pop(context),
                            ),
                            Spacer(),
                            Text(
                              'PDF Preview',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                              ),
                            ),
                            Spacer(),
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
                                        await _uploadPdf(
                                          context: context,
                                          pdfFile: pdfFile,
                                          userId: userId,
                                          receiverId: receiverId,
                                          onSend: onSend,
                                          onProgress: (progress) {
                                            setModalState(() {
                                              uploadProgress = progress;
                                            });
                                          },
                                          onError: (error) {
                                            onError(error);
                                            setModalState(() {
                                              isUploading = false;
                                            });
                                          },
                                        );
                                        if (isUploading) {
                                          Navigator.pop(context);
                                        }
                                      },
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            'PDF: ${path.basename(pdfFile.path)}',
                            style: TextStyle(color: Colors.white, fontSize: 16),
                          ),
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
  }

  static Future<void> _uploadPdf({
    required BuildContext context,
    required File pdfFile,
    required String userId,
    required String receiverId,
    required Function(Map<String, dynamic>) onSend,
    required Function(int) onProgress,
    required Function(String) onError,
  }) async {
    try {
      // Save PDF to local storage
      final appDir = await getApplicationDocumentsDirectory();
      final pdfDir = Directory('${appDir.path}/pdfs');
      if (!await pdfDir.exists()) await pdfDir.create();
      final localPath = '${pdfDir.path}/${path.basename(pdfFile.path)}';
      await pdfFile.copy(localPath);

      final mimeType = 'application/pdf';
      final fileName = path.basename(pdfFile.path);
      final length = await pdfFile.length();
      final tempId = DateTime.now().millisecondsSinceEpoch.toString();

      final fileStream = pdfFile.openRead().cast<List<int>>();
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
        Uri.parse('${AppConfig.baseUrl}/upload-pdf'),
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
          'is_pdf': true,
          'pdf_id': jsonData['pdf_id'],
          'temp_id': tempId,
          'isMe': true,
          'timestamp': DateTime.now().toIso8601String(),
          'read': false,
          'sent': true,
          'delivered': false,
          'filename': fileName,
          'local_pdf_path': localPath,
        };

        // Update database with local path
        final localDB = LocalDBHelper();
        await localDB.saveMessage(message);
        await localDB.updateLocalPdfPath(tempId, localPath);

        onSend(message);
      } else {
        throw Exception('Failed to upload PDF: ${response.statusCode}');
      }
    } catch (e) {
      onError('Failed to send PDF: $e');
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
}
