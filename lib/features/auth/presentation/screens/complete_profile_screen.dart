import 'package:flutter/material.dart';

import '../../../../core/constants/universities.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/widgets/app_loader.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../main_navigation_shell.dart';
import 'login_screen.dart';

const Color _purple = Color(0xFF6B4EFF);
const Color _purpleDark = Color(0xFF5635D8);
const Color _ink = Color(0xFF16124A);
const Color _muted = Color(0xFF67608A);
const Color _fieldBg = Color(0xFFF1EEFB);

/// Mandatory step before the app opens whenever name, stage or university is
/// missing: new Google accounts (Google gives name + email only) and old
/// accounts that skipped it in earlier versions. Existing progress and
/// subscription are kept; only these three fields are written.
class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _nameController = TextEditingController();
  String? _selectedStage;
  String? _selectedUniversity;
  // University already saved on the account → shown as plain text, not
  // tappable (changing it is owner-only).
  String? _lockedUniversity;
  bool _profileLoaded = false;
  bool _agreeTerms = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final meta = SupabaseService().currentUser?.userMetadata;
    final googleName = (meta?['full_name'] ?? meta?['name'] ?? '').toString();
    _nameController.text = googleName.trim();
    _prefillFromProfile();
  }

  /// Old accounts may already have some fields — show them pre-selected.
  /// A saved university cannot be changed here, only filled when empty.
  Future<void> _prefillFromProfile() async {
    final details = await SupabaseService().getUserDetails();
    if (!mounted) return;
    final name = details?['name']?.toString().trim() ?? '';
    final stage = details?['stage']?.toString().trim();
    final university = details?['university']?.toString().trim() ?? '';
    setState(() {
      // 'مستخدم جديد' is the placeholder the handle_new_user DB trigger writes
      // when Google gives no name — keep the Google name / empty field instead.
      if (name.isNotEmpty && name != 'مستخدم جديد') {
        _nameController.text = name;
      }
      if (_selectedStage == null && kStages.contains(stage)) {
        _selectedStage = stage;
      }
      if (university.isNotEmpty) _lockedUniversity = university;
      _profileLoaded = true;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _handleContinue() async {
    if (!_profileLoaded) return;
    final name = _nameController.text.trim();
    final university = _lockedUniversity ?? _selectedUniversity;
    if (name.isEmpty) {
      _showError('يرجى إدخال الاسم الكامل');
      return;
    }
    if (_selectedStage == null) {
      _showError('اختيار المرحلة إجباري، يرجى تحديد مرحلتك الدراسية');
      return;
    }
    if (university == null) {
      _showError('اختيار الجامعة إجباري، يرجى تحديد جامعتك');
      return;
    }
    if (!_agreeTerms) {
      _showError('يجب الموافقة على الشروط والأحكام');
      return;
    }

    final supabase = SupabaseService();
    final user = supabase.currentUser;
    if (user == null) {
      _goToLogin();
      return;
    }

    setState(() => _loading = true);
    try {
      await supabase.saveRequiredProfile(
        name: name,
        stage: _selectedStage!,
        university: university,
      );

      // Confirm the saved row really has all mandatory fields.
      final complete = await supabase.isProfileComplete();
      if (!mounted) return;
      if (complete != true) {
        _showError('تعذر حفظ البيانات، تحقق من الاتصال وحاول مرة أخرى');
        return;
      }
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainNavigationShell()),
        (route) => false,
      );
    } catch (e) {
      debugPrint('Save profile error: $e');
      if (mounted) _showError('تعذر حفظ البيانات، يرجى المحاولة مرة أخرى');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signOutAndBack() async {
    try {
      await SupabaseService().signOut();
    } catch (_) {}
    if (mounted) _goToLogin();
  }

  void _goToLogin() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _showError(String message) {
    showAppToast(context, message, isError: true);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _signOutAndBack();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F4FF),
        body: Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: _loading ? null : _signOutAndBack,
                      icon: const Icon(Icons.logout_rounded,
                          color: _muted, size: 20),
                      label: const Text('تسجيل الخروج',
                          style: TextStyle(
                              color: _muted,
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('أكمل بياناتك',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: _ink,
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.w900,
                          fontSize: 24)),
                  const SizedBox(height: 6),
                  const Text(
                      'خطوة واحدة فقط لعرض المواد المناسبة لمرحلتك وجامعتك',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: _muted, fontFamily: 'Cairo', fontSize: 14)),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                            color: _purple.withValues(alpha: 0.11),
                            blurRadius: 28,
                            offset: const Offset(0, 16)),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _Label('الاسم الكامل'),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _nameController,
                          style: const TextStyle(
                              color: _ink,
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.w700,
                              fontSize: 15),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: _fieldBg,
                            hintText: 'اكتب اسمك الكامل',
                            hintStyle: const TextStyle(
                                color: _muted,
                                fontFamily: 'Cairo',
                                fontSize: 14),
                            prefixIcon: const Icon(Icons.person_outline_rounded,
                                color: _muted, size: 22),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(15),
                                borderSide: BorderSide.none),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 16),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const _Label('المرحلة *'),
                        const SizedBox(height: 8),
                        _Dropdown(
                          value: _selectedStage,
                          items: kStages,
                          hint: 'اختر مرحلتك',
                          onChanged: (v) => setState(() => _selectedStage = v),
                        ),
                        const SizedBox(height: 16),
                        const _Label('الجامعة *'),
                        const SizedBox(height: 8),
                        if (!_profileLoaded)
                          const SizedBox(
                              height: 54,
                              child: Center(
                                  child: MiniSpinner(
                                      size: 22, color: _purple)))
                        else if (_lockedUniversity != null)
                          _LockedField(text: _lockedUniversity!)
                        else
                          _Dropdown(
                            value: _selectedUniversity,
                            items: kUniversities,
                            hint: 'اختر جامعتك',
                            onChanged: (v) =>
                                setState(() => _selectedUniversity = v),
                          ),
                        const SizedBox(height: 16),
                        InkWell(
                          onTap: () =>
                              setState(() => _agreeTerms = !_agreeTerms),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                      color:
                                          _agreeTerms ? _purple : Colors.white,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                          color: _purple, width: 1.5)),
                                  child: _agreeTerms
                                      ? const Icon(Icons.check_rounded,
                                          color: Colors.white, size: 16)
                                      : null,
                                ),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Text('أوافق على الشروط والأحكام',
                                      style: TextStyle(
                                          color: _ink,
                                          fontFamily: 'Cairo',
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700)),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),
                        _loading
                            ? const Center(
                                child: MiniSpinner(size: 34, color: _purple))
                            : _ContinueButton(onTap: _handleContinue),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          color: _ink,
          fontFamily: 'Cairo',
          fontWeight: FontWeight.w800,
          fontSize: 14));
}

