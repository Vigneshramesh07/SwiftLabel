import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/auth_provider.dart';
import '../providers/parcel_provider.dart';
import '../providers/profile_provider.dart';
import '../widgets/recepients_Screen.dart';
import '../widgets/postcode_lookup_field.dart';
import 'pickup_screen.dart';

class SendParcelScreen extends StatefulWidget {
  const SendParcelScreen({super.key});
  @override
  State<SendParcelScreen> createState() => _SendParcelScreenState();
}

class _SendParcelScreenState extends State<SendParcelScreen> {
  int _step = 0;
  final _step2 = Step2Controller();

  final _s1Key      = GlobalKey<FormState>();
  final _sNameCtrl  = TextEditingController();
  final _sPhoneCtrl = TextEditingController();
  final _sEmailCtrl = TextEditingController();
  final _sPcCtrl    = TextEditingController();
  final _sStrCtrl   = TextEditingController();
  final _sDoorCtrl  = TextEditingController();
  final _sCityCtrl  = TextEditingController();
  bool _sPcValid    = false;
  bool _useProfileData = false;

  final _cardNumberCtrl = TextEditingController();
  final _expiryCtrl     = TextEditingController();
  final _cvcCtrl        = TextEditingController();
  bool   _paymentLoading   = false;
  bool   _paymentConfirmed = false;
  bool   _generatingLabel  = false;
  String _paymentIntentId  = '';
  String _paymentError     = '';
  List<String> _sSenderStreetList  = [];
  String?      _sSenderSelectedStreet;
  bool         _sSenderPcLookedUp  = false;
  bool         _sSenderIsLookingUp  = false;
  bool         _sSenderPcValid      = false;
  String       _sSenderPcError      = '';
  Timer?       _sSenderDebounce;

  // REPLACE existing key constants at top of _SendParcelScreenState:
  static const bool _useLivePayment = true;
  void _onSenderPostcodeChanged(String value) {
    _sSenderDebounce?.cancel();
    setState(() {
      _sSenderPcValid        = false;
      _sSenderPcError        = '';
      _sSenderStreetList     = [];
      _sSenderSelectedStreet = null;
      _sPcValid              = false;
      _sStrCtrl.clear();
      _sCityCtrl.clear();
    });

    final cleaned = value.trim().replaceAll(' ', '').toUpperCase();
    if (cleaned.length < 5) return;

    _sSenderDebounce = Timer(const Duration(milliseconds: 600), () {
      _lookupSenderPostcode(cleaned);
    });
  }

