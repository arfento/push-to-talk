import 'package:flutter/material.dart';

class FileTransferDialog extends StatefulWidget {
  final String fileName;
  final int fileSize;
  final bool isSending;

  const FileTransferDialog({
    required this.fileName,
    required this.fileSize,
    required this.isSending,
  });

  @override
  _FileTransferDialogState createState() => _FileTransferDialogState();
}

class _FileTransferDialogState extends State<FileTransferDialog> {
  int _transferredBytes = 0;
  double get _progress => _transferredBytes / widget.fileSize;

  void updateProgress(int bytes) {
    if (mounted) {
      setState(() {
        _transferredBytes = bytes;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isSending ? 'Sending File' : 'Receiving File'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.fileName),
          SizedBox(height: 16),
          LinearProgressIndicator(value: _progress),
          SizedBox(height: 8),
          Text('${(_progress * 100).toStringAsFixed(1)}%'),
          Text('$_transferredBytes / ${widget.fileSize} bytes'),
        ],
      ),
    );
  }
}
