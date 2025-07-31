import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

class DocumentPreviewScreen extends StatelessWidget {
  final PlatformFile file;
  final Function() onSend;

  const DocumentPreviewScreen({
    Key? key,
    required this.file,
    required this.onSend,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Preview Document')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.insert_drive_file, size: 80, color: Colors.blue),
            SizedBox(height: 20),
            Text(file.name, style: TextStyle(fontSize: 18)),
            SizedBox(height: 10),
            Text('${(file.size / 1024).toStringAsFixed(2)} KB'),
            SizedBox(height: 30),
            ElevatedButton(
              onPressed: onSend,
              child: Text('Send Document'),
            ),
          ],
        ),
      ),
    );
  }
  
}