  Future<void> _lookupSenderPostcode(String postcode) async {
    setState(() { _sSenderIsLookingUp = true; _sSenderPcError = ''; });

    try {
      final res = await http.get(
        Uri.parse('https://api.postcodes.io/postcodes/$postcode'),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(res.body);

      if (res.statusCode != 200 || data['status'] != 200) {
        setState(() {
          _sSenderPcError       = 'Invalid postcode. Please check and try again.';
          _sSenderIsLookingUp   = false;
        });
        return;
      }

      final result = data['result'];
      final city = result['admin_district'] ??
          result['parish'] ?? result['region'] ?? 'Unknown';

      // Format postcode
      final clean = postcode.replaceAll(' ', '').toUpperCase();
      final formatted = clean.length >= 5
          ? '${clean.substring(0, clean.length - 3)} ${clean.substring(clean.length - 3)}'
          : clean;

      setState(() {
        _sPcCtrl.text   = formatted;
        _sCityCtrl.text = city;
        _sPcValid       = true;
        _sSenderPcValid = true;
      });

      final lat = result['latitude']  as double?;
      final lng = result['longitude'] as double?;
      if (lat != null && lng != null) {
        await _loadSenderStreets(lat, lng);
      }
    } on TimeoutException {
      setState(() { _sSenderPcError = 'Request timed out. Please try again.'; });
    } on SocketException {
      setState(() { _sSenderPcError = 'No internet connection.'; });
    } catch (e) {
      setState(() { _sSenderPcError = 'Could not look up postcode.'; });
    }

    setState(() { _sSenderIsLookingUp = false; });
  }

  Future<void> _loadSenderStreets(double lat, double lng) async {
    try {
      final Set<String> streets = {};

      final revRes = await http.get(
        Uri.parse('https://nominatim.openstreetmap.org/reverse'
            '?lat=$lat&lon=$lng&format=json&addressdetails=1&zoom=16'),
        headers: {'User-Agent': 'SwiftLabel Flutter App'},
      ).timeout(const Duration(seconds: 10));

      if (revRes.statusCode == 200) {
        final addr = (jsonDecode(revRes.body) as Map)['address'];
        final road = addr?['road'] ?? addr?['street'] ?? addr?['path'];
        if (road != null) streets.add(road.toString());
      }

      const delta = 0.004;
      final bbox  = '${lng - delta},${lat - delta},${lng + delta},${lat + delta}';

      final searchRes = await http.get(
        Uri.parse('https://nominatim.openstreetmap.org/search'
            '?q=road&format=json&addressdetails=1&limit=50'
            '&bounded=1&viewbox=$bbox'),
        headers: {'User-Agent': 'SwiftLabel Flutter App'},
      ).timeout(const Duration(seconds: 10));

      if (searchRes.statusCode == 200) {
        final List items = jsonDecode(searchRes.body);
        for (final item in items) {
          final addr = item['address'] as Map?;
          final road = addr?['road'] ?? addr?['street'] ?? addr?['path'];
          if (road != null && road.toString().isNotEmpty) streets.add(road.toString());
          final display = item['display_name']?.toString() ?? '';
          if (display.isNotEmpty) {
            final segment = display.split(',').first.trim();
            if (segment.isNotEmpty && !segment.contains(RegExp(r'\d{3}'))) {
              streets.add(segment);
            }
          }
        }
      }

      final overpassRes = await http.post(
        Uri.parse('https://overpass-api.de/api/interpreter'),
        body: '[out:json][timeout:12];way(around:400,$lat,$lng)[highway][name];out tags;',
      ).timeout(const Duration(seconds: 14));

      if (overpassRes.statusCode == 200) {
        final elements = (jsonDecode(overpassRes.body) as Map)['elements'] as List? ?? [];
        for (final el in elements) {
          final name = el['tags']?['name'];
          if (name != null && name.toString().isNotEmpty) streets.add(name.toString());
        }
      }

      final sorted = streets.toList()..sort();
      if (mounted) {
        setState(() {
          _sSenderStreetList = sorted.isNotEmpty ? sorted : [];
        });
      }
    } catch (e) {
      debugPrint('Sender street lookup error: $e');
    }
  }

  static const _emailUrl =
      'https://tjrjeemaacumepimjltg.supabase.co/functions/v1/send-label-email';
  static const _anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRqcmplZW1hYWN1bWVwaW1qbHRnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQxMjE2NjAsImV4cCI6MjA4OTY5NzY2MH0.gtBcFu-J48mPDk_S9ukfVdW-7gUmabGatmJ1g1_5zzo';
  bool _profilePrefilled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // _tryPrefillPostcode();
      // context.read<ProfileProvider>().addListener(_tryPrefillPostcode);
      final email = context.read<AuthProvider>().email;
      if (email.isNotEmpty && _sEmailCtrl.text.isEmpty) {
        setState(() => _sEmailCtrl.text = email);
      }
    });
  }

  void _tryPrefillPostcode() {
    if (!mounted || _profilePrefilled) return;
    final profile = context.read<ProfileProvider>();
    if (profile.postcode.isNotEmpty) {
      setState(() {
        _sPcCtrl.text = _formatUkPc(profile.postcode);
        _sPcValid     = _validUkPc(profile.postcode);
        _profilePrefilled = true;
      });
    }
  }

  @override
  void dispose() {
   // context.read<ProfileProvider>().removeListener(_tryPrefillPostcode);
    for (final c in [
      _sNameCtrl, _sPhoneCtrl, _sEmailCtrl, _sPcCtrl,
      _sStrCtrl, _sDoorCtrl, _sCityCtrl,
      _cardNumberCtrl, _expiryCtrl, _cvcCtrl,
    ]) { c.dispose(); }
    _step2.dispose();
    _sSenderDebounce?.cancel();
    super.dispose();
  }

  bool _validUkPc(String v) =>
      RegExp(r'^[A-Z]{1,2}[0-9][A-Z0-9]? ?[0-9][A-Z]{2}$',
          caseSensitive: false).hasMatch(v.trim());

  String _formatUkPc(String v) {
    final clean = v.trim().toUpperCase().replaceAll(' ', '');
    if (clean.length >= 5) {
      return '${clean.substring(0, clean.length - 3)} ${clean.substring(clean.length - 3)}';
    }
    return v.trim().toUpperCase();
  }

  void _applyProfileData() {
    final profile = context.read<ProfileProvider>();
    final auth    = context.read<AuthProvider>();
    _sNameCtrl.text  = profile.fullName;
    _sPhoneCtrl.text = profile.phone;
    _sEmailCtrl.text = auth.email;
    final addr = profile.addressLine1.trim();
    if (addr.isNotEmpty) {
      final parts = addr.split(' ');
      if (parts.length > 1 && RegExp(r'^\d+[A-Za-z]?$').hasMatch(parts[0])) {
        _sDoorCtrl.text = parts[0];
        _sStrCtrl.text  = parts.sublist(1).join(' ');
      } else {
        _sDoorCtrl.text = '';
        _sStrCtrl.text  = addr;
      }
    } else {
      _sDoorCtrl.text = '';
      _sStrCtrl.text  = '';
    }
    _sCityCtrl.text = profile.city;
    _sPcCtrl.text   = profile.postcode;
    _sPcValid       = _validUkPc(profile.postcode);
  }

  void _clearSenderFields() {
    _sNameCtrl.clear(); _sPhoneCtrl.clear(); _sEmailCtrl.clear();
    _sDoorCtrl.clear(); _sStrCtrl.clear(); _sCityCtrl.clear();
    _sPcCtrl.clear(); _sPcValid = false;
  }

  void _onToggleProfilePrefill(bool? value) {
    setState(() {
      _useProfileData = value ?? false;
      if (_useProfileData) { _applyProfileData(); } else { _clearSenderFields(); }
    });
  }

  bool get _profileCanPrefill {
    final p = context.read<ProfileProvider>();
    return p.fullName.isNotEmpty || p.addressLine1.isNotEmpty;
  }

  Future<void> _nextStep() async {
    final p = context.read<ParcelProvider>();
    if (_step == 0) {
      if (!(_s1Key.currentState?.validate() ?? false)) return;
      p.setSenderDetails(
        name:     _sNameCtrl.text.trim(),
        phone: '+44 ${_sPhoneCtrl.text.trim()}',
        email:    _sEmailCtrl.text.trim(),
        postcode: _formatUkPc(_sPcCtrl.text),
        street:   _sStrCtrl.text.trim(),
        door:     _sDoorCtrl.text.trim(),
        city:     _sCityCtrl.text.trim(),
      );
      setState(() => _step++);
      return;
    }
    if (_step == 1) {
      if (!_step2.validate(context)) return;

      if (_step2.serviceChecked && !_step2.serviceAvailable) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: [
              const Icon(Icons.cancel_rounded, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _step2.isInternational
                      ? 'No courier services available for '
                      '${_step2.selectedCountry?.name ?? 'this country'}. '
                      'Please choose a different destination.'
                      : 'No courier services available for this postcode. '
                      'Please check the details and try again.',
                ),
              ),
            ]),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        return;
      }

      p.setRecipientDetails(
        name:          _step2.nameCtrl.text.trim(),
        phone:         _step2.fullPhone,
        postcode:      _step2.postcode,
        street:        _step2.streetCtrl.text.trim(),
        door:          _step2.doorCtrl.text.trim(),
        city:          _step2.cityCtrl.text.trim(),
        international: _step2.isInternational,
        countryCode:   _step2.selectedCountry?.code   ?? 'GB',
        countryName:   _step2.selectedCountry?.name   ?? 'United Kingdom',
        state:         _step2.state,
        zip:           _step2.zipCtrl.text.trim(),
      );
      setState(() => _step++);
      return;
    }

    if (_step == 2) {
      // 1. Basic checks
      if (p.selectedSizeId.isEmpty || p.selectedParcelType.isEmpty) {
        _snack('Please select parcel size and type.');
        return;
      }

      // 2. Weight validation
      final error = p.validateWeightForSize();
      if (error != null) {
        _snack(error, isError: true);
        return;
      }

      final weight = double.tryParse(p.weightKg) ?? 0;
      if (weight > 30) {
        _snack('Maximum allowed weight is 30kg', isError: true);
        return;
      }

      setState(() => _step++);
      await p.getRates();
      return;
    }

    if (_step == 3) {
      if (p.selectedRate == null) {
        _snack('Please select a courier service.'); return;
      }
      setState(() => _step++);
      return;
    }

    if (_step == 4) {
      setState(() => _step++);
      return;
    }
  }

  // ── Payment Popup ─────────────────────────────────────────────
  Future<void> _showPaymentPopup({required bool success, String? message}) async {
    await showDialog(
      context: context,
      barrierDismissible: success,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15),
                blurRadius: 40, offset: const Offset(0, 10))],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 88, height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: success
                    ? const Color(0xFF059669).withOpacity(0.1)
                    : Colors.red.withOpacity(0.1),
                border: Border.all(
                  color: success
                      ? const Color(0xFF059669).withOpacity(0.3)
                      : Colors.red.withOpacity(0.3),
                  width: 4,
                ),
              ),
              child: Icon(
                success ? Icons.check_circle_rounded : Icons.cancel_rounded,
                size: 52,
                color: success ? const Color(0xFF059669) : Colors.red,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              success ? 'Payment Successful!' : 'Payment Failed',
              style: TextStyle( fontSize: 26, fontWeight: FontWeight.w800,
                color: success ? const Color(0xFF059669) : Colors.red,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              success
                  ? 'Payment confirmed.\nGenerating your shipping label now.'
                  : (message ?? 'Something went wrong. Please try again.'),
              style: const TextStyle(fontSize: 14, color: Color(0xFF6B6B6B), height: 1.5),
              textAlign: TextAlign.center,
            ),
            if (success && _paymentIntentId.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.receipt_long_outlined, size: 14, color: Color(0xFF059669)),
                  const SizedBox(width: 6),
                  Text(
                    'ID: ${_paymentIntentId.length > 18 ? '${_paymentIntentId.substring(0, 18)}...' : _paymentIntentId}',
                    style: const TextStyle(fontFamily: 'monospace',
                        fontSize: 11, color: Color(0xFF059669)),
                  ),
                ]),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: const Color(0xFFF3F0FF),
                    borderRadius: BorderRadius.circular(8)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.email_outlined, size: 14, color: Color(0xFF6D28D9)),
                  SizedBox(width: 6),
                  Text('Invoice & label will be sent to your email',
                      style: TextStyle(fontSize: 11, color: Color(0xFF6D28D9))),
                ]),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity, height: 48,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: success ? const Color(0xFF059669) : Colors.red,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                child: Text(success ? 'Continue →' : 'Try Again'),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Invoice Email ─────────────────────────────────────────────
  Future<void> _sendInvoiceEmail(ParcelProvider p) async {
    try {
      final email = _sEmailCtrl.text.trim();
      final rate  = p.selectedRate;
      final now   = DateTime.now();
      final html =
          '<div style="font-family:sans-serif;max-width:620px;margin:0 auto">'
          '<div style="background:linear-gradient(135deg,#FF7A2F,#FF5A00);padding:28px 32px;border-radius:12px 12px 0 0">'
          '<h1 style="margin:0;color:white;font-size:24px;font-weight:900">SwiftLabel</h1>'
          '<p style="margin:4px 0 0;color:rgba(255,255,255,0.85);font-size:14px">Payment Invoice</p>'
          '</div>'
          '<div style="background:white;padding:28px 32px;border:1px solid #EEEEEE;border-radius:0 0 12px 12px">'
          '<div style="margin-bottom:20px">'
          '<p style="margin:0;font-size:12px;color:#9B9B9B;letter-spacing:1px;text-transform:uppercase">Invoice For</p>'
          '<p style="margin:4px 0 0;font-size:16px;font-weight:700">${_sNameCtrl.text.trim()}</p>'
          '<p style="margin:2px 0;font-size:13px;color:#6B6B6B">$email</p>'
          '<p style="margin:2px 0;font-size:12px;color:#9B9B9B">${now.day}/${now.month}/${now.year}'
          '&nbsp;&nbsp; ID: ${_paymentIntentId.length > 20 ? _paymentIntentId.substring(0, 20) : _paymentIntentId}...</p>'
          '</div>'
          '<table style="width:100%;border-collapse:collapse">'
          '<tr style="background:#F9F9F9">'
          '<th style="padding:8px;text-align:left;font-size:11px;color:#9B9B9B">DESCRIPTION</th>'
          '<th style="padding:8px;text-align:left;font-size:11px;color:#9B9B9B">CARRIER</th>'
          '<th style="padding:8px;text-align:right;font-size:11px;color:#9B9B9B">AMOUNT</th>'
          '</tr>'
          '<tr style="border-bottom:1px solid #F5F5F5">'
          '<td style="padding:10px 8px;font-size:13px">${p.selectedSize?.name ?? ''} · ${p.selectedParcelType}</td>'
          '<td style="padding:10px 8px;font-size:12px;color:#6B6B6B">${rate?.carrier ?? ''}</td>'
          '<td style="padding:10px 8px;font-size:13px;font-weight:bold;text-align:right">£${rate?.price.toStringAsFixed(2) ?? '0.00'}</td>'
          '</tr>'
          '<tr style="border-bottom:1px solid #F5F5F5">'
          '<td style="padding:10px 8px;font-size:13px;color:#6B6B6B">${p.isInternational ? 'International Fee' : 'Service Fee'}</td>'
          '<td style="padding:10px 8px;font-size:12px;color:#9B9B9B">SwiftLabel</td>'
          '<td style="padding:10px 8px;font-size:13px;text-align:right">£${p.serviceFee.toStringAsFixed(2)}</td>'
          '</tr>'
          '</table>'
          '<div style="border-top:2px solid #EEEEEE;margin-top:16px;padding-top:16px">'
          '<p style="margin:0;font-size:14px;font-weight:700">Total Paid: £${p.totalCost.toStringAsFixed(2)}</p>'
          '</div>'
          '<div style="margin-top:20px;padding:14px;background:#F0FDF4;border-radius:10px;border:1px solid #BBF7D0">'
          '<p style="margin:0;font-size:13px;color:#059669;font-weight:600">✓ Payment Confirmed</p>'
          '<p style="margin:4px 0 0;font-size:12px;color:#6B7280">From: ${p.senderName}, ${p.senderCity} → To: ${p.recipName}, ${p.recipCity}</p>'
          '</div>'
          '<div style="margin-top:20px;padding:14px;background:#F3F0FF;border-radius:10px;border:1px solid #DDD6FE">'
          '<p style="margin:0;font-size:13px;color:#6D28D9;font-weight:600">📦 Your shipping label is on its way!</p>'
          '<p style="margin:4px 0 0;font-size:12px;color:#6B7280">You will receive a separate email with your label PDF and tracking number.</p>'
          '</div>'
          '<p style="margin-top:20px;font-size:11px;color:#9B9B9B;text-align:center">Powered by SwiftLabel · Thank you for shipping with us</p>'
          '</div></div>';
      await http.post(
        Uri.parse(_emailUrl),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $_anonKey'},
        body: jsonEncode({
          'email': email,
          'subject': 'SwiftLabel Invoice — £${p.totalCost.toStringAsFixed(2)}',
          'htmlContent': html,
          'trackingNumber': _paymentIntentId,
          'labelUrl': '',
          'carrier': 'Invoice',
          'service': '${p.selectedSize?.name ?? ''} · ${p.selectedParcelType}',
          'recipientName': _sNameCtrl.text.trim(),
          'recipientCity': p.recipCity,
        }),
      ).timeout(const Duration(seconds: 15));
      debugPrint('[Invoice] Sent successfully');
    } catch (e) {
      debugPrint('[Invoice] Error: $e');
    }
  }

  // ── Label Email ───────────────────────────────────────────────
  Future<void> _sendLabelEmail(ParcelProvider p) async {
    try {
      final email = _sEmailCtrl.text.trim();
      final now   = DateTime.now();
      final html =
          '<div style="font-family:sans-serif;max-width:620px;margin:0 auto">'
          '<div style="background:linear-gradient(135deg,#7C3AED,#6D28D9);padding:28px 32px;border-radius:12px 12px 0 0">'
          '<h1 style="margin:0;color:white;font-size:24px;font-weight:900">SwiftLabel</h1>'
          '<p style="margin:4px 0 0;color:rgba(255,255,255,0.85);font-size:14px">Your Shipping Label is Ready</p>'
          '</div>'
          '<div style="background:white;padding:28px 32px;border:1px solid #EEEEEE;border-radius:0 0 12px 12px">'
          '<div style="margin-bottom:20px">'
          '<p style="margin:0;font-size:12px;color:#9B9B9B;letter-spacing:1px;text-transform:uppercase">Sending To</p>'
          '<p style="margin:4px 0 0;font-size:16px;font-weight:700">${p.recipName}</p>'
          '<p style="margin:2px 0;font-size:13px;color:#6B6B6B">${p.recipCity}, ${p.recipPostcode}</p>'
          '</div>'
          '<div style="background:#F3F0FF;border:1px solid #DDD6FE;border-radius:10px;padding:16px;margin-bottom:16px">'
          '<p style="margin:0;font-size:11px;color:#6D28D9;letter-spacing:1px;text-transform:uppercase;font-weight:700">Tracking Number</p>'
          '<p style="margin:6px 0 0;font-family:monospace;font-size:20px;font-weight:900;color:#1A1A1A;letter-spacing:2px">'
          '${p.lastTrackingNumber}</p>'
          '</div>'
          '<table style="width:100%;border-collapse:collapse;margin-bottom:16px">'
          '<tr style="background:#F9F9F9">'
          '<th style="padding:8px;text-align:left;font-size:11px;color:#9B9B9B">CARRIER</th>'
          '<th style="padding:8px;text-align:left;font-size:11px;color:#9B9B9B">SERVICE</th>'
          '<th style="padding:8px;text-align:left;font-size:11px;color:#9B9B9B">DATE</th>'
          '<th style="padding:8px;text-align:right;font-size:11px;color:#9B9B9B">AMOUNT PAID</th>'
          '</tr>'
          '<tr>'
          '<td style="padding:10px 8px;font-size:13px;font-weight:600">${p.selectedRate?.carrier ?? ''}</td>'
          '<td style="padding:10px 8px;font-size:12px;color:#6B6B6B">${p.selectedRate?.service ?? ''}</td>'
          '<td style="padding:10px 8px;font-size:12px;color:#6B6B6B">${now.day}/${now.month}/${now.year}</td>'
          '<td style="padding:10px 8px;font-size:13px;font-weight:bold;text-align:right">£${p.totalCost.toStringAsFixed(2)}</td>'
          '</tr>'
          '</table>'
          '${p.lastLabelUrl.isNotEmpty
          ? '<div style="text-align:center;margin:24px 0">'
          '<a href="${p.lastLabelUrl}" style="display:inline-block;background:#6D28D9;color:white;'
          'padding:16px 40px;border-radius:12px;text-decoration:none;font-weight:bold;font-size:16px">'
          '⬇ Download Label PDF</a>'
          '<p style="margin:10px 0 0;font-size:12px;color:#9B9B9B">Tap the button to open your label</p>'
          '</div>'
          : ''}'
          '<div style="background:#F0FDF4;border:1px solid #BBF7D0;border-radius:10px;padding:14px;margin-bottom:16px">'
          '<p style="margin:0;font-size:13px;font-weight:700;color:#059669">✓ What to do next</p>'
          '<ol style="margin:8px 0 0;padding-left:18px;font-size:12px;color:#374151;line-height:1.8">'
          '<li>Print the label PDF (A4 or 6×4 label sheet)</li>'
          '<li>Attach it securely to your parcel</li>'
          '<li>Drop off at your nearest ${p.selectedRate?.carrier ?? 'courier'} location</li>'
          '</ol>'
          '</div>'
          '<p style="margin-top:20px;font-size:11px;color:#9B9B9B;text-align:center">'
          'Powered by SwiftLabel · Keep this email as your shipping receipt</p>'
          '</div></div>';

      await http.post(
        Uri.parse(_emailUrl),
        headers: {
          'Content-Type':  'application/json',
          'Authorization': 'Bearer $_anonKey',
        },
        body: jsonEncode({
          'email':          email,
          'subject':        '📦 Your Label is Ready — ${p.lastTrackingNumber}',
          'htmlContent':    html,
          'trackingNumber': p.lastTrackingNumber,
          'labelUrl':       p.lastLabelUrl,
          'carrier':        p.selectedRate?.carrier ?? '',
          'service':        p.selectedRate?.service ?? '',
          'recipientName':  p.recipName,
          'recipientCity':  p.recipCity,
        }),
      ).timeout(const Duration(seconds: 15));

      debugPrint('[LabelEmail] Sent successfully');
    } catch (e) {
      debugPrint('[LabelEmail] Error: $e');
    }
  }

  // ── Stripe Payment ────────────────────────────────────────────
  Future<void> _processPayment(ParcelProvider p) async {
    setState(() { _paymentLoading = true; _paymentError = ''; });

    try {
      // 1. Get client secret from your Supabase edge function
      final res = await http.post(
        Uri.parse('https://tjrjeemaacumepimjltg.supabase.co/functions/v1/create-payment-intent'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_anonKey',
        },
        body: jsonEncode({
          'amount': (p.totalCost * 100).round(),
          'currency': 'gbp',
          'email': _sEmailCtrl.text.trim(),
          'description': 'SwiftLabel — ${p.selectedSize?.name ?? ''} parcel',
        }),
      ).timeout(const Duration(seconds: 15));

      final body = jsonDecode(res.body);
      debugPrint('[Payment] Edge function response: $body');

      final clientSecret = body['clientSecret'] as String?;
      if (clientSecret == null || clientSecret.isEmpty) {
        throw Exception(body['error'] ?? 'Failed to create payment intent. Please try again.');
      }

      // 2. Init Stripe payment sheet
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'SwiftLabel',
          billingDetails: BillingDetails(
            name: _sNameCtrl.text.trim(),
            email: _sEmailCtrl.text.trim(),
          ),
          style: ThemeMode.light,
        ),
      );

      // 3. Present Stripe's native payment sheet
      await Stripe.instance.presentPaymentSheet();

      // 4. Payment succeeded — extract intent ID
      _paymentIntentId = clientSecret.split('_secret')[0]; // e.g. pi_xxx
      setState(() { _paymentConfirmed = true; _paymentLoading = false; });

      await _showPaymentPopup(success: true);
      if (!mounted) return;

      // 5. Generate label
      setState(() => _generatingLabel = true);
      final email = context.read<AuthProvider>().email;
      await p.buyLabel(userEmail: email);
      if (!mounted) return;
      setState(() => _generatingLabel = false);

      if (p.isSubmitted) {
        await _sendInvoiceEmail(p);
        _sendLabelEmail(p);
        if (p.requiresPickup && p.selectedRate != null) {
          await Navigator.push(context, MaterialPageRoute(
            builder: (_) => PickupScreen(
              carrierId:      p.selectedRate!.carrierId ?? '',
              carrierName:    p.selectedRate!.carrier,
              labelId:        p.lastLabelId,
              trackingNumber: p.lastTrackingNumber,
              labelUrl:       p.lastLabelUrl,
              senderName:     p.senderName,
              senderPhone:    p.senderPhone,
              senderEmail:    p.senderEmail,
              senderAddress:  '${p.senderDoor} ${p.senderStreet}'.trim(),
              senderCity:     p.senderCity,
              senderPostcode: p.senderPostcode,
            ),
          ));
          if (mounted) setState(() => _step = 6);
        } else {
          setState(() => _step = 6);
        }
      } else {
        await _sendLabelFailedEmail(p);
        if (mounted) {
          _snack(p.errorMessage.isNotEmpty
              ? p.errorMessage
              : 'Label generation failed. A refund will be issued within 3 business days.',
              isError: true);
        }
      }

    } on StripeException catch (e) {
      // User cancelled or card declined
      final msg = e.error.localizedMessage ?? 'Payment cancelled.';
      setState(() { _paymentError = msg; _paymentLoading = false; });
      if (e.error.code != FailureCode.Canceled) {
        await _showPaymentPopup(success: false, message: msg);
        await _sendPaymentFailedEmail(msg, p);
      }
    } catch (e) {
      final msg = e.toString().replaceAll('Exception: ', '');
      setState(() { _paymentError = msg; _paymentLoading = false; });
      await _showPaymentPopup(success: false, message: msg);
      await _sendPaymentFailedEmail(msg, p);
    }
  }

  Future<void> _sendPaymentFailedEmail(String reason, ParcelProvider p) async {
    try {
      final email = _sEmailCtrl.text.trim();
      if (email.isEmpty) return;
      final now = DateTime.now();
      final html =
          '<div style="font-family:sans-serif;max-width:620px;margin:0 auto">'
          '<div style="background:linear-gradient(135deg,#FF7A2F,#FF5A00);padding:28px 32px;border-radius:12px 12px 0 0">'
          '<h1 style="margin:0;color:white;font-size:24px;font-weight:900">SwiftLabel</h1>'
          '<p style="margin:4px 0 0;color:rgba(255,255,255,0.85);font-size:14px">Payment Failed</p>'
          '</div>'
          '<div style="background:white;padding:28px 32px;border:1px solid #EEE;border-radius:0 0 12px 12px">'
          '<div style="padding:16px;background:#FEF2F2;border:1px solid #FECACA;border-radius:10px;margin-bottom:20px">'
          '<p style="margin:0;font-size:15px;font-weight:700;color:#DC2626">❌ Payment Unsuccessful</p>'
          '<p style="margin:6px 0 0;font-size:13px;color:#6B7280">Your payment could not be processed. No charges have been made.</p>'
          '</div>'
          '<p style="font-size:14px;color:#1A1A1A;margin:0 0 6px"><strong>Name:</strong> ${_sNameCtrl.text.trim()}</p>'
          '<p style="font-size:14px;color:#1A1A1A;margin:0 0 6px"><strong>Date:</strong> ${now.day}/${now.month}/${now.year}</p>'
          '<p style="font-size:14px;color:#1A1A1A;margin:0 0 6px"><strong>Amount:</strong> £${p.totalCost.toStringAsFixed(2)}</p>'
          '<p style="font-size:14px;color:#DC2626;margin:0 0 20px"><strong>Reason:</strong> $reason</p>'
          '<div style="padding:16px;background:#FFFBEB;border:1px solid #FDE68A;border-radius:10px;margin-bottom:20px">'
          '<p style="margin:0;font-size:14px;font-weight:700;color:#D97706">💳 What to do next</p>'
          '<ul style="margin:8px 0 0;padding-left:18px;font-size:13px;color:#374151">'
          '<li style="margin-bottom:4px">Check your card details are correct</li>'
          '<li style="margin-bottom:4px">Ensure your card has sufficient funds</li>'
          '<li style="margin-bottom:4px">Try a different payment method</li>'
          '<li>Contact your bank if the issue persists</li>'
          '</ul></div>'
          '<p style="font-size:13px;color:#6B7280;margin:0">Return to the app to retry your payment.</p>'
          '<div style="margin-top:24px;padding-top:16px;border-top:1px solid #EEE">'
          '<p style="margin:0;font-size:11px;color:#9B9B9B">SwiftLabel · ${now.day}/${now.month}/${now.year}</p>'
          '</div></div></div>';

      await http.post(Uri.parse(_emailUrl),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $_anonKey'},
        body: jsonEncode({
          'email':          email,
          'subject':        '❌ Payment Failed — £${p.totalCost.toStringAsFixed(2)} · SwiftLabel',
          'htmlContent':    html,
          'trackingNumber': 'PAYMENT_FAILED',
          'labelUrl':       '',
          'carrier':        'Payment Notice',
          'service':        'Payment failed',
          'recipientName':  _sNameCtrl.text.trim(),
          'recipientCity':  p.recipCity,
        }),
      ).timeout(const Duration(seconds: 15));
      debugPrint('[PaymentFailedEmail] Sent');
    } catch (e) {
      debugPrint('[PaymentFailedEmail] Error: $e');
    }
  }

  Future<void> _sendLabelFailedEmail(ParcelProvider p) async {
    try {
      final email = _sEmailCtrl.text.trim();
      if (email.isEmpty) return;
      final now = DateTime.now();
      final html =
          '<div style="font-family:sans-serif;max-width:620px;margin:0 auto">'
          '<div style="background:linear-gradient(135deg,#FF7A2F,#FF5A00);padding:28px 32px;border-radius:12px 12px 0 0">'
          '<h1 style="margin:0;color:white;font-size:24px;font-weight:900">SwiftLabel</h1>'
          '<p style="margin:4px 0 0;color:rgba(255,255,255,0.85);font-size:14px">Label Generation Issue</p>'
          '</div>'
          '<div style="background:white;padding:28px 32px;border:1px solid #EEE;border-radius:0 0 12px 12px">'
          '<div style="padding:16px;background:#FEF2F2;border:1px solid #FECACA;border-radius:10px;margin-bottom:20px">'
          '<p style="margin:0;font-size:15px;font-weight:700;color:#DC2626">⚠️ Label Generation Failed</p>'
          '<p style="margin:6px 0 0;font-size:13px;color:#6B7280">Your payment was received but we could not generate your shipping label.</p>'
          '</div>'
          '<p style="font-size:14px;color:#1A1A1A;margin:0 0 6px"><strong>Name:</strong> ${_sNameCtrl.text.trim()}</p>'
          '<p style="font-size:14px;color:#1A1A1A;margin:0 0 6px"><strong>Date:</strong> ${now.day}/${now.month}/${now.year}</p>'
          '<p style="font-size:14px;color:#1A1A1A;margin:0 0 20px"><strong>Amount charged:</strong> £${p.totalCost.toStringAsFixed(2)}</p>'
          '<div style="padding:16px;background:#F0FDF4;border:1px solid #BBF7D0;border-radius:10px;margin-bottom:20px">'
          '<p style="margin:0;font-size:14px;font-weight:700;color:#059669">💚 Full Refund Guaranteed</p>'
          '<p style="margin:6px 0 0;font-size:13px;color:#374151">Your payment of <strong>£${p.totalCost.toStringAsFixed(2)}</strong> will be fully refunded within <strong>3 business days</strong>.</p>'
          '</div>'
          '<p style="font-size:13px;color:#6B7280;margin:0 0 6px">If you have questions, please reply to this email.</p>'
          '<p style="font-size:13px;color:#6B7280;margin:0">We apologise for the inconvenience.</p>'
          '<div style="margin-top:24px;padding-top:16px;border-top:1px solid #EEE">'
          '<p style="margin:0;font-size:11px;color:#9B9B9B">SwiftLabel · ${now.day}/${now.month}/${now.year}</p>'
          '</div></div></div>';

      await http.post(Uri.parse(_emailUrl),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $_anonKey'},
        body: jsonEncode({
          'email':          email,
          'subject':        '⚠️ Label Generation Failed — Refund Incoming · SwiftLabel',
          'htmlContent':    html,
          'trackingNumber': _paymentIntentId,
          'labelUrl':       '',
          'carrier':        'Refund Notice',
          'service':        'Label generation failed',
          'recipientName':  _sNameCtrl.text.trim(),
          'recipientCity':  p.recipCity,
        }),
      ).timeout(const Duration(seconds: 15));
      debugPrint('[LabelFailedEmail] Sent');
    } catch (e) {
      debugPrint('[LabelFailedEmail] Error: $e');
    }
  }

  // ── Mock Payment ──────────────────────────────────────────────
  Future<void> _processPaymentMock(ParcelProvider p) async {
    final num = _cardNumberCtrl.text.replaceAll(RegExp(r'\s'), '');
    final exp = _expiryCtrl.text;
    final cvc = _cvcCtrl.text.trim();
    if (num.length < 16 || exp.length < 5 || cvc.length < 3) {
      setState(() => _paymentError = 'Please fill in all card details correctly.');
      return;
    }

    // ── Phase 1: Simulate payment ─────────────────────────────
    setState(() { _paymentLoading = true; _paymentError = ''; });
    await Future.delayed(const Duration(seconds: 2));

    final bool paymentSucceeded = true; // ← swap with real Stripe result

    if (!paymentSucceeded) {
      setState(() { _paymentLoading = false; _paymentError = 'Your card was declined.'; });
      await Future.delayed(const Duration(milliseconds: 100));
      if (mounted) await _showPaymentPopup(success: false, message: 'Your card was declined. Please try a different card.');
      await _sendPaymentFailedEmail('Card was declined by the payment processor.', p);
      return;
    }

    _paymentIntentId = 'pi_test_${DateTime.now().millisecondsSinceEpoch}';
    setState(() { _paymentConfirmed = true; _paymentLoading = false; });

// ── Small delay to let setState rebuild before showing dialog ──
    await Future.delayed(const Duration(milliseconds: 100));

// ── Phase 2: Show payment success popup ───────────────────
    if (mounted) await _showPaymentPopup(success: true);
    if (!mounted) return;

    // ── Phase 3: Generate label with overlay ──────────────────
    setState(() => _generatingLabel = true);

    final email = context.read<AuthProvider>().email;
    await p.buyLabel(userEmail: email);

    if (!mounted) return;
    setState(() => _generatingLabel = false);

    if (p.isSubmitted) {
      // ── Label SUCCESS: send invoice THEN label email ───────
      await _sendInvoiceEmail(p);   // ← invoice only on success
      _sendLabelEmail(p);           // ← label email (non-blocking)

      if (p.requiresPickup && p.selectedRate != null) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PickupScreen(
            carrierId:      p.selectedRate!.carrierId ?? '',
            carrierName:    p.selectedRate!.carrier,
            labelId:        p.lastLabelId,
            trackingNumber: p.lastTrackingNumber,
            labelUrl:       p.lastLabelUrl,
            senderName:     p.senderName,
            senderPhone:    p.senderPhone,
            senderEmail:    p.senderEmail,
            senderAddress:  '${p.senderDoor} ${p.senderStreet}'.trim(),
            senderCity:     p.senderCity,
            senderPostcode: p.senderPostcode,
          )),
        );
        if (mounted) setState(() => _step = 6);
      } else {
        setState(() => _step = 6);
      }
    } else {
      // ── Label FAILED after payment → refund email only ────
      await _sendLabelFailedEmail(p);   // ← refund notice, NO invoice
      if (mounted) {
        _snack(
          p.errorMessage.isNotEmpty
              ? p.errorMessage
              : 'Label generation failed. A refund will be issued within 3 business days.',
          isError: true,
        );
      }
    }
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : const Color(0xFFFF5A00),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _showFullscreenQR(String labelUrl) {
    final p = context.read<ParcelProvider>();
    showDialog(
      context: context, barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
          // ── Logo + name ──────────────────────────────────
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: Image.asset('assets/images/logo.png',
                  width: 28, height: 28, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                        color: const Color(0xFFFF5A00),
                        borderRadius: BorderRadius.circular(7)),
                    child: const Icon(Icons.inventory_2_outlined,
                        color: Colors.white, size: 16),
                  )),
            ),
            const SizedBox(width: 8),
            const Text('SwiftLabel', style: TextStyle(
                fontFamily: 'Syne', fontSize: 16,
                fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
          ]),
          const SizedBox(height: 16),
          QrImageView(data: labelUrl, version: QrVersions.auto, size: 260,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square,
                  color: Color(0xFF1A1A1A)),
              dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Color(0xFF1A1A1A))),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
                color: const Color(0xFFF3F0FF),
                borderRadius: BorderRadius.circular(8)),
            child: Text(p.lastTrackingNumber,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12,
                    fontWeight: FontWeight.w700, color: Color(0xFF6D28D9))),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF6B6B6B),
                    side: const BorderSide(color: Color(0xFFE0E0E0)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
                child: const Text('Close'))),
            const SizedBox(width: 10),
            Expanded(child: ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(context);
                  final uri = Uri.parse(labelUrl);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                icon: const Icon(Icons.download_rounded, size: 16),
                label: const Text('Download'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6D28D9),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))))),
          ]),
        ])),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ParcelProvider>();
    return Stack(children: [
      Scaffold(
        backgroundColor: const Color(0xFFFAF9F7),
        body: SafeArea(child: Column(children: [
          _buildTopNav(),
          if (_step < 6) _buildBadges(),
          if (_step < 6) _buildStepIndicator(),
          Expanded(child: _buildBody(p)),
          if (_step < 6 && _step != 5) _buildBottomBar(p),
        ])),
      ),

      // ── Full-screen loader shown while label is generating ──
      if (_generatingLabel)
        Positioned.fill(
          child: Material(
            color: Colors.transparent,
            child: Container(
              color: Colors.black.withOpacity(0.75),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(
                  width: 120, height: 120,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2),
                        blurRadius: 40, offset: const Offset(0, 10))],
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const SizedBox(
                      width: 40, height: 40,
                      child: CircularProgressIndicator(color: Color(0xFF6D28D9), strokeWidth: 3),
                    ),
                    const SizedBox(height: 14),
                    const Text('Generating\nlabel...', textAlign: TextAlign.center,
                        style: TextStyle( fontSize: 13,
                            fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
                  ]),
                ),
                const SizedBox(height: 24),
                const Text('Please wait, do not close the app',
                    style: TextStyle(fontSize: 13, color: Colors.white70)),
              ]),
            ),
          ),
        ),
    ]);
  }

  Widget _buildTopNav() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    decoration: const BoxDecoration(color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE)))),
    child: Row(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.asset(
          'assets/images/logo.png',
          width: 30,
          height: 30,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
              color: const Color(0xFFFF5A00),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.inventory_2_outlined, color: Colors.white, size: 16),
          ),
        ),
      ),
      const SizedBox(width: 8),
      const Text('SwiftLabel', style: TextStyle(fontFamily: 'Syne', fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
      const Spacer(),
      GestureDetector(onTap: () => Navigator.pop(context),
          child: const Row(children: [Icon(Icons.arrow_back_ios, size: 14, color: Color(0xFF6B6B6B)), Text('Back to Dashboard', style: TextStyle(fontSize: 13, color: Color(0xFF6B6B6B)))])),
    ]),
  );

  Widget _buildBadges() => Container(
    color: Colors.white, padding: const EdgeInsets.symmetric(vertical: 8),
    child: SingleChildScrollView(scrollDirection: Axis.horizontal, physics: const NeverScrollableScrollPhysics(),
        child: Row(children: [const SizedBox(width: 16), _badge('✓ Label in Under 30 Seconds'), const SizedBox(width: 16), _badge('✓ No Account Required'), const SizedBox(width: 16), _badge('✓ Instant Download'), const SizedBox(width: 16)])),
  );

  Widget _badge(String text) => Text(text, style: const TextStyle(fontSize: 11, color: Color(0xFF059669), fontWeight: FontWeight.w500));

  Widget _buildStepIndicator() {
    const steps = ['Sender', 'Recipient', 'Parcel', 'Courier', 'Summary', 'Pay', 'Label'];
    return Container(
      color: Colors.white, padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Row(children: List.generate(steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          final idx = i ~/ 2;
          return Expanded(child: Container(height: 2, color: idx < _step ? const Color(0xFF6D28D9) : const Color(0xFFEEEEEE)));
        }
        final idx = i ~/ 2; final done = idx < _step; final cur = idx == _step;
        return Column(children: [
          Container(width: 28, height: 28,
              decoration: BoxDecoration(shape: BoxShape.circle,
                  color: done ? const Color(0xFF6D28D9) : cur ? const Color(0xFFF3F0FF) : const Color(0xFFF5F5F5),
                  border: Border.all(color: (done || cur) ? const Color(0xFF6D28D9) : const Color(0xFFE0E0E0), width: 1.5)),
              child: Center(child: done ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : Text('${idx + 1}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cur ? const Color(0xFF6D28D9) : const Color(0xFF9B9B9B))))),
          const SizedBox(height: 4),
          Text(steps[idx], style: TextStyle(fontSize: 9, fontWeight: cur ? FontWeight.w600 : FontWeight.w400, color: (done || cur) ? const Color(0xFF6D28D9) : const Color(0xFF9B9B9B))),
        ]);
      })),
    );
  }

  Widget _buildBody(ParcelProvider p) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_step == 0) _buildStep1(),
        if (_step == 1) RecipientDetailsStep(
          controller: _step2,
          senderPostcode: _sPcCtrl.text.trim().toUpperCase(),
        ),
        if (_step == 2) _buildStep3(p),
        if (_step == 3) _buildStep4(p),
        if (_step == 4) _buildStep5Summary(p),
        if (_step == 5) _buildStep5Payment(p),
        if (_step == 6) _buildStep6(p),
        const SizedBox(height: 24),
      ]),
    );
  }

  // ── STEP 1 ────────────────────────────────────────────────────
  Widget _buildStep1() {
    final profile = context.watch<ProfileProvider>();
    final isProfileComplete = _profileCanPrefill;
    return Form(key: _s1Key, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Step 1: Sender Details', style: TextStyle( fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
      const SizedBox(height: 4),
      const Text('Your contact information', style: TextStyle(fontSize: 13, color: Color(0xFF9B9B9B))),
      const SizedBox(height: 16),
      if (isProfileComplete) ...[
        GestureDetector(
          onTap: () => _onToggleProfilePrefill(!_useProfileData),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _useProfileData ? const Color(0xFFF0FDF4) : const Color(0xFFFFF5EE),
              border: Border.all(color: _useProfileData ? const Color(0xFF059669) : const Color(0xFFFFDDCC), width: _useProfileData ? 1.5 : 1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              AnimatedContainer(duration: const Duration(milliseconds: 150), width: 22, height: 22,
                  decoration: BoxDecoration(color: _useProfileData ? const Color(0xFF059669) : Colors.white,
                      border: Border.all(color: _useProfileData ? const Color(0xFF059669) : const Color(0xFFDDDDDD), width: 1.5),
                      borderRadius: BorderRadius.circular(6)),
                  child: _useProfileData ? const Icon(Icons.check_rounded, size: 14, color: Colors.white) : null),
              const SizedBox(width: 12),
              Container(width: 36, height: 36,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFFF5A00).withOpacity(0.1),
                      border: Border.all(color: const Color(0xFFFF5A00).withOpacity(0.3)),
                      image: profile.hasAvatar ? DecorationImage(image: NetworkImage(profile.avatarUrl), fit: BoxFit.cover) : null),
                  child: !profile.hasAvatar ? Center(child: Text(profile.initials, style: const TextStyle( fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFFF5A00)))) : null),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_useProfileData ? 'Using your saved details' : 'Use my saved profile details',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _useProfileData ? const Color(0xFF059669) : const Color(0xFF1A1A1A))),
                Text(_useProfileData ? '${profile.fullName} · ${profile.postcode}' : 'Auto-fill from your profile',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF9B9B9B)), overflow: TextOverflow.ellipsis),
              ])),
              Icon(_useProfileData ? Icons.edit_outlined : Icons.arrow_forward_ios_rounded, size: 14,
                  color: _useProfileData ? const Color(0xFF059669) : const Color(0xFFFF5A00)),
            ]),
          ),
        ),
        const SizedBox(height: 4),
        if (_useProfileData) const Text('✏️ Fields are editable — make changes if needed', style: TextStyle(fontSize: 11, color: Color(0xFF059669))),
        const SizedBox(height: 16),
      ],
      if (!isProfileComplete) ...[
        Container(padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFFF5EE), border: Border.all(color: const Color(0xFFFFDDCC)), borderRadius: BorderRadius.circular(10)),
            child: const Row(children: [Icon(Icons.person_add_outlined, size: 16, color: Color(0xFFFF5A00)), SizedBox(width: 8),
              Expanded(child: Text('Save your address in Profile to auto-fill next time', style: TextStyle(fontSize: 11, color: Color(0xFFFF5A00))))])),
        const SizedBox(height: 16),
      ],
      Row(
        children: [
          Expanded(
            child: _FieldCol(
              label: 'Full Name *',
              ctrl: _sNameCtrl,
              hint: 'Jane Smith',
              validator: (v) => (v?.isEmpty ?? true) ? 'Required' : null,
            ),
          ),
          const SizedBox(width: 6),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Phone',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6B6B6B),
                  ),
                ),
                const SizedBox(height: 6),

                Row(
                  children: [
                    // 🔹 +44 box
                    Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9F9F9),
                        border: Border.all(color: const Color(0xFFE0E0E0)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        '+44',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                    ),

                    const SizedBox(width: 8),

                    // 🔹 phone input
                    Expanded(
                      child: TextFormField(
                        controller: _sPhoneCtrl,
                        keyboardType: TextInputType.phone,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF1A1A1A),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return null;

                          final digits = v.replaceAll(RegExp(r'\D'), '');
                          if (digits.length < 10) return '(min 10 digits)';
                          if (digits.length > 11) return '(max 11 digits)';
                          return null;
                        },
                        decoration: InputDecoration(
                          hintText: '7700 900000',
                          hintStyle: const TextStyle(
                            color: Color(0xFFB0B0B0),
                            fontSize: 13,
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 13),

                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                            const BorderSide(color: Color(0xFFE0E0E0)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                            const BorderSide(color: Color(0xFFE0E0E0)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                                color: Color(0xFF6D28D9), width: 1.5),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      _FieldCol(label: 'Email *', ctrl: _sEmailCtrl, hint: 'you@example.com', type: TextInputType.emailAddress,
          note: 'Your label will be sent to this email', validator: (v) => (v?.isEmpty ?? true) ? 'Required' : null),
      const SizedBox(height: 12),
      // POSTCODE — remove the ValueKey entirely
      // POSTCODE FIELD — plain TextFormField, no PostcodeLookupField
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Postcode *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF6B6B6B))),
        const SizedBox(height: 6),
        TextFormField(
          controller: _sPcCtrl,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A1A)),
          onChanged: _onSenderPostcodeChanged,
          validator: (v) {
            if (v?.isEmpty ?? true) return 'Required';
            if (!_validUkPc(v!)) return 'Invalid format — use e.g. SW1A 1AA';
            return null;
          },
          decoration: InputDecoration(
            hintText: 'e.g. SW1A 1AA',
            hintStyle: const TextStyle(color: Color(0xFFB0B0B0), fontSize: 13),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            suffixIcon: _sSenderIsLookingUp
                ? const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(color: Color(0xFF6D28D9), strokeWidth: 2)))
                : _sSenderPcValid
                ? const Icon(Icons.check_circle_rounded, color: Color(0xFF059669), size: 20)
                : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: _sSenderPcValid ? const Color(0xFF059669) : _sSenderPcError.isNotEmpty ? Colors.red : const Color(0xFFE0E0E0))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF6D28D9), width: 1.5)),
            errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.red)),
          ),
        ),
        if (_sSenderPcError.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(_sSenderPcError, style: const TextStyle(fontSize: 11, color: Colors.red)),
        ],
        if (_sSenderPcValid && !_sSenderIsLookingUp) ...[
          const SizedBox(height: 4),
          const Text('✓ Postcode verified — city and streets auto-filled',
              style: TextStyle(fontSize: 11, color: Color(0xFF059669))),
        ],
      ]),
      const SizedBox(height: 12),

