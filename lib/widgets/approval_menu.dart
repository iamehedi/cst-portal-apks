import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/supabase_service.dart';
import '../utils/theme_provider.dart';
import '../utils/responsive.dart';
import 'common.dart';

/// Helper function to display the Responsive Approval Menu automatically
/// based on the current screen size.
Future<void> showResponsiveApprovalMenu(BuildContext context, {VoidCallback? onChanged}) async {
  final isLarge = Responsive.isLarge(context);

  if (isLarge) {
    // Desktop side-drawer overlay
    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss Approvals',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.centerRight,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
            child: Material(
              color: Colors.transparent,
              child: ResponsiveApprovalMenu(isDrawer: true, onChanged: onChanged),
            ),
          ),
        );
      },
    );
  } else {
    // Mobile bottom sheet
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ResponsiveApprovalMenu(isDrawer: false, onChanged: onChanged),
    );
  }
}

class ResponsiveApprovalMenu extends StatefulWidget {
  final bool isDrawer;
  final VoidCallback? onChanged;
  const ResponsiveApprovalMenu({super.key, required this.isDrawer, this.onChanged});

  @override
  State<ResponsiveApprovalMenu> createState() => _ResponsiveApprovalMenuState();
}

class _ResponsiveApprovalMenuState extends State<ResponsiveApprovalMenu> {
  List<Map<String, dynamic>> _pending = [];
  final Map<String, Map<String, dynamic>?> _duplicateInfo = {};
  bool _loading = true;
  String? _error;
  final Set<String> _processingIds = {};
  int _approvedCount = 0;
  int _rejectedCount = 0;

  @override
  void initState() {
    super.initState();
    _fetchPending();
  }

  /// Smart duplicate check: same name + same email + same other details = true duplicate.
  /// Same name + different email = different person (allow approval).
  Future<Map<String, dynamic>?> _checkDuplicate(Map<String, dynamic> profile) async {
    final name = (profile['name'] ?? '').toString().toLowerCase().trim();
    final email = (profile['email'] ?? '').toString().toLowerCase().trim();
    final role = (profile['role'] ?? 'student').toString().toLowerCase();

    if (name.isEmpty || email.isEmpty) return null;

    List<Map<String, dynamic>> sameName = [];

    // Check profiles table for approved users with the same name
    try {
      final profiles = await SupabaseService.client
          .from('profiles')
          .select()
          .eq('role', role)
          .eq('status', 'approved')
          .ilike('name', '%$name%');
      sameName.addAll(profiles.cast<Map<String, dynamic>>());
    } catch (_) {}

    // Check students/teachers table for entries with the same name
    try {
      if (role == 'teacher') {
        final teachers = await SupabaseService.client
            .from('teachers')
            .select()
            .ilike('teacher_name', '%$name%');
        sameName.addAll(teachers.cast<Map<String, dynamic>>());
      } else {
        final students = await SupabaseService.client
            .from('students')
            .select()
            .ilike('name', '%$name%');
        sameName.addAll(students.cast<Map<String, dynamic>>());
      }
    } catch (_) {}

    // Remove self from results
    sameName.removeWhere((r) => r['id']?.toString() == profile['id']?.toString());
    if (sameName.isEmpty) return null;

    // Check if any have the same email
    final sameEmail = sameName.where((r) =>
      (r['email'] ?? '').toString().toLowerCase().trim() == email
    ).toList();

    if (sameEmail.isEmpty) {
      // Same name but different email — different person, allow approval
      return {
        'type': 'same_name_diff_email',
        'count': sameName.length,
        'message': '${sameName.length} existing user(s) share this name (different email).',
      };
    }

    // Same name + same email — check other fields to confirm real duplicate
    if (role == 'student') {
      final roll = (profile['roll'] ?? '').toString().trim();
      final registration = (profile['registration'] ?? '').toString().trim();
      final shift = (profile['shift'] ?? '').toString().toLowerCase().trim();
      final session = (profile['session'] ?? '').toString().toLowerCase().trim();

      final allFieldsMatch = sameEmail.every((e) {
        if (roll.isNotEmpty && (e['roll'] ?? '').toString().trim() != roll) return false;
        if (registration.isNotEmpty && (e['registration'] ?? '').toString().trim() != registration) return false;
        if (shift.isNotEmpty && (e['shift'] ?? '').toString().toLowerCase().trim() != shift) return false;
        if (session.isNotEmpty && (e['session'] ?? '').toString().toLowerCase().trim() != session) return false;
        return true;
      });

      if (allFieldsMatch) {
        return {
          'type': 'exact',
          'count': sameEmail.length,
          'message': '⚠ Exact duplicate found (name + email + details match).',
        };
      }
      return {
        'type': 'same_name_email_diff_details',
        'count': sameEmail.length,
        'message': 'Same name and email found, but details differ — likely the same person with updated info.',
      };
    } else {
      // Teacher: check subject and designation
      final subject = (profile['subject'] ?? '').toString().toLowerCase().trim();
      final designation = (profile['designation'] ?? '').toString().toLowerCase().trim();

      final allFieldsMatch = sameEmail.every((e) {
        if (subject.isNotEmpty && (e['subject'] ?? '').toString().toLowerCase().trim() != subject) return false;
        if (designation.isNotEmpty && (e['designation'] ?? '').toString().toLowerCase().trim() != designation) return false;
        return true;
      });

      if (allFieldsMatch) {
        return {
          'type': 'exact',
          'count': sameEmail.length,
          'message': '⚠ Exact duplicate found (name + email + details match).',
        };
      }
      return {
        'type': 'same_name_email_diff_details',
        'count': sameEmail.length,
        'message': 'Same name and email found, but details differ.',
      };
    }
  }

