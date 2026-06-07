import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:file_picker/file_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/supabase_service.dart';
import '../services/update_service.dart';
import '../utils/theme_provider.dart';
import '../utils/responsive.dart';
import '../widgets/common.dart';
import '../widgets/image_crop_screen.dart';
import '../widgets/theme_picker.dart';

class ProfileScreen extends StatefulWidget {
  final Map<String, dynamic> profile;
  const ProfileScreen({super.key, required this.profile});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Map<String, dynamic> _profile;

  @override
  void initState() {
    super.initState();
    _profile = Map<String, dynamic>.from(widget.profile);
  }

  Future<void> _pickAndUploadPhoto() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      if (!mounted) return;
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        if (mounted) showAppSnackbar(context, 'Could not read image data', isError: true);
        return;
      }

      // Let the user crop to a square/circular area before uploading
      final croppedBytes = await ImageCropScreen.crop(context, bytes);
      if (croppedBytes == null) return; // user cancelled crop

      showAppSnackbar(context, 'Uploading photo…');

      final userId = _profile['id'].toString();
      final photoUrl = await SupabaseService.uploadProfilePhoto(croppedBytes, file.name);
      await SupabaseService.updateProfilePhotoUrl(userId, photoUrl);

      if (!mounted) return;
      setState(() => _profile['photo_url'] = photoUrl);

      if (mounted) showAppSnackbar(context, 'Profile photo updated!');
    } catch (e) {
      if (mounted) showAppSnackbar(context, friendlyError(e), isError: true);
    }
  }

  void _openChangePasswordSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ChangePasswordSheet(),
    );
  }

  void _openEditSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditProfileSheet(
        profile: _profile,
        onSaved: (updated) {
          setState(() => _profile = updated);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final name = _profile['name'] ?? '';

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text('My Profile', style: TextStyle(fontWeight: FontWeight.w700, color: c.white)),
        actions: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: c.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: Icon(Icons.edit, color: c.accent, size: 19),
              onPressed: _openEditSheet,
              tooltip: 'Edit Profile',
            ),
          ),
          IconButton(
            icon: Icon(Icons.palette_outlined, color: c.accent),
            tooltip: 'Theme',
            onPressed: () => showThemePicker(context),
          ),
          IconButton(
            icon: Icon(Icons.system_update, color: c.accent),
            tooltip: 'Check for Updates',
            onPressed: () => UpdateService.checkForUpdateManually(context),
          ),
          TextButton.icon(
            onPressed: () async {
              await SupabaseService.signOut();
            },
            icon: Icon(Icons.logout, color: c.danger, size: 16),
            label: Text('Logout', style: TextStyle(color: c.danger, fontSize: 13)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          Responsive.screenPadding(context),
          Responsive.screenPadding(context),
          Responsive.screenPadding(context),
          Responsive.screenPadding(context) + 88,
        ),
        child: Column(
          children: [
            AppCard(
              borderColor: c.accent.withValues(alpha: 0.2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: _pickAndUploadPhoto,
                    child: Stack(
                      children: [
                        UserAvatar(name: name, photoUrl: _profile['photo_url'], size: 90),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: c.accent,
                              shape: BoxShape.circle,
                              border: Border.all(color: c.bg2, width: 2),
                            ),
                            child: Icon(Icons.camera_alt, size: 14, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(name, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: c.white)),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_profile['semester'] != null)
                        AppBadge(label: '${SupabaseService.semesterFromInt(int.tryParse(_profile['semester']?.toString() ?? ''))} Semester', color: c.accent),
                      if (_profile['shift'] != null) ...[
                        const SizedBox(width: 8),
                        AppBadge(label: _profile['shift'], color: c.warn),
                      ],
                    ],
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 400.ms, curve: Curves.easeOut).scale(begin: const Offset(0.96, 0.96), duration: 400.ms, curve: Curves.easeOutBack),
            const SizedBox(height: 16),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('My Information', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.white)),
                  const SizedBox(height: 16),
                  _InfoTile(icon: Icons.email_outlined, label: 'Email', value: _profile['email'] ?? '—'),
                  _InfoTile(icon: Icons.badge_outlined, label: 'Roll No', value: _profile['roll'] ?? '—'),
                  _InfoTile(icon: Icons.card_membership_outlined, label: 'Registration', value: _profile['registration'] ?? '—'),
                  _InfoTile(icon: Icons.phone_outlined, label: 'Contact', value: _profile['contact'] ?? '—'),
                  _InfoTile(icon: Icons.calendar_today_outlined, label: 'Session', value: _profile['session'] ?? '—'),
                ],
              ),
            ).animate().fadeIn(duration: 400.ms, delay: 100.ms, curve: Curves.easeOut).slideY(begin: 12, end: 0, duration: 400.ms, delay: 100.ms, curve: Curves.easeOut            ),
            const SizedBox(height: 16),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(color: c.bg3, borderRadius: BorderRadius.circular(10)),
                        child: Icon(Icons.lock_outline, size: 18, color: c.accent),
                      ),
                      const SizedBox(width: 12),
                      Text('Security', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.white)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _openChangePasswordSheet,
                      icon: const Icon(Icons.key, size: 16),
                      label: const Text('Change Password'),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: c.border),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 400.ms, delay: 200.ms, curve: Curves.easeOut).slideY(begin: 12, end: 0, duration: 400.ms, delay: 200.ms, curve: Curves.easeOut),
            const SizedBox(height: 16),
            const _VersionCard().animate().fadeIn(duration: 400.ms, delay: 300.ms, curve: Curves.easeOut).slideY(begin: 12, end: 0, duration: 400.ms, delay: 300.ms, curve: Curves.easeOut),
          ],
        ),
      ),
    );
  }
}

