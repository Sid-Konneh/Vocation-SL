import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../core/errors.dart';
import '../models/models.dart';
import 'image_resize.dart';

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
  static const maxSourcePhotoBytes = 15 * 1024 * 1024;
  /// Documents (CVs, cover letters, supporting documents) are PDF only, so
  /// every employer can open them on any phone or computer.
  static const documentExtensions = ['pdf'];

  /// Lets the user pick a PDF (CV, cover letter or supporting document). Returns null if cancelled.
  /// Throws [ValidationException] for the wrong type or an oversized file.
  Future<PickedFile?> pickDocument() async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Choose a PDF file',
      type: FileType.custom,
      allowedExtensions: documentExtensions,
    );
    if (file == null) return null;
    final format = DocumentFormat.fromFileName(file.name);
    if (format != DocumentFormat.pdf) throw const ValidationException('Only PDF files can be uploaded. Save or export your document as a PDF first.');
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) throw const ValidationException('That file is empty. Choose another one.');
    if (bytes.length > maxDocumentBytes) throw const ValidationException('Files must be 5 MB or smaller.');
    return PickedFile(name: file.name, bytes: bytes, format: format);
  }

  /// Lets the user pick a photo or logo and shrinks it to at most [maxSide]
  /// pixels, so large phone photos upload quickly and always fit storage limits.
  Future<PickedFile?> pickPhoto({String dialogTitle = 'Choose a profile photo', int maxSide = 512}) async {
    final file = await FilePicker.pickFile(dialogTitle: dialogTitle, type: FileType.image);
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) throw const ValidationException('That image is empty. Choose another one.');
    if (bytes.length > maxSourcePhotoBytes) throw const ValidationException('Choose an image smaller than 15 MB.');
    final small = ImageResize.shrink(bytes, maxSide: maxSide);
    if (small.bytes.length > maxPhotoBytes) throw const ValidationException('Photos must be 2 MB or smaller.');
    final base = file.name.contains('.') ? file.name.substring(0, file.name.lastIndexOf('.')) : file.name;
    return PickedFile(name: '$base.${small.extension}', bytes: small.bytes);
  }

  /// Lets an employer pick their job advert: a PDF, or a photo of a printed or
  /// newspaper advert. Photos are shrunk but kept large enough to read.
  Future<PickedFile?> pickJobAdvert() async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Choose the job advert (PDF or photo)',
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) throw const ValidationException('That file is empty. Choose another one.');
    if (DocumentFormat.fromFileName(file.name) == DocumentFormat.pdf) {
      if (bytes.length > maxDocumentBytes) throw const ValidationException('Files must be 5 MB or smaller.');
      return PickedFile(name: file.name, bytes: bytes, format: DocumentFormat.pdf);
    }
    if (bytes.length > maxSourcePhotoBytes) throw const ValidationException('Choose an image smaller than 15 MB.');
    final small = ImageResize.shrink(bytes, maxSide: 2000);
    if (small.bytes.length > maxDocumentBytes) throw const ValidationException('That photo is too large. Try a smaller one or a PDF.');
    final base = file.name.contains('.') ? file.name.substring(0, file.name.lastIndexOf('.')) : file.name;
    return PickedFile(name: '$base.${small.extension}', bytes: small.bytes);
  }
}
