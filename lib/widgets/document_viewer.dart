import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/app_theme.dart';
import '../models/models.dart';
import 'common.dart';
import 'skeletons.dart';
import 'states.dart';

/// Opens a CV or cover letter inside the app. PDFs are shown in place;
/// Word files can't be rendered in the app, so they get a download button.
Future<void> viewDocument(
  BuildContext context, {
  required String title,
  required String fileName,
  required DocumentFormat? format,
  required String? storagePath,
  required Future<String> Function(String storagePath) loadUrl,
}) async {
  if (storagePath == null || storagePath.isEmpty) {
    showSnack(context, 'This file was attached in demo mode and can\'t be opened.', error: true);
    return;
  }
  await Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => DocumentViewerScreen(
      title: title,
      fileName: fileName,
      format: format ?? DocumentFormat.fromFileName(fileName) ?? DocumentFormat.pdf,
      loadUrl: () => loadUrl(storagePath),
    ),
  ));
}

class DocumentViewerScreen extends StatefulWidget {
  const DocumentViewerScreen({super.key, required this.title, required this.fileName, required this.format, required this.loadUrl});
  final String title;
  final String fileName;
  final DocumentFormat format;
  final Future<String> Function() loadUrl;

  @override
  State<DocumentViewerScreen> createState() => _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends State<DocumentViewerScreen> {
  late Future<String> _url = widget.loadUrl();

  Future<void> _download(String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) showSnack(context, 'Couldn\'t open the file.', error: true);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
        future: _url,
        builder: (context, snap) {
          final url = snap.data;
          return Scaffold(
            appBar: AppBar(
              title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.title),
                Text(widget.fileName, style: context.text.bodySmall?.copyWith(color: context.palette.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
              actions: [
                if (url != null)
                  IconButton(tooltip: 'Download or open outside the app', icon: const Icon(Icons.download_rounded), onPressed: () => _download(url)),
              ],
            ),
            body: switch (snap) {
              AsyncSnapshot(hasError: true) => ErrorState(error: snap.error!, onRetry: () => setState(() => _url = widget.loadUrl())),
              AsyncSnapshot(hasData: false) => const DocumentSkeleton(),
              _ when widget.format == DocumentFormat.pdf => PdfViewer.uri(
                  Uri.parse(url!),
                  params: PdfViewerParams(
                    backgroundColor: context.palette.surface,
                    loadingBannerBuilder: (context, bytesDownloaded, totalBytes) => const DocumentSkeleton(),
                    errorBannerBuilder: (context, error, stackTrace, documentRef) => _Fallback(
                      message: 'This PDF couldn\'t be displayed in the app.',
                      onDownload: () => _download(url),
                    ),
                  ),
                ),
              _ => _Fallback(
                  message: '${widget.format.label} files can\'t be previewed in the app. Download the file to read it.',
                  onDownload: () => _download(url!),
                ),
            },
          );
        },
      );
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.message, required this.onDownload});
  final String message;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.description_outlined, size: 56, color: context.palette.muted),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: context.text.bodyLarge),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: onDownload, icon: const Icon(Icons.download_rounded), label: const Text('Download file')),
          ]),
        ),
      );
}