// STREET FIELD — dropdown when streets available, text otherwise
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Street *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF6B6B6B))),
        const SizedBox(height: 6),
        if (_sSenderStreetList.isNotEmpty)
          DropdownButtonFormField<String>(
            value: _sSenderSelectedStreet,
            isExpanded: true,
            hint: const Text('Select your street', style: TextStyle(color: Color(0xFFB0B0B0), fontSize: 14)),
            style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A1A)),
            decoration: InputDecoration(
              filled: true, fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF6D28D9), width: 1.5)),
            ),
            items: [
              ..._sSenderStreetList.map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis))),
              const DropdownMenuItem(value: '__manual__',
                  child: Text('✏️ Enter manually', style: TextStyle(color: Color(0xFF6D28D9), fontWeight: FontWeight.w600))),
            ],
            onChanged: (val) {
              setState(() {
                if (val == '__manual__') {
                  _sSenderSelectedStreet = null;
                  _sSenderStreetList     = [];
                  _sStrCtrl.clear();
                } else {
                  _sSenderSelectedStreet = val;
                  _sStrCtrl.text         = val ?? '';
                }
              });
            },
            validator: (v) => (v == null || v.isEmpty || v == '__manual__') ? 'Required' : null,
          )
        else
          TextFormField(
            controller: _sStrCtrl,
            style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A1A)),
            validator: (v) => (v?.isEmpty ?? true) ? 'Required' : null,
            decoration: InputDecoration(
              hintText: 'Baker Street',
              hintStyle: const TextStyle(color: Color(0xFFB0B0B0), fontSize: 13),
              filled: true, fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF6D28D9), width: 1.5)),
              errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.red)),
            ),
          ),
        if (_sSenderPcValid && _sSenderStreetList.isEmpty && !_sSenderIsLookingUp) ...[
          const SizedBox(height: 4),
          const Text('Type your street name above', style: TextStyle(fontSize: 11, color: Color(0xFF9B9B9B))),
        ],
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _FieldCol(label: 'Door / No. *', ctrl: _sDoorCtrl, hint: '12A', validator: (v) => (v?.isEmpty ?? true) ? 'Required' : null)),
        const SizedBox(width: 10),
        Expanded(child: _FieldCol(label: 'City *', ctrl: _sCityCtrl, hint: 'London', validator: (v) => (v?.isEmpty ?? true) ? 'Required' : null)),
      ]),
    ]));
  }

  // ── STEP 3 ────────────────────────────────────────────────────
  Widget _buildStep3(ParcelProvider p) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Step 3: Parcel Details', style: TextStyle( fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
    const SizedBox(height: 20),
    const Text('Parcel Size Guide', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF3A3A3A))),
    const SizedBox(height: 10),
    GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.6,
        children: ParcelProvider.sizes.map((size) {
          final sel = p.selectedSizeId == size.id;
          return GestureDetector(onTap: () => p.setSize(size.id),
              child: Container(padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: sel ? const Color(0xFFF3F0FF) : Colors.white,
                      border: Border.all(color: sel ? const Color(0xFF6D28D9) : const Color(0xFFEEEEEE), width: sel ? 1.5 : 1),
                      borderRadius: BorderRadius.circular(12)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Flexible(child: Text(size.name, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: sel ? const Color(0xFF6D28D9) : const Color(0xFF1A1A1A)))),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(color: sel ? const Color(0xFF6D28D9).withOpacity(0.1) : const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(4)),
                          child: Text(size.maxWeight, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: sel ? const Color(0xFF6D28D9) : const Color(0xFF6B6B6B)))),
                    ]),
                    const SizedBox(height: 4),
                    Text(size.dimensions, style: const TextStyle(fontSize: 10, color: Color(0xFF6B6B6B))),
                    const Spacer(),
                    Text(size.examples, style: const TextStyle(fontSize: 9, color: Color(0xFF9B9B9B)), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ])));
        }).toList()),
    const SizedBox(height: 20),
    const Text('Parcel Type', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF3A3A3A))),
    const SizedBox(height: 10),
    Wrap(spacing: 8, runSpacing: 8, children: ParcelProvider.parcelTypes.map((t) {
      final sel = p.selectedParcelType == t;
      return GestureDetector(onTap: () => p.setParcelType(t),
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(color: sel ? const Color(0xFF6D28D9) : Colors.white,
                  border: Border.all(color: sel ? const Color(0xFF6D28D9) : const Color(0xFFE0E0E0)), borderRadius: BorderRadius.circular(20)),
              child: Text(t, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: sel ? Colors.white : const Color(0xFF3A3A3A)))));
    }).toList()),
    const SizedBox(height: 20),
    Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Weight (kg)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF6B6B6B))),
        const SizedBox(height: 6),
        TextFormField(
          initialValue: p.weightKg,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
          onChanged: (val) { p.setWeight(val); setState(() {}); },
          style: const TextStyle(fontSize: 14),
          decoration: _inputDec('e.g. 1.5'),
        ),
        const SizedBox(height: 5),
        if (p.selectedSizeId.isNotEmpty && p.weightKg.isNotEmpty)
          Builder(builder: (context) {
            final err = p.validateWeightForSize();
            if (err == null) {
              return Row(children: const [
                Icon(Icons.check_circle_rounded, size: 13, color: Color(0xFF059669)),
                SizedBox(width: 4),
                Text('Weight OK',
                    style: TextStyle(fontSize: 11, color: Color(0xFF059669), fontWeight: FontWeight.w500)),
              ]);
            }
            // ── Error pill ─────────────────────────────────────
            return Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                border: Border.all(color: const Color(0xFFFECACA)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(Icons.info_outline_rounded, size: 13, color: Color(0xFFDC2626)),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(err,
                      style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFFDC2626),
                          height: 1.4,
                          fontWeight: FontWeight.w500)),
                ),
              ]),
            );
          }),
      ])),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Value (£)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF6B6B6B))),
        const SizedBox(height: 6),
        TextFormField(initialValue: p.parcelValueGbp, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))], onChanged: p.setParcelValue,
            style: const TextStyle(fontSize: 14), decoration: _inputDec('e.g. 50.00')),
      ])),
    ]),
  ]);

  // ── STEP 4 ────────────────────────────────────────────────────
  Widget _buildStep4(ParcelProvider p) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Step 4: Choose Courier', style: TextStyle( fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
    const SizedBox(height: 4),
    const Text('Live prices from ShipEngine', style: TextStyle(fontSize: 13, color: Color(0xFF9B9B9B))),
    const SizedBox(height: 20),
    if (p.isLoadingRates) const Center(child: Column(children: [
      SizedBox(height: 30),
      CircularProgressIndicator(color: Color(0xFF6D28D9), strokeWidth: 2.5),
      SizedBox(height: 14),
      Text('Comparing live rates from couriers...', style: TextStyle(fontSize: 13, color: Color(0xFF9B9B9B))),
      SizedBox(height: 30),
    ])),
    if (!p.isLoadingRates && p.ratesError.isNotEmpty) ...[
      Container(padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.red.withOpacity(0.05), border: Border.all(color: Colors.red.withOpacity(0.2)), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [const Icon(Icons.error_outline_rounded, color: Colors.red, size: 18), const SizedBox(width: 10), Expanded(child: Text(p.ratesError, style: const TextStyle(fontSize: 13, color: Colors.red)))])),
      const SizedBox(height: 12),
      SizedBox(width: double.infinity, height: 44, child: OutlinedButton.icon(onPressed: () => p.getRates(), icon: const Icon(Icons.refresh_rounded, size: 16), label: const Text('Try Again'),
          style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF6D28D9), side: const BorderSide(color: Color(0xFF6D28D9)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))))),
    ],
    if (!p.isLoadingRates && p.ratesError.isEmpty && p.liveRates.isNotEmpty) ...[
      const SizedBox(height: 12),
      Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(8)),
          child: const Row(children: [
            Expanded(flex: 3, child: Text('Courier', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF6B6B6B)))),
            Expanded(flex: 3, child: Text('Delivery', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF6B6B6B)))),
            Expanded(flex: 3, child: Text('Service', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF6B6B6B)))),
            Text('Price', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF6B6B6B))),
          ])),
      const SizedBox(height: 6),
      ...p.sortedRates.map((rate) {
        final sel = p.selectedRateId == rate.rateId;
        return GestureDetector(onTap: () => p.selectRate(rate),
            child: Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(color: sel ? const Color(0xFFFFFBE6) : Colors.white,
                    border: Border.all(color: sel ? const Color(0xFFF5C400) : const Color(0xFFEEEEEE), width: sel ? 1.5 : 1),
                    borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  Expanded(flex: 3, child: Row(children: [
                    _SendCarrierLogo(carrier: rate.carrier, color: rate.carrierColor),
                    const SizedBox(width: 8),
                    Expanded(child: Text(rate.carrier, style: TextStyle(fontSize: 13, fontWeight: sel ? FontWeight.w700 : FontWeight.w500, color: const Color(0xFF1A1A1A)), overflow: TextOverflow.ellipsis)),
                  ])),
                  Expanded(flex: 3, child: Text(rate.deliveryLabel, style: const TextStyle(fontSize: 11, color: Color(0xFF6B6B6B)))),
                  Expanded(flex: 3, child: Text(rate.service, style: const TextStyle(fontSize: 10, color: Color(0xFF9B9B9B)), overflow: TextOverflow.ellipsis)),
                  Text('£${rate.price.toStringAsFixed(2)}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: sel ? const Color(0xFF1A1A1A) : const Color(0xFF3A3A3A))),
                ])));
      }),
    ],
  ]);

  // ── STEP 5: Summary ───────────────────────────────────────────
  Widget _buildStep5Summary(ParcelProvider p) {
    final rate = p.selectedRate;
    if (rate == null) return const SizedBox();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Order Summary', style: TextStyle( fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
      const SizedBox(height: 16),
      Container(width: double.infinity, padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: const Color(0xFFFFFBE6), border: Border.all(color: const Color(0xFFF5C400)), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            _SendCarrierLogo(carrier: rate.carrier, color: rate.carrierColor),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(rate.carrier, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
              Text(rate.service, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
              Text(rate.deliveryLabel, style: const TextStyle(fontSize: 12, color: Color(0xFF6B6B6B))),
            ]),
          ])),
      const SizedBox(height: 12),
      Container(padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFEEEEEE)), borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            const Text('Price Breakdown', style: TextStyle( fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
            const SizedBox(height: 12),
            _PriceRow(label: 'Shipping Label (${rate.carrier})', value: '£${rate.price.toStringAsFixed(2)}'),
            _PriceRow(
              label: p.isInternational ? 'International Fee' : 'Service Fee',
              value: '£${p.serviceFee.toStringAsFixed(2)}',
            ),
            _PriceRow(label: 'Parcel Size', value: p.selectedSize?.name ?? '—'),
            const Divider(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Total', style: TextStyle( fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
              Text('£${p.totalCost.toStringAsFixed(2)}', style: const TextStyle( fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
            ]),
          ])),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _AddressCard(label: 'FROM', name: p.senderName, city: p.senderCity, postcode: p.senderPostcode, phone: p.senderPhone)),
        const SizedBox(width: 10),
        Expanded(child: _AddressCard(label: 'TO', name: p.recipName, city: p.recipCity, postcode: p.recipPostcode, phone: p.recipPhone)),
      ]),
      const SizedBox(height: 12),
      Container(padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFEEEEEE)), borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            const Icon(Icons.inventory_2_outlined, size: 18, color: Color(0xFF6B6B6B)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${p.selectedSize?.name ?? ''} · ${p.selectedParcelType}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A))),
              Text(p.selectedSize?.dimensions ?? '', style: const TextStyle(fontSize: 11, color: Color(0xFF9B9B9B))),
            ])),
          ])),
      const SizedBox(height: 16),
      Container(padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: const Color(0xFFF9F9F9), border: Border.all(color: const Color(0xFFEEEEEE)), borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            const Text('TRUSTED SHIPPING PARTNERS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF9B9B9B), letterSpacing: 1)),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 10,
              children: [
                _PartnerLogo('Royal Mail',  'assets/carriers/royal_mail.png',  const Color(0xFFE30613)),
                _PartnerLogo('Parcelforce', 'assets/carriers/parcelforce.png', const Color(0xFF003087)),
                _PartnerLogo('Evri',        'assets/carriers/evri.png',        const Color(0xFF8B5CF6)),
                _PartnerLogo('DPD',         'assets/carriers/dpd.png',         const Color(0xFFE8001C)),
                _PartnerLogo('Yodel',       'assets/carriers/yodel.png',       const Color(0xFF6D28D9)),
                _PartnerLogo('FedEx',       'assets/carriers/fedex.png',       const Color(0xFF4D148C)),
                _PartnerLogo('DHL',         'assets/carriers/dhl.png',         const Color(0xFFFFC300)),
                _PartnerLogo('UPS',         'assets/carriers/ups.png',         const Color(0xFF351C15)),
                _PartnerLogo('GlobalPost',  'assets/carriers/globalpost.png',  const Color(0xFF0284C7)),
              ],
            ),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [_TrustBadge('🔒 Stripe Secure'), const SizedBox(width: 12), _TrustBadge('🛡️ SSL Protected')]),
          ])),
      const SizedBox(height: 8),
      Center(child: GestureDetector(onTap: () => setState(() => _step = 0),
          child: const Text('← Edit details', style: TextStyle(fontSize: 12, color: Color(0xFF6B6B6B), decoration: TextDecoration.underline)))),
    ]);
  }

  // ── STEP 5: Payment ───────────────────────────────────────────
  // Widget _buildStep5Payment(ParcelProvider p) {
  //   final rate = p.selectedRate;
  //   return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
  //     Container(
  //       width: double.infinity,
  //       decoration: BoxDecoration(
  //         color: const Color(0xFF6D28D9),
  //         borderRadius: BorderRadius.circular(16),
  //       ),
  //       child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
  //         Container(
  //           padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
  //           decoration: BoxDecoration(
  //             color: Colors.white.withOpacity(0.08),
  //             borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
  //             border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.15))),
  //           ),
  //           child: Row(children: [
  //             Icon(Icons.local_shipping_outlined, size: 13, color: Colors.white.withOpacity(0.6)),
  //             const SizedBox(width: 6),
  //             Text('Shipping summary',
  //                 style: TextStyle(fontSize: 11, letterSpacing: 0.6, fontWeight: FontWeight.w500, color: Colors.white.withOpacity(0.6))),
  //           ]),
  //         ),
  //         Padding(
  //           padding: const EdgeInsets.all(16),
  //           child: Column(children: [
  //             Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
  //               Container(
  //                 width: 40, height: 40,
  //                 decoration: BoxDecoration(
  //                   color: Colors.white.withOpacity(0.15),
  //                   borderRadius: BorderRadius.circular(10),
  //                 ),
  //                 child: Icon(Icons.local_shipping_outlined, color: Colors.white.withOpacity(0.9), size: 20),
  //               ),
  //               const SizedBox(width: 12),
  //               Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
  //                 Text(rate?.carrier ?? '',
  //                     style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
  //                 const SizedBox(height: 2),
  //                 Text('${p.selectedSize?.name ?? ''} · ${rate?.deliveryLabel ?? ''}',
  //                     style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.65))),
  //                 const SizedBox(height: 6),
  //                 Container(
  //                   padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
  //                   decoration: BoxDecoration(
  //                     color: Colors.white.withOpacity(0.15),
  //                     borderRadius: BorderRadius.circular(20),
  //                   ),
  //                   child: Text('Estimated delivery: ${rate?.deliveryLabel ?? ''}',
  //                       style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.9))),
  //                 ),
  //               ])),
  //             ]),
  //             const SizedBox(height: 14),
  //             Container(
  //               padding: const EdgeInsets.only(top: 14),
  //               decoration: BoxDecoration(
  //                 border: Border(top: BorderSide(color: Colors.white.withOpacity(0.15))),
  //               ),
  //               child: Row(children: [
  //                 Expanded(child: Column(children: [
  //                   Text('Shipping Label', style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.55))),
  //                   const SizedBox(height: 4),
  //                   Text('£${p.shippingCost.toStringAsFixed(2)}',
  //                       style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.85))),
  //                 ])),
  //                 Container(width: 0.5, height: 28, color: Colors.white.withOpacity(0.2)),
  //                 Expanded(child: Column(children: [
  //                   Text('Service Fee', style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.55))),
  //                   const SizedBox(height: 4),
  //                   Text('£${p.serviceFee.toStringAsFixed(2)}',
  //                       style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.85))),
  //                 ])),
  //                 Container(width: 0.5, height: 28, color: Colors.white.withOpacity(0.2)),
  //                 Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
  //                   Text('Total', style: TextStyle(fontSize: 11, letterSpacing: 0.5, color: Colors.white.withOpacity(0.55))),
  //                   const SizedBox(height: 2),
  //                   Text('£${p.totalCost.toStringAsFixed(2)}',
  //                       style: const TextStyle( fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
  //                 ])),
  //               ]),
  //             ),
  //           ]),
  //         ),
  //       ]),
  //     ),
  //     const SizedBox(height: 20),
  //     Container(
  //         decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFF0F0F0)),
  //             boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 24, offset: const Offset(0, 6))]),
  //         child: Column(children: [
  //           Container(padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
  //               decoration: const BoxDecoration(color: Color(0xFFFAFAFA),
  //                   borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
  //                   border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0)))),
  //               child: Row(children: [
  //                 Container(width: 38, height: 38, decoration: BoxDecoration(color: const Color(0xFF059669).withOpacity(0.1), shape: BoxShape.circle),
  //                     child: const Icon(Icons.lock_rounded, color: Color(0xFF059669), size: 19)),
  //                 const SizedBox(width: 12),
  //                 const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
  //                   Text('Card Details', style: TextStyle( fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
  //                   Text('256-bit SSL · Powered by Stripe', style: TextStyle(fontSize: 11, color: Color(0xFF059669))),
  //                 ])),
  //                 Row(children: [_CardBadge('VISA', const Color(0xFF1A1F71)), const SizedBox(width: 4), _CardBadge('MC', const Color(0xFFEB001B)), const SizedBox(width: 4), _CardBadge('AMEX', const Color(0xFF007BC1))]),
  //               ])),
  //           Padding(padding: const EdgeInsets.fromLTRB(18, 20, 18, 20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
  //             const Text('Card Number', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF9B9B9B), letterSpacing: 0.5)),
  //             const SizedBox(height: 8),
  //             Container(decoration: BoxDecoration(color: const Color(0xFFF8F8F8), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE8E8E8))),
  //                 child: TextFormField(controller: _cardNumberCtrl, keyboardType: TextInputType.number, maxLength: 22,
  //                     style: const TextStyle(fontSize: 16, color: Color(0xFF1A1A1A), fontFamily: 'monospace', letterSpacing: 2),
  //                     decoration: const InputDecoration(hintText: '1234  5678  9012  3456', hintStyle: TextStyle(color: Color(0xFFB0B0B0), fontSize: 14, letterSpacing: 1, fontFamily: 'monospace'),
  //                         border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14), counterText: '',
  //                         suffixIcon: Padding(padding: EdgeInsets.only(right: 12), child: Icon(Icons.credit_card_rounded, color: Color(0xFFB0B0B0), size: 20)),
  //                         suffixIconConstraints: BoxConstraints(minWidth: 0, minHeight: 0)),
  //                     inputFormatters: [FilteringTextInputFormatter.digitsOnly, _CardNumberFormatter()], onChanged: (_) => setState(() {}))),
  //             const SizedBox(height: 14),
  //             Row(children: [
  //               Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
  //                 const Text('Expiry Date', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF9B9B9B), letterSpacing: 0.5)),
  //                 const SizedBox(height: 8),
  //                 Container(decoration: BoxDecoration(color: const Color(0xFFF8F8F8), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE8E8E8))),
  //                     child: TextFormField(controller: _expiryCtrl, keyboardType: TextInputType.number, maxLength: 5,
  //                         style: const TextStyle(fontSize: 16, color: Color(0xFF1A1A1A), fontFamily: 'monospace', letterSpacing: 2),
  //                         decoration: const InputDecoration(hintText: 'MM/YY', hintStyle: TextStyle(color: Color(0xFFB0B0B0), fontSize: 14, letterSpacing: 1), border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14), counterText: ''),
  //                         inputFormatters: [FilteringTextInputFormatter.digitsOnly, _ExpiryFormatter()], onChanged: (_) => setState(() {}))),
  //               ])),
  //               const SizedBox(width: 12),
  //               Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
  //                 const Text('CVC', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF9B9B9B), letterSpacing: 0.5)),
  //                 const SizedBox(height: 8),
  //                 Container(decoration: BoxDecoration(color: const Color(0xFFF8F8F8), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE8E8E8))),
  //                     child: TextFormField(controller: _cvcCtrl, keyboardType: TextInputType.number, maxLength: 3, obscureText: true,
  //                         style: const TextStyle(fontSize: 16, color: Color(0xFF1A1A1A), letterSpacing: 6),
  //                         decoration: const InputDecoration(hintText: '•••', hintStyle: TextStyle(color: Color(0xFFB0B0B0), fontSize: 18, letterSpacing: 4), border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14), counterText: '',
  //                             suffixIcon: Padding(padding: EdgeInsets.only(right: 12), child: Icon(Icons.lock_outline_rounded, color: Color(0xFFB0B0B0), size: 18)), suffixIconConstraints: BoxConstraints(minWidth: 0, minHeight: 0)),
  //                         inputFormatters: [FilteringTextInputFormatter.digitsOnly], onChanged: (_) => setState(() {}))),
  //               ])),
  //             ]),
  //             const SizedBox(height: 20),
  //             Container(padding: const EdgeInsets.all(16),
  //                 decoration: BoxDecoration(color: const Color(0xFFF0FDF4), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFBBF7D0))),
  //                 child: Column(children: [
  //                   Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
  //                     Text('${rate?.carrier ?? ''} shipping', style: const TextStyle(fontSize: 13, color: Color(0xFF3A3A3A))),
  //                     Text('£${(rate?.price ?? 0).toStringAsFixed(2)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A))),
  //                   ]),
  //                   const SizedBox(height: 8),
  //                   Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
  //                     Text(p.isInternational ? 'International fee' : 'Service fee', style: const TextStyle(fontSize: 13, color: Color(0xFF3A3A3A))),
  //                     Text('£${p.serviceFee.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A))),
  //                   ]),
  //                   const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider(height: 1, color: Color(0xFFBBF7D0))),
  //                   Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
  //                     const Text('Total charged today', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
  //                     Text('£${p.totalCost.toStringAsFixed(2)}', style: const TextStyle( fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF059669))),
  //                   ]),
  //                 ])),
  //             const SizedBox(height: 14),
  //             if(!_useLivePayment)
  //             Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
  //                 decoration: BoxDecoration(color: const Color(0xFFF3F0FF), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFDDD6FE))),
  //                 child: const Row(children: [Icon(Icons.science_outlined, size: 15, color: Color(0xFF6D28D9)), SizedBox(width: 8),
  //                   Expanded(child: Text('Test mode  ·  4242 4242 4242 4242  ·  Any future date  ·  Any 3-digit CVC', style: TextStyle(fontSize: 11, color: Color(0xFF6D28D9), height: 1.4)))])),
  //           ])),
  //         ])),
  //     if (_paymentError.isNotEmpty) ...[
  //       const SizedBox(height: 14),
  //       Container(padding: const EdgeInsets.all(12),
  //           decoration: BoxDecoration(color: Colors.red.withOpacity(0.05), border: Border.all(color: Colors.red.withOpacity(0.2)), borderRadius: BorderRadius.circular(10)),
  //           child: Row(children: [const Icon(Icons.error_outline_rounded, color: Colors.red, size: 16), const SizedBox(width: 8), Expanded(child: Text(_paymentError, style: const TextStyle(fontSize: 12, color: Colors.red)))])),
  //     ],
  //     const SizedBox(height: 24),
  //     SizedBox(width: double.infinity, height: 58,
  //         child: ElevatedButton(
  //           onPressed: _paymentLoading
  //               ? null
  //               : () {
  //             if (_useLivePayment) {
  //               _processPayment(p);
  //             } else {
  //               _processPaymentMock(p);
  //             }
  //           },
  //           style: ElevatedButton.styleFrom(
  //               backgroundColor: const Color(0xFF059669),
  //               foregroundColor: Colors.white,
  //               disabledBackgroundColor: const Color(0xFF059669).withOpacity(0.6),
  //               elevation: 0,
  //               shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  //               textStyle: const TextStyle( fontSize: 17, fontWeight: FontWeight.w800)),
  //           child: _paymentLoading
  //               ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
  //             SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)),
  //             SizedBox(width: 12),
  //             Text('Processing payment...'),
  //           ])
  //               : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
  //             const Icon(Icons.lock_rounded, size: 18, color: Colors.white),
  //             const SizedBox(width: 8),
  //             Text('Pay £${p.totalCost.toStringAsFixed(2)} securely'),
  //           ]),
  //         )),
  //     const SizedBox(height: 12),
  //     const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
  //       Icon(Icons.verified_user_outlined, size: 12, color: Color(0xFFB0B0B0)), SizedBox(width: 4),
  //       Text('Stripe  ·  PCI DSS compliant  ·  256-bit SSL', style: TextStyle(fontSize: 10, color: Color(0xFFB0B0B0))),
  //     ]),
  //   ]);
  // }

  Widget _buildStep5Payment(ParcelProvider p) {
    final rate = p.selectedRate;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Shipping Summary Card ─────────────────────────────
      Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF6D28D9),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.15))),
            ),
            child: Row(children: [
              Icon(Icons.local_shipping_outlined, size: 13, color: Colors.white.withOpacity(0.6)),
              const SizedBox(width: 6),
              Text('Shipping summary',
                  style: TextStyle(fontSize: 11, letterSpacing: 0.6,
                      fontWeight: FontWeight.w500, color: Colors.white.withOpacity(0.6))),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.local_shipping_outlined,
                      color: Colors.white.withOpacity(0.9), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(rate?.carrier ?? '',
                      style: const TextStyle(fontSize: 14,
                          fontWeight: FontWeight.w600, color: Colors.white)),
                  const SizedBox(height: 2),
                  Text('${p.selectedSize?.name ?? ''} · ${rate?.deliveryLabel ?? ''}',
                      style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.65))),
                ])),
              ]),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.only(top: 14),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.white.withOpacity(0.15))),
                ),
                child: Row(children: [
                  Expanded(child: Column(children: [
                    Text('Shipping', style: TextStyle(fontSize: 11,
                        color: Colors.white.withOpacity(0.55))),
                    const SizedBox(height: 4),
                    Text('£${p.shippingCost.toStringAsFixed(2)}',
                        style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.85))),
                  ])),
                  Container(width: 0.5, height: 28, color: Colors.white.withOpacity(0.2)),
                  Expanded(child: Column(children: [
                    Text('Service Fee', style: TextStyle(fontSize: 11,
                        color: Colors.white.withOpacity(0.55))),
                    const SizedBox(height: 4),
                    Text('£${p.serviceFee.toStringAsFixed(2)}',
                        style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.85))),
                  ])),
                  Container(width: 0.5, height: 28, color: Colors.white.withOpacity(0.2)),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('Total', style: TextStyle(fontSize: 11,
                        color: Colors.white.withOpacity(0.55))),
                    const SizedBox(height: 2),
                    Text('£${p.totalCost.toStringAsFixed(2)}',
                        style: const TextStyle( fontSize: 20,
                            fontWeight: FontWeight.w700, color: Colors.white)),
                  ])),
                ]),
              ),
            ]),
          ),
        ]),
      ),

      const SizedBox(height: 20),

      // ── Address summary ───────────────────────────────────
      Row(children: [
        Expanded(child: _AddressCard(
            label: 'FROM', name: p.senderName,
            city: p.senderCity, postcode: p.senderPostcode, phone: p.senderPhone)),
        const SizedBox(width: 10),
        Expanded(child: _AddressCard(
            label: 'TO', name: p.recipName,
            city: p.recipCity, postcode: p.recipPostcode, phone: p.recipPhone)),
      ]),

      const SizedBox(height: 20),

      // ── Trust badges ──────────────────────────────────────
      const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.lock_rounded, size: 14, color: Color(0xFF059669)),
        SizedBox(width: 6),
        Text('Secured by Stripe · 256-bit SSL · PCI DSS compliant',
            style: TextStyle(fontSize: 11, color: Color(0xFF6B6B6B))),
      ]),

      const SizedBox(height: 20),

      // ── Error message ─────────────────────────────────────
      // if (_paymentError.isNotEmpty) ...[
      //   Container(
      //     padding: const EdgeInsets.all(12),
      //     decoration: BoxDecoration(
      //       color: Colors.red.withOpacity(0.05),
      //       border: Border.all(color: Colors.red.withOpacity(0.2)),
      //       borderRadius: BorderRadius.circular(10),
      //     ),
      //     child: Row(children: [
      //       const Icon(Icons.error_outline_rounded, color: Colors.red, size: 16),
      //       const SizedBox(width: 8),
      //       Expanded(child: Text(_paymentError,
      //           style: const TextStyle(fontSize: 12, color: Colors.red))),
      //     ]),
      //   ),
      //   const SizedBox(height: 14),
      // ],

      // ── Pay Button → opens Stripe sheet ──────────────────
      SizedBox(
        width: double.infinity,
        height: 58,
        child: ElevatedButton(
          onPressed: _paymentLoading ? null : () => _processPayment(p),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF059669),
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0xFF059669).withOpacity(0.6),
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            textStyle: const TextStyle(
                 fontSize: 17, fontWeight: FontWeight.w800),
          ),
          child: _paymentLoading
              ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)),
            SizedBox(width: 12),
            Text('Processing...'),
          ])
              : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.lock_rounded, size: 18, color: Colors.white),
            const SizedBox(width: 8),
            Text('Pay £${p.totalCost.toStringAsFixed(2)} securely'),
          ]),
        ),
      ),

      const SizedBox(height: 12),
      const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.verified_user_outlined, size: 12, color: Color(0xFFB0B0B0)),
        SizedBox(width: 4),
        Text('Stripe · PCI DSS compliant · 256-bit SSL',
            style: TextStyle(fontSize: 10, color: Color(0xFFB0B0B0))),
      ]),
    ]);
  }

  // ── STEP 6: Label ─────────────────────────────────────────────
  Widget _buildStep6(ParcelProvider p) {
    final hasLabel = p.lastLabelUrl.isNotEmpty;
    return Center(child: Column(children: [
      const SizedBox(height: 20),
      Container(width: 80, height: 80, decoration: BoxDecoration(color: const Color(0xFF059669).withOpacity(0.1), shape: BoxShape.circle),
          child: const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF059669), size: 44)),
      const SizedBox(height: 16),
      const Text('Parcel Booked!', style: TextStyle( fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
      const SizedBox(height: 6),
      const Text('Your label has been emailed to you.\nPrint it and attach to your parcel.', textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Color(0xFF6B6B6B), height: 1.6)),
      const SizedBox(height: 12),
      Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: const Color(0xFFF0FDF4), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFBBF7D0))),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.email_outlined, size: 14, color: Color(0xFF059669)), SizedBox(width: 6),
            Text('Invoice & label sent to your email', style: TextStyle(fontSize: 12, color: Color(0xFF059669), fontWeight: FontWeight.w500))])),
      const SizedBox(height: 20),
      Container(width: double.infinity, padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFEEEEEE)), borderRadius: BorderRadius.circular(14)),
          child: Column(children: [
            const Text('Tracking Number', style: TextStyle(fontSize: 12, color: Color(0xFF9B9B9B))),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(p.lastTrackingNumber, style: const TextStyle(fontFamily: 'monospace', fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A), letterSpacing: 1)),
              const SizedBox(width: 8),
              GestureDetector(onTap: () { Clipboard.setData(ClipboardData(text: p.lastTrackingNumber)); _snack('Tracking number copied!'); },
                  child: const Icon(Icons.copy_rounded, size: 16, color: Color(0xFF9B9B9B))),
            ]),
            const SizedBox(height: 20), const Divider(), const SizedBox(height: 16),
            if (hasLabel) ...[
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Scan  Digital Label', style: TextStyle( fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
                GestureDetector(onTap: () => _showFullscreenQR(p.lastLabelUrl),
                    child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: const Color(0xFF6D28D9).withOpacity(0.08), borderRadius: BorderRadius.circular(20)),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.fullscreen_rounded, size: 14, color: Color(0xFF6D28D9)), SizedBox(width: 4), Text('Expand', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF6D28D9)))]))),
              ]),
              const SizedBox(height: 8),
              Container(
                  alignment: Alignment.center,
                  child: const Text('Scan this QR code yourself, or show it to the staff at your drop-off point.',textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Color(0xFF6B6B6B)))),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: Image.asset('assets/images/logo.png',
                      width: 28, height: 28, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(
                            color: const Color(0xFFFF5A00),
                            borderRadius: BorderRadius.circular(7)),
                        child: const Icon(Icons.inventory_2_outlined,
                            color: Colors.white, size: 16),
                      )),
                ),
                const SizedBox(width: 8),
                const Text('SwiftLabel', style: TextStyle(
                    fontFamily: 'Syne', fontSize: 16,
                    fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
              ]),
              const SizedBox(height: 12),
              GestureDetector(onTap: () => _showFullscreenQR(p.lastLabelUrl),
                  child: Container(padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFEEEEEE), width: 2), borderRadius: BorderRadius.circular(12)),
                      child: QrImageView(data: p.lastLabelUrl, version: QrVersions.auto, size: 180, backgroundColor: Colors.white,
                          eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF1A1A1A)),
                          dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF1A1A1A))))),
              const SizedBox(height: 8),
              const Text('Scan with any camera to open label', style: TextStyle(fontSize: 11, color: Color(0xFF9B9B9B))),
              const Text('Tap QR to expand fullscreen', style: TextStyle(fontSize: 10, color: Color(0xFFB0B0B0))),
          ],
          ])),
      const SizedBox(height: 16),
      if (hasLabel) SizedBox(width: double.infinity, height: 48,
          child: ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _downloadLabel(p.lastLabelUrl, p.lastTrackingNumber);
              },  icon: const Icon(Icons.download_rounded, size: 18, color: Colors.white),
              label: const Text('Download Label PDF'),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6D28D9), foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), textStyle: const TextStyle( fontSize: 15, fontWeight: FontWeight.w700)))),
      const SizedBox(height: 10),
      SizedBox(width: double.infinity, height: 48,
          child: OutlinedButton.icon(onPressed: () { p.reset(); Navigator.pop(context); },
              icon: const Icon(Icons.home_outlined, size: 18), label: const Text('Back to Dashboard'),
              style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF6B6B6B), side: const BorderSide(color: Color(0xFFE0E0E0)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))))),
    ]));
  }
  Future<void> _downloadLabel(String url, String trackingNumber) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(children: [
          SizedBox(width: 16, height: 16,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
          SizedBox(width: 12),
          Text('Downloading label...'),
        ]),
        backgroundColor: const Color(0xFF6D28D9),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 30),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );

    try {
      // ── Request permission ────────────────────────────────
      if (Platform.isAndroid) {
        final status = await Permission.storage.request();
        if (!status.isGranted && !status.isLimited) {
          final manageStatus = await Permission.manageExternalStorage.request();
          if (!manageStatus.isGranted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            _snack('Storage permission required to save PDF.', isError: true);
            return;
          }
        }
      }

      // ── Save path ─────────────────────────────────────────
      final fileName = 'SwiftLabel_${trackingNumber.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}.pdf';
      String filePath;

      if (Platform.isAndroid) {
        filePath = '/storage/emulated/0/Download/$fileName';
      } else {
        final dir = await getApplicationDocumentsDirectory();
        filePath = '${dir.path}/$fileName';
      }

      // ── Download ──────────────────────────────────────────
      final dio = Dio();
      await dio.download(url, filePath);

      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      if (!mounted) return;

      // ── Success + open ────────────────────────────────────
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            const Expanded(child: Text('Label saved to Downloads!')),
          ]),
          backgroundColor: const Color(0xFF059669),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          action: SnackBarAction(
            label: 'Open',
            textColor: Colors.white,
            onPressed: () async {
              final result = await OpenFilex.open(filePath);
              if (result.type != ResultType.done && mounted) {
                // Fallback to browser if no PDF app
                await launchUrl(Uri.parse(url),
                    mode: LaunchMode.inAppBrowserView);
              }
            },
          ),
        ),
      );

      // Auto open
      final result = await OpenFilex.open(filePath);
      if (result.type != ResultType.done && mounted) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView);
      }

    } catch (e) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      debugPrint('[Download] Error: $e');

      if (!mounted) return;

      // ── Fallback: open in browser ─────────────────────────
      try {
        await launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView);
      } catch (_) {
        _snack('Could not open label. Try again.', isError: true);
      }
    }
  }

  Future<int> _getAndroidSdkInt() async {
    try {
      if (Platform.isAndroid) {
        final info = await DeviceInfoPlugin().androidInfo;
        return info.version.sdkInt;
      }
    } catch (_) {}
    return 0;
  }

  // ── Bottom Bar ────────────────────────────────────────────────
  Widget _buildBottomBar(ParcelProvider p) {
    final isLoading = p.isLoading || p.isLoadingRates;
    final btnLabel  = _step == 4 ? 'Proceed to Payment →' : 'Continue →';
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFEEEEEE)))),
      child: Row(children: [
        if (_step > 0) ...[
          Expanded(flex: 1, child: GestureDetector(onTap: () => setState(() => _step--),
              child: Container(height: 48,
                  decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFE0E0E0)), borderRadius: BorderRadius.circular(10)),
                  child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.arrow_back_ios, size: 14, color: Color(0xFF6B6B6B)), Text('Previous', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF6B6B6B)))])))),
          const SizedBox(width: 12),
        ],
        Expanded(flex: 2, child: SizedBox(height: 48,
            child: ElevatedButton(
              onPressed: isLoading ? null : _nextStep,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6D28D9), foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), textStyle: const TextStyle( fontSize: 15, fontWeight: FontWeight.w700)),
              child: isLoading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Text(btnLabel),
            ))),
      ]),
    );
  }

  InputDecoration _inputDec(String hint) => InputDecoration(
    hintText: hint, hintStyle: const TextStyle(color: Color(0xFFB0B0B0), fontSize: 13),
    filled: true, fillColor: Colors.white, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF6D28D9), width: 1.5)),
  );
}


