import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../services/supabase_service.dart';
import '../services/connectivity_service.dart';
import '../utils/theme_provider.dart';

void _hapticLight() => HapticFeedback.lightImpact();

String _avatarImageUrl(String url, {int? width}) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return trimmed;

  // Supabase Storage URLs (getPublicUrl) serve images at original resolution.
  // The original code appended ?width=N which Supabase ignores, so images were
  // served raw — if the uploaded image was small, it would appear pixelated.
  // The real fix is to ensure images are uploaded at sufficient resolution
  // (see uploadProfilePhoto in supabase_service.dart).
  //
  // We keep a lightweight cache buster here — the key fix is the upload side.
  final sep = trimmed.contains('?') ? '&' : '?';
  return '$trimmed${sep}v=${width ?? ''}';
}

// ── Gradient Text ────────────────────────────────────────────────────────────
class GradientText extends StatelessWidget {
  final String text;
  final Gradient? gradient;
  final TextStyle? style;

  const GradientText({
    super.key,
    required this.text,
    this.gradient,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final grad = gradient ?? context.colors.accentGradient;
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => grad.createShader(
        Rect.fromLTWH(0, 0, bounds.width, bounds.height),
      ),
      child: Text(text, style: style),
    );
  }
}

// ── Premium Glassmorphism Card (greeting card style) ────────────────────────
// Card with deep navy gradient (#0D1B38→#060E1E dark / warm cream light),
// accent-tinted gradient overlay (greeting card style), accent glass border,
// and neon glow shadow (dark only).
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? borderColor;
  final double radius;
  final Gradient? gradient;
  final List<BoxShadow>? boxShadow;
  final Color? color;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.borderColor,
    this.radius = 16,
    this.gradient,
    this.boxShadow,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isLight = c.isLight;

    return Container(
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color,
        gradient: color != null ? null : (gradient ?? c.cardGradient),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: borderColor ?? (isLight
              ? const Color(0xFFD4C9B6).withValues(alpha: 0.4)
              : c.accent.withValues(alpha: 0.08)),
          width: 0.5,
        ),
        boxShadow: boxShadow ?? (color != null ? [] : [
          BoxShadow(
            color: isLight
                ? c.cardShadow
                : Colors.black.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
          if (!isLight)
            BoxShadow(
              color: c.accent.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 0),
            ),
        ]),
      ),
      child: child,
    );
  }
}

// ── Section Header ───────────────────────────────────────────────────────────
class SectionHeader extends StatelessWidget {
  final String title;
  final IconData? icon;
  final Color? iconColor;
  final Widget? trailing;
  final bool centered;

  const SectionHeader({
    super.key,
    required this.title,
    this.icon,
    this.iconColor,
    this.trailing,
    this.centered = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = GoogleFonts.rajdhani(
      textStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: c.white,
        letterSpacing: 0.3,
      ),
    );

    if (centered) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
        decoration: BoxDecoration(
          color: c.bg2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: iconColor ?? c.accent),
              const SizedBox(width: 8),
            ],
            Text(title, style: style),
          ],
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: iconColor ?? c.accent),
          const SizedBox(width: 8),
        ],
        Text(title, style: style),
        const Spacer(),
        if (trailing != null) trailing!,
      ],
    );
  }
}

