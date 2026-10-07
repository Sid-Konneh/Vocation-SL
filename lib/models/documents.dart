/// CV/resume and cover letter models.
library;

enum DocumentFormat {
  pdf('PDF'),
  doc('DOC'),
  docx('DOCX');

  const DocumentFormat(this.label);
  final String label;

  static DocumentFormat? fromFileName(String name) {
    final ext = name.split('.').last.toLowerCase();
    return switch (ext) {
      'pdf' => DocumentFormat.pdf,
      'doc' => DocumentFormat.doc,
      'docx' => DocumentFormat.docx,
      _ => null,
    };
  }
}

class Resume {
  const Resume({
    required this.id,
    required this.fileName,
    required this.sizeBytes,
    required this.uploadedAt,
    required this.format,
    this.storagePath,
  });

  final String id;
  final String fileName;
  final int sizeBytes;
  final DateTime uploadedAt;
  final DocumentFormat format;

  /// Remote path (e.g. Supabase Storage key). Null for demo/local-only files.
  final String? storagePath;

  factory Resume.fromJson(Map<String, dynamic> j) => Resume(
        id: j['id'] as String,
        fileName: j['file_name'] as String,
        sizeBytes: (j['size_bytes'] as num?)?.toInt() ?? 0,
        uploadedAt: DateTime.parse(j['uploaded_at'] as String),
        format: DocumentFormat.values.firstWhere((f) => f.name == j['format'], orElse: () => DocumentFormat.pdf),
        storagePath: j['storage_path'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'file_name': fileName,
        'size_bytes': sizeBytes,
        'uploaded_at': uploadedAt.toIso8601String(),
        'format': format.name,
        'storage_path': storagePath,
      };
}

enum CoverLetterKind { uploaded, written }

class CoverLetter {
  const CoverLetter({
    required this.id,
    required this.kind,
    this.fileName,
    this.sizeBytes,
    this.format,
    this.text,
    this.storagePath,
  });

  final String id;
  final CoverLetterKind kind;
  final String? fileName;
  final int? sizeBytes;
  final DocumentFormat? format;
  final String? text;
  final String? storagePath;

  String get displayName => kind == CoverLetterKind.uploaded ? (fileName ?? 'Cover letter') : 'Written cover letter';

  factory CoverLetter.fromJson(Map<String, dynamic> j) => CoverLetter(
        id: j['id'] as String,
        kind: j['kind'] == 'uploaded' ? CoverLetterKind.uploaded : CoverLetterKind.written,
        fileName: j['file_name'] as String?,
        sizeBytes: (j['size_bytes'] as num?)?.toInt(),
        format: j['format'] == null
            ? null
            : DocumentFormat.values.firstWhere((f) => f.name == j['format'], orElse: () => DocumentFormat.pdf),
        text: j['text'] as String?,
        storagePath: j['storage_path'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'file_name': fileName,
        'size_bytes': sizeBytes,
        'format': format?.name,
        'text': text,
        'storage_path': storagePath,
      };
}