  Future<void> _fetchPending({bool showLoading = true}) async {
    if (!mounted) return;
    if (showLoading) setState(() => _loading = true);
    try {
      final data = await SupabaseService.getPendingProfiles();
      if (mounted) {
        setState(() {
          _pending = data;
          _duplicateInfo.clear();
          _error = null;
          _loading = false;
        });
        // Run all duplicate checks in parallel then apply once
        final results = await Future.wait(
          data.map((p) => _checkDuplicate(p)),
        );
        if (mounted) {
          final info = <String, Map<String, dynamic>?>{};
          for (int i = 0; i < data.length; i++) {
            if (results[i] != null) {
              info[data[i]['id'].toString()] = results[i];
            }
          }
          setState(() {
            _duplicateInfo.clear();
            _duplicateInfo.addAll(info);
          });
        }
      }
    } catch (e) {
      if (mounted) {
        if (showLoading) showAppSnackbar(context, friendlyError(e), isError: true);
        setState(() {
          _loading = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  Future<void> _approve(Map<String, dynamic> profile) async {
    final id = profile['id'].toString();
    if (_processingIds.contains(id)) return;

    // Duplicate info is shown as a visual warning on the card only.
    // It does NOT block approval — admin always proceeds directly.

    setState(() => _processingIds.add(id));

    try {
      final role = (profile['role'] ?? 'student').toString().toLowerCase();
      final email = profile['email']?.toString();

      // Delete existing records with the same email (merge/update)
      if (email != null && email.isNotEmpty) {
        if (role == 'teacher') {
          final existing = await SupabaseService.client.from('teachers').select().eq('email', email);
          for (var t in existing) {
            final existingId = t['id'].toString();
            if (existingId != id) {
              await SupabaseService.deleteTeacher(existingId);
            }
          }
        } else {
          final existing = await SupabaseService.client.from('students').select().eq('email', email);
          for (var s in existing) {
            final existingId = s['id'].toString();
            if (existingId != id) {
              await SupabaseService.deleteStudent(existingId);
            }
          }
        }
      }

      if (role == 'teacher') {
        await SupabaseService.upsertTeacher({
          'id': id,
          'teacher_name': profile['name'],
          'email': profile['email'],
          'phone': profile['contact'],
          'subject': profile['subject'],
          'designation': profile['designation'],
        });
      } else {
        await SupabaseService.upsertStudent({
          'id': id,
          'name': profile['name'],
          'email': profile['email'],
          'roll': profile['roll'] ?? '',
          'registration': profile['registration'] ?? '',
          'contact': profile['contact'] ?? '',
          'semester': SupabaseService.semesterToInt(profile['semester']?.toString()),
          'shift': profile['shift'],
          'session': profile['session'],
          'photo_url': profile['photo_url'],
        });
      }

      await SupabaseService.approveProfile(id);

      // Success: re-fetch from server to ensure consistency
      if (mounted) {
        setState(() => _approvedCount++);
        showAppSnackbar(context, '${profile['name']} approved successfully!');
        widget.onChanged?.call();
        await _fetchPending(showLoading: false);
      }
    } catch (e) {
      // Error: stay on menu, show error snackbar inside it
      if (mounted) {
        showAppSnackbar(context, friendlyError(e), isError: true);
      }
    } finally {
      if (mounted) setState(() => _processingIds.remove(id));
    }
  }

  Future<void> _reject(Map<String, dynamic> profile) async {
    final id = profile['id'].toString();
    if (_processingIds.contains(id)) return;

    final c = context.colorsOf;
    final confirm = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.bg2,
        title: Text('Reject User', style: TextStyle(color: c.white)),
        content: Text('Are you sure you want to reject ${profile['name']}? They will be completely removed and can re-register later.',
            style: TextStyle(color: c.muted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Reject', style: TextStyle(color: c.danger)),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    if (!mounted) return;
    setState(() => _processingIds.add(id));

    try {
      await SupabaseService.safeDeleteUser(id);

      // Success: re-fetch from server to ensure consistency
      if (mounted) {
        setState(() => _rejectedCount++);
        showAppSnackbar(context, '${profile['name']} has been rejected.');
        widget.onChanged?.call();
        await _fetchPending(showLoading: false);
      }
    } catch (e) {
      // Error: stay on menu, show error snackbar inside it
      if (mounted) {
        showAppSnackbar(context, friendlyError(e), isError: true);
      }
    } finally {
      if (mounted) setState(() => _processingIds.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final padding = Responsive.screenPadding(context);
    final isLarge = widget.isDrawer;

    // Body content shared between bottom sheet and sidebar layouts
    final Widget header = Padding(
      padding: EdgeInsets.fromLTRB(padding, padding, padding, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [                  const GradientText(
                  text: 'Pending Approvals',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                Text(
                  _loading
                      ? 'Loading requests...'
                      : '${_pending.length} pending'
                          '${_approvedCount > 0 ? ' · $_approvedCount approved' : ''}'
                          '${_rejectedCount > 0 ? ' · $_rejectedCount rejected' : ''}',
                  style: TextStyle(color: c.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: c.muted),
            tooltip: 'Close',
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );

    final Widget content;
    if (_loading) {
      content = ListView.builder(
        padding: EdgeInsets.symmetric(horizontal: padding),
        itemCount: 3,
        itemBuilder: (_, __) => const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: ShimmerBox(height: 140),
        ),
      );
    } else if (_pending.isEmpty) {
      content = _error != null
          ? EmptyState(
              icon: Icons.cloud_off,
              title: 'Failed to load',
              subtitle: _error ?? '',
              actionLabel: 'Retry',
              onAction: () => _fetchPending(),
            )
          : const EmptyState(
              icon: Icons.check_circle,
              title: 'All caught up!',
              subtitle: 'No registration requests require your approval.',
            );
    } else {
      content = ListView.builder(
        padding: EdgeInsets.symmetric(horizontal: padding),
        itemCount: _pending.length,
        itemBuilder: (_, i) {
          final profile = _pending[i];
          final id = profile['id'].toString();
          return _ApprovalMenuCard(
            profile: profile,
            index: i,
            isProcessing: _processingIds.contains(id),
            duplicateInfo: _duplicateInfo[id],
            onApprove: () => _approve(profile),
            onReject: () => _reject(profile),
          );
        },
      );
    }

    if (isLarge) {
      // Wide screen drawer container
      return Container(
        width: 480,
        height: double.infinity,
        decoration: BoxDecoration(
          color: c.bg2,
          border: Border(left: BorderSide(color: c.border, width: 1.5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 30,
              offset: const Offset(-8, 0),
            )
          ],
        ),
        child: SafeArea(
          child: Column(
            children: [
              header,
              const Divider(height: 1),
              Expanded(child: content),
            ],
          ),
        ),
      ).animate().slideX(begin: 1.0, end: 0.0, duration: 250.ms, curve: Curves.easeOutQuad);
    } else {
      // Mobile bottom sheet container
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (_, controller) {
            return Container(
              decoration: BoxDecoration(
                color: c.bg2,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(color: c.border, width: 1.5),
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    // Drag Handle
                    Container(
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(
                        color: c.muted.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    header,
                    const Divider(height: 1),
                    Expanded(
                      child: (_pending.isNotEmpty && !_loading)
                          ? ListView.builder(
                              controller: controller,
                              padding: EdgeInsets.symmetric(horizontal: padding),
                              itemCount: _pending.length,
                              itemBuilder: (_, i) {
                                final profile = _pending[i];
                                final id = profile['id'].toString();
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _ApprovalMenuCard(
                                    profile: profile,
                                    index: i,
                                    isProcessing: _processingIds.contains(id),
                                    duplicateInfo: _duplicateInfo[id],
                                    onApprove: () => _approve(profile),
                                    onReject: () => _reject(profile),
                                  ),
                                );
                              },
                            )
                          : SingleChildScrollView(
                              controller: controller,
                              child: SizedBox(
                                height: MediaQuery.of(context).size.height * 0.75,
                                child: content,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    }
  }
}

class _ApprovalMenuCard extends StatelessWidget {
  final Map<String, dynamic> profile;
  final int index;
  final bool isProcessing;
  final Map<String, dynamic>? duplicateInfo;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _ApprovalMenuCard({
    required this.profile,
    required this.index,
    required this.isProcessing,
    this.duplicateInfo,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final role = (profile['role'] ?? 'student').toString().toLowerCase();

    return AppCard(
      borderColor: c.border,
      radius: 14,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar(
                name: profile['name'] ?? '',
                photoUrl: profile['photo_url'],
                size: 42,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile['name'] ?? '',
                      style: TextStyle(color: c.white, fontWeight: FontWeight.w700, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      profile['email'] ?? '',
                      style: TextStyle(color: c.muted, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              AppBadge(
                label: role.toUpperCase(),
                color: role == 'teacher' ? c.accentPink : c.accent3,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Roll, registration, semester parameters for students
          if (role == 'student')
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (profile['semester'] != null)
                  _CardChip(label: '${SupabaseService.semesterFromInt(int.tryParse(profile['semester']?.toString() ?? ''))} Semester'),
                if (profile['roll'] != null && profile['roll'].toString().isNotEmpty)
                  _CardChip(label: 'Roll: ${profile['roll']}'),
                if (profile['shift'] != null && profile['shift'].toString().isNotEmpty)
                  _CardChip(label: profile['shift']),
                if (profile['session'] != null && profile['session'].toString().isNotEmpty)
                  _CardChip(label: profile['session']),
              ],
            ),
          if (role == 'teacher')
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (profile['designation'] != null && profile['designation'].toString().isNotEmpty)
                  _CardChip(label: profile['designation']),
                if (profile['subject'] != null && profile['subject'].toString().isNotEmpty)
                  _CardChip(label: 'Subject: ${profile['subject']}'),
                if (profile['contact'] != null && profile['contact'].toString().isNotEmpty)
                  _CardChip(label: 'Phone: ${profile['contact']}'),
              ],
            ),
          // Duplicate warning
          if (duplicateInfo != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Icon(
                    duplicateInfo!['type'] == 'exact'
                        ? Icons.warning_amber
                        : Icons.info_outline,
                    size: 13,
                    color: duplicateInfo!['type'] == 'exact' ? c.warn : c.accentOrange,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      duplicateInfo!['message'] ?? '',
                      style: TextStyle(
                        color: duplicateInfo!['type'] == 'exact' ? c.warn : c.accentOrange,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          if (isProcessing)
            const Center(
              child: SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: onReject,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: c.danger.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: c.danger.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.close, size: 14, color: c.danger),
                          const SizedBox(width: 4),
                          Text(
                            'Reject',
                            style: TextStyle(color: c.danger, fontWeight: FontWeight.w700, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: onApprove,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: c.accent3.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: c.accent3.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check, size: 14, color: c.accent3),
                          const SizedBox(width: 4),
                          Text(
                            'Approve',
                            style: TextStyle(color: c.accent3, fontWeight: FontWeight.w700, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    )
        .animate(delay: Duration(milliseconds: (index * 50).clamp(0, 500)))
        .fadeIn(duration: 250.ms)
        .slideY(begin: 0.05, end: 0, duration: 250.ms, curve: Curves.easeOut);
  }
}

class _CardChip extends StatelessWidget {
  final String label;
  const _CardChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.bg3,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(color: c.muted, fontSize: 10, fontWeight: FontWeight.w500),
      ),
    );
  }
}