// ── Status Badge ─────────────────────────────────────────────────────────────
class StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final bool filled;

  const StatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: filled ? Colors.transparent : color.withValues(alpha: 0.3),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: filled ? 0.15 : 0.08),
            blurRadius: filled ? 8 : 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        label,
        style: GoogleFonts.dmSans(
          textStyle: TextStyle(
            color: filled ? Colors.white : color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

// ── Stat Card (icon + number + label) ────────────────────────────────────────
class StatCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;
  final Widget? sparkline;
  final int index;

  const StatCard({
    super.key,
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
    this.sparkline,
    this.index = 0,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: '$value $label',
      child: AppCard(
      padding: const EdgeInsets.all(16),
      gradient: LinearGradient(
        colors: [
          color.withValues(alpha: 0.08),
          color.withValues(alpha: 0.02),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderColor: color.withValues(alpha: 0.2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const Spacer(),
              if (sparkline != null)
                SizedBox(width: 60, height: 30, child: sparkline!),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: GoogleFonts.exo2(
              textStyle: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: c.white,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.dmSans(
              textStyle: TextStyle(
                fontSize: 12,
                color: c.muted,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    ).animate(
      delay: Duration(milliseconds: (index * 80).clamp(0, 600)),
    ).fadeIn(duration: 350.ms).scale(
      begin: const Offset(0.92, 0.92),
      end: const Offset(1, 1),
      duration: 350.ms,
      curve: Curves.easeOutBack,
    ),
    );
  }
}

// ── Action Card (icon + label, used in quick actions) ────────────────────────
class ActionCard extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final int index;
  final VoidCallback onTap;

  const ActionCard({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.index,
    required this.onTap,
  });

  @override
  State<ActionCard> createState() => _ActionCardState();
}

class _ActionCardState extends State<ActionCard> {
  bool _pressing = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
      onTapDown: (_) => setState(() => _pressing = true),
      onTapUp: (_) => setState(() => _pressing = false),
      onTapCancel: () => setState(() => _pressing = false),
      onTap: () {
        _hapticLight();
        widget.onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              widget.color.withValues(alpha: _pressing ? 0.15 : 0.08),
              Colors.transparent,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _pressing
                ? widget.color.withValues(alpha: 0.5)
                : widget.color.withValues(alpha: 0.15),
            width: _pressing ? 1.5 : 1,
          ),
          boxShadow: _pressing
              ? [
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.15),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(widget.icon, color: widget.color, size: 24),
            ),
            const SizedBox(height: 10),
            Text(
              widget.label,
              style: GoogleFonts.dmSans(
                textStyle: TextStyle(
                  color: c.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ).animate(
      delay: Duration(milliseconds: (widget.index * 70).clamp(0, 600)),
    ).fadeIn(duration: 350.ms).scale(
      begin: const Offset(0.9, 0.9),
      end: const Offset(1, 1),
      duration: 350.ms,
      curve: Curves.easeOutBack,
    ),
    );
  }
}

// ── User List Tile (avatar + name + status + arrow) ─────────────────────────
class UserListTile extends StatelessWidget {
  final String name;
  final String? subtitle;
  final String? initials;
  final String? photoUrl;
  final Widget? trailing;
  final Color? avatarGradientStart;
  final Color? avatarGradientEnd;
  final VoidCallback? onTap;

  const UserListTile({
    super.key,
    required this.name,
    this.subtitle,
    this.initials,
    this.photoUrl,
    this.trailing,
    this.avatarGradientStart,
    this.avatarGradientEnd,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final gStart = avatarGradientStart ?? c.accent;
    final gEnd = avatarGradientEnd ?? c.accentDim;
    final avatarCacheSize =
        (48 * MediaQuery.of(context).devicePixelRatio * 3.0).round().clamp(384, 768);

    return Semantics(
      button: onTap != null,
      label: name,
      child: GestureDetector(
      onTap: onTap != null
          ? () {
              _hapticLight();
              onTap!();
            }
          : null,
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [gStart, gEnd],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: photoUrl != null && photoUrl!.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: CachedNetworkImage(
                          imageUrl: _avatarImageUrl(photoUrl!, width: avatarCacheSize),
                          fit: BoxFit.cover,
                          width: 48,
                          height: 48,
                          memCacheWidth: avatarCacheSize,
                          memCacheHeight: avatarCacheSize,
                          filterQuality: FilterQuality.high,
                        ),
                      )
                    : Text(
                        initials ?? (name.isNotEmpty ? name[0].toUpperCase() : '?'),
                        style: GoogleFonts.exo2(
                          textStyle: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 14),
            // Name + subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: GoogleFonts.dmSans(
                      textStyle: TextStyle(
                        color: c.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      style: GoogleFonts.dmSans(
                        textStyle: TextStyle(
                          color: c.muted,
                          fontSize: 12,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Trailing
            if (trailing != null) trailing!,
            if (trailing == null)
              Icon(
                Icons.chevron_right,
                color: c.muted.withValues(alpha: 0.5),
                size: 20,
              ),
          ],
        ),
      ),
    ),
    );
  }
}

// ── Filter Chip (premium glassmorphic) ──────────────────────────────────────
class FilterChipWidget extends StatefulWidget {
  final String label;
  final bool selected;
  final Color? selectedColor;
  final VoidCallback onTap;

  const FilterChipWidget({
    super.key,
    required this.label,
    required this.selected,
    this.selectedColor,
    required this.onTap,
  });

  @override
  State<FilterChipWidget> createState() => _FilterChipWidgetState();
}

class _FilterChipWidgetState extends State<FilterChipWidget> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = widget.selectedColor ?? c.accent;
    final active = widget.selected || _hovered;

    return Semantics(
      button: true,
      label: widget.label,
      selected: widget.selected,
      child: MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: widget.selected
                ? color.withValues(alpha: 0.15)
                : active
                    ? color.withValues(alpha: 0.06)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.selected
                  ? color.withValues(alpha: 0.4)
                  : active
                      ? color.withValues(alpha: 0.2)
                      : c.muted.withValues(alpha: 0.2),
              width: widget.selected ? 1.5 : 1,
            ),
            boxShadow: [
              if (active)
                BoxShadow(
                  color: color.withValues(alpha: widget.selected ? 0.15 : 0.08),
                  blurRadius: widget.selected ? 10 : 6,
                  offset: const Offset(0, 2),
                ),
            ],
          ),
          child: Text(
            widget.label,
            style: GoogleFonts.dmSans(
              textStyle: TextStyle(
                color: widget.selected
                    ? color
                    : active
                        ? c.white
                        : c.muted,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
              ),
            ),
          ),
        ),
      ),
    ),
    );
  }
}

// ── Glow Button ──────────────────────────────────────────────────────────────
class GlowButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Color color;
  final bool loading;

  const GlowButton({
    super.key,
    required this.label,
    this.icon,
    required this.onPressed,
    this.color = const Color(0xFF1E88E5),
    this.loading = false,
  });

  @override
  State<GlowButton> createState() => _GlowButtonState();
}