class _PartnerLogo extends StatelessWidget {
  final String name, assetPath;
  final Color  color;
  const _PartnerLogo(this.name, this.assetPath, this.color);

  @override
  Widget build(BuildContext context) {
    final abbr = name.length > 3 ? name.substring(0, 3) : name;
    final fs   = abbr.length >= 3 ? 7.0 : 9.0;

    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 48, height: 32,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFEEEEEE)),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 4, offset: const Offset(0, 2))],
        ),
        padding: const EdgeInsets.all(4),
        child: Image.asset(
          assetPath,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Center(
            child: Text(abbr, style: TextStyle(
                fontSize: fs, fontWeight: FontWeight.w800, color: color)),
          ),
        ),
      ),
      const SizedBox(height: 4),
      Text(name, style: const TextStyle(
          fontSize: 9, fontWeight: FontWeight.w500, color: Color(0xFF6B6B6B))),
    ]);
  }
}
// ── Shared Widgets ────────────────────────────────────────────────

class _FieldCol extends StatelessWidget {
  final String label, hint;
  final TextEditingController ctrl;
  final TextInputType type;
  final String? Function(String?)? validator;
  final String? note;
  const _FieldCol({required this.label, required this.ctrl, required this.hint, this.type = TextInputType.text, this.validator, this.note});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF6B6B6B))),
    const SizedBox(height: 6),
    TextFormField(controller: ctrl, keyboardType: type, style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A1A)), validator: validator,
        decoration: InputDecoration(hintText: hint, hintStyle: const TextStyle(color: Color(0xFFB0B0B0), fontSize: 13), filled: true, fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF6D28D9), width: 1.5)),
            errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.red)))),
    if (note != null) ...[const SizedBox(height: 4), Text(note!, style: const TextStyle(fontSize: 11, color: Color(0xFF059669)))],
  ]);
}

