import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/supabase_service.dart';
import '../utils/theme_provider.dart';
import '../widgets/common.dart' show SubjectBadge, SemesterBadge, showAppSnackbar;

/// In-app preview screen for notes.
///
/// Supports four preview modes depending on the note's data:
/// - **Image**: renders the note_file_url as an inline image.
/// - **PDF**: opens in an external PDF viewer app via url_launcher.
/// - **Web/URL**: shows a card to open the URL externally.
/// - **Text/Markdown**: renders note_content directly as formatted markdown.
///
/// If a note has both a file and text content, both are shown.
class NotePreviewScreen extends StatefulWidget {
  final Map<String, dynamic> note;

  const NotePreviewScreen({super.key, required this.note});

  @override
  State<NotePreviewScreen> createState() => _NotePreviewScreenState();
}

class _NotePreviewScreenState extends State<NotePreviewScreen> {
  late final String _title;
  late final String? _fileUrl;
  late final String? _content;
  late final _PreviewType _type;
  late final bool _hasContent;

  // ─── Image extensions for detection ────────────────────────────────────────────
  static const _imageExtensions = [
    '.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp',
  ];

  @override
  void initState() {
    super.initState();
    final note = widget.note;
    _title = note['note_title'] ?? 'Untitled';
    _fileUrl = note['note_file_url'] as String?;
    _content = note['note_content'] as String?;
    _hasContent = _content != null && _content!.trim().isNotEmpty;
    _type = _detectType();
  }

  _PreviewType _detectType() {
    if (_fileUrl != null && _fileUrl!.isNotEmpty) {
      final lower = _fileUrl!.toLowerCase();
      // Check if it's an image file
      if (_imageExtensions.any((ext) => lower.contains(ext))) {
        return _PreviewType.image;
      }
      // Check if it's a PDF
      if (lower.contains('.pdf')) return _PreviewType.pdf;
      // Otherwise, treat as a web URL
      return _PreviewType.web;
    }
    if (_hasContent) return _PreviewType.text;
    return _PreviewType.empty;
  }

