import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:io';

class PdfViewerScreen extends StatefulWidget {
  final String pdfUrl;
  final String filename;
  final String? localPdfPath;

  const PdfViewerScreen({
    Key? key,
    required this.pdfUrl,
    required this.filename,
    this.localPdfPath,
  }) : super(key: key);

  @override
  _PdfViewerScreenState createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  String? _localPath;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializePdf();
  }

  Future<bool> _isConnected() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    return connectivityResult.contains(ConnectivityResult.mobile) ||
        connectivityResult.contains(ConnectivityResult.wifi);
  }

  Future<void> _initializePdf() async {
    try {
      // Check if local PDF exists
      if (widget.localPdfPath != null &&
          await File(widget.localPdfPath!).exists()) {
        setState(() {
          _localPath = widget.localPdfPath;
          _isLoading = false;
        });
        return;
      }

      // Check connectivity before attempting download
      final isOnline = await _isConnected();
      if (!isOnline) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'No internet connection. PDF not available locally.';
        });
        return;
      }

      // Download PDF if online
      await _downloadAndSavePdf();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error loading PDF: $e';
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_errorMessage!)));
    }
  }

  Future<void> _downloadAndSavePdf() async {
    try {
      final response = await http.get(Uri.parse(widget.pdfUrl));
      if (response.statusCode == 200) {
        final dir = await getApplicationDocumentsDirectory();
        final pdfDir = Directory('${dir.path}/pdfs');
        if (!await pdfDir.exists()) await pdfDir.create();
        final file = File('${pdfDir.path}/${widget.filename}');
        await file.writeAsBytes(response.bodyBytes);
        setState(() {
          _localPath = file.path;
          _isLoading = false;
        });
      } else {
        throw Exception('Failed to download PDF: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error downloading PDF: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.filename)),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _localPath != null
              ? PDFView(
                filePath: _localPath!,
                enableSwipe: true,
                swipeHorizontal: false,
                autoSpacing: true,
                pageFling: true,
                onError: (error) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error rendering PDF: $error')),
                  );
                },
              )
              : Center(
                child: Text(
                  _errorMessage ?? 'Failed to load PDF',
                  style: const TextStyle(fontSize: 16, color: Colors.red),
                ),
              ),
    );
  }

  @override
  void dispose() {
    // Retain local PDF for offline access
    super.dispose();
  }
}