class _PostcodeField extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final bool isValid;
  final void Function(String) onChanged;
  final String? Function(String?)? validator;
  const _PostcodeField({required this.label, required this.ctrl, required this.isValid, required this.onChanged, this.validator});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF6B6B6B))),
    const SizedBox(height: 6),
    TextFormField(controller: ctrl, textCapitalization: TextCapitalization.characters, style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A1A)), validator: validator, onChanged: onChanged,
        decoration: InputDecoration(hintText: 'e.g. SW1A 1AA', hintStyle: const TextStyle(color: Color(0xFFB0B0B0), fontSize: 14), filled: true, fillColor: Colors.white,
            suffixIcon: isValid ? const Icon(Icons.check_circle_rounded, color: Color(0xFF059669), size: 20) : null,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: isValid ? const Color(0xFF059669) : const Color(0xFFE0E0E0))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF6D28D9), width: 1.5)),
            errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.red)))),
  ]);
}

class _SortTab extends StatelessWidget {
  final String label; final bool selected; final VoidCallback onTap;
  const _SortTab({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(onTap: onTap,
      child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(color: selected ? const Color(0xFF6D28D9) : Colors.white, border: Border.all(color: selected ? const Color(0xFF6D28D9) : const Color(0xFFE0E0E0)), borderRadius: BorderRadius.circular(20)),
          child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: selected ? Colors.white : const Color(0xFF3A3A3A)))));
}

