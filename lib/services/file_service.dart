import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../core/errors.dart';
import '../models/models.dart';

class PickedFile {
  const PickedFile({required this.name, required this.bytes, this.format});
  final String name;
  final Uint8List bytes;
  final DocumentFormat? format;
  int get size => bytes.length;
}

/// Wraps the platform file picker and validates documents.
class FileService {
  static const maxDocumentBytes = 5 * 1024 * 1024;
  static const maxPhotoBytes = 2 * 1024 * 1024;
  static const documentExtensions = ['pdf', 'doc', 'docx'];

  /// Lets the user pick a CV or cover letter. Returns null if cancelled.
  /// Throws [ValidationException] for the wrong type or an oversized file.
  Future<PickedFile?> pickDocument() async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Choose a PDF or Word document',
      type: FileType.custom,
      allowedExtensions: documentExtensions,
    );
    if (file == null) return null;
    final format = DocumentFormat.fromFileName(file.name);
    if (format == null) throw const ValidationException('Choose a PDF, DOC or DOCX file.');
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) throw const ValidationException('That file is empty. Choose another one.');
    if (bytes.length > maxDocumentBytes) throw const ValidationException('Files must be 5 MB or smaller.');
    return PickedFile(name: file.name, bytes: bytes, format: format);
  }

  Future<PickedFile?> pickPhoto() async {
    final file = await FilePicker.pickFile(dialogTitle: 'Choose a profile photo', type: FileType.image);
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    if (bytes.length > maxPhotoBytes) throw const ValidationException('Photos must be 2 MB or smaller.');
    return PickedFile(name: file.name, bytes: bytes);
  }
}
