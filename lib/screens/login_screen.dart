import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../services/auth_service.dart';
import '../services/sync_service.dart';

class LoginScreen extends StatefulWidget {
  final bool isSignup;
  const LoginScreen({super.key, required this.isSignup});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late bool _isSignup;
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  bool _obscure = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _isSignup = widget.isSignup;
  }

  Future<void> _submit() async {
    setState(() => _errorMessage = null);
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;

    if (email.isEmpty || pass.isEmpty) {
      setState(() => _errorMessage = 'Please fill in all fields.');
      return;
    }
    if (_isSignup && pass != _confirmPassCtrl.text) {
      setState(() => _errorMessage = 'Passwords do not match.');
      return;
    }

    final auth = context.read<AuthService>();
    try {
      if (_isSignup) {
        await auth.signUp(email, pass);
      } else {
        await auth.login(email, pass);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _errorMessage = e.toString().replaceAll('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = context.watch<SyncService>().isOnline;

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        backgroundColor: AppColors.bgPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppColors.textSecondary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _isSignup ? 'Create Account' : 'Login',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isOnline)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.wifi_off, color: AppColors.warning, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Login requires internet. Use No Internet Mode to access cached data.',
                      style: GoogleFonts.inter(fontSize: 12, color: AppColors.warning),
                    ),
                  ),
                ]),
              ),
            _inputField('Email', _emailCtrl, TextInputType.emailAddress),
            const SizedBox(height: 14),
            _inputField('Password', _passCtrl, TextInputType.visiblePassword, obscure: _obscure,
              suffix: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                    color: AppColors.textSecondary, size: 18),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            if (_isSignup) ...[
              const SizedBox(height: 14),
              _inputField('Confirm Password', _confirmPassCtrl, TextInputType.visiblePassword, obscure: true),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                ),
                child: Text(_errorMessage!,
                    style: GoogleFonts.inter(fontSize: 13, color: AppColors.danger)),
              ),
            ],
            const SizedBox(height: 24),
            Consumer<AuthService>(builder: (_, auth, __) {
              final canSubmit = isOnline && !auth.isLoading;
              return SizedBox(
                width: double.infinity,
                height: 52,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: canSubmit ? AppColors.accentGradient : null,
                    color: canSubmit ? null : AppColors.border,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: canSubmit ? AppColors.accentShadow : null,
                  ),
                  child: ElevatedButton(
                    onPressed: canSubmit ? _submit : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      disabledBackgroundColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: auth.isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Text(
                            _isSignup ? 'Create Account' : 'Sign In',
                            style: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: Colors.white)),
                  ),
                ),
              );
            }),
            const SizedBox(height: 16),
            Center(
              child: TextButton(
                onPressed: () => setState(() => _isSignup = !_isSignup),
                child: Text(
                  _isSignup
                      ? 'Already have an account? Login'
                      : "Don't have an account? Sign Up",
                  style: GoogleFonts.inter(fontSize: 13, color: AppColors.accentPrimary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _inputField(String label, TextEditingController ctrl, TextInputType type,
      {bool obscure = false, Widget? suffix}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: AppColors.bgElevated,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
          ),
          child: TextField(
            controller: ctrl,
            keyboardType: type,
            obscureText: obscure,
            style: GoogleFonts.inter(fontSize: 14, color: AppColors.textPrimary),
            decoration: InputDecoration(
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              suffixIcon: suffix,
            ),
          ),
        ),
      ],
    );
  }
}