class _PriceRow extends StatelessWidget {
  final String label, value;
  const _PriceRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 8),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF6B6B6B))),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A))),
      ]));
}

class _AddressCard extends StatelessWidget {
  final String label, name, city, postcode, phone;
  const _AddressCard({required this.label, required this.name, required this.city, required this.postcode, required this.phone});
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFEEEEEE)), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF9B9B9B), letterSpacing: 0.8)),
        const SizedBox(height: 6),
        Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A))),
        Text('$city, $postcode', style: const TextStyle(fontSize: 11, color: Color(0xFF6B6B6B))),
        Text(phone, style: const TextStyle(fontSize: 11, color: Color(0xFF6B6B6B))),
      ]));
}

class _PartnerDot extends StatelessWidget {
  final String name; final Color color;
  const _PartnerDot(this.name, this.color);
  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 5),
    Text(name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Color(0xFF3A3A3A))),
  ]);
}

class _TrustBadge extends StatelessWidget {
  final String label;
  const _TrustBadge(this.label);
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFE0E0E0)), borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Color(0xFF3A3A3A))));
}

class _CardBadge extends StatelessWidget {
  final String label; final Color color;
  const _CardBadge(this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(4), border: Border.all(color: color.withOpacity(0.2))),
      child: Text(label, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: color, letterSpacing: 0.5)));
}

