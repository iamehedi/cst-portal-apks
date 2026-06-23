import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:pdfrx/pdfrx.dart';
import '../services/supabase_service.dart';
import '../services/cache_service.dart';
import '../utils/theme_provider.dart';
import '../widgets/common.dart';
import '../utils/page_transitions.dart';

// ─── Reactive State Model ────────────────────────────────────────────────────
class _NoticesModel extends ChangeNotifier {
  List<Map<String, dynamic>> notices = [];
  bool initialLoading = true;
  bool isOffline = false;
  StreamSubscription<List<Map<String, dynamic>>>? _noticesSub;
  Completer<void>? _refreshCompleter;

  Future<void> refresh() async {
    final completer = Completer<void>();
    _refreshCompleter = completer;
    _subscribe();
    await completer.future.timeout(const Duration(seconds: 15), onTimeout: () {});
  }

  void init() {
    if (!CacheService.isStale(CacheService.noticesKey)) {
      final cached = CacheService.loadList(CacheService.noticesKey);
      if (cached != null && cached.isNotEmpty) {
        notices = cached;
        initialLoading = false;
        notifyListeners();
      }
    }
    _subscribe();
  }

  void _subscribe() {
    _noticesSub?.cancel();
    _noticesSub = SupabaseService.getNoticesStream().listen((data) {
      _apply(data);
    }, onError: (_) {
      if (notices.isNotEmpty) {
        isOffline = true;
      } else {
        initialLoading = false;
      }
      notifyListeners();
    });
  }

  /// Intelligent duplicate filtering:
  ///   1. Exact duplicate (same title + description) — keep latest
  ///   2. Title similarity ≥80% posted within 5 minutes — collapse
  ///   3. Exact same title, any description, within 2 minutes — likely re-post
  void _apply(List<Map<String, dynamic>> raw) {
    initialLoading = false;
    isOffline = false;

    if (raw.length < 2) {
      notices = raw;
      CacheService.saveList(CacheService.noticesKey, raw);
      notifyListeners();
      return;
    }

    final keep = <Map<String, dynamic>>[];

    for (final notice in raw) {
      bool isDuplicate = false;

      for (int i = 0; i < keep.length; i++) {
        final existing = keep[i];
        final score = _similarityScore(notice, existing);

        if (score >= 1.0) {
          // Exact duplicate — replace with the newer one
          keep[i] = Map<String, dynamic>.from(notice);
          isDuplicate = true;
          break;
        }

        if (score >= 0.8) {
          // High similarity — keep the newer one, merge duplicate_count
          final merged = Map<String, dynamic>.from(notice);
          merged['_dup_count'] = _dupCount(existing) + 1;
          keep[i] = merged;
          isDuplicate = true;
          break;
        }
      }

      if (!isDuplicate) {
        keep.add(Map<String, dynamic>.from(notice));
      }
    }

    notices = keep;
    CacheService.saveList(CacheService.noticesKey, keep);
    notifyListeners();
    // Complete the pending refresh completer (if any)
    if (_refreshCompleter != null && !_refreshCompleter!.isCompleted) {
      _refreshCompleter!.complete();
      _refreshCompleter = null;
    }
  }

  /// Returns a score 0.0–1.0 measuring how similar two notices are.
  double _similarityScore(Map<String, dynamic> a, Map<String, dynamic> b) {
    // Same ID — perfect match
    if (a['id']?.toString() == b['id']?.toString()) return 1.0;

    final titleA = (a['title'] ?? '').toString().trim().toLowerCase();
    final titleB = (b['title'] ?? '').toString().trim().toLowerCase();
    final descA = (a['description'] ?? '').toString().trim().toLowerCase();
    final descB = (b['description'] ?? '').toString().trim().toLowerCase();

    // Exact title + description match
    if (titleA == titleB && descA == descB) return 1.0;

    // Jaccard similarity on title words
    final wordsA = titleA.split(RegExp(r'\s+'))..removeWhere((w) => w.isEmpty);
    final wordsB = titleB.split(RegExp(r'\s+'))..removeWhere((w) => w.isEmpty);
    if (wordsA.isEmpty || wordsB.isEmpty) return 0.0;

    final setA = wordsA.toSet();
    final setB = wordsB.toSet();
    final intersection = setA.intersection(setB).length;
    final union = setA.union(setB).length;
    final titleJaccard = intersection / union;

    // Time proximity bonus
    final timeA = DateTime.tryParse(a['created_at']?.toString() ?? '');
    final timeB = DateTime.tryParse(b['created_at']?.toString() ?? '');
    double timeBonus = 0.0;
    if (timeA != null && timeB != null) {
      final diff = timeA.difference(timeB).abs().inMinutes;
      if (diff <= 2) {
        timeBonus = 0.25;
      } else if (diff <= 5) {
        timeBonus = 0.15;
      } else if (diff <= 15) {
        timeBonus = 0.05;
      }
    }

    return (titleJaccard * 0.75 + timeBonus).clamp(0.0, 1.0);
  }