class _GlowButtonState extends State<GlowButton> {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: widget.color.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: widget.loading ? null : widget.onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: widget.color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: widget.color.withValues(alpha: 0.4),
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: widget.loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, size: 18),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    widget.label,
                    style: GoogleFonts.dmSans(
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ── Dark Text Field (premium glassmorphic) ──────────────────────────────────
class DarkTextField extends StatefulWidget {
  final String hint;
  final IconData? prefixIcon;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;

  const DarkTextField({
    super.key,
    required this.hint,
    this.prefixIcon,
    this.controller,
    this.onChanged,
  });

  @override
  State<DarkTextField> createState() => _DarkTextFieldState();
}

class _DarkTextFieldState extends State<DarkTextField> {
  final _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (mounted) setState(() => _focused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: c.bg3,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _focused
              ? c.accent.withValues(alpha: 0.4)
              : c.border.withValues(alpha: 0.3),
          width: _focused ? 1.5 : 1,
        ),
        boxShadow: [
          if (_focused)
            BoxShadow(
              color: c.accent.withValues(alpha: 0.1),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        onChanged: widget.onChanged,
        style: GoogleFonts.dmSans(
          textStyle: TextStyle(
            color: c.white,
            fontSize: 14,
            letterSpacing: 0,
          ),
        ),
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: GoogleFonts.dmSans(
            textStyle: TextStyle(
              color: c.muted.withValues(alpha: 0.5),
              fontSize: 14,
              letterSpacing: 0,
            ),
          ),
          prefixIcon: widget.prefixIcon != null
              ? Icon(widget.prefixIcon, color: c.muted, size: 20)
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
    );
  }
}

// ── Section Title (legacy compat) ────────────────────────────────────────────
class SectionTitle extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final bool useGradient;
  final IconData? icon;
  final bool centered;

  const SectionTitle({
    super.key,
    required this.title,
    this.trailing,
    this.useGradient = true,
    this.icon,
    this.centered = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = GoogleFonts.rajdhani(
      textStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: c.white,
        letterSpacing: 0.3,
      ),
    );

    if (centered) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
        decoration: BoxDecoration(
          color: c.bg2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: c.accent),
              const SizedBox(width: 8),
            ],
            Text(title, style: style),
          ],
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: c.accent),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: useGradient
              ? GradientText(text: title, style: style)
              : Text(title, style: style),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

// ── Legacy Badge (compat) ────────────────────────────────────────────────────
class AppBadge extends StatelessWidget {
  final String label;
  final Color color;

  const AppBadge({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        label,
        style: GoogleFonts.dmSans(
          textStyle: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w500,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

// ── Primary Button ───────────────────────────────────────────────────────────
class PrimaryButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
  });

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = widget.onPressed != null && !widget.loading;
    return GestureDetector(
      onTapDown: enabled ? (_) => _animController.forward() : null,
      onTapUp: enabled
          ? (_) {
              _animController.reverse();
              _hapticLight();
              widget.onPressed?.call();
            }
          : null,
      onTapCancel: enabled ? () => _animController.reverse() : null,
      child: AnimatedBuilder(
        animation: _scaleAnim,
        builder: (context, child) =>
            Transform.scale(scale: _scaleAnim.value, child: child),
        child: Container(
          width: double.infinity,
          height: 52,
          decoration: BoxDecoration(
            color: enabled ? c.accent : c.muted.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: c.accent.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [],
          ),
          child: ElevatedButton(
            onPressed: widget.loading ? null : widget.onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              textStyle: GoogleFonts.dmSans(
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  letterSpacing: 0,
                ),
              ),
            ),
            child: widget.loading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: c.white),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.icon != null) ...[
                        Icon(widget.icon, size: 18),
                        const SizedBox(width: 8),
                      ],
                      Text(widget.label),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ── Ghost Button (premium glassmorphic) ─────────────────────────────────────
class GhostButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? color;

  const GhostButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color,
  });

  @override
  State<GhostButton> createState() => _GhostButtonState();
}

class _GhostButtonState extends State<GhostButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = widget.color ?? c.accent;
    final enabled = widget.onPressed != null;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: _hovered && enabled
                ? color.withValues(alpha: 0.06)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hovered && enabled
                  ? color.withValues(alpha: 0.4)
                  : color.withValues(alpha: 0.2),
              width: _hovered && enabled ? 1.5 : 1,
            ),
            boxShadow: [
              if (_hovered && enabled)
                BoxShadow(
                  color: color.withValues(alpha: 0.1),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
            ],
          ),
          child: OutlinedButton(
            onPressed: widget.onPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: color,
              side: BorderSide.none,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, size: 16),
                  const SizedBox(width: 6),
                ],
                Text(
                  widget.label,
                  style: GoogleFonts.dmSans(
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Secondary Button (premium glassmorphic) ─────────────────────────────────
class SecondaryButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  @override
  State<SecondaryButton> createState() => _SecondaryButtonState();
}

class _SecondaryButtonState extends State<SecondaryButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnim;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = widget.onPressed != null;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTapDown: enabled ? (_) => _animController.forward() : null,
        onTapUp: enabled
            ? (_) {
                _animController.reverse();
                _hapticLight();
                widget.onPressed?.call();
              }
            : null,
        onTapCancel: enabled ? () => _animController.reverse() : null,
        child: AnimatedBuilder(
          animation: _scaleAnim,
          builder: (context, child) =>
              Transform.scale(scale: _scaleAnim.value, child: child),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                if (_hovered && enabled)
                  BoxShadow(
                    color: c.accent.withValues(alpha: 0.15),
                    blurRadius: 14,
                    offset: const Offset(0, 3),
                  ),
              ],
            ),
            child: OutlinedButton(
              onPressed: widget.onPressed,
              style: OutlinedButton.styleFrom(
                foregroundColor: c.accent,
                side: BorderSide(
                  color: _hovered && enabled
                      ? c.accent.withValues(alpha: 0.5)
                      : c.accent.withValues(alpha: 0.3),
                  width: 1.5,
                ),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                textStyle: GoogleFonts.dmSans(
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    letterSpacing: 0,
                  ),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, size: 16),
                    const SizedBox(width: 6),
                  ],
                  Text(widget.label),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Form Field (premium glassmorphic) ───────────────────────────────────────
class AppTextField extends StatefulWidget {
  final String label;
  final String? hint;
  final TextEditingController? controller;
  final bool obscureText;
  final TextInputType? keyboardType;
  final IconData? prefixIcon;
  final String? Function(String?)? validator;
  final int? maxLines;
  final Widget? suffix;