// ── Version Card with Check for Updates ─────────────────────────────────────

class _VersionCard extends StatefulWidget {
  const _VersionCard();

  @override
  State<_VersionCard> createState() => _VersionCardState();
}

class _VersionCardState extends State<_VersionCard> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _version = '${info.version} (${info.buildNumber})');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      borderColor: c.border,
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: c.bg3, borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.info_outline, size: 18, color: c.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CST Portal', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.white)),
                if (_version.isNotEmpty)
                  Text('Version $_version', style: TextStyle(color: c.muted, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Edit Profile Bottom Sheet ────────────────────────────────────────────────

class _EditProfileSheet extends StatefulWidget {
  final Map<String, dynamic> profile;
  final ValueChanged<Map<String, dynamic>> onSaved;

  const _EditProfileSheet({required this.profile, required this.onSaved});

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _rollCtrl;
  late final TextEditingController _regCtrl;
  late final TextEditingController _contactCtrl;
  late final TextEditingController _sessionCtrl;
  late String _semester;
  late String _shift;
  bool _saving = false;

  static const _shifts = ['Morning', 'Day'];

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.profile['name'] ?? '');
    _rollCtrl = TextEditingController(text: widget.profile['roll'] ?? '');
    _regCtrl = TextEditingController(text: widget.profile['registration'] ?? '');
    _contactCtrl = TextEditingController(text: widget.profile['contact'] ?? '');
    _sessionCtrl = TextEditingController(text: widget.profile['session'] ?? '');
    _semester = SupabaseService.semesterFromInt(int.tryParse(widget.profile['semester']?.toString() ?? ''));
    _shift = widget.profile['shift'] ?? 'Day';
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
      final id = widget.profile['id'].toString();
      final data = <String, dynamic>{
        'name': _nameCtrl.text.trim(),
        'roll': _rollCtrl.text.trim(),
        'registration': _regCtrl.text.trim(),
        'contact': _contactCtrl.text.trim(),
        'session': _sessionCtrl.text.trim(),
        'semester': SupabaseService.semesterToInt(_semester),
        'shift': _shift,
      };

      // Update both profiles and students tables
      // Note: students.id is auto-generated (not the auth user UUID),
      // so we look up the student record by email instead.
      // Include email so upsert won't fail if profile row doesn't exist yet
      await SupabaseService.upsertProfile({
        'id': id,
        'email': widget.profile['email']?.toString(),
        ...data,
      });
      await SupabaseService.updateStudentByEmail(
        widget.profile['email']?.toString() ?? '',
        data,
      );

      final updated = {
        ...widget.profile,
        ...data,
        'semester': SupabaseService.semesterToInt(_semester),
      };
      widget.onSaved(updated);

      if (mounted) {
        showAppSnackbar(context, 'Profile updated successfully!');
        Navigator.pop(context);
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
              Text('Edit Profile', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.white)),
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

              // Semester picker removed (uses current semester from profile)
              // Shift only
              DropdownButtonFormField<String>(
                initialValue: _shift,
                dropdownColor: c.bg2,
                style: TextStyle(color: c.white),
                decoration: InputDecoration(
                  labelText: 'Shift',
                  labelStyle: TextStyle(color: c.muted),
                  filled: true,
                  fillColor: c.bg2,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.accent)),
                ),
                items: _shifts.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (v) => setState(() => _shift = v ?? _shift),
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

// ── Change Password Bottom Sheet ────────────────────────────────────────────

class _ChangePasswordSheet extends StatefulWidget {
  const _ChangePasswordSheet();

  @override
  State<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<_ChangePasswordSheet> {
  final _formKey = GlobalKey<FormState>();
  final _newPwdCtrl = TextEditingController();
  final _confirmPwdCtrl = TextEditingController();
  bool _newVisible = false;
  bool _confirmVisible = false;
  bool _saving = false;

  @override
  void dispose() {
    _newPwdCtrl.dispose();
    _confirmPwdCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      await SupabaseService.updatePassword(_newPwdCtrl.text.trim());

      if (mounted) {
        showAppSnackbar(context, 'Password changed successfully!');
        Navigator.pop(context);
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
              Text('Change Password', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.white)),
              const SizedBox(height: 20),

              // New Password
              TextFormField(
                controller: _newPwdCtrl,
                obscureText: !_newVisible,
                style: TextStyle(color: c.white),
                decoration: InputDecoration(
                  labelText: 'New Password',
                  labelStyle: TextStyle(color: c.muted),
                  prefixIcon: Icon(Icons.lock_outline, color: c.muted),
                  suffixIcon: IconButton(
                    icon: Icon(_newVisible ? Icons.visibility_off : Icons.visibility, color: c.muted, size: 20),
                    onPressed: () => setState(() => _newVisible = !_newVisible),
                  ),
                  filled: true,
                  fillColor: c.bg2,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.accent)),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'New password is required';
                  if (v.trim().length < 6) return 'Password must be at least 6 characters';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Confirm New Password
              TextFormField(
                controller: _confirmPwdCtrl,
                obscureText: !_confirmVisible,
                style: TextStyle(color: c.white),
                decoration: InputDecoration(
                  labelText: 'Confirm New Password',
                  labelStyle: TextStyle(color: c.muted),
                  prefixIcon: Icon(Icons.lock_outline, color: c.muted),
                  suffixIcon: IconButton(
                    icon: Icon(_confirmVisible ? Icons.visibility_off : Icons.visibility, color: c.muted, size: 20),
                    onPressed: () => setState(() => _confirmVisible = !_confirmVisible),
                  ),
                  filled: true,
                  fillColor: c.bg2,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.accent)),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Please confirm your new password';
                  if (v.trim() != _newPwdCtrl.text.trim()) return 'Passwords do not match';
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Save button
              ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Change Password', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Info Tile ────────────────────────────────────────────────────────────────

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoTile({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: c.bg3, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 16, color: c.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: c.muted, fontSize: 11, fontWeight: FontWeight.w600)),
                Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.white, fontSize: 14, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
