import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/supabase_service.dart';
import '../utils/theme_provider.dart';
import '../utils/responsive.dart';
import '../widgets/common.dart';

class StudentProfileScreen extends StatefulWidget {
  final Map<String, dynamic> student;
  final bool isAdmin;
  final bool isTeacher;
  const StudentProfileScreen({super.key, required this.student, required this.isAdmin, this.isTeacher = false});

  @override
  State<StudentProfileScreen> createState() => _StudentProfileScreenState();
}

class _StudentProfileScreenState extends State<StudentProfileScreen> {
  late Map<String, dynamic> _student;

  @override
  void initState() {
    super.initState();
    _student = Map<String, dynamic>.from(widget.student);
  }

  void _openEditSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditStudentSheet(
        student: _student,
        onSaved: (updated) {
          setState(() => _student = updated);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final name = _student['name'] ?? '';
    final canViewDetails = widget.isAdmin || widget.isTeacher;
    final studentId = _student['id']?.toString() ?? '';
    final qrData = studentId.isNotEmpty
        ? '{"v":1,"id":"$studentId"}'
        : 'Name: $name\nRoll: ${_student['roll'] ?? ''}\nReg: ${_student['registration'] ?? ''}\nEmail: ${_student['email'] ?? ''}';

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text('Student Profile', style: TextStyle(fontWeight: FontWeight.w700, color: c.white)),
        actions: [
          if (widget.isAdmin) ...[
            IconButton(
              icon: Icon(Icons.edit_outlined, color: c.accent),
              onPressed: _openEditSheet,
              tooltip: 'Edit Student',
            ),
            PopupMenuButton<String>(
              color: c.bg2,
              onSelected: (v) async {
                if (v == 'delete') {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      backgroundColor: c.bg2,
                      title: Text('Delete Student', style: TextStyle(color: c.white)),
                      content: Text('This will remove the student completely. They can re-register with the same email.', style: TextStyle(color: c.muted)),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                        TextButton(onPressed: () => Navigator.pop(context, true),
                          child: Text('Delete', style: TextStyle(color: c.danger))),
                      ],
                    ),
                  );
                  if (ok == true && context.mounted) {
                    final sid = _student['id'].toString();
                    final email = (_student['email'] ?? '').toString();
                    final photoUrl = (_student['photo_url'] ?? '').toString();

                    try {
                      // 1. Delete from students table by profile id (same id used during approval upsert)
                      try {
                        await SupabaseService.deleteStudent(sid);
                      } catch (_) {}

                      // 2. Also delete by email as fallback
                      if (email.isNotEmpty) {
                        try {
                          final existing = await SupabaseService.client
                              .from('students')
                              .select('id')
                              .eq('email', email);
                          for (final s in existing) {
                            await SupabaseService.deleteStudent(s['id'].toString());
                          }
                        } catch (_) {}
                      }

                      // 3. Delete the auth user + profile
                      await SupabaseService.safeDeleteUser(sid);

                      // 4. Delete profile photo from storage
                      if (photoUrl.isNotEmpty) {
                        try {
                          await SupabaseService.deleteProfilePhoto(sid);
                        } catch (_) {}
                      }

                      if (context.mounted) {
                        showAppSnackbar(context, 'Student deleted successfully');
                        Navigator.pop(context, true);
                      }
                    } catch (e) {
                      if (context.mounted) {
                        showAppSnackbar(context, friendlyError(e), isError: true);
                      }
                    }
                  }
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'delete', child: Row(children: [
                  Icon(Icons.delete_outline, color: c.danger, size: 16),
                  const SizedBox(width: 8),
                  Text('Delete', style: TextStyle(color: c.danger)),
                ])),
              ],
            ),
          ],
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(Responsive.screenPadding(context)),
        child: Column(
          children: [
            // Photo & Name
            AppCard(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  UserAvatar(name: name, photoUrl: _student['photo_url'], size: 100),
                  const SizedBox(height: 16),
                  Text(name, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: c.white)),
                  const SizedBox(height: 6),
                ],
              ),
            ).animate().fadeIn(duration: 400.ms, curve: Curves.easeOut).scale(begin: const Offset(0.96, 0.96), duration: 400.ms, curve: Curves.easeOutBack),
            const SizedBox(height: 16),

            // Info Card
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Student Information', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.white)),
                  const SizedBox(height: 16),
                  _InfoRow(label: 'Roll No', value: _student['roll'] ?? '—', icon: Icons.badge_outlined),
                  _InfoRow(label: 'Shift', value: _student['shift'] ?? '—', icon: Icons.wb_sunny_outlined),
                  _InfoRow(label: 'Session', value: _student['session'] ?? '—', icon: Icons.calendar_today_outlined),
                  if (canViewDetails) ...[
                    _InfoRow(label: 'Registration', value: _student['registration'] ?? '—', icon: Icons.card_membership_outlined),
                    _InfoRow(label: 'Email', value: _student['email'] ?? '—', icon: Icons.email_outlined),
                    _InfoRow(label: 'Contact', value: _student['contact'] ?? '—', icon: Icons.phone_outlined),
                  ],
                ],
              ),
            ).animate().fadeIn(duration: 400.ms, delay: 100.ms, curve: Curves.easeOut).slideY(begin: 12, end: 0, duration: 400.ms, delay: 100.ms, curve: Curves.easeOut),

            if (canViewDetails) ...[
              const SizedBox(height: 16),

              // QR Code
              AppCard(
                child: Column(
                  children: [
                    Text('Student QR Code', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.white)),
                    const SizedBox(height: 4),
                    Text('Teacher can scan this to mark attendance', style: TextStyle(color: c.muted, fontSize: 12)),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: QrImageView(data: qrData, version: QrVersions.auto, size: 180, backgroundColor: Colors.white),
                    ),
                    if (studentId.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('ID: $studentId', style: TextStyle(color: c.muted, fontSize: 10)),
                    ],
                  ],
                ),
              ).animate().fadeIn(duration: 400.ms, delay: 200.ms, curve: Curves.easeOut).slideY(begin: 12, end: 0, duration: 400.ms, delay: 200.ms, curve: Curves.easeOut),
            ],
          ],
        ),
      ),
    );
  }
}


