import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/supabase_service.dart';
import '../utils/theme_provider.dart';
import '../utils/responsive.dart';
import '../widgets/common.dart';

class TeacherProfileScreen extends StatelessWidget {
  final Map<String, dynamic> teacher;
  final bool isAdmin;
  const TeacherProfileScreen({super.key, required this.teacher, required this.isAdmin});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final name = teacher['teacher_name'] ?? '';
    final initials = name.isNotEmpty
        ? name.split(' ').map((p) => p.isNotEmpty ? p[0] : '').take(2).join().toUpperCase()
        : '?';

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text('Faculty Profile', style: TextStyle(fontWeight: FontWeight.w700, color: c.white)),
        actions: [
          if (isAdmin)
            PopupMenuButton<String>(
              color: c.bg2,
              onSelected: (v) async {
                if (v == 'delete') {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      backgroundColor: c.bg2,
                      title: Text('Delete Faculty', style: TextStyle(color: c.white)),
                      content: Text('This will remove the faculty completely. They can re-register with the same email.', style: TextStyle(color: c.muted)),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                        TextButton(onPressed: () => Navigator.pop(context, true),
                          child: Text('Delete', style: TextStyle(color: c.danger))),
                      ],
                    ),
                  );
                  if (ok == true && context.mounted) {
                    final tid = teacher['id'].toString();
                    await SupabaseService.deleteTeacher(tid);
                    await SupabaseService.safeDeleteUser(tid);
                    if (context.mounted) Navigator.pop(context, true);
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
                  Container(
                    width: 100, height: 100,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [c.accent, c.accentDim]),
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: c.accentGlow, blurRadius: 20)],
                    ),
                    child: Center(child: Text(initials, style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: Colors.white))),
                  ),
                  const SizedBox(height: 16),
                  Text(name, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: c.white)),
                  const SizedBox(height: 6),
                  AppBadge(label: teacher['designation'] ?? 'Faculty', color: c.accent),
                ],
              ),
            ).animate().fadeIn(duration: 400.ms, curve: Curves.easeOut).scale(begin: const Offset(0.96, 0.96), duration: 400.ms, curve: Curves.easeOutBack),
            const SizedBox(height: 16),

            // Info Card
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Faculty Information', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.white)),
                  const SizedBox(height: 16),
                  _InfoTile(icon: Icons.work_outline, label: 'Designation', value: teacher['designation'] ?? '—'),
                  _InfoTile(icon: Icons.book_outlined, label: 'Subject / Department', value: teacher['subject'] ?? '—'),
                  _InfoTile(icon: Icons.email_outlined, label: 'Email', value: teacher['email'] ?? '—'),
                  _InfoTile(icon: Icons.phone_outlined, label: 'Contact', value: teacher['phone'] ?? '—'),
                ],
              ),
            ).animate().fadeIn(duration: 400.ms, delay: 100.ms, curve: Curves.easeOut).slideY(begin: 12, end: 0, duration: 400.ms, delay: 100.ms, curve: Curves.easeOut),
          ],
        ),
      ),
    );
  }
}

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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: c.muted, fontSize: 11, fontWeight: FontWeight.w600)),
              Text(value, style: TextStyle(color: c.white, fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}
