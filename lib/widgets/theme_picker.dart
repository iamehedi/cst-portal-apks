import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../utils/theme_provider.dart';

void showThemePicker(BuildContext context) {
  final themeProv = context.read<ThemeProvider>();

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return ChangeNotifierProvider.value(
        value: themeProv,
        child: Consumer<ThemeProvider>(
          builder: (_, prov, __) {
            final c = prov.colors;
            return Container(
              decoration: BoxDecoration(
                color: c.bg2,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border(
                    top: BorderSide(
                        color: c.accent.withValues(alpha: 0.15), width: 0.5)),
              ),
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: c.muted.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Change Theme',
                    style: GoogleFonts.rajdhani(
                      textStyle: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: c.white,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _ThemeOption(
                    label: 'CSTIAN DARK',
                    subtitle: 'Deep navy · Material You palette',
                    icon: Icons.palette_outlined,
                    color: const Color(0xFF6366F1),
                    colors: c,
                    selected: prov.currentTheme == AppTheme.dynamic,
                    onTap: () {
                      prov.setTheme(AppTheme.dynamic);
                      Navigator.pop(ctx);
                    },
                  ),
                  _ThemeOption(
                    label: 'CSTIAN NEON',
                    subtitle: 'Electric blue · neon glow',
                    icon: Icons.dark_mode,
                    color: const Color(0xFF1E88E5),
                    colors: c,
                    selected: prov.currentTheme == AppTheme.appleDark,
                    onTap: () {
                      prov.setTheme(AppTheme.appleDark);
                      Navigator.pop(ctx);
                    },
                  ),
                  _ThemeOption(
                    label: 'CSTIAN WHITE',
                    subtitle: 'Warm ivory · navy ink accent',
                    icon: Icons.light_mode,
                    color: const Color(0xFF2C3E6B),
                    colors: c,
                    selected: prov.currentTheme == AppTheme.appleLight,
                    onTap: () {
                      prov.setTheme(AppTheme.appleLight);
                      Navigator.pop(ctx);
                    },
                  ),
                  _ThemeOption(
                    label: 'System Default',
                    subtitle: 'Follows your device theme',
                    icon: Icons.settings_brightness_outlined,
                    color: const Color(0xFF7C4DFF),
                    colors: c,
                    selected: prov.currentTheme == AppTheme.system,
                    onTap: () {
                      prov.setTheme(AppTheme.system);
                      Navigator.pop(ctx);
                    },
                  ),
                ],
              ),
            );
          },
        ),
      );
    },
  );
}

class _ThemeOption extends StatefulWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final ThemeColors colors;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeOption({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.colors,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_ThemeOption> createState() => _ThemeOptionState();
}

class _ThemeOptionState extends State<_ThemeOption> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final active = widget.selected || _hovered;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: widget.selected
                ? widget.color.withValues(alpha: 0.08)
                : active
                    ? c.bg3.withValues(alpha: 0.8)
                    : c.bg3,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: widget.selected
                  ? widget.color.withValues(alpha: 0.4)
                  : active
                      ? widget.color.withValues(alpha: 0.2)
                      : c.border.withValues(alpha: 0.3),
              width: widget.selected ? 1.5 : 1,
            ),
            boxShadow: [
              if (widget.selected)
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.12),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: widget.color.withValues(alpha: 0.15),
                    width: 0.5,
                  ),
                ),
                child: Icon(widget.icon, color: widget.color, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.label,
                      style: GoogleFonts.dmSans(
                        textStyle: TextStyle(
                          color: c.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    Text(
                      widget.subtitle,
                      style: GoogleFonts.dmSans(
                        textStyle: TextStyle(
                            color: c.muted, fontSize: 12, letterSpacing: 0),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.selected
                      ? widget.color.withValues(alpha: 0.15)
                      : Colors.transparent,
                  border: Border.all(
                    color: widget.selected
                        ? widget.color
                        : c.muted.withValues(alpha: 0.3),
                    width: widget.selected ? 2 : 1,
                  ),
                ),
                child: widget.selected
                    ? Icon(Icons.check, color: widget.color, size: 14)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