class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits  = newValue.text.replaceAll(RegExp(r'\s'), '');
    final limited = digits.length > 16 ? digits.substring(0, 16) : digits;
    final buf     = StringBuffer();
    for (int i = 0; i < limited.length; i++) { if (i > 0 && i % 4 == 0) buf.write('  '); buf.write(limited[i]); }
    final str = buf.toString();
    return TextEditingValue(text: str, selection: TextSelection.collapsed(offset: str.length));
  }
}

class _ExpiryFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll('/', '');
    String str   = digits;
    if (digits.length >= 2) str = '${digits.substring(0, 2)}/${digits.substring(2)}';
    return newValue.copyWith(text: str, selection: TextSelection.collapsed(offset: str.length));
  }
}

class _SendCarrierLogo extends StatelessWidget {
  final String carrier;
  final Color  color;
  const _SendCarrierLogo({required this.carrier, required this.color});

  static const _assets = <String, String>{
    'Royal Mail':                   'assets/carriers/royal_mail.png',
    'Parcelforce Royal Mail':       'assets/carriers/parcelforce.png',
    'Parcelforce':                  'assets/carriers/parcelforce.png',
    'Evri':                         'assets/carriers/evri.png',
    'Evri (Hermes)':                'assets/carriers/evri.png',
    'DPD UK':                       'assets/carriers/dpd.png',
    'DPD':                          'assets/carriers/dpd.png',
    'Yodel':                        'assets/carriers/yodel.png',
    'FedEx UK':                     'assets/carriers/fedex.png',
    'FedEx':                        'assets/carriers/fedex.png',
    'DHL Express MyDHL API':        'assets/carriers/dhl.png',
    'DHL Express':                  'assets/carriers/dhl.png',
    'DHL':                          'assets/carriers/dhl.png',
    'UPS':                          'assets/carriers/ups.png',
    'GlobalPost':                   'assets/carriers/globalpost.png',
    'Stamps.com':                   'assets/carriers/globalpost.png',
    'ShipStation Carrier Services': 'assets/carriers/globalpost.png',
  };