  Future<void> _openExternally() async {
    if (_fileUrl == null || _fileUrl!.isEmpty) return;
    final uri = Uri.parse(_fileUrl!);
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        showAppSnackbar(context, 'Could not open file', isError: true);
      }
    } catch (e) {
      if (mounted) {
        showAppSnackbar(context, 'Could not open file: $e', isError: true);
      }
    }
  }

  static const _downloadChannel =
      MethodChannel('com.cst.cst_portal/downloads');

  Future<void> _downloadFile() async {
    try {
      showAppSnackbar(context, 'Downloading...', isError: false);

      if (_hasContent && _fileUrl == null) {
        // Text-only note — save as .md file
        final sanitizedTitle =
            _title.replaceAll(RegExp(r'[\s<>:"/\\|?*]+'), '_');
        final bytes = _content!.codeUnits;
        final path = await _downloadChannel.invokeMethod<String>(
          'saveToDownloads',
          {
            'fileName': '$sanitizedTitle.md',
            'bytes': Uint8List.fromList(bytes),
            'mimeType': 'text/markdown',
          },
        );
        if (mounted) {
          showAppSnackbar(context, 'Saved to $path', isError: false);
        }
        return;
      }

      if (_fileUrl == null || _fileUrl!.isEmpty) return;

      final response = await http.get(Uri.parse(_fileUrl!));
      if (response.statusCode != 200) {
        if (mounted) showAppSnackbar(context, 'Download failed', isError: true);
        return;
      }

      final uri = Uri.parse(_fileUrl!);
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      final fileName = segments.isNotEmpty ? segments.last : 'file';

      final lower = fileName.toLowerCase();
      final mimeType = lower.endsWith('.pdf')
          ? 'application/pdf'
          : lower.endsWith('.jpg') || lower.endsWith('.jpeg')
              ? 'image/jpeg'
              : lower.endsWith('.png')
                  ? 'image/png'
                  : 'application/octet-stream';

      final path = await _downloadChannel.invokeMethod<String>(
        'saveToDownloads',
        {
          'fileName': fileName,
          'bytes': response.bodyBytes,
          'mimeType': mimeType,
        },
      );

      if (mounted) {
        showAppSnackbar(context, 'Saved to $path', isError: false);
      }
    } on PlatformException catch (e) {
      if (mounted) {
        showAppSnackbar(
          context,
          'Download error: ${e.message}',
          isError: true,
        );
      }
    } catch (e) {
      if (mounted) {
        showAppSnackbar(
          context,
          'Download error: ${e.toString()}',
          isError: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(
          _title,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: c.white,
            fontSize: 15,
          ),
        ),
        actions: [
          // Download button
          if (_type == _PreviewType.pdf || _type == _PreviewType.text)
            IconButton(
              icon: Icon(Icons.download_outlined, color: c.accent, size: 20),
              tooltip: 'Download',
              onPressed: _downloadFile,
            ),
        ],
      ),
      body: _hasContent && _type != _PreviewType.text
          ? Column(
              children: [
                _MetaHeader(note: widget.note),
                _ContentHeader(content: _content!, isExpanded: false),
                Container(
                  height: 0.5,
                  color: c.border.withValues(alpha: 0.5),
                ),
                Expanded(child: _buildPreview(c)),
              ],
            )
          : Column(
              children: [
                _MetaHeader(note: widget.note),
                Expanded(child: _buildPreview(c)),
              ],
            ),
    );
  }

  Widget _buildPreview(ThemeColors c) {
    switch (_type) {
      case _PreviewType.image:
        return _buildImageViewer(c);
      case _PreviewType.pdf:
        return _buildPdfViewer(c);
      case _PreviewType.web:
        return _buildFileViewer(
          c,
          icon: Icons.language,
          title: 'Web Link',
          subtitle: 'Open this link in your device browser.',
          buttonLabel: 'Open in Browser',
          buttonIcon: Icons.open_in_browser,
        );
      case _PreviewType.text:
        return _buildTextViewer(c);
      case _PreviewType.empty:
        return _buildEmptyState(c);
    }
  }

  /// Renders an image file inline with loading and error states.
  Widget _buildImageViewer(ThemeColors c) {
    if (_fileUrl == null || _fileUrl!.isEmpty) return _buildEmptyState(c);

    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 5.0,
      child: Center(
        child: CachedNetworkImage(
          imageUrl: _fileUrl!,
          fit: BoxFit.contain,
          memCacheWidth: 1200,
          placeholder: (context, url) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: c.bg2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.border.withValues(alpha: 0.5)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: CircularProgressIndicator(strokeWidth: 3, color: c.accent),
                ),
              ),
              const SizedBox(height: 12),
              Text('Loading image...', style: TextStyle(color: c.muted, fontSize: 13)),
            ],
          ).animate().fadeIn(),
          errorWidget: (context, url, error) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: c.bg2,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: c.danger.withValues(alpha: 0.3)),
                ),
                child: Icon(Icons.broken_image_outlined, color: c.danger, size: 36),
              ).animate().fadeIn().scale(
                begin: const Offset(0.8, 0.8),
                duration: 400.ms,
                curve: Curves.easeOutBack,
              ),
              const SizedBox(height: 16),
              Text(
                'Failed to load image',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.white),
              ).animate().fadeIn(delay: 100.ms),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _openExternally,
                icon: Icon(Icons.open_in_new, size: 16, color: c.accent),
                label: Text('Open externally', style: TextStyle(color: c.accent)),
              ).animate().fadeIn(delay: 200.ms),
            ],
          ),
        ),
      ),
    );
  }

  /// In-app PDF viewer using pdfrx. Loads directly from URI.
  Widget _buildPdfViewer(ThemeColors c) {
    if (_fileUrl == null || _fileUrl!.isEmpty) return _buildEmptyState(c);

    return PdfViewer.uri(
      Uri.parse(_fileUrl!),
      params: PdfViewerParams(
        loadingBannerBuilder: (context, bytesDownloaded, totalBytes) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(strokeWidth: 3, color: c.accent),
              ),
              const SizedBox(height: 16),
              Text('Loading PDF...', style: TextStyle(color: c.muted, fontSize: 13)),
            ],
          ),
        ),
        errorBannerBuilder: (context, error, stackTrace, documentRef) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.picture_as_pdf, size: 48, color: c.danger),
                const SizedBox(height: 16),
                Text('PDF Failed to Load', style: TextStyle(color: c.white, fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text('$error', style: TextStyle(color: c.muted, fontSize: 12), textAlign: TextAlign.center),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _openExternally,
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Open Externally'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Renders a card for PDF / web URL files with open and download actions.
  Widget _buildFileViewer(
    ThemeColors c, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String buttonLabel,
    required IconData buttonIcon,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: c.bg2,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: c.border),
              ),
              child: Icon(icon, size: 48, color: c.accent),
            ).animate().fadeIn(duration: 400.ms).scale(
              begin: const Offset(0.8, 0.8),
              duration: 400.ms,
              curve: Curves.easeOutBack,
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: c.white,
              ),
            ).animate().fadeIn(duration: 400.ms, delay: 100.ms),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(color: c.muted, fontSize: 14, height: 1.5),
              textAlign: TextAlign.center,
            ).animate().fadeIn(duration: 400.ms, delay: 150.ms),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: _openExternally,
              icon: Icon(buttonIcon, size: 20),
              label: Text(buttonLabel),
              style: ElevatedButton.styleFrom(
                backgroundColor: c.accent,
                foregroundColor: c.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
            ).animate().fadeIn(duration: 400.ms, delay: 200.ms).slideY(
              begin: 0.1,
              end: 0,
              duration: 400.ms,
              delay: 200.ms,
              curve: Curves.easeOut,
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _downloadFile,
              icon: Icon(Icons.download_outlined, size: 18, color: c.muted),
              label: Text(
                'Download instead',
                style: TextStyle(color: c.muted, fontSize: 13),
              ),
            ).animate().fadeIn(duration: 400.ms, delay: 250.ms),
          ],
        ),
      ),
    );
  }

  Widget _buildTextViewer(ThemeColors c) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Markdown(
            data: _content ?? '',
            selectable: true,
            styleSheet: MarkdownStyleSheet(
              h1: TextStyle(
                color: c.white,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                height: 1.3,
              ),
              h2: TextStyle(
                color: c.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
              h3: TextStyle(
                color: c.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
              p: TextStyle(color: c.text, fontSize: 15, height: 1.7),
              strong: TextStyle(color: c.white, fontWeight: FontWeight.w700),
              em: TextStyle(color: c.text, fontStyle: FontStyle.italic),
              blockquote: TextStyle(
                color: c.muted,
                fontSize: 15,
                height: 1.6,
                fontStyle: FontStyle.italic,
              ),
              blockquoteDecoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: c.accent.withValues(alpha: 0.5),
                    width: 3,
                  ),
                ),
              ),
              code: TextStyle(
                color: c.accent,
                fontSize: 13,
                fontFamily: 'monospace',
                backgroundColor: c.bg3,
              ),
              codeblockDecoration: BoxDecoration(
                color: c.bg3,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: c.border.withValues(alpha: 0.5)),
              ),
              listBullet: TextStyle(color: c.accent, fontSize: 15),
              horizontalRuleDecoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: c.border.withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
              ),
              a: TextStyle(color: c.accent, decoration: TextDecoration.underline),
              blockSpacing: 12,
              listIndent: 24,
            ),
            padding: const EdgeInsets.all(20),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(
      begin: 0.03,
      end: 0,
      duration: 400.ms,
      curve: Curves.easeOut,
    );
  }

  Widget _buildEmptyState(ThemeColors c) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: c.bg2,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: c.border),
            ),
            child: Center(
              child: Icon(Icons.description, size: 36, color: c.accent),
            ),
          ).animate().fadeIn(duration: 400.ms).scale(
            begin: const Offset(0.8, 0.8),
            duration: 400.ms,
            curve: Curves.easeOutBack,
          ),
          const SizedBox(height: 16),
          Text(
            'No preview available',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: c.white,
            ),
          ).animate().fadeIn(duration: 400.ms, delay: 100.ms),
          const SizedBox(height: 6),
          Text(
            'This note has no file or text content.',
            style: TextStyle(color: c.muted, fontSize: 13),
            textAlign: TextAlign.center,
          ).animate().fadeIn(duration: 400.ms, delay: 200.ms),
        ],
      ),
    );
  }
}