  int _dupCount(Map<String, dynamic> n) => (n['_dup_count'] as int?) ?? 0;

  @override
  void dispose() {
    _noticesSub?.cancel();
    super.dispose();
  }
}

// ─── Screen ──────────────────────────────────────────────────────────────────
class NoticesScreen extends StatefulWidget {
  final bool isAdmin;
  const NoticesScreen({super.key, required this.isAdmin});

  @override
  State<NoticesScreen> createState() => _NoticesScreenState();
}

class _NoticesScreenState extends State<NoticesScreen> {
  late final _model = _NoticesModel();

  @override
  void initState() {
    super.initState();
    _model.init();
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  Future<void> _delete(String id, [String? attachmentUrl]) async {
    final c = context.colorsOf;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: c.bg2,
        title: Text('Delete Notice', style: TextStyle(color: c.white)),
        content: Text('Are you sure?', style: TextStyle(color: c.muted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text('Delete', style: TextStyle(color: c.danger))),
        ],
      ),
    );
    if (ok != true) return;
    if (attachmentUrl != null && attachmentUrl.isNotEmpty) {
      try { await SupabaseService.deleteNoticeFile(attachmentUrl); } catch (_) {}
    }
    await SupabaseService.deleteNotice(id);
  }

  void _showForm([Map<String, dynamic>? notice]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colorsOf.bg2,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _NoticeForm(notice: notice, onSaved: () => Navigator.pop(context)),
    );
  }

  void _showNoticeDetail(Map<String, dynamic> notice) {
    showDialog(
      context: context,
      useSafeArea: false,
      builder: (ctx) => _NoticeDetailDialog(
        notice: notice,
        isAdmin: widget.isAdmin,
        onEdit: () {
          Navigator.pop(ctx);
          _showForm(notice);
        },
        onDelete: () {
          Navigator.pop(ctx);
          _delete(notice['id'].toString(), notice['attachment_url']?.toString());
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text('Notices', style: TextStyle(fontWeight: FontWeight.w700, color: c.white)),
        actions: [
          if (widget.isAdmin)
            IconButton(icon: Icon(Icons.add, color: c.accent), onPressed: () => _showForm(), tooltip: 'Add notice'),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListenableBuilder(
              listenable: _model,
              builder: (ctx, _) {
                final m = _model;
                final c = context.colors;
                if (m.initialLoading) {
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: 5,
                    itemBuilder: (_, __) => const Padding(padding: EdgeInsets.only(bottom: 12), child: ShimmerBox(height: 110)),
                  );
                }
                if (m.notices.isEmpty) {
                  return SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: const SizedBox(
                      height: 400,
                      child: EmptyState(icon: Icons.mail_outline, title: 'No notices', subtitle: 'No notices have been posted yet.'),
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: m.refresh,
                  color: c.accent,
                  backgroundColor: c.bg2,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: m.notices.length,
                    itemBuilder: (_, i) => _NoticeCard(
                      notice: m.notices[i],
                      isAdmin: widget.isAdmin,
                      onTap: () => _showNoticeDetail(m.notices[i]),
                      index: i,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  final Map<String, dynamic> notice;
  final bool isAdmin;
  final VoidCallback onTap;
  final int index;

  const _NoticeCard({
    required this.notice,
    required this.isAdmin,
    required this.onTap,
    required this.index,
  });

  int get _dupCount => (notice['_dup_count'] as int?) ?? 0;

  String _formatDate(Map<String, dynamic> n) {
    final d = n['created_at'];
    if (d == null) return '';
    return DateFormat('MMM d, yyyy').format(
      DateTime.tryParse(d.toString())?.toLocal() ?? DateTime.now(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasDesc = notice['description'] != null &&
        notice['description'].toString().isNotEmpty;
    final hasAttachment = notice['attachment_url'] != null &&
        notice['attachment_url'].toString().isNotEmpty;

    return RepaintBoundary(
      child: GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: c.bg2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: c.border.withValues(alpha: 0.15),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: c.accentOrange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.campaign,
                      color: Colors.amber,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          notice['title'] ?? '',
                          style: TextStyle(
                            color: c.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _formatDate(notice),
                          style: TextStyle(color: c.muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.open_in_new,
                    color: c.muted.withValues(alpha: 0.4),
                    size: 16,
                  ),
                ],
              ),
            ),
            // Description preview
            if (hasDesc)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Text(
                  notice['description'].toString(),
                  style: TextStyle(color: c.text, fontSize: 13, height: 1.5),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            // Bottom row: attachment badge (centered) + dup count
            if (hasAttachment || _dupCount > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (hasAttachment)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: c.accent.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: c.accent.withValues(alpha: 0.15)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.attach_file, size: 12, color: c.accent.withValues(alpha: 0.7)),
                            const SizedBox(width: 4),
                            Text(
                              'Attachment',
                              style: TextStyle(
                                color: c.accent.withValues(alpha: 0.7),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ).animate().fadeIn(
                        duration: 300.ms,
                        delay: 150.ms,
                        curve: Curves.easeOut,
                      ).scaleXY(
                        begin: 0.92,
                        end: 1.0,
                        duration: 300.ms,
                        delay: 150.ms,
                        curve: Curves.easeOutBack,
                      ),
                    if (hasAttachment && _dupCount > 0)
                      const SizedBox(width: 10),
                    if (_dupCount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: c.accentOrange.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.merge, size: 10, color: c.accentOrange),
                            const SizedBox(width: 3),
                            Text(
                              '$_dupCount similar merged',
                              style: TextStyle(
                                color: c.accentOrange,
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ).animate().fadeIn(
                        duration: 300.ms,
                        delay: 230.ms,
                        curve: Curves.easeOut,
                      ).scaleXY(
                        begin: 0.92,
                        end: 1.0,
                        duration: 300.ms,
                        delay: 230.ms,
                        curve: Curves.easeOutBack,
                      ),
                  ],
                ),
              ),
            if (!hasAttachment && _dupCount == 0)
              const SizedBox(height: 12),
          ],
        ),
      ),
      ),
    ).animate(
      delay: Duration(milliseconds: (index * 60).clamp(0, 600)),
    ).fadeIn(duration: 400.ms, curve: Curves.easeOut).slideY(
      begin: 0.08,
      end: 0,
      duration: 400.ms,
      curve: Curves.easeOut,
    );
  }
}

// ── Notice Detail Dialog ─────────────────────────────────────────────────────
class _NoticeDetailDialog extends StatelessWidget {
  final Map<String, dynamic> notice;
  final bool isAdmin;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _NoticeDetailDialog({
    required this.notice,
    required this.isAdmin,
    required this.onEdit,
    required this.onDelete,
  });

  String get _formattedDate {
    final d = notice['created_at'];
    if (d == null) return '';
    return DateFormat('MMM d, yyyy · h:mm a').format(
      DateTime.tryParse(d.toString())?.toLocal() ?? DateTime.now(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasDesc = notice['description'] != null &&
        notice['description'].toString().isNotEmpty;
    final hasAttachment = notice['attachment_url'] != null &&
        notice['attachment_url'].toString().isNotEmpty;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: Container(
        decoration: BoxDecoration(
          color: c.bg2,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.border.withValues(alpha: 0.2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header with gradient strip ────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    c.accentOrange.withValues(alpha: 0.1),
                    Colors.transparent,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: c.accentOrange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.campaign, color: Colors.amber, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          notice['title'] ?? '',
                          style: TextStyle(
                            color: c.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 17,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _formattedDate,
                          style: TextStyle(color: c.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Scrollable content ────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Divider
                    Container(
                      height: 1,
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 16),
                      color: c.border.withValues(alpha: 0.15),
                    ),
                    // Description
                    if (hasDesc)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          notice['description'].toString(),
                          style: TextStyle(
                            color: c.text,
                            fontSize: 14,
                            height: 1.7,
                          ),
                        ),
                      ),
                    if (!hasDesc)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          'No description provided.',
                          style: TextStyle(
                            color: c.muted.withValues(alpha: 0.6),
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    // Attachment
                    if (hasAttachment)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Center(
                          child: _AttachmentBtn(
                            url: notice['attachment_url'].toString(),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // ── Footer actions ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  // Back button
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        foregroundColor: c.muted,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Close'),
                    ),
                  ),
                  // Admin actions
                  if (isAdmin) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextButton(
                        onPressed: onEdit,
                        style: TextButton.styleFrom(
                          foregroundColor: c.accent,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Edit'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextButton(
                        onPressed: onDelete,
                        style: TextButton.styleFrom(
                          foregroundColor: c.danger,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Delete'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Attachment button with in-app preview support ───────────────────────────
class _AttachmentBtn extends StatelessWidget {
  final String url;
  const _AttachmentBtn({required this.url});

  bool get _isPdf => url.toLowerCase().contains('.pdf');
  bool get _isImage {
    final lower = url.toLowerCase();
    return ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp']
        .any((ext) => lower.contains(ext));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final previewable = _isPdf || _isImage;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Preview button (for PDFs and images)
        if (previewable)
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              buildCupertinoRoute(_NoticeAttachmentPreview(url: url)),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: c.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: c.accent.withValues(alpha: 0.15)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isPdf ? Icons.picture_as_pdf : Icons.image,
                    size: 14, color: c.accent,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    _isPdf ? 'Preview PDF' : 'View Image',
                    style: TextStyle(
                      color: c.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (previewable) const SizedBox(width: 8),
        // Open externally button
        GestureDetector(
          onTap: () async {
            try {
              await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            } catch (_) {
              if (context.mounted) {
                showAppSnackbar(context, 'Could not open attachment', isError: true);
              }
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: c.bg3,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: c.border.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.open_in_new, size: 13, color: c.muted),
                const SizedBox(width: 5),
                Text(
                  'Open Externally',
                  style: TextStyle(
                    color: c.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}


// ── In-App Notice Attachment Preview ─────────────────────────────────────────
class _NoticeAttachmentPreview extends StatelessWidget {
  final String url;
  const _NoticeAttachmentPreview({required this.url});

  bool get _isPdf => url.toLowerCase().contains('.pdf');

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(
          _isPdf ? 'PDF Preview' : 'Image Preview',
          style: TextStyle(fontWeight: FontWeight.w700, color: c.white),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.open_in_new, color: c.accent, size: 20),
            tooltip: 'Open Externally',
            onPressed: () async {
              try {
                await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
              } catch (_) {
                if (context.mounted) {
                  showAppSnackbar(context, 'Could not open file', isError: true);
                }
              }
            },
          ),
        ],
      ),
      body: _isPdf ? _buildPdfViewer(c) : _buildImageViewer(c),
    );
  }

  Widget _buildPdfViewer(ThemeColors c) {
    return PdfViewer.uri(
      Uri.parse(url),
      params: PdfViewerParams(
        loadingBannerBuilder: (context, bytesDownloaded, totalBytes) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 36, height: 36,
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
                Text('Failed to Load PDF', style: TextStyle(color: c.white, fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text('$error', style: TextStyle(color: c.muted, fontSize: 12), textAlign: TextAlign.center),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () async {
                    try {
                      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                    } catch (_) {}
                  },
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

  Widget _buildImageViewer(ThemeColors c) {
    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 5.0,
      child: Center(
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.contain,
          memCacheWidth: 1200,
          placeholder: (context, url) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 36, height: 36,
                child: CircularProgressIndicator(strokeWidth: 3, color: c.accent),
              ),
              const SizedBox(height: 12),
              Text('Loading image...', style: TextStyle(color: c.muted, fontSize: 13)),
            ],
          ).animate().fadeIn(),
          errorWidget: (context, url, error) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80, height: 80,
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
              Text('Failed to load image', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.white)),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoticeForm extends StatefulWidget {
  final Map<String, dynamic>? notice;
  final VoidCallback onSaved;
  const _NoticeForm({this.notice, required this.onSaved});

  @override
  State<_NoticeForm> createState() => _NoticeFormState();
}

class _NoticeFormState extends State<_NoticeForm> {
  final _formKey = GlobalKey<FormState>();
  late final _titleCtrl = TextEditingController(text: widget.notice?['title'] ?? '');
  late final _descCtrl = TextEditingController(text: widget.notice?['description'] ?? '');
  bool _saving = false;
  PlatformFile? _pickedFile;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'ppt', 'pptx', 'zip', 'rar', 'jpg', 'jpeg', 'png'],
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        debugPrint('[NoticeForm] Picked file: ${file.name}, size: ${file.size}, hasBytes: ${file.bytes != null}');
        setState(() => _pickedFile = file);
      }
    } catch (e) {
      debugPrint('[NoticeForm] FilePicker error: $e');
      try {
        final result = await FilePicker.pickFiles(type: FileType.any);
        if (result != null && result.files.isNotEmpty) {
          final file = result.files.first;
          debugPrint('[NoticeForm] Fallback picked file: ${file.name}, size: ${file.size}, hasBytes: ${file.bytes != null}');
          setState(() => _pickedFile = file);
        }
      } catch (e2) {
        debugPrint('[NoticeForm] Fallback FilePicker also failed: $e2');
        if (mounted) showAppSnackbar(context, 'Could not open file picker', isError: true);
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final data = <String, dynamic>{
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'user_id': SupabaseService.currentUser?.id,
      };
      if (_pickedFile != null) {
        if (_pickedFile!.bytes == null) {
          debugPrint('[NoticeForm] Picked file has null bytes — cannot upload');
          if (mounted) showAppSnackbar(context, 'Could not read file. Try a different file.', isError: true);
          setState(() => _saving = false);
          return;
        }
        debugPrint('[NoticeForm] Uploading file: ${_pickedFile!.name}, bytes: ${_pickedFile!.bytes!.length}');
        data['attachment_url'] = await SupabaseService.uploadNoticeFile(_pickedFile!.bytes!, _pickedFile!.name);
        debugPrint('[NoticeForm] Upload complete: ${data['attachment_url']}');
      }
      if (widget.notice != null) {
        await SupabaseService.updateNotice(widget.notice!['id'].toString(), data);
      } else {
        await SupabaseService.client.from('notices').insert(data);
      }
      widget.onSaved();
    } catch (e) {
      debugPrint('[NoticeForm] Save error: $e');
      if (mounted) showAppSnackbar(context, friendlyError(e), isError: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasExistingAttachment = widget.notice?['attachment_url'] != null &&
        widget.notice!['attachment_url'].toString().isNotEmpty && _pickedFile == null;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.notice != null ? 'Edit Notice' : 'Post Notice',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.white))
                .animate().fadeIn(duration: 300.ms).slideY(begin: 8, end: 0, duration: 300.ms),
              const SizedBox(height: 20),
              AppTextField(label: 'Title', controller: _titleCtrl, validator: (v) => v == null || v.isEmpty ? 'Required' : null)
                .animate().fadeIn(duration: 300.ms, delay: 50.ms).slideY(begin: 8, end: 0, duration: 300.ms, delay: 50.ms),
              const SizedBox(height: 16),
              AppTextField(label: 'Description', controller: _descCtrl, maxLines: 4)
                .animate().fadeIn(duration: 300.ms, delay: 80.ms).slideY(begin: 8, end: 0, duration: 300.ms, delay: 80.ms),
              const SizedBox(height: 16),
              Text('ATTACHMENT (OPTIONAL)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.muted))
                .animate().fadeIn(duration: 300.ms, delay: 100.ms).slideY(begin: 8, end: 0, duration: 300.ms, delay: 100.ms),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _pickFile,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: c.bg3,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _pickedFile != null ? c.accent.withValues(alpha: 0.5) : c.border,
                      width: _pickedFile != null ? 1.5 : 0.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(width: 36, height: 36, decoration: BoxDecoration(color: c.accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                        child: Icon(_pickedFile != null ? Icons.description : Icons.upload_file, color: c.accent, size: 18)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_pickedFile != null ? _pickedFile!.name : (hasExistingAttachment ? 'Replace existing attachment' : 'Tap to select a file'),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: _pickedFile != null ? c.white : c.muted, fontSize: 13, fontWeight: _pickedFile != null ? FontWeight.w600 : FontWeight.w400)),
                            if (_pickedFile != null && _pickedFile!.size > 0)
                              Text('${(_pickedFile!.size / 1024).toStringAsFixed(0)} KB', style: TextStyle(color: c.muted, fontSize: 10)),
                          ],
                        ),
                      ),
                      if (_pickedFile != null)
                        GestureDetector(onTap: () => setState(() => _pickedFile = null),
                          child: Padding(padding: const EdgeInsets.only(left: 8), child: Icon(Icons.close, color: c.danger, size: 16)))
                      else
                        Icon(Icons.folder_open, color: c.muted, size: 16),
                    ],
                  ),
                ),
              ).animate().fadeIn(duration: 300.ms, delay: 100.ms).slideY(begin: 8, end: 0, duration: 300.ms, delay: 100.ms),
              const SizedBox(height: 24),
              PrimaryButton(label: 'Save Notice', onPressed: _save, loading: _saving, icon: Icons.save_outlined)
                .animate().fadeIn(duration: 300.ms, delay: 170.ms).slideY(begin: 8, end: 0, duration: 300.ms, delay: 170.ms),
            ],
          ),
        ),
      ),
    );
  }
}