  static const _abbr = <String, String>{
    'Royal Mail':                   'RM',
    'Parcelforce Royal Mail':       'PF',
    'Parcelforce':                  'PF',
    'Evri':                         'EV',
    'Evri (Hermes)':                'EV',
    'DPD UK':                       'DPD',
    'DPD':                          'DPD',
    'Yodel':                        'YDL',
    'FedEx UK':                     'FedEx',
    'FedEx':                        'FedEx',
    'DHL Express MyDHL API':        'DHL',
    'DHL Express':                  'DHL',
    'DHL':                          'DHL',
    'UPS':                          'UPS',
    'GlobalPost':                   'GP',
    'Stamps.com':                   'STP',
    'ShipStation Carrier Services': 'SS',
    'InPost':                       'IN',
  };

  @override
  Widget build(BuildContext context) {
    final assetPath = _assets[carrier];
    final abbr      = _abbr[carrier]
        ?? carrier.substring(0, carrier.length > 2 ? 2 : carrier.length);
    final fs        = abbr.length >= 5 ? 7.0 : abbr.length == 4 ? 8.0 : 10.0;

    return Container(
      width: 38, height: 26,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      padding: const EdgeInsets.all(3),
      child: assetPath != null
          ? Image.asset(
        assetPath,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Center(
          child: Text(abbr, style: TextStyle(
              fontSize: fs, fontWeight: FontWeight.w800, color: color)),
        ),
      )
          : Center(
        child: Text(abbr, style: TextStyle(
            fontSize: fs, fontWeight: FontWeight.w800, color: color)),
      ),
    );
  }
}