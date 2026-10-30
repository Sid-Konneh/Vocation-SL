import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/app_theme.dart';
import '../models/models.dart';
import 'common.dart';
import 'document_viewer.dart';

/// An employer's job advert (PDF or photo). Photos show as a preview that
/// opens full screen with zoom; PDFs open in the app's PDF viewer.
/// [bytes] shows a file picked but not yet uploaded.
class JobAdvertView extends StatelessWidget {
  const JobAdvertView({super.key, this.url = '', this.bytes, this.fileName = '', this.maxHeight = 420});
  final String url;
  final Uint8List? bytes;
  final String fileName;
  final double maxHeight;

  bool get _isPdf => Job.isPdfAdvert(bytes != null ? fileName : url) || url.startsWith('data:application/pdf');

  ImageProvider? get _image {
    if (bytes != null) return MemoryImage(bytes!);
    if (url.startsWith('data:')) {
      try {
        return MemoryImage(base64Decode(url.substring(url.indexOf(',') + 1)));
      } catch (_) {
        return null;
      }
    }
    return url.isEmpty ? null : NetworkImage(url);
  }

  /// The PDF's bytes when it isn't uploaded yet (just picked, or demo mode).
  Uint8List? get _pdfBytes {
    if (bytes != null) return bytes;
    if (!url.startsWith('data:')) return null;
    try {
      return base64Decode(url.substring(url.indexOf(',') + 1));
    } catch (_) {
      return null;
    }
  }

  /// Opens the PDF inside the app, with a button to download it.
  void _openPdf(BuildContext context) {
    final data = _pdfBytes;
    final name = fileName.isNotEmpty ? fileName : 'Job advert.pdf';
    if (data != null) {
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Job advert')),
          body: PdfViewer.data(data, sourceName: name, params: PdfViewerParams(backgroundColor: context.palette.surface)),
        ),
      ));
      return;
    }
    if (url.isEmpty) return showSnack(context, 'Save the job first to open the PDF.', error: true);
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => DocumentViewerScreen(
        title: 'Job advert',
        fileName: name,
        format: DocumentFormat.pdf,
        loadUrl: () async => url,
        downloadUrl: _downloadUrl,
      ),
    ));
  }

  /// Supabase Storage sends a file as a download, not a page, when the
  /// address ends in `?download=` and a file name.
  static String _downloadUrl(String url) {
    final uri = Uri.parse(url);
    if (!uri.path.contains('/storage/v1/object/public/')) return url;
    return uri.replace(queryParameters: {...uri.queryParameters, 'download': 'Job advert.pdf'}).toString();
  }

  Future<void> _download(BuildContext context) async {
    final ok = await launchUrl(Uri.parse(_downloadUrl(url)), mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) showSnack(context, 'Couldn\'t download the PDF. Try again.', error: true);
  }

  void _openImage(BuildContext context, ImageProvider image) => showDialog<void>(
        context: context,
        builder: (d) => Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: Stack(children: [
            Positioned.fill(
              child: InteractiveViewer(maxScale: 5, child: Center(child: Image(image: image, fit: BoxFit.contain))),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: SafeArea(
                child: IconButton.filledTonal(tooltip: 'Close', onPressed: () => Navigator.pop(d), icon: const Icon(Icons.close_rounded)),
              ),
            ),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_isPdf) {
      return Card(
        child: ListTile(
          onTap: () => _openPdf(context),
          leading: const Icon(Icons.picture_as_pdf_rounded, color: AppColors.danger, size: 32),
          title: const Text('Job advert (PDF)'),
          subtitle: Text(fileName.isNotEmpty ? fileName : 'Tap to read the full advert'),
          // Only a saved advert has an address to download from.
          trailing: url.startsWith('http')
              ? IconButton(tooltip: 'Download PDF', icon: const Icon(Icons.download_rounded), onPressed: () => _download(context))
              : const Icon(Icons.chevron_right_rounded),
        ),
      );
    }
    final image = _image;
    if (image == null) return const SizedBox.shrink();
    return Semantics(
      button: true,
      label: 'Job advert image. Tap to view full screen',
      child: InkWell(
        onTap: () => _openImage(context, image),
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          child: Stack(children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: Image(
                image: image,
                width: double.infinity,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                errorBuilder: (_, _, _) => Container(
                  height: 120,
                  color: context.palette.border,
                  alignment: Alignment.center,
                  child: const Text('The advert image couldn\'t load. Pull down to refresh.'),
                ),
              ),
            ),
            Positioned(
              right: 10,
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.65), borderRadius: BorderRadius.circular(20)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.zoom_in_rounded, color: Colors.white, size: 18),
                  SizedBox(width: 4),
                  Text('Tap to enlarge', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
