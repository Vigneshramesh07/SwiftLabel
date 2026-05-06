import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'dashboard_screen.dart';

const String _demoEmail = 'demo@swiftlabel.co.uk';
const String _demoOtp   = '123456';

class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final List<TextEditingController> _controllers =
  List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes =
  List.generate(6, (_) => FocusNode());

  int  _countdown   = 30;
  bool _canResend   = false;
  bool _isVerifying = false;

  @override
  void initState() {
    super.initState();
    _startTimer();

    // ── Demo auto-fill ──────────────────────────────────────────
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final email = context.read<AuthProvider>().email;
      if (email == _demoEmail) {
        for (int i = 0; i < 6; i++) {
          _controllers[i].text = _demoOtp[i];
        }
        // Auto-verify after short delay so reviewer can see the filled boxes
        Future.delayed(const Duration(milliseconds: 700), () {
          if (mounted) _handleVerify();
        });
      } else {
        _focusNodes[0].requestFocus();
      }
    });
  }

  void _startTimer() {
    setState(() { _countdown = 30; _canResend = false; });
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() {
        if (_countdown > 0) { _countdown--; }
        else { _canResend = true; }
      });
      return _countdown > 0;
    });
  }

  @override
  void dispose() {
    for (final c in _controllers) c.dispose();
    for (final f in _focusNodes) f.dispose();
    super.dispose();
  }

  String get _otpCode => _controllers.map((c) => c.text).join();

  void _onDigitChanged(int index, String value) {
    if (value.length > 1) {
      _controllers[index].text = value[value.length - 1];
    }
    context.read<AuthProvider>().resetError();

    if (value.isNotEmpty && index < 5) {
      _focusNodes[index + 1].requestFocus();
    }
    if (index == 5 && _otpCode.length == 6) {
      Future.microtask(() => _handleVerify());
    }
  }

  Future<void> _handleVerify() async {
    if (_isVerifying) return;
    if (_otpCode.length < 6) return;

    setState(() => _isVerifying = true);

    final auth    = context.read<AuthProvider>();
    final success = await auth.verifyOtp(_otpCode);

    if (mounted) setState(() => _isVerifying = false);

    if (mounted && success) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
            (route) => false,
      );
    } else if (mounted && !success) {
      // Don't clear boxes for demo account — backend may not have bypass yet
      final email = context.read<AuthProvider>().email;
      if (email != _demoEmail) {
        for (final c in _controllers) c.clear();
        _focusNodes[0].requestFocus();
      }
    }
  }

  Future<void> _handleResend() async {
    for (final c in _controllers) c.clear();
    _focusNodes[0].requestFocus();
    context.read<AuthProvider>().resetError();

    final auth = context.read<AuthProvider>();
    await auth.sendOtp(auth.email);

    if (mounted && auth.status == AuthStatus.error) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(auth.errorMessage),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      return;
    }

    _startTimer();
  }

  @override
  Widget build(BuildContext context) {
    final auth      = context.watch<AuthProvider>();
    final isLoading = auth.status == AuthStatus.loading;
    final hasError  = auth.status == AuthStatus.error;
    final isDemo    = auth.email == _demoEmail;

    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F7),
      body: SafeArea(
        child: Column(
          children: [
            _TopNavBar(onBack: () => Navigator.pop(context)),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 48),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF5EE),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFFFE0CC)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // ── Icon ─────────────────────
                            Container(
                              width: 64, height: 64,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFFF7A2F), Color(0xFFFF5A00)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [BoxShadow(
                                  color: const Color(0xFFFF5A00).withOpacity(0.3),
                                  blurRadius: 16, offset: const Offset(0, 6),
                                )],
                              ),
                              child: const Icon(Icons.mark_email_read_outlined,
                                  color: Colors.white, size: 30),
                            ),
                            const SizedBox(height: 24),

                            const Text('Check Your Email',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontFamily: 'Syne', fontSize: 24,
                                  fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A)),
                            ),
                            const SizedBox(height: 12),

                            Text(
                              isDemo
                                  ? 'Demo mode — access code auto-filled for review.'
                                  : "We've sent a 6-digit secure access code to",
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 14, color: Color(0xFF6B6B6B), height: 1.6),
                            ),

                            Text(
                              auth.email,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 14,
                                  fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A)),
                            ),

                            if (!isDemo) ...[
                              const SizedBox(height: 6),
                              const Text(
                                'Check your inbox and spam folder.',
                                style: TextStyle(fontSize: 12, color: Color(0xFF9B9B9B)),
                              ),
                            ],

                            const SizedBox(height: 16),

                            // // ── Demo info banner ──────────
                            // if (isDemo)
                            //   Container(
                            //     width: double.infinity,
                            //     padding: const EdgeInsets.all(12),
                            //     margin: const EdgeInsets.only(bottom: 8),
                            //     decoration: BoxDecoration(
                            //       color: const Color(0xFFF0F7FF),
                            //       borderRadius: BorderRadius.circular(10),
                            //       border: Border.all(color: const Color(0xFFB5D4F4)),
                            //     ),
                            //     child: const Row(children: [
                            //       Icon(Icons.preview_rounded,
                            //           size: 14, color: Color(0xFF378ADD)),
                            //       SizedBox(width: 8),
                            //       Expanded(
                            //         child: Text(
                            //           'Demo review — OTP 123456 auto-filled. Logging you in...',
                            //           style: TextStyle(
                            //               fontSize: 12,
                            //               color: Color(0xFF185FA5),
                            //               fontWeight: FontWeight.w500),
                            //         ),
                            //       ),
                            //     ]),
                            //   ),
                            //
                            // const SizedBox(height: 16),

                            const Align(
                              alignment: Alignment.centerLeft,
                              child: Text('Enter Access Code',
                                  style: TextStyle(fontSize: 13,
                                      fontWeight: FontWeight.w600, color: Color(0xFF3A3A3A))),
                            ),
                            const SizedBox(height: 10),

                            // ── OTP Boxes ─────────────────
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: List.generate(6, (i) {
                                return SizedBox(
                                  width: 40, height: 52,
                                  child: TextFormField(
                                    controller: _controllers[i],
                                    focusNode: _focusNodes[i],
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.center,
                                    maxLength: 1,
                                    style: const TextStyle(
                                        fontSize: 22, fontWeight: FontWeight.w700,
                                        color: Color(0xFF1A1A1A)),
                                    decoration: InputDecoration(
                                      counterText: '',
                                      filled: true,
                                      fillColor: Colors.white,
                                      contentPadding: EdgeInsets.zero,
                                      border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          borderSide: BorderSide(
                                              color: hasError ? Colors.red : const Color(0xFFE0E0E0))),
                                      enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          borderSide: BorderSide(
                                              color: hasError ? Colors.red : const Color(0xFFE0E0E0))),
                                      focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          borderSide: const BorderSide(color: Color(0xFFFF5A00), width: 1.5)),
                                    ),
                                    onChanged: (v) => _onDigitChanged(i, v),
                                    onTap: () {
                                      _controllers[i].selection = TextSelection.fromPosition(
                                          TextPosition(offset: _controllers[i].text.length));
                                    },
                                  ),
                                );
                              }),
                            ),

                            // ── Error ─────────────────────
                            if (hasError) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.05),
                                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(children: [
                                  const Icon(Icons.error_outline_rounded, size: 16, color: Colors.red),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(auth.errorMessage,
                                      style: const TextStyle(color: Colors.red, fontSize: 13))),
                                ]),
                              ),
                            ],

                            const SizedBox(height: 20),

                            // ── Verify Button ─────────────
                            SizedBox(
                              width: double.infinity, height: 48,
                              child: ElevatedButton(
                                onPressed: isLoading || _otpCode.length < 6 ? null : _handleVerify,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFF5A00),
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: const Color(0xFFFFB899),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  textStyle: const TextStyle(
                                      fontSize: 15, fontWeight: FontWeight.w700),
                                ),
                                child: isLoading
                                    ? const SizedBox(height: 20, width: 20,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                    : const Text('Verify & Access Shipments'),
                              ),
                            ),

                            const SizedBox(height: 20),

                            // ── Resend Timer (hidden for demo) ────────
                            if (!isDemo)
                              _canResend
                                  ? GestureDetector(
                                onTap: _handleResend,
                                child: const Text(
                                  "Didn't receive it? Resend code",
                                  style: TextStyle(fontSize: 13,
                                      color: Color(0xFFFF5A00),
                                      fontWeight: FontWeight.w600,
                                      decoration: TextDecoration.underline,
                                      decorationColor: Color(0xFFFF5A00)),
                                ),
                              )
                                  : Text(
                                'Resend code in 0:${_countdown.toString().padLeft(2, '0')}',
                                style: const TextStyle(fontSize: 13, color: Color(0xFF9B9B9B)),
                              ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),
                    const Text('🔒 Your data is protected with bank-level encryption',
                        style: TextStyle(fontSize: 11, color: Color(0xFFB0B0B0))),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopNavBar extends StatelessWidget {
  final VoidCallback onBack;
  const _TopNavBar({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      child: Row(children: [
        Container(width: 30, height: 30,
            decoration: BoxDecoration(color: const Color(0xFFFF5A00),
                borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.inventory_2_outlined, color: Colors.white, size: 16)),
        const SizedBox(width: 8),
        const Text('SwiftLabel',
            style: TextStyle(fontFamily: 'Syne', fontSize: 17,
                fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
        const Spacer(),
        GestureDetector(
          onTap: onBack,
          child: const Row(children: [
            Icon(Icons.arrow_back_ios, size: 14, color: Color(0xFF6B6B6B)),
            Text('Back', style: TextStyle(fontSize: 13, color: Color(0xFF6B6B6B))),
          ]),
        ),
      ]),
    );
  }
}