class _Dropdown extends StatelessWidget {
  final String? value;
  final List<String> items;
  final String hint;
  final ValueChanged<String?> onChanged;

  const _Dropdown(
      {required this.value,
      required this.items,
      required this.hint,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    // The popup list follows the app theme (dark in dark mode) but the field
    // itself is always light → white items on a dark popup, ink on a light one;
    // the chosen value inside the field stays ink.
    final popupIsDark = Theme.of(context).canvasColor.computeLuminance() < 0.5;
    const fieldText = TextStyle(
        color: _ink,
        fontSize: 13,
        fontWeight: FontWeight.w700,
        fontFamily: 'Cairo');
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
          color: _fieldBg, borderRadius: BorderRadius.circular(15)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          iconEnabledColor: _muted,
          hint: Text(hint,
              style: const TextStyle(
                  color: _muted, fontSize: 13, fontFamily: 'Cairo')),
          style: fieldText.copyWith(
              color: popupIsDark ? Colors.white : _ink),
          selectedItemBuilder: (_) => items
              .map((item) => Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(item,
                      overflow: TextOverflow.ellipsis, style: fieldText)))
              .toList(),
          items: items
              .map((item) => DropdownMenuItem<String>(
                  value: item,
                  child: Text(item, overflow: TextOverflow.ellipsis)))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _LockedField extends StatelessWidget {
  final String text;
  const _LockedField({required this.text});

  @override
  Widget build(BuildContext context) => Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
            color: _fieldBg, borderRadius: BorderRadius.circular(15)),
        alignment: AlignmentDirectional.centerStart,
        // Plain text, no tap action, no hint — the saved university is
        // simply shown (changing it is owner-only, from the profile screen).
        child: Text(text,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: _ink,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFamily: 'Cairo')),
      );
}

class _ContinueButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ContinueButton({required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            height: 54,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF7B5EFF), _purpleDark]),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                    color: _purple.withValues(alpha: 0.34),
                    blurRadius: 18,
                    offset: const Offset(0, 8)),
              ],
            ),
            child: const Center(
              child: Text('متابعة',
                  style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w900,
                      fontSize: 17)),
            ),
          ),
        ),
      );
}