// ── Edit Student Bottom Sheet (admin only) ─────────────────────────────────

class _EditStudentSheet extends StatefulWidget {
  final Map<String, dynamic> student;
  final ValueChanged<Map<String, dynamic>> onSaved;

  const _EditStudentSheet({required this.student, required this.onSaved});

  @override
  State<_EditStudentSheet> createState() => _EditStudentSheetState();
}

class _EditStudentSheetState extends State<_EditStudentSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _rollCtrl;
  late final TextEditingController _regCtrl;
  late final TextEditingController _contactCtrl;
  late final TextEditingController _sessionCtrl;
  late String _shift;
  bool _saving = false;

  static const _shifts = ['Morning', 'Day'];

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.student['name'] ?? '');
    _rollCtrl = TextEditingController(text: widget.student['roll'] ?? '');
    _regCtrl = TextEditingController(text: widget.student['registration'] ?? '');
    _contactCtrl = TextEditingController(text: widget.student['contact'] ?? '');
    _sessionCtrl = TextEditingController(text: widget.student['session'] ?? '');
    _shift = widget.student['shift'] ?? 'Day';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _rollCtrl.dispose();
    _regCtrl.dispose();
    _contactCtrl.dispose();
    _sessionCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final data = <String, dynamic>{
        'name': _nameCtrl.text.trim(),
        'roll': _rollCtrl.text.trim(),
        'registration': _regCtrl.text.trim(),
        'contact': _contactCtrl.text.trim(),
        'session': _sessionCtrl.text.trim(),
        'shift': _shift,
      };

      final email = widget.student['email']?.toString() ?? '';
      final studentId = widget.student['id']?.toString() ?? '';
      final source = widget.student['_source']?.toString() ?? '';

      // Update profiles table if the student has a registered profile (source == 'profile')
      if (source == 'profile' && email.isNotEmpty) {
        await SupabaseService.upsertProfile({
          'id': studentId,
          'email': email,
          ...data,
        });
      }

      // Update students table (always, for legacy compatibility)
      if (email.isNotEmpty) {
        await SupabaseService.updateStudentByEmail(email, data);
      } else if (studentId.isNotEmpty) {
        // Fallback: try direct update by students table ID
        try {
          await SupabaseService.updateStudent(studentId, data);
        } catch (_) {}
      }

      final updated = {
        ...widget.student,
        ...data,
      };
      widget.onSaved(updated);

      if (mounted) {
        showAppSnackbar(context, 'Student details updated successfully!');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) showAppSnackbar(context, friendlyError(e), isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 20, 20, bottom + 20),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: c.muted.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Text('Edit Student Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.white)),
              const SizedBox(height: 8),
              Text('Changes will be saved to both profile and student records.',
                  style: TextStyle(color: c.muted, fontSize: 12)),
              const SizedBox(height: 20),

              // Name
              TextFormField(
                controller: _nameCtrl,
                style: TextStyle(color: c.white),
                decoration: InputDecoration(
                  labelText: 'Full Name',
                  labelStyle: TextStyle(color: c.muted),
                  prefixIcon: Icon(Icons.person_outline, color: c.muted),
                  filled: true,
                  fillColor: c.bg2,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.accent)),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
              ),
              const SizedBox(height: 12),

              // Roll
              TextFormField(
                controller: _rollCtrl,
                style: TextStyle(color: c.white),
                decoration: InputDecoration(
                  labelText: 'Roll No',
                  labelStyle: TextStyle(color: c.muted),
                  prefixIcon: Icon(Icons.badge_outlined, color: c.muted),
                  filled: true,
                  fillColor: c.bg2,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.accent)),
                ),
              ),
              const SizedBox(height: 12),

              // Registration
              TextFormField(
                controller: _regCtrl,
                style: TextStyle(color: c.white),
                decoration: InputDecoration(
                  labelText: 'Registration No',
                  labelStyle: TextStyle(color: c.muted),
                  prefixIcon: Icon(Icons.card_membership_outlined, color: c.muted),
                  filled: true,
                  fillColor: c.bg2,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.accent)),
                ),
              ),
              const SizedBox(height: 12),

              // Contact
              TextFormField(
                controller: _contactCtrl,
                style: TextStyle(color: c.white),
                decoration: InputDecoration(
                  labelText: 'Contact',
                  labelStyle: TextStyle(color: c.muted),
                  prefixIcon: Icon(Icons.phone_outlined, color: c.muted),
                  filled: true,
                  fillColor: c.bg2,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.accent)),
                ),
              ),
              const SizedBox(height: 12),

              // Session
              TextFormField(
                controller: _sessionCtrl,
                style: TextStyle(color: c.white),
                decoration: InputDecoration(
                  labelText: 'Session',
                  labelStyle: TextStyle(color: c.muted),
                  prefixIcon: Icon(Icons.calendar_today_outlined, color: c.muted),
                  filled: true,
                  fillColor: c.bg2,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.accent)),
                ),
              ),
              const SizedBox(height: 12),

              // Shift
              Text('SHIFT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.muted)),
              const SizedBox(height: 8),
              Row(
                children: _shifts.map((sh) {
                  final sel = _shift == sh;
                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: GestureDetector(
                      onTap: () => setState(() => _shift = sh),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: sel ? c.accent.withValues(alpha: 0.15) : c.bg3,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: sel ? c.accent : c.border),
                        ),
                        child: Text(sh, style: TextStyle(color: sel ? c.accent : c.white, fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              // Save button
              ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.accent,
                  foregroundColor: c.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _InfoRow({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 16, color: c.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: c.muted, fontSize: 11, fontWeight: FontWeight.w600)),
                Text(value, style: TextStyle(color: c.white, fontSize: 14, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