  const AppTextField({
    super.key,
    required this.label,
    this.hint,
    this.controller,
    this.obscureText = false,
    this.keyboardType,
    this.prefixIcon,
    this.validator,
    this.maxLines = 1,
    this.suffix,
  });

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  final _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (mounted) setState(() => _focused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label.toUpperCase(),
          style: GoogleFonts.dmSans(
            textStyle: TextStyle(
              color: _focused ? c.accent : c.muted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(height: 8),
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              if (_focused)
                BoxShadow(
                  color: c.accent.withValues(alpha: 0.1),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
            ],
          ),
          child: TextFormField(
            controller: widget.controller,
            focusNode: _focusNode,
            obscureText: widget.obscureText,
            keyboardType: widget.keyboardType,
            validator: widget.validator,
            maxLines: widget.obscureText ? 1 : widget.maxLines,
            style: GoogleFonts.dmSans(
              textStyle:
                  TextStyle(color: c.text, fontSize: 14, letterSpacing: 0),
            ),
            decoration: InputDecoration(
              hintText: widget.hint,
              prefixIcon: widget.prefixIcon != null
                  ? Container(
                      margin: const EdgeInsets.only(left: 4, right: 8),
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _focused
                            ? c.accent.withValues(alpha: 0.1)
                            : c.bg3,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        widget.prefixIcon,
                        size: 18,
                        color: _focused ? c.accent : c.muted,
                      ),
                    )
                  : null,
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 48, minHeight: 48),
              suffix: widget.suffix,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Shimmer Loading (premium glassmorphic) ──────────────────────────────────
class ShimmerBox extends StatelessWidget {
  final double height;
  final double? width;
  final double radius;

  const ShimmerBox({
    super.key,
    required this.height,
    this.width,
    this.radius = 12,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: 'Loading',
      child: ExcludeSemantics(
        child: Shimmer.fromColors(
          baseColor: c.bg3.withValues(alpha: 0.4),
          highlightColor: c.bg3.withValues(alpha: 0.7),
          child: Container(
            height: height,
            width: width,
            decoration: BoxDecoration(
              gradient: c.cardGradient,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                  color: c.accent.withValues(alpha: 0.08), width: 0.5),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Empty State ──────────────────────────────────────────────────────────────
class EmptyState extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    this.iconColor,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: '$title. $subtitle',
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: AppCard(
            gradient: c.subtleGradient,
            borderColor: c.accent.withValues(alpha: 0.1),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.accent.withValues(alpha: 0.08),
                      border: Border.all(color: c.accent.withValues(alpha: 0.15), width: 1),
                    ),
                    child: Center(child: Icon(icon, size: 32, color: iconColor ?? c.accent)),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: GoogleFonts.rajdhani(
                    textStyle: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: c.white,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: GoogleFonts.dmSans(
                    textStyle: TextStyle(
                      color: c.muted,
                      fontSize: 13,
                      letterSpacing: 0,
                    ),
                  ),
                  textAlign: TextAlign.center,
                ),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: onAction,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: c.accent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        actionLabel!,
                        style: GoogleFonts.dmSans(
                          textStyle: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ).animate().fadeIn(duration: 400.ms, curve: Curves.easeOut)
              .scale(begin: const Offset(0.92, 0.92), duration: 400.ms, curve: Curves.easeOutBack),
        ),
      ),
    );
  }
}

// ── Floating Bottom Nav ───────────────────────────────────────────────────────
/// High-fidelity glassmorphism floating bottom navigation bar with pill shape.
/// Features a transparent frosted-glass background with 20% opacity gradient
/// (#1A2332→#0F172A), 20px backdrop blur, 1px translucent white border,
/// vibrant cyan-blue active icon (#38BDF8) with soft radial glow, and
/// low-contrast slate-gray inactive icons (#94A3B8 at 50% opacity).
class FloatingBottomNav extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<BottomNavigationBarItem> items;
  final bool isVisible;

  const FloatingBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
    this.isVisible = true,
  });

  @override
  State<FloatingBottomNav> createState() => _FloatingBottomNavState();
}

class _FloatingBottomNavState extends State<FloatingBottomNav> {
  static const Color _activeColor = Color(0xFF1E88E5);
  static const Color _inactiveColor = Color(0xFF94A3B8);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isLight = c.isLight;

