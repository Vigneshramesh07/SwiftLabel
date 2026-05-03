import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'dashboard_screen.dart';
import 'otp_screen.dart';

const String _demoEmail = 'demo@swiftlabel.co.uk';

class EmailScreen extends StatefulWidget {
  const EmailScreen({super.key});

  @override
  State<EmailScreen> createState() => _EmailScreenState();
}

class _EmailScreenState extends State<EmailScreen> {
  final _emailController = TextEditingController();
  final _formKey         = GlobalKey<FormState>();
  bool  _isSending       = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final auth = context.read<AuthProvider>();
      await auth.checkSession();
      if (auth.isLoggedIn && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
        );
      }
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  bool _isValidEmail(String email) =>
      RegExp(r'^[\w.-]+@[\w.-]+\.\w+$').hasMatch(email);

  Future<void> _handleSend() async {
    if (_isSending) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSending = true);

    final auth = context.read<AuthProvider>();
    await auth.sendOtp(_emailController.text.trim());

    if (mounted) setState(() => _isSending = false);

    if (mounted && auth.status == AuthStatus.codeSent) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const OtpScreen()),
      );
    }
  }

  void _handleDemoLogin() {
    _emailController.text = _demoEmail;
    // Trigger validation then send
    if (_formKey.currentState!.validate()) {
      _handleSend();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth      = context.watch<AuthProvider>();
    final isLoading = auth.status == AuthStatus.loading;
    final hasError  = auth.status == AuthStatus.error;

    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F7),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _TopNavBar(),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      const SizedBox(height: 48),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(32),
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
                                child: const Icon(Icons.inventory_2_outlined,
                                    color: Colors.white, size: 30),
                              ),
                              const SizedBox(height: 24),

                              // ── Headline ──────────────────
                              const Text(
                                'Access Your Shipments',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'Syne', fontSize: 24,
                                  fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A),
                                ),
                              ),
                              const SizedBox(height: 12),

                              const Text(
                                'Enter your email address to securely view your shipment history, parcel labels, and tracking updates.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 14, color: Color(0xFF6B6B6B), height: 1.6),
                              ),
                              const SizedBox(height: 8),

                              const Text(
                                "We'll send a one-time secure access code to your email. No password required.",
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 13, color: Color(0xFF9B9B9B), height: 1.5),
                              ),
                              const SizedBox(height: 28),

                              // ── Email Field ───────────────
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Email Address',
                                      style: TextStyle(fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF3A3A3A))),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    controller: _emailController,
                                    keyboardType: TextInputType.emailAddress,
                                    autocorrect: false,
                                    style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A1A)),
                                    onChanged: (_) {
                                      if (auth.status == AuthStatus.error) {
                                        context.read<AuthProvider>().resetError();
                                      }
                                    },
                                    decoration: InputDecoration(
                                      hintText: 'Enter your email address',
                                      hintStyle: const TextStyle(color: Color(0xFFB0B0B0), fontSize: 14),
                                      filled: true,
                                      fillColor: Colors.white,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                      border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                                      enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          borderSide: BorderSide(
                                              color: hasError ? Colors.red : const Color(0xFFE0E0E0))),
                                      focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          borderSide: const BorderSide(color: Color(0xFFFF5A00), width: 1.5)),
                                      errorBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          borderSide: const BorderSide(color: Colors.red)),
                                      focusedErrorBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          borderSide: const BorderSide(color: Colors.red, width: 1.5)),
                                    ),
                                    validator: (v) {
                                      if (v == null || v.isEmpty) return 'Email is required';
                                      if (!_isValidEmail(v)) return 'Enter a valid email address';
                                      return null;
                                    },
                                  ),

                                  // ── API Error ─────────────
                                  if (hasError) ...[
                                    const SizedBox(height: 8),
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
                                            style: const TextStyle(fontSize: 12, color: Colors.red))),
                                      ]),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 16),

                              // ── Demo Login Banner ─────────
                              GestureDetector(
                                onTap: isLoading ? null : _handleDemoLogin,
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF0F7FF),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: const Color(0xFFB5D4F4)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Row(children: [
                                        Icon(Icons.preview_rounded,
                                            size: 14, color: Color(0xFF378ADD)),
                                        SizedBox(width: 6),
                                        Text('Demo Access',
                                            style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF185FA5))),
                                      ]),
                                      const SizedBox(height: 8),
                                      _DemoRow(label: 'Email', value: _demoEmail),
                                      const SizedBox(height: 4),
                                      const _DemoRow(label: 'OTP', value: '123456'),
                                      const SizedBox(height: 8),
                                      const Text('Tap to auto-fill and continue →',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: Color(0xFF378ADD),
                                              fontWeight: FontWeight.w500)),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),

                              // ── Send Button ───────────────
                              SizedBox(
                                width: double.infinity, height: 48,
                                child: ElevatedButton(
                                  onPressed: isLoading ? null : _handleSend,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFFF5A00),
                                    foregroundColor: Colors.white,
                                    disabledBackgroundColor: const Color(0xFFFFB899),
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    textStyle: const TextStyle(fontFamily: 'Syne', fontSize: 15, fontWeight: FontWeight.w700),
                                  ),
                                  child: isLoading
                                      ? const SizedBox(height: 20, width: 20,
                                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                      : const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text('Send Secure Access Code'),
                                      SizedBox(width: 6),
                                      Icon(Icons.arrow_forward, size: 16),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),

                              // ── Trust Signals ─────────────
                              _TrustSignal(label: 'Secure email verification'),
                              const SizedBox(height: 8),
                              _TrustSignal(label: 'No password required'),
                              const SizedBox(height: 8),
                              _TrustSignal(label: 'Fast access to your shipments'),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

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
      ),
    );
  }
}

// ── Demo credential row ────────────────────────────────────────────
class _DemoRow extends StatelessWidget {
  final String label;
  final String value;
  const _DemoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      SizedBox(
        width: 42,
        child: Text('$label:',
            style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF378ADD),
                fontWeight: FontWeight.w600)),
      ),
      const SizedBox(width: 6),
      Text(value,
          style: const TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              color: Color(0xFF185FA5),
              letterSpacing: 0.3)),
    ]);
  }
}

class _TopNavBar extends StatelessWidget {
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
            decoration: BoxDecoration(color: const Color(0xFFFF5A00), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.inventory_2_outlined, color: Colors.white, size: 16)),
        const SizedBox(width: 8),
        const Text('SwiftLabel',
            style: TextStyle(fontFamily: 'Syne', fontSize: 17,
                fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
        const Spacer(),
      ]),
    );
  }
}

class _TrustSignal extends StatelessWidget {
  final String label;
  const _TrustSignal({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(width: 18, height: 18,
          decoration: BoxDecoration(
              color: const Color(0xFF10B981).withOpacity(0.12),
              shape: BoxShape.circle),
          child: const Icon(Icons.check, size: 11, color: Color(0xFF10B981))),
      const SizedBox(width: 8),
      Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF6B6B6B))),
    ]);
  }
}