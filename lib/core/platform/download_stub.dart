import 'dart:typed_data';

/// False outside the browser: use the share sheet instead.
const downloadSupported = false;

void downloadBytes(String fileName, Uint8List bytes, String mimeType) {}