    return AnimatedSlide(
      offset: Offset(0, widget.isVisible ? 0 : 2),
      duration: 300.ms,
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: widget.isVisible ? 1.0 : 0.0,
        duration: 200.ms,
        child: isLight ? _buildLightNav() : _buildDarkNav(),
      ),
    );
  }

  /// Adaptive blur sigma — use lower value on mobile (GPU-bound) vs. web (CSS-accelerated).
  static double get _blurSigma => kIsWeb ? 20.0 : 8.0;

  // ── Dark: Premium frosted-glass nav ─────────────────────────────────────
  Widget _buildDarkNav() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(100),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: _activeColor.withValues(alpha: 0.06),
              blurRadius: 40,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(100),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: _blurSigma, sigmaY: _blurSigma),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(100),
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF1A2332).withValues(alpha: 0.12),
                    const Color(0xFF0F172A).withValues(alpha: 0.12),
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.10),
                  width: 1.0,
                ),
              ),
              child: _buildNavItems(),
            ),
          ),
        ),
      ),
    );
  }

  // ── Light: Simplified clean nav ──────────────────────────────────────────
  Widget _buildLightNav() {
    const Color activeColor = Color(0xFF1E88E5);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(100),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(100),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: _blurSigma, sigmaY: _blurSigma),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(100),
                gradient: LinearGradient(
                  colors: [
                    Color.lerp(Colors.white, activeColor, 0.04)!,
                    Colors.white.withValues(alpha: 0.68),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                border: Border.all(
                  color: const Color(0xFFD4C9B6).withValues(alpha: 0.35),
                  width: 0.5,
                ),
              ),
              child: _buildNavItemsLight(activeColor),
            ),
          ),
        ),
      ),
    );
  }

  // ── Nav Items (Dark) ─────────────────────────────────────────────────────
  Widget _buildNavItems() {
    final itemCount = widget.items.length;
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = constraints.maxWidth / itemCount;
        final activeLeft = itemWidth * widget.currentIndex;
        return SizedBox(
          height: 56,
          child: Stack(
            children: [
              // Radial glow behind active icon
              Positioned(
                left: activeLeft,
                width: itemWidth,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          _activeColor.withValues(alpha: 0.22),
                          _activeColor.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Icon items
              Row(
                children: List.generate(itemCount, (index) {
                  final isActive = index == widget.currentIndex;
                  final item = widget.items[index];
                  final iconWidget = isActive
                      ? item.activeIcon
                      : item.icon;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => widget.onTap(index),
                      behavior: HitTestBehavior.opaque,
                      child: Semantics(
                        button: true,
                        label: item.label ?? 'Tab $index',
                        selected: isActive,
                        child: SizedBox(
                          height: 56,
                          child: Center(
                            child: IconTheme(
                              data: IconThemeData(
                                color: isActive
                                    ? _activeColor
                                    : _inactiveColor.withValues(alpha: 0.50),
                                size: 24,
                              ),
                              child: iconWidget,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Nav Items (Light) ────────────────────────────────────────────────────
  Widget _buildNavItemsLight(Color activeColor) {
    final itemCount = widget.items.length;
    return SizedBox(
      height: 56,
      child: Row(
        children: List.generate(itemCount, (index) {
          final isActive = index == widget.currentIndex;
          final item = widget.items[index];
          final iconWidget = isActive
              ? item.activeIcon
              : item.icon;
          return Expanded(
            child: GestureDetector(
              onTap: () => widget.onTap(index),
              behavior: HitTestBehavior.opaque,
              child: Semantics(
                button: true,
                label: item.label ?? 'Tab $index',
                selected: isActive,
                child: SizedBox(
                  height: 56,
                  child: Center(
                    child: IconTheme(
                      data: IconThemeData(
                        color: isActive
                            ? activeColor
                            : const Color(0xFF666666),
                        size: 24,
                      ),
                      child: iconWidget,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ── Offline Banner (premium glassmorphic) ───────────────────────────────────
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      liveRegion: true,
      label: 'Offline — showing cached data',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              c.accentOrange.withValues(alpha: 0.08),
              c.accentOrange.withValues(alpha: 0.03),
            ],
          ),
          border: Border(
            bottom: BorderSide(
              color: c.accentOrange.withValues(alpha: 0.2),
              width: 0.5,
            ),
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off, size: 14, color: c.accentOrange),
              const SizedBox(width: 6),
              Text(
                'Offline — showing cached data',
                style: GoogleFonts.dmSans(
                  textStyle: TextStyle(
                    color: c.accentOrange,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Back Online Banner (brief green indicator) ──────────────────────────────
class OnlineBanner extends StatelessWidget {
  const OnlineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      liveRegion: true,
      label: 'Back online',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              c.accent3.withValues(alpha: 0.12),
              c.accent3.withValues(alpha: 0.04),
            ],
          ),
          border: Border(
            bottom: BorderSide(
              color: c.accent3.withValues(alpha: 0.3),
              width: 0.5,
            ),
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi, size: 14, color: c.accent3),
              const SizedBox(width: 6),
              Text(
                'Back Online',
                style: GoogleFonts.dmSans(
                  textStyle: TextStyle(
                    color: c.accent3,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.5, end: 0, duration: 300.ms, curve: Curves.easeOutCubic);
  }
}

// ── Connectivity-aware banner pair (offline + brief online) ────────────────
/// Replaces a plain [OfflineBanner] line. Shows:
/// - The [OfflineBanner] when the screen reports [isOffline]
/// - A brief [OnlineBanner] (3 s) when the device regains connectivity
/// - Calls [onRefresh] when transitioning from offline → online
///
/// Place this inline inside a [Column] where you would otherwise write
/// `if (isOffline) const OfflineBanner()`. It handles all connectivity
/// awareness internally via [ConnectivityService].
class ConnectivityBanners extends StatefulWidget {
  final bool isOffline;
  final VoidCallback? onRefresh;

  const ConnectivityBanners({
    super.key,
    this.isOffline = false,
    this.onRefresh,
  });

  @override
  State<ConnectivityBanners> createState() => _ConnectivityBannersState();
}

class _ConnectivityBannersState extends State<ConnectivityBanners> {
  bool _wasDeviceOffline = false;
  bool _showOnlineBanner = false;

  @override
  void initState() {
    super.initState();
    _wasDeviceOffline = !ConnectivityService().isOnline.value;
    ConnectivityService().isOnline.addListener(_onConnectivityChanged);
  }

  void _onConnectivityChanged() {
    final online = ConnectivityService().isOnline.value;
    final wasOffline = _wasDeviceOffline;
    _wasDeviceOffline = !online;

    // Transition: was offline → now online
    if (wasOffline && online && mounted) {
      setState(() => _showOnlineBanner = true);
      // Trigger data refresh
      widget.onRefresh?.call();
      // Auto-dismiss after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _showOnlineBanner = false);
      });
    }
  }

  @override
  void dispose() {
    ConnectivityService().isOnline.removeListener(_onConnectivityChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Return a non-expanding column so it can be placed inline in any parent Column
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.isOffline) const OfflineBanner(),
        if (_showOnlineBanner) const OnlineBanner(),
      ],
    );
  }
}

// ── Avatar (premium glassmorphic) ───────────────────────────────────────────
class UserAvatar extends StatelessWidget {
  final String? photoUrl;
  final String name;
  final double size;
  final double? borderRadius;
  final double borderOpacity;

  const UserAvatar({
    super.key,
    required this.name,
    this.photoUrl,
    this.size = 48,
    this.borderRadius,
    this.borderOpacity = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final initials = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final borderWidth = size * 0.06;
    final isCircle = borderRadius == null;
    final cacheSize =
        (size * MediaQuery.of(context).devicePixelRatio * 3.0).round().clamp(512, 2048);

    return Semantics(
      image: true,
      label: name,
      child: Container(
      width: size + borderWidth * 2,
      height: size + borderWidth * 2,
      decoration: BoxDecoration(
        shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: isCircle ? null : BorderRadius.circular(borderRadius!),
        gradient: LinearGradient(
          colors: [c.accent.withValues(alpha: borderOpacity), c.accentDim.withValues(alpha: borderOpacity)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: c.accent.withValues(alpha: 0.08 * borderOpacity),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(borderWidth),
        child: ClipRRect(
          borderRadius: isCircle ? BorderRadius.circular(size / 2) : BorderRadius.circular(borderRadius!),
          child: photoUrl != null && photoUrl!.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: _avatarImageUrl(photoUrl!, width: cacheSize),
                  fit: BoxFit.cover,
                  width: size,
                  height: size,
                  memCacheWidth: cacheSize,
                  memCacheHeight: cacheSize,
                  filterQuality: FilterQuality.high,
                  placeholder: (_, __) => Container(
                    color: c.bg3,
                    child: Center(
                      child: Text(
                        initials,
                        style: GoogleFonts.exo2(
                          textStyle: TextStyle(
                            color: c.accent,
                            fontWeight: FontWeight.w700,
                            fontSize: size * 0.35,
                          ),
                        ),
                      ),
                    ),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    color: c.bg3,
                    child: Center(
                      child: Text(
                        initials,
                        style: GoogleFonts.exo2(
                          textStyle: TextStyle(
                            color: c.accent,
                            fontWeight: FontWeight.w700,
                            fontSize: size * 0.35,
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              : Container(
                  width: size,
                  height: size,
                  color: c.bg3,
                  child: Center(
                    child: Text(
                      initials,
                      style: GoogleFonts.exo2(
                        textStyle: TextStyle(
                          color: c.accent,
                          fontWeight: FontWeight.w700,
                          fontSize: size * 0.35,
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ),
    ),
    );
  }
}

// ── Subject Badge ────────────────────────────────────────────────────────────
class SubjectBadge extends StatelessWidget {
  final String label;
  const SubjectBadge({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.subjectTagBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: c.subjectTagText.withValues(alpha: 0.3), width: 0.5),
        boxShadow: [
          BoxShadow(
            color: c.subjectTagText.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        label,
        style: GoogleFonts.dmSans(
          textStyle: TextStyle(
            color: c.subjectTagText,
            fontSize: 10,
            fontWeight: FontWeight.w500,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

// ── Semester Badge ───────────────────────────────────────────────────────────
class SemesterBadge extends StatelessWidget {
  final String label;
  const SemesterBadge({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.semesterTagBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: c.semesterTagText.withValues(alpha: 0.3), width: 0.5),
        boxShadow: [
          BoxShadow(
            color: c.semesterTagText.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        label,
        style: GoogleFonts.dmSans(
          textStyle: TextStyle(
            color: c.semesterTagText,
            fontSize: 10,
            fontWeight: FontWeight.w500,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

// ── Action Icon Button (premium glassmorphic) ───────────────────────────────
class ActionIconButton extends StatefulWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool compact;
  final String? tooltip;

  const ActionIconButton({
    super.key,
    required this.icon,
    required this.color,
    required this.onTap,
    this.compact = false,
    this.tooltip,
  });

  @override
  State<ActionIconButton> createState() => _ActionIconButtonState();
}

class _ActionIconButtonState extends State<ActionIconButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnim;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 150));
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.85).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.compact ? 28.0 : 32.0;
    final iconSize = widget.compact ? 13.0 : 15.0;
    final radius = widget.compact ? 6.0 : 8.0;

    Widget button = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTapDown: (_) => _animController.forward(),
        onTapUp: (_) {
          _animController.reverse();
          _hapticLight();
          widget.onTap();
        },
        onTapCancel: () => _animController.reverse(),
        child: AnimatedBuilder(
          animation: _scaleAnim,
          builder: (context, child) => Transform.scale(
            scale: _scaleAnim.value,
            child: child,
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: _hovered
                  ? widget.color.withValues(alpha: 0.15)
                  : widget.color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: _hovered
                    ? widget.color.withValues(alpha: 0.3)
                    : widget.color.withValues(alpha: 0.1),
                width: 0.5,
              ),
              boxShadow: [
                if (_hovered)
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
              ],
            ),
            child:
                Icon(widget.icon, color: widget.color, size: iconSize),
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      button = Tooltip(message: widget.tooltip!, child: button);
    }
    return Semantics(
      button: true,
      label: widget.tooltip,
      child: button,
    );
  }
}

// ── User-friendly error messages ─────────────────────────────────────────────
String friendlyError(Object error) {
  final msg = error.toString().toLowerCase();
  if (msg.contains('socketexception') ||
      msg.contains('failed host lookup') ||
      msg.contains('network')) {
    return 'No internet connection. Please check your network.';
  }
  if (msg.contains('timeout') || msg.contains('timed out')) {
    return 'Request timed out. Please try again.';
  }
  if (msg.contains('401') ||
      msg.contains('unauthorized') ||
      msg.contains('invalid login')) {
    return 'Invalid email or password.';
  }
  if (msg.contains('403') || msg.contains('forbidden')) {
    return 'You don\'t have permission for this action.';
  }
  if (msg.contains('409') ||
      msg.contains('duplicate') ||
      msg.contains('already registered') ||
      msg.contains('already exists')) {
    return 'This record already exists.';
  }
  if (msg.contains('413') ||
      msg.contains('too large') ||
      msg.contains('file size')) {
    return 'File is too large. Please choose a smaller file.';
  }
  if (msg.contains('429') || msg.contains('too many')) {
    return 'Too many requests. Please wait and try again.';
  }
  if (msg.contains('500') ||
      msg.contains('502') ||
      msg.contains('503') ||
      msg.contains('server')) {
    return 'Server error. Please try again later.';
  }
  if (msg.contains('storageexception') || msg.contains('upload')) {
    return 'File upload failed. Please try again.';
  }
  if (msg.contains('row-level security') ||
      msg.contains('rls') ||
      msg.contains('permission denied')) {
    return 'Permission denied. Please contact admin.';
  }
  debugPrint('[Error] $error');
  return 'Something went wrong. Please try again.';
}

// ── Off Days Manager ───────────────────────────────────────────────────────
/// Shows a bottom sheet for admin to manage college off days.
/// Returns a [Future] that completes when the sheet is dismissed.
Future<void> showOffDaysManager(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _OffDaysManagerSheet(),
  );
}

class _OffDaysManagerSheet extends StatefulWidget {
  const _OffDaysManagerSheet();

  @override
  State<_OffDaysManagerSheet> createState() => _OffDaysManagerSheetState();
}

class _OffDaysManagerSheetState extends State<_OffDaysManagerSheet> {
  List<Map<String, dynamic>> _offDays = [];
  bool _loading = true;

  // Add form state
  bool _showForm = false;
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  final _reasonCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final data = await SupabaseService.getFutureOffDays();
      if (mounted) setState(() { _offDays = data; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add() async {
    setState(() => _saving = true);
    try {
      await SupabaseService.insertOffDay({
        'start_date': _startDate.toIso8601String().substring(0, 10),
        'end_date': _endDate.toIso8601String().substring(0, 10),
        'reason': _reasonCtrl.text.trim(),
        'created_by': SupabaseService.currentUser?.id,
      });
      _reasonCtrl.clear();
      _startDate = DateTime.now();
      _endDate = DateTime.now();
      setState(() => _showForm = false);
      await _fetch();
      if (mounted) showAppSnackbar(context, 'Off day added');
    } catch (e) {
      if (mounted) showAppSnackbar(context, friendlyError(e), isError: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _delete(String id) async {
    try {
      await SupabaseService.deleteOffDay(id);
      await _fetch();
      if (mounted) showAppSnackbar(context, 'Removed');
    } catch (e) {
      if (mounted) showAppSnackbar(context, friendlyError(e), isError: true);
    }
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
      builder: _datePickerTheme,
    );
    if (picked != null) {
      setState(() {
        _startDate = picked;
        if (_endDate.isBefore(picked)) _endDate = picked;
      });
    }
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: _startDate,
      lastDate: DateTime(2030),
      builder: _datePickerTheme,
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  Widget _datePickerTheme(BuildContext context, Widget? child) {
    return Theme(
      data: buildDatePickerTheme(context, Theme.of(context)),
      child: child!,
    );
  }

  String _formatDate(String dateStr) {
    try {
      return DateFormat('MMM d, yyyy').format(DateTime.parse(dateStr));
    } catch (_) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colorsOf;
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40, height: 4,
            decoration: BoxDecoration(color: c.muted.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2)),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
            child: Row(
              children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(color: c.warn.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                  child: Icon(Icons.event_busy, size: 18, color: c.warn),
                ),
                const SizedBox(width: 10),
                Text('College Off Days', style: TextStyle(color: c.white, fontSize: 17, fontWeight: FontWeight.w700)),
                const Spacer(),
                if (!_showForm)
                  GestureDetector(
                    onTap: () => setState(() => _showForm = true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: c.accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add, size: 14, color: c.accent),
                          const SizedBox(width: 4),
                          Text('Add', style: TextStyle(color: c.accent, fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Info note
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Icon(Icons.notifications_off_outlined, size: 13, color: c.warn),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Class reminders will be paused on off days',
                    style: TextStyle(color: c.warn.withValues(alpha: 0.8), fontSize: 11, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
          // Add form
          if (_showForm)
            Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: _pickStartDate,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            decoration: BoxDecoration(color: c.bg2, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.border)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('FROM', style: TextStyle(color: c.muted, fontSize: 9, fontWeight: FontWeight.w700)),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(Icons.calendar_today, size: 14, color: c.accent),
                                    const SizedBox(width: 6),
                                    Text(_formatDate(_startDate.toIso8601String().substring(0, 10)), style: TextStyle(color: c.white, fontSize: 13)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(Icons.arrow_forward, color: c.muted, size: 16),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: _pickEndDate,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            decoration: BoxDecoration(color: c.bg2, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.border)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('TO', style: TextStyle(color: c.muted, fontSize: 9, fontWeight: FontWeight.w700)),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(Icons.calendar_today, size: 14, color: c.accent),
                                    const SizedBox(width: 6),
                                    Text(_formatDate(_endDate.toIso8601String().substring(0, 10)), style: TextStyle(color: c.white, fontSize: 13)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _ReasonField(c: c, controller: _reasonCtrl),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _showForm = false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: c.border)),
                            child: Center(child: Text('Cancel', style: TextStyle(color: c.muted, fontSize: 13))),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: _saving ? null : _add,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(10)),
                            child: Center(
                              child: _saving
                                  ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : Text('Save', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          // List of off days
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _offDays.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.event_busy, size: 40, color: c.muted.withValues(alpha: 0.4)),
                            const SizedBox(height: 12),
                            Text('No off days scheduled', style: TextStyle(color: c.muted, fontSize: 14)),
                            Text('Add upcoming holidays or breaks', style: TextStyle(color: c.muted.withValues(alpha: 0.6), fontSize: 12)),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(20),
                        itemCount: _offDays.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final d = _offDays[i];
                          final start = d['start_date']?.toString() ?? '';
                          final end = d['end_date']?.toString() ?? '';
                          final reason = d['reason']?.toString() ?? '';
                          final today = DateTime.now().toIso8601String().substring(0, 10);
                          final isActive = start.compareTo(today) <= 0 && today.compareTo(end) <= 0;
                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isActive ? c.warn.withValues(alpha: 0.08) : c.bg2,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: isActive ? c.warn.withValues(alpha: 0.3) : c.border),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 36, height: 36,
                                  decoration: BoxDecoration(
                                    color: isActive ? c.warn.withValues(alpha: 0.15) : c.bg3,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    isActive ? Icons.warning_amber : Icons.event,
                                    color: isActive ? c.warn : c.muted,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            '${_formatDate(start)} – ${_formatDate(end)}',
                                            style: TextStyle(color: c.white, fontSize: 13, fontWeight: FontWeight.w600),
                                          ),
                                          if (isActive) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(color: c.warn.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                                              child: Text('NOW', style: TextStyle(color: c.warn, fontSize: 9, fontWeight: FontWeight.w700)),
                                            ),
                                          ],
                                        ],
                                      ),
                                      if (reason.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(reason, style: TextStyle(color: c.muted, fontSize: 12)),
                                      ],
                                    ],
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => _delete(d['id']?.toString() ?? ''),
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(color: c.danger.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                                    child: Icon(Icons.delete_outline, size: 16, color: c.danger),
                                  ),
                                ),
                              ],
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

// ── Reason Field (premium glassmorphic, blue border on focus) ─────────────
class _ReasonField extends StatefulWidget {
  final ThemeColors c;
  final TextEditingController controller;
  const _ReasonField({required this.c, required this.controller});

  @override
  State<_ReasonField> createState() => _ReasonFieldState();
}

class _ReasonFieldState extends State<_ReasonField> {
  final _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (mounted) setState(() => _focused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: c.bg2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _focused ? c.accent : c.border,
            width: _focused ? 1.5 : 1.0,
          ),
          boxShadow: _focused
              ? [BoxShadow(color: c.accent.withValues(alpha: 0.08), blurRadius: 6, offset: const Offset(0, 2))]
              : [],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: TextField(
          focusNode: _focusNode,
          controller: widget.controller,
          style: TextStyle(color: c.text, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Reason (e.g. Holiday, Exam Week...)',
            hintStyle: TextStyle(color: c.muted.withValues(alpha: 0.5), fontSize: 13),
            filled: true,
            fillColor: c.bg2,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
    );
  }
}

// ── Off Days Banner ──────────────────────────────────────────────────────────
/// Banner shown on the routine screen when college is off today or within the week.
class OffDaysBanner extends StatelessWidget {
  final List<Map<String, dynamic>> offDays;

  const OffDaysBanner({super.key, required this.offDays});

  @override
  Widget build(BuildContext context) {
    final c = context.colorsOf;
    final today = DateTime.now().toIso8601String().substring(0, 10);

    // Current off period (today is within range)
    final current = offDays.where((d) {
      final s = d['start_date']?.toString() ?? '';
      final e = d['end_date']?.toString() ?? '';return s.compareTo(today) <= 0 && today.compareTo(e) <= 0;
        }).toList();

    if (current.isEmpty) return const SizedBox.shrink();

    final reasons = current.map((d) => d['reason']?.toString() ?? '').where((r) => r.isNotEmpty).toList();
    final reasonText = reasons.isNotEmpty ? ' · ${reasons.join(', ')}' : '';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [c.warn.withValues(alpha: 0.12), c.warn.withValues(alpha: 0.04)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.warn.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(color: c.warn.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
            child: Icon(Icons.event_busy, size: 16, color: c.warn),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'College is off today$reasonText',
              style: TextStyle(color: c.warn, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.1, end: 0, duration: 300.ms);
  }
}

// ── Date Picker Theme Builder ──────────────────────────────────────────────
/// Builds a [ThemeData] for [showDatePicker] / [showTimePicker] that works
/// correctly in both light and dark modes.
///
/// The key fix: in light mode the default Material date picker uses
/// [onSurfaceVariant] for header labels (month/year, weekday names).
/// If that color is light (as in [ColorScheme.dark]), those labels become
/// invisible on a light [surface]. This builder ensures all text colors
/// are properly set for the current brightness.
ThemeData buildDatePickerTheme(BuildContext context, ThemeData base) {
  final c = context.colorsOf;
  final isLight = c.isLight;

  // Start with the correct brightness, then override only the specific slots
  // that need to match the app's custom palette.
  final scheme = (isLight ? ColorScheme.light() : ColorScheme.dark()).copyWith(
    primary: c.accent,
    onPrimary: Colors.white,
    primaryContainer: c.accent.withValues(alpha: 0.2),
    onPrimaryContainer: c.accent,
    surface: c.bg2,
    onSurface: isLight ? c.text : c.white,
    onSurfaceVariant: c.muted,
    outline: c.border,
  );

  return base.copyWith(
    colorScheme: scheme,
  );
}

// ── Toast / Snackbar helper ──────────────────────────────────────────────────
void showAppSnackbar(BuildContext context, String message,
    {bool isError = false}) {
  final c = context.colorsOf;
  final color = isError ? c.danger : c.accent2;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.dmSans(
                textStyle: const TextStyle(
                  fontSize: 13,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
        ],
      ),
      backgroundColor: c.bg2,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.3)),
      ),
      elevation: 4,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    ),
  );
}
