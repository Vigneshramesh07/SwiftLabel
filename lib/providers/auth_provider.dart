import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

enum AuthStatus { idle, loading, codeSent, verified, error }

// ── Demo credentials (App Store / Play Store review) ──────────────
const String _demoEmail = 'demo@swiftlabel.co.uk';
const String _demoOtp   = '123456';
const String _demoToken = 'demo-session-token';

class AuthProvider extends ChangeNotifier {
  // ── Supabase Edge Function URL ────────────────────────────────
  static const _functionUrl =
      'https://tjrjeemaacumepimjltg.supabase.co/functions/v1/send-otp';

  // ── Supabase Anon Key ─────────────────────────────────────────
  static const _anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRqcmplZW1hYWN1bWVwaW1qbHRnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQxMjE2NjAsImV4cCI6MjA4OTY5NzY2MH0.gtBcFu-J48mPDk_S9ukfVdW-7gUmabGatmJ1g1_5zzo';

  AuthStatus _status       = AuthStatus.idle;
  String     _email        = '';
  String     _errorMessage = '';
  String     _sessionToken = '';

  AuthStatus get status       => _status;
  String     get email        => _email;
  String     get errorMessage => _errorMessage;
  bool       get isLoggedIn   => _sessionToken.isNotEmpty;

  // ── Send OTP via Brevo ────────────────────────────────────────
  Future<void> sendOtp(String email) async {
    _status       = AuthStatus.loading;
    _email        = email;
    _errorMessage = '';
    notifyListeners();

    // ── Demo bypass: skip email send ──────────────────────────
    if (email.trim().toLowerCase() == _demoEmail) {
      await Future.delayed(const Duration(milliseconds: 800));
      _status = AuthStatus.codeSent;
      notifyListeners();
      return;
    }

    try {
      final response = await http.post(
        Uri.parse(_functionUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_anonKey',
        },
        body: jsonEncode({'email': email}),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        _status = AuthStatus.codeSent;
      } else {
        _status       = AuthStatus.error;
        _errorMessage = data['error'] ?? 'Failed to send code. Please try again.';
      }
    } catch (e) {
      _status       = AuthStatus.error;
      _errorMessage = 'Network error. Please check your connection.';
    }

    notifyListeners();
  }

  // ── Verify OTP ────────────────────────────────────────────────
  Future<bool> verifyOtp(String otp) async {
    _status       = AuthStatus.loading;
    _errorMessage = '';
    notifyListeners();

    // ── Demo bypass: accept fixed OTP without hitting Supabase ──
    if (_email.trim().toLowerCase() == _demoEmail && otp == _demoOtp) {
      await Future.delayed(const Duration(milliseconds: 800));

      _sessionToken = _demoToken;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('session_token', _sessionToken);
      await prefs.setString('session_email',  _email);

      _status = AuthStatus.verified;
      notifyListeners();
      return true;
    }

    try {
      final response = await http.post(
        Uri.parse(_functionUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_anonKey',
        },
        body: jsonEncode({
          'email':  _email,
          'action': 'verify',
          'otp':    otp,
        }),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        _sessionToken = data['sessionToken'];

        // Save session locally so user stays logged in
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('session_token', _sessionToken);
        await prefs.setString('session_email',  _email);

        _status = AuthStatus.verified;
        notifyListeners();
        return true;
      } else {
        _status       = AuthStatus.error;
        _errorMessage = data['error'] ?? 'Incorrect code. Please try again.';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _status       = AuthStatus.error;
      _errorMessage = 'Network error. Please check your connection.';
      notifyListeners();
      return false;
    }
  }

  // ── Auto-login on app open ────────────────────────────────────
  Future<void> checkSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('session_token') ?? '';
      final email = prefs.getString('session_email') ?? '';

      if (token.isNotEmpty && email.isNotEmpty) {
        _sessionToken = token;
        _email        = email;
        _status       = AuthStatus.verified;
        notifyListeners();
      }
    } catch (e) {
      // Session check failed — stay on login screen
    }
  }

  // ── Clear error when user types again ─────────────────────────
  void resetError() {
    if (_status == AuthStatus.error) {
      _status       = AuthStatus.codeSent;
      _errorMessage = '';
      notifyListeners();
    }
  }

  // ── Logout ────────────────────────────────────────────────────
  Future<void> reset() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('session_token');
      await prefs.remove('session_email');
    } catch (e) {
      // ignore
    }

    _sessionToken = '';
    _status       = AuthStatus.idle;
    _email        = '';
    _errorMessage = '';
    notifyListeners();
  }
}