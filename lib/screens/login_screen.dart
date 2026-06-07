import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import '../utils/theme_provider.dart';
import '../utils/responsive.dart';
import '../widgets/common.dart';
import '../widgets/theme_picker.dart';

class LoginScreen extends StatefulWidget {
  /// Set to true before navigating to LoginScreen to show rejection message.
  static bool showRejectedMessage = false;

  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLogin = true;
  bool _loading = false;
  bool _obscure = true;
  String _userType = 'student'; // 'student' | 'teacher'

  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    // If this user was rejected (auth deleted by admin), show message and
    // switch to registration so they can re-register immediately.
    if (LoginScreen.showRejectedMessage) {
      LoginScreen.showRejectedMessage = false;
      _isLogin = false; // switch to registration form
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          showAppSnackbar(
              context, 'You have been rejected. Please register again.',
              isError: true);
        }
      });
    }
  }

  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _rollCtrl = TextEditingController();
  final _regCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _sessionCtrl = TextEditingController();
  // Teacher-specific
  final _subjectCtrl = TextEditingController();
  final _designationCtrl = TextEditingController();
  String _semester = '1st';
  String _shift = 'Day';

  static const _semesters = [
    '1st',
    '2nd',
    '3rd',
    '4th',
    '5th',
    '6th',
    '7th',
    '8th'
  ];
  static const _shifts = ['Morning', 'Day'];

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _nameCtrl.dispose();
    _rollCtrl.dispose();
    _regCtrl.dispose();
    _contactCtrl.dispose();
    _sessionCtrl.dispose();
    _subjectCtrl.dispose();
    _designationCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      if (_isLogin) {
        final res = await SupabaseService.signIn(
            _emailCtrl.text.trim(), _passCtrl.text);
        if (res.user == null) throw Exception('Login failed');
      } else {
        // We pass all fields as user metadata so the database trigger
        // (handle_new_user) can populate the profiles table.
        // 'status' defaults to 'pending', 'is_admin' defaults to false.
        final metadata = <String, dynamic>{
          'name': _nameCtrl.text.trim(),
          'role': _userType, // 'student' or 'teacher'
        };
        if (_userType == 'student') {
          metadata.addAll({
            'roll': _rollCtrl.text.trim(),
            'registration': _regCtrl.text.trim(),
            'contact': _contactCtrl.text.trim(),
            'semester': SupabaseService.semesterToInt(_semester),
            'shift': _shift,
            'session': _sessionCtrl.text.trim(),
          });
        } else {
          metadata.addAll({
            'contact': _contactCtrl.text.trim(),
            'subject': _subjectCtrl.text.trim(),
            'designation': _designationCtrl.text.trim(),
          });
        }
        final res = await SupabaseService.signUp(
            _emailCtrl.text.trim(), _passCtrl.text,
            data: metadata);
        if (res.user == null) throw Exception('Registration failed');
        if (mounted) {
          showAppSnackbar(context, '✅ Registered! Waiting for admin approval.');
          setState(() {
            _isLogin = true;
            _loading = false;
          });
          return;
        }
      }
    } on AuthException catch (e) {
      if (mounted) showAppSnackbar(context, e.message, isError: true);
    } catch (e) {
      if (mounted) showAppSnackbar(context, friendlyError(e), isError: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: Responsive.screenPadding(context),
                  vertical: 24,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 20),
                      // Logo
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: c.accent,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Center(
                            child: Icon(Icons.school, color: Colors.white, size: 36)),
                      )
                          .animate()
                          .fadeIn(duration: 500.ms, curve: Curves.easeOut)
                          .scale(
                              begin: const Offset(0.8, 0.8),
                              duration: 500.ms,
                              curve: Curves.easeOutBack),
                      const SizedBox(height: 20),
                      Text(
                        'CST Department',
                        style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: c.white),
                      )
                          .animate()
                          .fadeIn(
                              duration: 400.ms,
                              delay: 150.ms,
                              curve: Curves.easeOut)
                          .slideY(
                              begin: 16,
                              end: 0,
                              duration: 400.ms,
                              delay: 150.ms,
                              curve: Curves.easeOut),
                      const SizedBox(height: 6),
                      Text(
                        _isLogin
                            ? 'Welcome back! Sign in to continue.'
                            : _userType == 'student'
                                ? 'Student Registration'
                                : 'Teacher Registration',
                        style: TextStyle(color: c.muted, fontSize: 14),
                        textAlign: TextAlign.center,
                      )
                          .animate()
                          .fadeIn(
                              duration: 400.ms,
                              delay: 250.ms,
                              curve: Curves.easeOut)
                          .slideY(
                              begin: 12,
                              end: 0,
                              duration: 400.ms,
                              delay: 250.ms,
                              curve: Curves.easeOut),
                      const SizedBox(height: 28),

                      // Form
                      AppCard(
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!_isLogin) ...[
                                // Student / Teacher toggle
                                Container(
                                  decoration: BoxDecoration(
                                    color: c.bg2,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: c.border),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: () => setState(
                                              () => _userType = 'student'),
                                          child: AnimatedContainer(
                                            duration: const Duration(
                                                milliseconds: 200),
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 12),
                                            decoration: BoxDecoration(
                                              color: _userType == 'student'
                                                  ? c.accent
                                                      .withValues(alpha: 0.15)
                                                  : Colors.transparent,
                                              borderRadius:
                                                  BorderRadius.circular(11),
                                              border: _userType == 'student'
                                                  ? Border.all(
                                                      color: c.accent
                                                          .withValues(
                                                              alpha: 0.4))
                                                  : null,
                                            ),
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Icon(Icons.school,
                                                    size: 14,
                                                    color: _userType ==
                                                            'student'
                                                        ? c.white
                                                        : c.muted),
                                                const SizedBox(width: 6),
                                                Text(
                                                  'Student',
                                                  style: TextStyle(
                                                    color:
                                                        _userType == 'student'
                                                            ? c.accent
                                                            : c.muted,
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: () => setState(
                                              () => _userType = 'teacher'),
                                          child: AnimatedContainer(
                                            duration: const Duration(
                                                milliseconds: 200),
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 12),
                                            decoration: BoxDecoration(
                                              color: _userType == 'teacher'
                                                  ? c.accent
                                                      .withValues(alpha: 0.15)
                                                  : Colors.transparent,
                                              borderRadius:
                                                  BorderRadius.circular(11),
                                              border: _userType == 'teacher'
                                                  ? Border.all(
                                                      color: c.accent
                                                          .withValues(
                                                              alpha: 0.4))
                                                  : null,
                                            ),
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Icon(Icons.person,
                                                    size: 14,
                                                    color: _userType ==
                                                            'teacher'
                                                        ? c.white
                                                        : c.muted),
                                                const SizedBox(width: 6),
                                                Text(
                                                  'Teacher',
                                                  style: TextStyle(
                                                    color:
                                                        _userType == 'teacher'
                                                            ? c.accent
                                                            : c.muted,
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                                AppTextField(
                                  label: 'Full Name',
                                  hint: 'Your full name',
                                  controller: _nameCtrl,
                                  prefixIcon: Icons.person_outline,
                                  validator: (v) => v == null || v.isEmpty
                                      ? 'Required'
                                      : null,
                                ),
                                const SizedBox(height: 16),
                              ],
                              AppTextField(
                                label: 'Email',
                                hint: 'your@email.com',
                                controller: _emailCtrl,
                                prefixIcon: Icons.email_outlined,
                                keyboardType: TextInputType.emailAddress,
                                validator: (v) => v == null || !v.contains('@')
                                    ? 'Valid email required'
                                    : null,
                              ),
                              const SizedBox(height: 16),
                              AppTextField(
                                label: 'Password',
                                hint: '••••••••',
                                controller: _passCtrl,
                                obscureText: _obscure,
                                prefixIcon: Icons.lock_outline,
                                validator: (v) => v == null || v.length < 6
                                    ? 'Min 6 characters'
                                    : null,
                                suffix: GestureDetector(
                                  onTap: () =>
                                      setState(() => _obscure = !_obscure),
                                  child: Icon(
                                      _obscure
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                      size: 18,
                                      color: c.muted),
                                ),
                              ),
                              if (!_isLogin) ...[
                                const SizedBox(height: 16),
                                if (_userType == 'student') ...[
                                  AppTextField(
                                      label: 'Roll No',
                                      hint: 'e.g. 123456',
                                      controller: _rollCtrl,
                                      prefixIcon: Icons.badge_outlined,
                                      validator: (v) => v == null || v.isEmpty
                                          ? 'Required'
                                          : null),
                                  const SizedBox(height: 16),
                                  AppTextField(
                                      label: 'Registration No',
                                      hint: 'e.g. REG-2021',
                                      controller: _regCtrl,
                                      prefixIcon:
                                          Icons.card_membership_outlined,
                                      validator: (v) => v == null || v.isEmpty
                                          ? 'Required'
                                          : null),
                                  const SizedBox(height: 16),
                                  AppTextField(
                                      label: 'Contact',
                                      hint: '01XXXXXXXXX',
                                      controller: _contactCtrl,
                                      prefixIcon: Icons.phone_outlined,
                                      keyboardType: TextInputType.phone,
                                      validator: (v) => v == null || v.isEmpty
                                          ? 'Required'
                                          : null),
                                  const SizedBox(height: 16),
                                  AppTextField(
                                      label: 'Session',
                                      hint: 'e.g. 2021-2022',
                                      controller: _sessionCtrl,
                                      prefixIcon:
                                          Icons.calendar_today_outlined,
                                      validator: (v) => v == null || v.isEmpty
                                          ? 'Required'
                                          : null),
                                  const SizedBox(height: 16),
                                  _buildDropdownRow(),
                                ] else ...[
                                  AppTextField(
                                      label: 'Subject',
                                      hint: 'e.g. Data Structures',
                                      controller: _subjectCtrl,
                                      prefixIcon: Icons.book_outlined,
                                      validator: (v) => v == null || v.isEmpty
                                          ? 'Required'
                                          : null),
                                  const SizedBox(height: 16),
                                  AppTextField(
                                      label: 'Designation',
                                      hint: 'e.g. Lecturer',
                                      controller: _designationCtrl,
                                      prefixIcon: Icons.work_outline,
                                      validator: (v) => v == null || v.isEmpty
                                          ? 'Required'
                                          : null),
                                  const SizedBox(height: 16),
                                  AppTextField(
                                      label: 'Phone',
                                      hint: '01XXXXXXXXX',
                                      controller: _contactCtrl,
                                      prefixIcon: Icons.phone_outlined,
                                      keyboardType: TextInputType.phone,
                                      validator: (v) => v == null || v.isEmpty
                                          ? 'Required'
                                          : null),
                                ],
                              ],
                              const SizedBox(height: 24),
                              PrimaryButton(
                                label: _isLogin
                                    ? 'Sign In'
                                    : _userType == 'student'
                                        ? 'Register as Student'
                                        : 'Register as Teacher',
                                onPressed: _submit,
                                loading: _loading,
                                icon: _isLogin ? Icons.login : Icons.person_add,
                              )
                                  .animate()
                                  .fadeIn(
                                      duration: 400.ms,
                                      delay: 400.ms,
                                      curve: Curves.easeOut)
                                  .slideY(
                                      begin: 12,
                                      end: 0,
                                      duration: 400.ms,
                                      delay: 400.ms,
                                      curve: Curves.easeOut),

                              const SizedBox(height: 16),
                              Center(
                                child: GestureDetector(
                                  onTap: () =>
                                      setState(() => _isLogin = !_isLogin),
                                  child: RichText(
                                    text: TextSpan(
                                      style: TextStyle(
                                          color: c.muted, fontSize: 13),
                                      children: [
                                        TextSpan(
                                            text: _isLogin
                                                ? "Don't have an account? "
                                                : "Already have an account? "),
                                        TextSpan(
                                          text:
                                              _isLogin ? 'Register' : 'Sign In',
                                          style: TextStyle(
                                              color: c.accent,
                                              fontWeight: FontWeight.w700),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                          .animate()
                          .fadeIn(
                              duration: 400.ms,
                              delay: 300.ms,
                              curve: Curves.easeOut)
                          .slideY(
                              begin: 16,
                              end: 0,
                              duration: 400.ms,
                              delay: 300.ms,
                              curve: Curves.easeOut),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
            // Theme picker button
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: Icon(Icons.palette_outlined, color: c.muted, size: 22),
                onPressed: () => showThemePicker(context),
                tooltip: 'Change Theme',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdownRow() {
    final c = context.colors;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('SEMESTER',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: c.muted)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: c.bg3,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _semester,
                    dropdownColor: c.bg2,
                    style: TextStyle(color: c.text, fontSize: 14),
                    isExpanded: true,
                    items: _semesters
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _semester = v);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('SHIFT',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: c.muted)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: c.bg3,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _shift,
                    dropdownColor: c.bg2,
                    style: TextStyle(color: c.text, fontSize: 14),
                    isExpanded: true,
                    items: _shifts
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _shift = v);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
