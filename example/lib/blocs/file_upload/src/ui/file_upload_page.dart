import 'package:flutter/material.dart';

import 'file_upload_widget.dart';

class FileUploadPage extends StatelessWidget {
  const FileUploadPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Submit Form'),
      ),
      body: const FileUploadWidget(),
    );
  }
}