/// A small header showing note metadata (subject, semester).
class _MetaHeader extends StatelessWidget {
  final Map<String, dynamic> note;
  const _MetaHeader({required this.note});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final subject = note['subject'] as String?;
    final semester = int.tryParse(note['semester']?.toString() ?? '');

    if (subject == null && semester == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: c.bg2,
        border: Border(
          bottom: BorderSide(color: c.border.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          if (subject != null) ...[
            SubjectBadge(label: subject),
            const SizedBox(width: 8),
          ],
          if (semester != null)
            SemesterBadge(
              label: '${SupabaseService.semesterFromInt(semester)} Sem',
            ),
        ],
      ),
    );
  }
}

/// Collapsible header that shows text content when a note has both
/// a file and text content.
class _ContentHeader extends StatefulWidget {
  final String content;
  final bool isExpanded;

  const _ContentHeader({required this.content, this.isExpanded = false});

  @override
  State<_ContentHeader> createState() => _ContentHeaderState();
}

class _ContentHeaderState extends State<_ContentHeader> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.isExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: c.bg2,
              border: Border(
                bottom: BorderSide(color: c.border.withValues(alpha: 0.5)),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _expanded ? Icons.expand_less : Icons.article_outlined,
                  color: c.accent,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'Description',
                  style: TextStyle(
                    color: c.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  color: c.muted,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: Padding(
            padding: const EdgeInsets.all(16),
            child: ClipRect(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.35),
              child: Markdown(
              data: widget.content,
              selectable: true,
              shrinkWrap: true,
              styleSheet: MarkdownStyleSheet(
                p: TextStyle(color: c.text, fontSize: 14, height: 1.6),
                strong: TextStyle(color: c.white, fontWeight: FontWeight.w700),
                em: TextStyle(color: c.text, fontStyle: FontStyle.italic),
                code: TextStyle(
                  color: c.accent,
                  fontSize: 12,
                  fontFamily: 'monospace',
                  backgroundColor: c.bg3,
                ),                  blockSpacing: 8,
                listIndent: 20,
              ),
            ),
          ),
          ),
        ),
          secondChild: const SizedBox.shrink(),
          crossFadeState:
              _expanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
          duration: 200.ms,
        ),
      ],
    );
  }
}

enum _PreviewType { image, pdf, web, text, empty }
