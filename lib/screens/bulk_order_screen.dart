import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/auth_provider.dart';
import '../providers/profile_provider.dart';
import '../utilis/service_fee.dart';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_filex/open_filex.dart';

// =============================================================================
// MODELS
// =============================================================================


class BulkRate {
  final String rateId, carrier, service, carrierId, serviceCode;
  final double price;
  final int?   estimatedDays;
  const BulkRate({
    required this.rateId, required this.carrier, required this.service,
    required this.carrierId, required this.serviceCode, required this.price,
    this.estimatedDays,
  });
  Color get color {
    final c = carrier.toLowerCase();
    if (c.contains('royal'))  return const Color(0xFFE30613);
    if (c.contains('evri'))   return const Color(0xFF8B5CF6);
    if (c.contains('dpd'))    return const Color(0xFFE8001C);
    if (c.contains('yodel'))  return const Color(0xFF6D28D9);
    if (c.contains('parcel')) return const Color(0xFF003087);
    if (c.contains('fedex'))  return const Color(0xFF4D148C);
    if (c.contains('dhl'))    return const Color(0xFFFFC300);
    if (c.contains('ups'))    return const Color(0xFF351C15);
    return const Color(0xFF6B6B6B);
  }
  String get daysLabel {
    if (estimatedDays == null) return service;
    if (estimatedDays! <= 1)   return 'Next day';
    return '$estimatedDays–${estimatedDays! + 1} days';
  }
}

class BulkRow {
  final int rowNum;
  late TextEditingController nameCtrl;
  late TextEditingController phoneCtrl;
  late TextEditingController addressCtrl;
  late TextEditingController cityCtrl;
  late TextEditingController postcodeCtrl;
  String parcelSize;
  String parcelType;
  bool isExpanded = false;
  bool showRates = false;
  late TextEditingController weightCtrl;

  bool   postcodeValid = true;
  String postcodeError = '';

  List<BulkRate> rates        = [];
  int            selectedIdx  = 0;
  bool           loadingRates = false;
  String         rateError    = '';

  String status         = 'pending';
  String trackingNumber = '';
  String labelUrl       = '';
  String carrier        = '';
  String service        = '';
  double price          = 0;
  String errorMsg       = '';

  BulkRow({required this.rowNum, this.parcelSize = 'sm', this.parcelType = 'Other'}) {
    nameCtrl     = TextEditingController();
    phoneCtrl    = TextEditingController();
    addressCtrl  = TextEditingController();
    cityCtrl     = TextEditingController();
    postcodeCtrl = TextEditingController();
    weightCtrl   = TextEditingController(text: '1.0');
  }

  void dispose() {
    nameCtrl.dispose(); phoneCtrl.dispose(); addressCtrl.dispose();
    cityCtrl.dispose(); postcodeCtrl.dispose(); weightCtrl.dispose();
  }

  String get recipientName     => nameCtrl.text.trim();
  String get recipientPhone    => phoneCtrl.text.trim();
  String get recipientAddress  => addressCtrl.text.trim();
  String get recipientCity     => cityCtrl.text.trim();
  String get recipientPostcode => postcodeCtrl.text.trim().toUpperCase();
  double get weightKg          => double.tryParse(weightCtrl.text.trim()) ?? 1.0;

  void validatePostcode({String? senderPostcode}) {
    final pc = recipientPostcode;
    final clean = pc.replaceAll(' ', '');

    if (clean.isEmpty) {
      postcodeValid = false;
      postcodeError = 'Missing postcode';
      return;
    }

    final ok = RegExp(r'^[A-Z]{1,2}[0-9][A-Z0-9]?[0-9][A-Z]{2}$')
        .hasMatch(clean);

    if (!ok) {
      postcodeValid = false;
      postcodeError = 'Invalid UK postcode: $pc';
      return;
    }

    /// 🔥 NEW VALIDATION
    if (senderPostcode != null) {
      final senderClean =
      senderPostcode.replaceAll(' ', '').toUpperCase();

      if (senderClean == clean.toUpperCase()) {
        postcodeValid = false;
        postcodeError =
        'Sender and receiver postcode cannot be same';
        return;
      }
    }

    /// ✅ valid
    postcodeValid = true;
    postcodeError = '';

    postcodeCtrl.text =
    '${clean.substring(0, clean.length - 3)} ${clean.substring(clean.length - 3)}';
  }

  bool get hasError => status == 'failed';
  bool get isValid  =>
      recipientName.isNotEmpty && recipientAddress.isNotEmpty &&
          recipientCity.isNotEmpty && postcodeValid &&
          parcelSize.isNotEmpty && parcelType.isNotEmpty && weightKg > 0;

  String? get validationError {
    if (recipientName.isEmpty)    return 'Missing name';
    if (recipientAddress.isEmpty) return 'Missing address';
    if (recipientCity.isEmpty)    return 'Missing city';
    if (!postcodeValid)           return postcodeError;
    if (weightKg <= 0)            return 'Invalid weight';
    return null;
  }

  BulkRate? get selectedRate =>
      rates.isNotEmpty && selectedIdx < rates.length ? rates[selectedIdx] : null;
  bool get serviceUnavailable =>
      !loadingRates && rates.isEmpty && rateError.isNotEmpty;
}

// =============================================================================
// SCREEN
// =============================================================================

class BulkOrderScreen extends StatefulWidget {
  const BulkOrderScreen({super.key});
  @override State<BulkOrderScreen> createState() => _BulkOrderScreenState();
}

class _BulkOrderScreenState extends State<BulkOrderScreen> {
  int _step = 0;

  static const bool _useLivePayment = true;

  static const _anonKey       = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRqcmplZW1hYWN1bWVwaW1qbHRnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQxMjE2NjAsImV4cCI6MjA4OTY5NzY2MH0.gtBcFu-J48mPDk_S9ukfVdW-7gUmabGatmJ1g1_5zzo';
  static const _shipEngineUrl = 'https://tjrjeemaacumepimjltg.supabase.co/functions/v1/shipengine-courier';
  static const _emailUrl      = 'https://tjrjeemaacumepimjltg.supabase.co/functions/v1/send-label-email';

  final _supabase = Supabase.instance.client;

  final _sKey       = GlobalKey<FormState>();
  final _sNameCtrl  = TextEditingController();
  final _sPhoneCtrl = TextEditingController();
  final _sEmailCtrl = TextEditingController();
  final _sAddrCtrl  = TextEditingController();
  final _sCityCtrl  = TextEditingController();
  final _sDoorCtrl  = TextEditingController();
  final _sPcCtrl    = TextEditingController();
  final _batchCtrl  = TextEditingController();
  bool _sPcValid    = false;

  final _cardNumberCtrl = TextEditingController();
  final _expiryCtrl     = TextEditingController();
  final _cvcCtrl        = TextEditingController();

  List<String> _sSenderStreetList  = [];
  String?      _sSenderSelectedStreet;
  bool         _sSenderIsLookingUp  = false;
  bool         _sSenderPcValid      = false;
  String       _sSenderPcError      = '';
  Timer?       _sSenderDebounce;

  int _recipientCount = 1;

  List<BulkRow> _rows            = [];
  bool          _loadingAllRates = false;
  bool          _isProcessing    = false;
  int           _currentIdx      = 0;
  String?       _bulkOrderId;
  void _onSenderPostcodeChanged(String value) {
    _sSenderDebounce?.cancel();
    setState(() {
      _sSenderPcValid        = false;
      _sSenderPcError        = '';
      _sSenderStreetList     = [];
      _sSenderSelectedStreet = null;
      _sPcValid              = false;
      _sAddrCtrl.clear();
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
  // ── Single flag controlling the overlay ──────────────────────
  bool   _generatingLabels = false;

  bool   _paymentLoading   = false;
  bool   _paymentConfirmed = false;
  String _paymentIntentId  = '';
  String _paymentError     = '';
  bool   _sendingInvoice   = false;
  bool   _invoiceSent      = false;
  bool   _sendingLabels    = false;
  bool   _labelsSent       = false;

  // ── Computed ──────────────────────────────────────────────────
  int    get _successCount => _rows.where((r) => r.status == 'success').length;
  int    get _failedCount  => _rows.where((r) => r.status == 'failed').length;
  int    get _pendingCount => _rows.where((r) => r.status == 'pending').length;
  List<BulkRow> get _validRows   => _rows.where((r) => r.isValid).toList();
  List<BulkRow> get _invalidRows => _rows.where((r) => !r.isValid).toList();

  double get _totalSelected =>
      _validRows.fold(0.0, (s, r) =>
      s + (r.selectedRate?.price ?? 0) + ServiceFee.domestic(r.parcelSize));

  double get _totalPaid =>
      _rows.fold(0.0, (s, r) => s + (r.status == 'success' ? r.price : 0));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = context.read<ProfileProvider>();
      _testBulkInsert();
      if (p.fullName.isNotEmpty)     _sNameCtrl.text  = p.fullName;
      if (p.phone.isNotEmpty)        _sPhoneCtrl.text  = p.phone;
      if (p.addressLine1.isNotEmpty) _sAddrCtrl.text   = p.addressLine1;
      if (p.city.isNotEmpty)         _sCityCtrl.text   = p.city;
      if (p.postcode.isNotEmpty) {
        _sPcCtrl.text = p.postcode;
        _sPcValid = _validUkPc(p.postcode);
      }
      _sEmailCtrl.text = context.read<AuthProvider>().email;
    });
  }

  @override
  void dispose() {
    for (final c in [_sNameCtrl,_sPhoneCtrl,_sEmailCtrl,_sAddrCtrl,
      _sCityCtrl,_sPcCtrl,_batchCtrl,_cardNumberCtrl,_expiryCtrl,_cvcCtrl]) {
      c.dispose();
    }
    for (final r in _rows) r.dispose();
    super.dispose();
  }

  bool _validUkPc(String v) =>
      RegExp(r'^[A-Z]{1,2}[0-9][A-Z0-9]? ?[0-9][A-Z]{2}$',
          caseSensitive: false).hasMatch(v.trim());

  String _formatUkPc(String v) {
    final c = v.trim().toUpperCase().replaceAll(' ', '');
    if (c.length >= 5) return '${c.substring(0, c.length - 3)} ${c.substring(c.length - 3)}';
    return v.trim().toUpperCase();
  }

  void _createRows() {
    for (final r in _rows) r.dispose();
    _rows = List.generate(_recipientCount, (i) => BulkRow(rowNum: i + 1));
    setState(() => _step = 2);
  }

  Future<void> _validateAndConfirm() async {
    for (final r in _rows) r.validatePostcode();
    setState(() {});
    final valid     = _validRows.length;
    final invalid   = _invalidRows.length;
    final invalidPc = _rows.where((r) => !r.postcodeValid).length;
    if (valid == 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please fill in at least one complete row.'),
        backgroundColor: Colors.red, behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    final confirmed = await _showConfirmDialog(
        total: _rows.length, valid: valid, invalid: invalid, invalidPc: invalidPc);
    if (confirmed == true) _loadAllRates();
  }
  Future<void> _testBulkInsert() async {
    try {
      debugPrint('[TEST] Starting direct insert test...');
      final res = await _supabase.from('bulk_orders').insert({
        'user_email':      'srivishal600@gmail.com',
        'batch_name':      'TEST BATCH',
        'sender_name':     'Test Sender',
        'sender_phone':    '07700000000',
        'sender_email':    'srivishal600@gmail.com',
        'sender_address':  '1 Test Street',
        'sender_city':     'London',
        'sender_postcode': 'SW1A 1AA',
        'total_parcels':   1,
        'processed':       0,
        'failed':          0,
        'total_cost':      0.0,
        'status':          'processing',
      }).select('id').single();

      debugPrint('[TEST] ✓ SUCCESS! id=${res['id']}');
    } catch (e, stack) {
      debugPrint('[TEST] ✗ FAILED: $e');
      debugPrint('[TEST] ✗ TYPE: ${e.runtimeType}');
      debugPrint('[TEST] ✗ STACK: $stack');
    }
  }

  Future<bool?> _showConfirmDialog({
    required int total, required int valid,
    required int invalid, required int invalidPc,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxHeight: 520),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12),
                  blurRadius: 40, offset: const Offset(0, 10))]),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 60, height: 60,
                  decoration: BoxDecoration(color: const Color(0xFFFFF5EE),
                      borderRadius: BorderRadius.circular(16)),
                  child: const Icon(Icons.checklist_rounded,
                      color: Color(0xFFFF5A00), size: 30)),
              const SizedBox(height: 16),
              const Text('Are you sure?', style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
              const SizedBox(height: 6),
              const Text('Review your data before proceeding',
                  style: TextStyle(fontSize: 12, color: Color(0xFF9B9B9B))),
              const SizedBox(height: 20),
              Row(children: [
                _ConfirmStat('$total', 'Entered', const Color(0xFF6D28D9)),
                const SizedBox(width: 8),
                _ConfirmStat('$valid', 'Valid', const Color(0xFF059669)),
                const SizedBox(width: 8),
                _ConfirmStat('$invalid', 'Issues',
                    invalid > 0 ? Colors.red : const Color(0xFF9B9B9B)),
              ]),
              if (invalidPc > 0) ...[
                const SizedBox(height: 14),
                Container(padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.red.withOpacity(0.05),
                        border: Border.all(color: Colors.red.withOpacity(0.2)),
                        borderRadius: BorderRadius.circular(10)),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Icon(Icons.error_outline_rounded, color: Colors.red, size: 14),
                      const SizedBox(width: 8),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('$invalidPc invalid UK postcode${invalidPc > 1 ? "s" : ""} — these rows will be skipped.',
                            style: const TextStyle(fontSize: 12,
                                fontWeight: FontWeight.w600, color: Colors.red)),
                        const SizedBox(height: 4),
                        const Text('Go back to fix them, or tap Proceed to skip them.',
                            style: TextStyle(fontSize: 11, color: Color(0xFF9B9B9B))),
                      ])),
                    ])),
              ],
              if (invalid == 0) ...[
                const SizedBox(height: 12),
                Container(padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: const Color(0xFFF0FDF4),
                        border: Border.all(color: const Color(0xFFBBF7D0)),
                        borderRadius: BorderRadius.circular(10)),
                    child: const Row(children: [
                      Icon(Icons.check_circle_outline_rounded,
                          color: Color(0xFF059669), size: 14),
                      SizedBox(width: 6),
                      Text('All rows are valid — ready to get prices!',
                          style: TextStyle(fontSize: 12, color: Color(0xFF059669))),
                    ])),
              ],
              const SizedBox(height: 20),
              Row(children: [
                Expanded(child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF6B6B6B),
                      side: const BorderSide(color: Color(0xFFE0E0E0)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12)),
                  child: const Text('Go Back'),
                )),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton(
                  onPressed: valid > 0 ? () => Navigator.pop(context, true) : null,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF5A00),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      textStyle: const TextStyle(
                           fontWeight: FontWeight.w700)),
                  child: Text('Proceed ($valid rows)'),
                )),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  // ── Load rates ────────────────────────────────────────────────
  Future<void> _loadAllRates() async {
    setState(() { _loadingAllRates = true; _step = 3; });
    final valid = _validRows;
    for (int i = 0; i < valid.length; i += 5) {
      final batch = valid.sublist(i, (i + 5).clamp(0, valid.length));
      await Future.wait(batch.map(_loadRatesForRow));
      if (mounted) setState(() {});
    }
    setState(() => _loadingAllRates = false);
  }

  Future<void> _loadRatesForRow(BulkRow row) async {
    row.loadingRates = true; row.rateError = '';
    try {
      final res = await http.post(Uri.parse(_shipEngineUrl),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $_anonKey'},
        body: jsonEncode({
          'action': 'get_rates',
          'shipment': {
            'sender': {
              'name':     _sNameCtrl.text.trim(),
              'address':  _sAddrCtrl.text.trim(),
              'city':     _sCityCtrl.text.trim(),
              'postcode': _formatUkPc(_sPcCtrl.text),
              'phone':    _sPhoneCtrl.text.trim(),
              'email':    _sEmailCtrl.text.trim(),
            },
            'recipient': {
              'name':     row.recipientName,
              'address':  row.recipientAddress,
              'city':     row.recipientCity,
              'postcode': row.recipientPostcode,
              'phone':    row.recipientPhone.isNotEmpty
                  ? row.recipientPhone : '07700000000',
              'country':  'GB',
            },
            'parcel': {'size': row.parcelSize, 'weight_kg': row.weightKg},
          },
        }),
      ).timeout(const Duration(seconds: 30));
      final data = jsonDecode(res.body);
      debugPrint('[Bulk] get_rates row ${row.rowNum}: ${res.statusCode}');
      if (res.statusCode == 200 && data['success'] == true) {
        final rawRates = data['rates'] as List? ?? [];
        row.rates = rawRates.map((r) => BulkRate(
          rateId:        r['rateId']?.toString()      ?? '',
          carrier:       r['carrier']?.toString()     ?? 'Carrier',
          service:       r['service']?.toString()     ?? 'Standard',
          carrierId:     r['carrierId']?.toString()   ?? '',
          serviceCode:   r['serviceCode']?.toString() ?? '',
          price:         (r['price'] as num).toDouble(),
          estimatedDays: r['estimatedDays'] != null
              ? int.tryParse(r['estimatedDays'].toString()) : null,
        )).toList()..sort((a, b) => a.price.compareTo(b.price));
        row.selectedIdx = 0;
      } else {
        row.rateError = data['error']?.toString() ?? 'No services available';
      }
    } catch (e) {
      row.rateError = 'Network error — please retry';
      debugPrint('[Bulk] get_rates error row ${row.rowNum}: $e');
    }
    row.loadingRates = false;
  }

  // ── Payment ───────────────────────────────────────────────────
  // ✅ FIX: clean linear flow, no race conditions
  // Future<void> _processPayment() async {
  //   final num = _cardNumberCtrl.text.replaceAll(RegExp(r'\s'), '');
  //   final exp = _expiryCtrl.text;
  //   final cvc = _cvcCtrl.text.trim();
  //
  //   if (_useLivePayment) {
  //     // ── LIVE: validate card fields ──────────────────────────
  //     if (num.length < 16 || exp.length < 5 || cvc.length < 3) {
  //       setState(() => _paymentError = 'Please fill in all card details correctly.');
  //       return;
  //     }
  //   } else {
  //     // ── TEST: just check something is entered ───────────────
  //     if (num.isEmpty) {
  //       setState(() => _paymentError = 'Enter any test card number to continue.');
  //       return;
  //     }
  //   }
  //
  //   setState(() { _paymentLoading = true; _paymentError = ''; });
  //
  //   String intentId;
  //
  //   if (_useLivePayment) {
  //     // ── LIVE Stripe ───────────────────────────────────────
  //     final num2     = _cardNumberCtrl.text.replaceAll(RegExp(r'\s'), '');
  //     final parts    = _expiryCtrl.text.split('/');
  //     final expMonth = int.tryParse(parts[0].trim()) ?? 0;
  //     final expYear  = int.tryParse(parts[1].trim()) ?? 0;
  //     final fullYear = expYear < 100 ? 2000 + expYear : expYear;
  //     final amountPence = (_totalSelected * 100).round();
  //
  //     try {
  //       final tokenRes = await http.post(
  //         Uri.parse('https://api.stripe.com/v1/tokens'),
  //         headers: {
  //           'Authorization': 'Bearer $_stripeSecretKey',
  //           'Content-Type': 'application/x-www-form-urlencoded',
  //         },
  //         body: {
  //           'card[number]':    num2,
  //           'card[exp_month]': expMonth.toString(),
  //           'card[exp_year]':  fullYear.toString(),
  //           'card[cvc]':       _cvcCtrl.text.trim(),
  //         },
  //       ).timeout(const Duration(seconds: 15));
  //       if (tokenRes.statusCode != 200) {
  //         final err = jsonDecode(tokenRes.body);
  //         throw Exception(err['error']?['message'] ?? 'Card declined.');
  //       }
  //       final tokenId = jsonDecode(tokenRes.body)['id'] as String;
  //
  //       final piRes = await http.post(
  //         Uri.parse('https://api.stripe.com/v1/payment_intents'),
  //         headers: {
  //           'Authorization': 'Bearer $_stripeSecretKey',
  //           'Content-Type': 'application/x-www-form-urlencoded',
  //         },
  //         body: {
  //           'amount':                 amountPence.toString(),
  //           'currency':               'gbp',
  //           'payment_method_types[]': 'card',
  //           'description':            'SwiftLabel Bulk — ${_validRows.length} labels',
  //           'receipt_email':          _sEmailCtrl.text.trim(),
  //         },
  //       ).timeout(const Duration(seconds: 15));
  //       if (piRes.statusCode != 200) {
  //         final err = jsonDecode(piRes.body);
  //         throw Exception(err['error']?['message'] ?? 'Payment setup failed.');
  //       }
  //       intentId = jsonDecode(piRes.body)['id'] as String;
  //
  //       final pmRes = await http.post(
  //         Uri.parse('https://api.stripe.com/v1/payment_methods'),
  //         headers: {
  //           'Authorization': 'Bearer $_stripeSecretKey',
  //           'Content-Type': 'application/x-www-form-urlencoded',
  //         },
  //         body: {
  //           'type':                   'card',
  //           'card[token]':            tokenId,
  //           'billing_details[name]':  _sNameCtrl.text.trim(),
  //           'billing_details[email]': _sEmailCtrl.text.trim(),
  //         },
  //       ).timeout(const Duration(seconds: 15));
  //       if (pmRes.statusCode != 200) {
  //         final err = jsonDecode(pmRes.body);
  //         throw Exception(err['error']?['message'] ?? 'Card declined.');
  //       }
  //       final pmId = jsonDecode(pmRes.body)['id'] as String;
  //
  //       final confirmRes = await http.post(
  //         Uri.parse('https://api.stripe.com/v1/payment_intents/$intentId/confirm'),
  //         headers: {
  //           'Authorization': 'Bearer $_stripeSecretKey',
  //           'Content-Type': 'application/x-www-form-urlencoded',
  //         },
  //         body: {
  //           'payment_method': pmId,
  //           'return_url':     'https://swiftlabel.app/return',
  //         },
  //       ).timeout(const Duration(seconds: 15));
  //       final confirmData = jsonDecode(confirmRes.body);
  //       final status = confirmData['status'] as String? ?? '';
  //       if (confirmRes.statusCode != 200 ||
  //           (status != 'succeeded' && status != 'requires_action')) {
  //         throw Exception(
  //             confirmData['error']?['message'] ?? 'Payment failed: $status');
  //       }
  //     } catch (e) {
  //       final errMsg = e.toString().replaceAll('Exception: ', '');
  //       setState(() { _paymentLoading = false; _paymentError = errMsg; });
  //       await _showPaymentPopup(success: false, message: errMsg);
  //       await _sendPaymentFailedEmail(errMsg);
  //       return;
  //     }
  //   } else {
  //     // ── TEST mode ─────────────────────────────────────────
  //     await Future.delayed(const Duration(seconds: 1));
  //     intentId = 'pi_test_${DateTime.now().millisecondsSinceEpoch}';
  //   }
  //
  //   _paymentIntentId = intentId;
  //   setState(() { _paymentConfirmed = true; _paymentLoading = false; });
  //   await _showPaymentPopup(success: true);
  //
  //   setState(() => _generatingLabels = true);
  //   try {
  //     await _startProcessing();
  //   } catch (e) {
  //     debugPrint('❌ PROCESS ERROR => $e');
  //     await _sendLabelFailedEmail();
  //   } finally {
  //     if (mounted) setState(() => _generatingLabels = false);
  //   }
  // }
  Future<void> _processPayment() async {
    setState(() { _paymentLoading = true; _paymentError = ''; });

    try {
      // 1. Get client secret from Supabase edge function
      final res = await http.post(
        Uri.parse('https://tjrjeemaacumepimjltg.supabase.co/functions/v1/create-payment-intent'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_anonKey',
        },
        body: jsonEncode({
          'amount': (_totalSelected * 100).round(),
          'currency': 'gbp',
          'email': _sEmailCtrl.text.trim(),
          'description': 'SwiftLabel Bulk — ${_validRows.length} labels',
        }),
      ).timeout(const Duration(seconds: 15));

      final body = jsonDecode(res.body);
      debugPrint('[BulkPayment] Edge function response: $body');

      final clientSecret = body['clientSecret'] as String?;
      if (clientSecret == null || clientSecret.isEmpty) {
        throw Exception(body['error'] ?? 'Failed to create payment intent.');
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

      // 3. Present Stripe sheet
      await Stripe.instance.presentPaymentSheet();

      // 4. Payment succeeded
      _paymentIntentId = clientSecret.split('_secret')[0];
      setState(() { _paymentConfirmed = true; _paymentLoading = false; });

      await _showPaymentPopup(success: true);
      if (!mounted) return;

      // 5. Generate labels
      setState(() => _generatingLabels = true);
      try {
        await _startProcessing();
      } catch (e) {
        debugPrint('❌ PROCESS ERROR => $e');
        await _sendLabelFailedEmail();
      } finally {
        if (mounted) setState(() => _generatingLabels = false);
      }

    } on StripeException catch (e) {
      final msg = e.error.localizedMessage ?? 'Payment cancelled.';
      setState(() { _paymentError = msg; _paymentLoading = false; });
      if (e.error.code != FailureCode.Canceled) {
        await _showPaymentPopup(success: false, message: msg);
        await _sendPaymentFailedEmail(msg);
      }
    } catch (e) {
      final msg = e.toString().replaceAll('Exception: ', '');
      setState(() { _paymentError = msg; _paymentLoading = false; });
      await _showPaymentPopup(success: false, message: msg);
      await _sendPaymentFailedEmail(msg);
    }
  }

  // ✅ All processing in one clean async method — no setState conflicts
  Future<void> _runProcessingPipeline() async {
    final email = context.read<AuthProvider>().email;

    // ── STEP 1: Create bulk_orders record first ───────────────
    String? savedBulkOrderId;
    try {
      final batchName = _batchCtrl.text.trim().isNotEmpty
          ? _batchCtrl.text.trim()
          : 'Batch ${DateTime.now().day}/${DateTime.now().month}';

      final res = await _supabase.from('bulk_orders').insert({
        'user_email':      email,
        'batch_name':      batchName,
        'sender_name':     _sNameCtrl.text.trim(),
        'sender_phone':    _sPhoneCtrl.text.trim(),
        'sender_email':    _sEmailCtrl.text.trim(),
        'sender_address':  _sAddrCtrl.text.trim(),
        'sender_city':     _sCityCtrl.text.trim(),
        'sender_postcode': _formatUkPc(_sPcCtrl.text),
        'total_parcels':   _validRows.length,
        'processed':       0,
        'failed':          0,
        'total_cost':      0,
        'status':          'processing',
      }).select().single();

      savedBulkOrderId = res['id']?.toString();
      _bulkOrderId = savedBulkOrderId;
      debugPrint('[Bulk] ✓ bulk_order created id=$savedBulkOrderId');
    } catch (e) {
      debugPrint('[Bulk] ✗ bulk_order create failed: $e');
      // Continue even if this fails — labels are more important
    }

    // ── STEP 2: Process each label row ────────────────────────
    for (int i = 0; i < _validRows.length; i++) {
      if (!mounted) break;
      if (mounted) setState(() {
        _currentIdx = i;
        _validRows[i].status = 'processing';
      });
      await _processRow(_validRows[i], email, bulkOrderId: savedBulkOrderId);
      if (mounted) setState(() {});
      await Future.delayed(const Duration(milliseconds: 150));
    }

    // ── STEP 3: Update bulk_orders with final stats ────────────
    if (savedBulkOrderId != null) {
      try {
        final finalStatus = _failedCount == 0
            ? 'completed'
            : _successCount == 0 ? 'failed' : 'partial';
        await _supabase.from('bulk_orders').update({
          'processed':             _validRows.length,
          'failed':                _failedCount,
          'total_cost':            _totalPaid,
          'status':                finalStatus,
          'stripe_payment_intent': _paymentIntentId,
        }).eq('id', savedBulkOrderId);
        debugPrint('[Bulk] ✓ bulk_order updated → $finalStatus');
      } catch (e) {
        debugPrint('[Bulk] ✗ bulk_order update failed: $e');
      }
    }

    // ── STEP 4: Hide overlay, move to done screen ─────────────
    if (mounted) {
      setState(() {
        _isProcessing    = false;
        _generatingLabels = false;
        _step            = 6;    // ← THIS was the missing line
      });
    }

    // ── STEP 5: Send emails (after screen updates) ────────────
    if (_successCount > 0) await _sendAllLabelsEmail();
    await _sendInvoiceEmail();
  }

  // ── Process single row ────────────────────────────────────────
  Future<void> _processRow(BulkRow row, String userEmail, {String? bulkOrderId}) async {
    final rate = row.selectedRate;
    if (rate == null) {
      row.status   = 'failed';
      row.errorMsg = 'No courier selected';
      return;
    }
    try {
      debugPrint('[Bulk] create_label row ${row.rowNum} → ${row.recipientName}');
      final res = await http.post(Uri.parse(_shipEngineUrl),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $_anonKey'},
        body: jsonEncode({
          'action':      'create_label',
           'rateId':      rate.rateId,
          'carrier':     rate.carrier,
          'carrierId':   rate.carrierId,
          'serviceCode': rate.serviceCode,
          'shipment': {
            'sender': {
              'name':     _sNameCtrl.text.trim(),
              'address':  _sAddrCtrl.text.trim(),
              'city':     _sCityCtrl.text.trim(),
              'postcode': _formatUkPc(_sPcCtrl.text),
              'phone':    _sPhoneCtrl.text.trim(),
              'email':    _sEmailCtrl.text.trim(),
            },
            'recipient': {
              'name':     row.recipientName,
              'address':  row.recipientAddress,
              'city':     row.recipientCity,
              'postcode': row.recipientPostcode,
              'phone':    row.recipientPhone.isNotEmpty
                  ? row.recipientPhone : '07700000000',
              'country':  'GB',
            },
            'parcel': {'size': row.parcelSize, 'weight_kg': row.weightKg},
          },
        }),
      ).timeout(const Duration(seconds: 40));

      final data = jsonDecode(res.body);
      debugPrint('[Bulk] create_label row ${row.rowNum}: ${res.statusCode} → ${data['success']}');

      if (res.statusCode == 200 && data['success'] == true) {
        row.status         = 'success';
        row.trackingNumber = data['tracking_number']?.toString() ?? '';
        row.labelUrl       = data['label_url']?.toString()       ?? '';
        row.carrier        = data['carrier']?.toString()         ?? rate.carrier;
        row.service        = data['service']?.toString()         ?? rate.service;
        row.price = rate.price + ServiceFee.domestic(row.parcelSize);

        // ✅ Save to shipments with source='bulk' and bulk_order_id
        try {
          await _supabase.from('shipments').insert({
            'user_email':         userEmail,
            'tracking_number':    row.trackingNumber,
            'label_url':          row.labelUrl,
            'carrier':            row.carrier,
            'service':            row.service,
            'sender_name':        _sNameCtrl.text.trim(),
            'sender_address':     _sAddrCtrl.text.trim(),
            'sender_city':        _sCityCtrl.text.trim(),
            'sender_postcode':    _formatUkPc(_sPcCtrl.text),
            'recipient_name':     row.recipientName,
            'recipient_address':  row.recipientAddress,
            'recipient_city':     row.recipientCity,
            'recipient_postcode': row.recipientPostcode,
            'parcel_size':        row.parcelSize,
            'parcel_type':        row.parcelType,
            'weight_kg':          row.weightKg,
            'price':              row.price,
            'currency':           'GBP',
            'status':             'label_created',
            'source':             'bulk',              // ← keeps it out of single shipments tab
            'bulk_order_id':      _bulkOrderId,
          });
          debugPrint('[Bulk] ✓ shipment saved for ${row.recipientName}');
        } catch (e) {
          debugPrint('[Bulk] ✗ shipment insert failed: $e');
        }
      } else {
        final errMsg = data['error']?.toString() ?? data['message']?.toString() ?? 'Label creation failed';
        debugPrint('[Bulk] ✗ Row ${row.rowNum} failed: $errMsg');
        row.status   = 'failed';
        row.errorMsg = errMsg;
      }
    } catch (e) {
      row.status   = 'failed';
      row.errorMsg = e.toString().replaceAll('Exception: ', '');
      debugPrint('[Bulk] ✗ Row ${row.rowNum} exception: ${row.errorMsg}');
    }
  }

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
          decoration: BoxDecoration(color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15),
                  blurRadius: 40, offset: const Offset(0, 10))]),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 88, height: 88,
                decoration: BoxDecoration(shape: BoxShape.circle,
                    color: success
                        ? const Color(0xFF059669).withOpacity(0.1)
                        : Colors.red.withOpacity(0.1),
                    border: Border.all(
                        color: success
                            ? const Color(0xFF059669).withOpacity(0.3)
                            : Colors.red.withOpacity(0.3),
                        width: 4)),
                child: Icon(success ? Icons.check_circle_rounded : Icons.cancel_rounded,
                    size: 52,
                    color: success ? const Color(0xFF059669) : Colors.red)),
            const SizedBox(height: 20),
            Text(success ? 'Payment Successful!' : 'Payment Failed',
                style: TextStyle( fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: success ? const Color(0xFF059669) : Colors.red),
                textAlign: TextAlign.center),
            const SizedBox(height: 10),
            Text(success
                ? 'Payment of £${_totalSelected.toStringAsFixed(2)} confirmed.\nGenerating ${_validRows.length} labels now.'
                : (message ?? 'Something went wrong. Please try again.'),
                style: const TextStyle(fontSize: 14, color: Color(0xFF6B6B6B), height: 1.5),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            SizedBox(width: double.infinity, height: 48,
                child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: success ? const Color(0xFF059669) : Colors.red,
                        foregroundColor: Colors.white, elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        textStyle: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                    child: Text(success ? 'Continue →' : 'Try Again'))),
          ]),
        ),
      ),
    );
  }

  // ── Invoice email ─────────────────────────────────────────────
  Future<void> _sendInvoiceEmail() async {
    if (!mounted) return;
    setState(() => _sendingInvoice = true);
    try {
      final email       = _sEmailCtrl.text.trim();
      final batch       = _batchCtrl.text.trim().isNotEmpty
          ? _batchCtrl.text.trim()
          : 'Batch ${DateTime.now().day}/${DateTime.now().month}';
      final now         = DateTime.now();
      final successRows = _validRows.where((r) => r.status == 'success').toList();
      final failedRows  = _validRows.where((r) => r.status == 'failed').toList();

      final successItems = successRows.map((r) =>
      '<tr>'
          '<td style="padding:8px;font-size:13px">${r.recipientName}</td>'
          '<td style="padding:8px;font-size:12px;color:#6B6B6B">${r.recipientCity}</td>'
          '<td style="padding:8px;font-size:12px">${r.carrier}</td>'
          '<td style="padding:8px;font-size:13px;font-weight:bold;text-align:right">'
          '£${r.price.toStringAsFixed(2)}</td>'
          '</tr>').join('');

      final failedSection = failedRows.isNotEmpty
          ? '<div style="margin-top:16px;padding:14px;background:#FEF2F2;border:1px solid #FECACA;border-radius:10px">'
          '<p style="margin:0 0 8px;font-size:13px;font-weight:700;color:#DC2626">'
          '⚠ ${failedRows.length} label${failedRows.length > 1 ? "s" : ""} failed</p>'
          '${failedRows.map((r) =>
      '<div style="margin-bottom:6px;padding:8px;background:white;border-radius:6px;border:1px solid #FECACA">'
          '<p style="margin:0;font-size:12px;font-weight:600">${r.recipientName} · ${r.recipientCity}</p>'
          '<p style="margin:2px 0 0;font-size:11px;color:#DC2626">${r.errorMsg.isNotEmpty ? r.errorMsg : "Label generation failed"}</p>'
          '</div>').join('')}'
          '<p style="margin:10px 0 0;font-size:11px;color:#6B7280">You have not been charged for failed labels.</p>'
          '</div>'
          : '';

      final allSuccess = failedRows.isEmpty;
      final allFailed  = successRows.isEmpty;
      final statusBanner = allFailed
          ? '<div style="padding:14px;background:#FEF2F2;border:1px solid #FECACA;border-radius:10px;margin-bottom:16px">'
          '<p style="margin:0;font-size:14px;font-weight:700;color:#DC2626">✗ All labels failed — you have not been charged.</p></div>'
          : allSuccess
          ? '<div style="padding:14px;background:#F0FDF4;border:1px solid #BBF7D0;border-radius:10px;margin-bottom:16px">'
          '<p style="margin:0;font-size:14px;font-weight:700;color:#059669">✓ All ${successRows.length} labels generated successfully</p></div>'
          : '<div style="padding:14px;background:#FFFBEB;border:1px solid #FDE68A;border-radius:10px;margin-bottom:16px">'
          '<p style="margin:0;font-size:14px;font-weight:700;color:#D97706">⚠ ${successRows.length} of ${_validRows.length} labels generated</p>'
          '<p style="margin:4px 0 0;font-size:12px;color:#6B7280">${failedRows.length} failed — not charged for those.</p></div>';

      final html =
          '<div style="font-family:sans-serif;max-width:600px;margin:0 auto">'
          '<div style="background:linear-gradient(135deg,#FF7A2F,#FF5A00);padding:28px 32px;border-radius:12px 12px 0 0">'
          '<h1 style="margin:0;color:white;font-size:22px;font-weight:900">SwiftLabel</h1>'
          '<p style="margin:4px 0 0;color:rgba(255,255,255,0.85);font-size:14px">Bulk Invoice — $batch</p></div>'
          '<div style="background:white;padding:28px 32px;border:1px solid #EEE;border-radius:0 0 12px 12px">'
          '<p style="margin:0 0 4px;font-size:15px;font-weight:700">${_sNameCtrl.text.trim()}</p>'
          '<p style="margin:0 0 16px;font-size:13px;color:#6B6B6B">$email · ${now.day}/${now.month}/${now.year}</p>'
          '$statusBanner'
          '${successRows.isNotEmpty ? '<table style="width:100%;border-collapse:collapse;margin-bottom:8px">'
          '<tr style="background:#F9F9F9">'
          '<th style="padding:8px;text-align:left;font-size:11px;color:#9B9B9B">RECIPIENT</th>'
          '<th style="padding:8px;text-align:left;font-size:11px;color:#9B9B9B">CITY</th>'
          '<th style="padding:8px;text-align:left;font-size:11px;color:#9B9B9B">CARRIER</th>'
          '<th style="padding:8px;text-align:right;font-size:11px;color:#9B9B9B">CHARGED</th>'
          '</tr>$successItems</table>'
          '<div style="border-top:2px solid #EEE;margin-top:8px;padding-top:12px">'
         '</div>' : ''}'
          '$failedSection</div></div>';

      final subject = allFailed
          ? 'SwiftLabel — Bulk Order Failed · $batch'
          : allSuccess
          ? 'SwiftLabel Invoice — £${_totalPaid.toStringAsFixed(2)} · $batch'
          : 'SwiftLabel Invoice — £${_totalPaid.toStringAsFixed(2)} (${successRows.length}/${_validRows.length} labels) · $batch';

      await http.post(Uri.parse(_emailUrl),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $_anonKey'},
        body: jsonEncode({
          'email':          email,
          'subject':        subject,
          'htmlContent':    html,
          'trackingNumber': _paymentIntentId,
          'labelUrl':       '',
          'carrier':        'Invoice',
          'service':        '${successRows.length}/${_validRows.length} parcels',
          'recipientName':  _sNameCtrl.text.trim(),
          'recipientCity':  '',
        }),
      ).timeout(const Duration(seconds: 15));
      if (mounted) setState(() => _invoiceSent = true);
    } catch (e) {
      debugPrint('[Invoice] $e');
    }
    if (mounted) setState(() => _sendingInvoice = false);
  }
  Future<void> _startProcessing() async {
    final email = context.read<AuthProvider>().email.trim();
    setState(() { _step = 5; _isProcessing = true; _currentIdx = 0; });

    // ── Step 1: Create bulk_order record FIRST ────────────────────
    String? savedBulkOrderId;
    try {
      final batchName = _batchCtrl.text.trim().isNotEmpty
          ? _batchCtrl.text.trim()
          : 'Batch ${DateTime.now().day}/${DateTime.now().month}';

      debugPrint('[Bulk] Inserting bulk_order for $email');

      final res = await _supabase.from('bulk_orders').insert({
        'user_email':      email.toLowerCase(),
        'batch_name':      batchName,
        'sender_name':     _sNameCtrl.text.trim(),
        'sender_phone':    _sPhoneCtrl.text.trim(),
        'sender_email':    _sEmailCtrl.text.trim(),
        'sender_address':  _sAddrCtrl.text.trim(),
        'sender_city':     _sCityCtrl.text.trim(),
        'sender_postcode': _formatUkPc(_sPcCtrl.text),
        'total_parcels':   _validRows.length,
        'processed':       0,
        'failed':          0,
        'total_cost':      0.0,
        'status':          'processing',
      }).select('id').single();

      savedBulkOrderId = res['id']?.toString();
      _bulkOrderId     = savedBulkOrderId;
      debugPrint('[Bulk] ✓ Created bulk_order id=$savedBulkOrderId');
    } catch (e) {
      debugPrint('[Bulk] ✗ bulk_order insert failed: $e');
      // Continue anyway — labels must still process
    }

    // ── Step 2: Process each label row ───────────────────────────
    for (int i = 0; i < _validRows.length; i++) {
      if (!mounted) break;
      setState(() {
        _currentIdx = i;
        _validRows[i].status = 'processing';
      });
      await _processRow(_validRows[i], email, bulkOrderId: savedBulkOrderId);
      if (mounted) setState(() {});
      await Future.delayed(const Duration(milliseconds: 300));
    }

    // ── Step 3: Update bulk_order with final stats ────────────────
    if (savedBulkOrderId != null) {
      try {
        final finalStatus = _failedCount == 0
            ? 'completed'
            : _successCount == 0 ? 'failed' : 'partial';

        await _supabase.from('bulk_orders').update({
          'processed':             _validRows.length,
          'failed':                _failedCount,
          'total_cost':            _totalPaid,
          'status':                finalStatus,
          'stripe_payment_intent': _paymentIntentId,
        }).eq('id', savedBulkOrderId);

        debugPrint('[Bulk] ✓ Updated bulk_order → $finalStatus');
      } catch (e) {
        debugPrint('[Bulk] ✗ bulk_order update failed: $e');
      }
    }

    // ── Step 4: Navigate to done screen ──────────────────────────
    if (mounted) setState(() { _isProcessing = false; _step = 6; });

    // ── Step 5: Send emails ───────────────────────────────────────
    if (_successCount == 0 && _validRows.isNotEmpty) {
      await _sendLabelFailedEmail();
    } else {
      await _sendInvoiceEmail();
      if (_successCount > 0) await _sendAllLabelsEmail();
    }
  }

  Future<void> _sendAllLabelsEmail() async {
    if (!mounted) return;
    setState(() => _sendingLabels = true);
    try {
      final email = _sEmailCtrl.text.trim();
      final batch = _batchCtrl.text.trim().isNotEmpty
          ? _batchCtrl.text.trim() : 'Bulk Order';
      final done  = _validRows
          .where((r) => r.status == 'success' && r.labelUrl.isNotEmpty)
          .toList();
      if (done.isEmpty) { setState(() => _sendingLabels = false); return; }

      final cards = done.asMap().entries.map((e) {
        final i = e.key + 1; final r = e.value;
        return '<div style="margin-bottom:10px;padding:12px;border:1px solid #EEE;border-radius:8px">'
            '<p style="margin:0;font-size:14px;font-weight:700">$i. ${r.recipientName}</p>'
            '<p style="margin:0;font-size:12px;color:#6B6B6B">${r.carrier} · ${r.trackingNumber}</p>'
            '<a href="${r.labelUrl}" style="display:inline-block;margin-top:8px;background:#FF5A00;'
            'color:white;padding:8px 14px;border-radius:6px;text-decoration:none;'
            'font-size:12px;font-weight:600">Download Label</a></div>';
      }).join('');

      final html =
          '<div style="font-family:sans-serif;max-width:600px;margin:0 auto">'
          '<div style="background:linear-gradient(135deg,#FF7A2F,#FF5A00);padding:28px 32px;border-radius:12px 12px 0 0">'
          '<h1 style="margin:0;color:white;font-size:22px;font-weight:900">SwiftLabel</h1>'
          '<p style="margin:4px 0 0;color:rgba(255,255,255,.85);font-size:14px">Your Labels — $batch</p></div>'
          '<div style="background:white;padding:28px 32px;border:1px solid #EEE;border-radius:0 0 12px 12px">'
          '<div style="background:#F0FDF4;border:1px solid #BBF7D0;border-radius:8px;padding:12px;margin-bottom:16px">'
          '<p style="margin:0;font-size:14px;font-weight:700;color:#059669">✓ ${done.length} labels generated</p></div>'
          '$cards</div></div>';

      await http.post(Uri.parse(_emailUrl),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $_anonKey'},
        body: jsonEncode({
          'email':          email,
          'subject':        '📦 Your ${done.length} Labels — $batch',
          'htmlContent':    html,
          'trackingNumber': 'BULK',
          'labelUrl':       '',
          'carrier':        'Bulk',
          'service':        '${done.length} labels',
          'recipientName':  _sNameCtrl.text.trim(),
          'recipientCity':  '',
        }),
      ).timeout(const Duration(seconds: 20));
      if (mounted) setState(() => _labelsSent = true);
    } catch (e) {
      debugPrint('[Labels] $e');
    }
    if (mounted) setState(() => _sendingLabels = false);
  }

  Future<void> _sendLabelFailedEmail() async {
    if (!mounted) return;
    try {
      final email = _sEmailCtrl.text.trim();
      final batch = _batchCtrl.text.trim().isNotEmpty
          ? _batchCtrl.text.trim()
          : 'Batch ${DateTime.now().day}/${DateTime.now().month}';
      final now = DateTime.now();

      final html =
          '<div style="font-family:sans-serif;max-width:600px;margin:0 auto">'
          '<div style="background:linear-gradient(135deg,#FF7A2F,#FF5A00);padding:28px 32px;border-radius:12px 12px 0 0">'
          '<h1 style="margin:0;color:white;font-size:22px;font-weight:900">SwiftLabel</h1>'
          '<p style="margin:4px 0 0;color:rgba(255,255,255,0.85);font-size:14px">Label Generation Issue — $batch</p></div>'
          '<div style="background:white;padding:28px 32px;border:1px solid #EEE;border-radius:0 0 12px 12px">'
          '<div style="padding:16px;background:#FEF2F2;border:1px solid #FECACA;border-radius:10px;margin-bottom:20px">'
          '<p style="margin:0;font-size:15px;font-weight:700;color:#DC2626">⚠️ Label Generation Failed</p>'
          '<p style="margin:6px 0 0;font-size:13px;color:#6B7280">Your payment was received but we could not generate your shipping labels.</p></div>'
          '<p style="font-size:14px;color:#1A1A1A;margin:0 0 6px"><strong>Order:</strong> $batch</p>'
          '<p style="font-size:14px;color:#1A1A1A;margin:0 0 6px"><strong>Date:</strong> ${now.day}/${now.month}/${now.year}</p>'
          '<p style="font-size:14px;color:#1A1A1A;margin:0 0 20px"><strong>Amount charged:</strong> £${_totalSelected.toStringAsFixed(2)}</p>'
          '<div style="padding:16px;background:#F0FDF4;border:1px solid #BBF7D0;border-radius:10px;margin-bottom:20px">'
          '<p style="margin:0;font-size:14px;font-weight:700;color:#059669">💚 Full Refund Guaranteed</p>'
          '<p style="margin:6px 0 0;font-size:13px;color:#374151">Your payment of <strong>£${_totalSelected.toStringAsFixed(2)}</strong> will be fully refunded to your original payment method within <strong>3 business days</strong>.</p>'
          '</div>'
          '<p style="font-size:13px;color:#6B7280;margin:0 0 6px">If you have any questions, please reply to this email or contact our support team.</p>'
          '<p style="font-size:13px;color:#6B7280;margin:0">We apologise for the inconvenience.</p>'
          '<div style="margin-top:24px;padding-top:16px;border-top:1px solid #EEE">'
          '<p style="margin:0;font-size:11px;color:#9B9B9B">SwiftLabel · Automated notification · ${now.day}/${now.month}/${now.year}</p>'
          '</div></div></div>';

      await http.post(Uri.parse(_emailUrl),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $_anonKey'},
        body: jsonEncode({
          'email':          email,
          'subject':        '⚠️ Label Generation Failed — Refund Incoming · $batch',
          'htmlContent':    html,
          'trackingNumber': _paymentIntentId,
          'labelUrl':       '',
          'carrier':        'Refund Notice',
          'service':        'Label generation failed',
          'recipientName':  _sNameCtrl.text.trim(),
          'recipientCity':  '',
        }),
      ).timeout(const Duration(seconds: 15));
      debugPrint('[Email] ✓ label-failed email sent');
    } catch (e) {
      debugPrint('[Email] ✗ label-failed email error: $e');
    }
  }

  Future<void> _sendPaymentFailedEmail(String reason) async {
    try {
      final email = _sEmailCtrl.text.trim();
      if (email.isEmpty) return;
      final batch = _batchCtrl.text.trim().isNotEmpty
          ? _batchCtrl.text.trim()
          : 'Batch ${DateTime.now().day}/${DateTime.now().month}';
      final now = DateTime.now();

      final html =
          '<div style="font-family:sans-serif;max-width:600px;margin:0 auto">'
          '<div style="background:linear-gradient(135deg,#FF7A2F,#FF5A00);padding:28px 32px;border-radius:12px 12px 0 0">'
          '<h1 style="margin:0;color:white;font-size:22px;font-weight:900">SwiftLabel</h1>'
          '<p style="margin:4px 0 0;color:rgba(255,255,255,0.85);font-size:14px">Payment Failed — $batch</p></div>'
          '<div style="background:white;padding:28px 32px;border:1px solid #EEE;border-radius:0 0 12px 12px">'
          '<div style="padding:16px;background:#FEF2F2;border:1px solid #FECACA;border-radius:10px;margin-bottom:20px">'
          '<p style="margin:0;font-size:15px;font-weight:700;color:#DC2626">❌ Payment Unsuccessful</p>'
          '<p style="margin:6px 0 0;font-size:13px;color:#6B7280">Your payment could not be processed. No charges have been made to your account.</p></div>'
          '<p style="font-size:14px;color:#1A1A1A;margin:0 0 6px"><strong>Order:</strong> $batch</p>'
          '<p style="font-size:14px;color:#1A1A1A;margin:0 0 6px"><strong>Date:</strong> ${now.day}/${now.month}/${now.year}</p>'
          '<p style="font-size:14px;color:#1A1A1A;margin:0 0 6px"><strong>Amount:</strong> £${_totalSelected.toStringAsFixed(2)}</p>'
          '<p style="font-size:14px;color:#DC2626;margin:0 0 20px"><strong>Reason:</strong> $reason</p>'
          '<div style="padding:16px;background:#FFFBEB;border:1px solid #FDE68A;border-radius:10px;margin-bottom:20px">'
          '<p style="margin:0;font-size:14px;font-weight:700;color:#D97706">💳 What to do next</p>'
          '<ul style="margin:8px 0 0;padding-left:18px;font-size:13px;color:#374151">'
          '<li style="margin-bottom:4px">Check your card details are correct</li>'
          '<li style="margin-bottom:4px">Ensure your card has sufficient funds</li>'
          '<li style="margin-bottom:4px">Try a different payment method</li>'
          '<li>Contact your bank if the issue persists</li>'
          '</ul></div>'
          '<p style="font-size:13px;color:#6B7280;margin:0">Your labels have not been created. Return to the app to retry your payment.</p>'
          '<div style="margin-top:24px;padding-top:16px;border-top:1px solid #EEE">'
          '<p style="margin:0;font-size:11px;color:#9B9B9B">SwiftLabel · Automated notification · ${now.day}/${now.month}/${now.year}</p>'
          '</div></div></div>';

      await http.post(Uri.parse(_emailUrl),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $_anonKey'},
        body: jsonEncode({
          'email':          email,
          'subject':        '❌ Payment Failed — £${_totalSelected.toStringAsFixed(2)} · $batch',
          'htmlContent':    html,
          'trackingNumber': 'PAYMENT_FAILED',
          'labelUrl':       '',
          'carrier':        'Payment Notice',
          'service':        'Payment failed',
          'recipientName':  _sNameCtrl.text.trim(),
          'recipientCity':  '',
        }),
      ).timeout(const Duration(seconds: 15));
      debugPrint('[Email] ✓ payment-failed email sent');
    } catch (e) {
      debugPrint('[Email] ✗ payment-failed email error: $e');
    }
  }

  // ==========================================================================
  // BUILD
  // ==========================================================================
  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Scaffold(
        backgroundColor: const Color(0xFFFAF9F7),
        body: SafeArea(child: Column(children: [
          _buildNav(),
          _buildStepIndicator(),
          Expanded(child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (_step == 0) _buildStep0(),
              if (_step == 1) _buildStep1CountPicker(),
              if (_step == 2) _buildStep2DataEntry(),
              if (_step == 3) _buildStep3Courier(),
              if (_step == 4) _buildStep4Payment(),
              if (_step == 5) _buildStep5Processing(),
              if (_step == 6) _buildStep6Done(),
              const SizedBox(height: 40),
            ]),
          )),
          if (_step < 5) _buildBottomBar(),
        ])),
      ),
      // ✅ Overlay — only shows while _generatingLabels is true
      if (_generatingLabels)
        Positioned.fill(
          child: Material(
            color: Colors.transparent,
            child: Container(
              color: Colors.black.withOpacity(0.8),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(
                  width: 160, height: 160,
                  decoration: BoxDecoration(color: Colors.white,
                      borderRadius: BorderRadius.circular(24)),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const SizedBox(width: 48, height: 48,
                        child: CircularProgressIndicator(
                            color: Color(0xFFFF5A00), strokeWidth: 3.5)),
                    const SizedBox(height: 14),
                    const Text('Generating\nlabels...', textAlign: TextAlign.center,
                        style: TextStyle( fontSize: 14,
                            fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
                    const SizedBox(height: 6),
                    Text(
                      '${_successCount + _failedCount} / ${_validRows.length}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF9B9B9B)),
                    ),
                  ]),
                ),
                const SizedBox(height: 20),
                Text('Processing ${_validRows.length} parcels...',
                    style: const TextStyle(fontSize: 13, color: Colors.white70)),
                const SizedBox(height: 6),
                const Text('Please do not close the app',
                    style: TextStyle(fontSize: 12, color: Colors.white38)),
              ]),
            ),
          ),
        ),
    ]);
  }

  Widget _buildNav() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    decoration: const BoxDecoration(color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE)))),
    child: Row(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.asset('assets/images/logo.png', width: 30, height: 30,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: 30, height: 30,
              decoration: BoxDecoration(color: const Color(0xFFFF5A00),
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.inventory_2_outlined,
                  color: Colors.white, size: 16),
            )),
      ),
      const SizedBox(width: 8),
      const Text('SwiftLabel', style: TextStyle(fontFamily: 'Syne', fontSize: 17,
          fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
      const Spacer(),
      GestureDetector(
        onTap: () => Navigator.pop(context),
        child: const Row(children: [
          Icon(Icons.arrow_back_ios, size: 14, color: Color(0xFF6B6B6B)),
          Text('Back to Dashboard', style: TextStyle(fontSize: 13, color: Color(0xFF6B6B6B))),
        ]),
      ),
    ]),
  );

  Widget _buildStepIndicator() {
    const steps = ['Sender','Count','Fill Data','Courier','Pay','Labels','Done'];
    return Container(color: Colors.white, padding: const EdgeInsets.fromLTRB(10,10,10,14),
      child: Row(children: List.generate(steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          final idx = i ~/ 2;
          return Expanded(child: Container(height: 2,
              color: idx < _step ? const Color(0xFFFF5A00) : const Color(0xFFEEEEEE)));
        }
        final idx = i ~/ 2; final done = idx < _step; final cur = idx == _step;
        return Column(children: [
          Container(width: 22, height: 22,
              decoration: BoxDecoration(shape: BoxShape.circle,
                  color: done ? const Color(0xFFFF5A00)
                      : cur ? const Color(0xFFFFF5EE) : const Color(0xFFF5F5F5),
                  border: Border.all(
                      color: (done || cur) ? const Color(0xFFFF5A00)
                          : const Color(0xFFE0E0E0), width: 1.5)),
              child: Center(child: done
                  ? const Icon(Icons.check, size: 12, color: Colors.white)
                  : Text('${idx + 1}', style: TextStyle(fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: cur ? const Color(0xFFFF5A00) : const Color(0xFF9B9B9B))))),
          const SizedBox(height: 3),
          Text(steps[idx], style: TextStyle(fontSize: 7,
              fontWeight: cur ? FontWeight.w600 : FontWeight.w400,
              color: (done || cur) ? const Color(0xFFFF5A00) : const Color(0xFF9B9B9B))),
        ]);
      })),
    );
  }

  Widget _buildStep0() => Form(
    key: _sKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        /// 🔹 Header
        _header('Sender Details', 'These details appear on all labels'),
        const SizedBox(height: 20),

        /// 🔹 Batch Name (ONLY EXTRA FIELD)
        _FieldCol(
          label: 'Batch Name (optional)',
          ctrl: _batchCtrl,
          hint: 'e.g. April Orders',
        ),

        const SizedBox(height: 16),

        /// 🔹 Name + Phone (MATCH SEND PARCEL UI)
        Row(
          children: [
            Expanded(
              child: _FieldCol(
                label: 'Full Name *',
                ctrl: _sNameCtrl,
                hint: 'Jane Smith',
                validator: _req,
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
                      /// +44 BOX (SMALL — SAME AS SEND PARCEL)
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
                          ),
                        ),
                      ),

                      const SizedBox(width: 8),

                      /// PHONE INPUT
                      Expanded(
                        child: TextFormField(
                          controller: _sPhoneCtrl,
                          keyboardType: TextInputType.phone,
                          style: const TextStyle(fontSize: 14),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return null;
                            final digits = v.replaceAll(RegExp(r'\D'), '');
                            if (digits.length < 10) return '(min 10 digits)';
                            if (digits.length > 11) return '(max 11 digits)';
                            return null;
                          },
                          decoration: InputDecoration(
                            hintText: '7700 900000',
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 13),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
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

        /// 🔹 Email
        _FieldCol(
          label: 'Email *',
          ctrl: _sEmailCtrl,
          hint: 'you@example.com',
          validator: _req,
        ),

        const SizedBox(height: 12),

        /// 🔹 POSTCODE (MATCH SEND PARCEL)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Postcode *',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),

            TextFormField(
              controller: _sPcCtrl,
              textCapitalization: TextCapitalization.characters,
              onChanged: _onSenderPostcodeChanged,
              validator: (v) {
                if (v?.isEmpty ?? true) return 'Required';
                if (!_validUkPc(v!)) return 'Invalid postcode';
                return null;
              },
              decoration: InputDecoration(
                hintText: 'SW1A 1AA',
                filled: true,
                fillColor: Colors.white,
                suffixIcon: _sSenderIsLookingUp
                    ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
                    : _sSenderPcValid
                    ? const Icon(Icons.check_circle,
                    color: Colors.green, size: 18)
                    : null,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),

            if (_sSenderPcError.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_sSenderPcError,
                    style: const TextStyle(color: Colors.red, fontSize: 11)),
              ),
          ],
        ),

        const SizedBox(height: 12),

        /// 🔹 STREET (DROPDOWN OR INPUT)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Street *',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),

            _sSenderStreetList.isNotEmpty
                ? DropdownButtonFormField<String>(
              value: _sSenderSelectedStreet,
              items: _sSenderStreetList
                  .map((e) => DropdownMenuItem(
                value: e,
                child: Text(e),
              ))
                  .toList(),
              onChanged: (v) {
                setState(() {
                  _sSenderSelectedStreet = v;
                  _sAddrCtrl.text = v ?? '';
                });
              },
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            )
                : _FieldCol(
              label: '',
              ctrl: _sAddrCtrl,
              hint: 'Baker Street',
              validator: _req,
            ),
          ],
        ),

        const SizedBox(height: 12),

        /// 🔹 DOOR + CITY
        Row(
          children: [
            Expanded(
              child: _FieldCol(
                label: 'Door / No. *',
                ctrl: _sDoorCtrl,
                hint: '12A',
                validator: _req,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _FieldCol(
                label: 'City *',
                ctrl: _sCityCtrl,
                hint: 'London',
                validator: _req,
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _buildStep1CountPicker() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _header('How many recipients?', 'UK domestic parcels only'),
        const SizedBox(height: 24),
        Center(child: Column(children: [
          Container(width: 120, height: 120,
              decoration: BoxDecoration(color: const Color(0xFFFFF5EE),
                  border: Border.all(color: const Color(0xFFFF5A00).withOpacity(0.3), width: 2),
                  borderRadius: BorderRadius.circular(24)),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('$_recipientCount', style: const TextStyle(
                    fontSize: 48, fontWeight: FontWeight.w800, color: Color(0xFFFF5A00))),
                const Text('recipients', style: TextStyle(fontSize: 12, color: Color(0xFF9B9B9B))),
              ])),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            GestureDetector(
              onTap: () { if (_recipientCount > 1) setState(() => _recipientCount--); },
              child: Container(width: 52, height: 52,
                  decoration: BoxDecoration(
                      color: _recipientCount > 1 ? const Color(0xFFFFF5EE) : const Color(0xFFF5F5F5),
                      border: Border.all(
                          color: _recipientCount > 1 ? const Color(0xFFFF5A00) : const Color(0xFFE0E0E0),
                          width: 1.5),
                      borderRadius: BorderRadius.circular(14)),
                  child: Icon(Icons.remove_rounded, size: 24,
                      color: _recipientCount > 1 ? const Color(0xFFFF5A00) : const Color(0xFFCCCCCC))),
            ),
            const SizedBox(width: 20),
            GestureDetector(
              onTap: () { if (_recipientCount < 100) setState(() => _recipientCount++); },
              child: Container(width: 52, height: 52,
                  decoration: BoxDecoration(color: const Color(0xFFFF5A00),
                      borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.add_rounded, size: 24, color: Colors.white)),
            ),
          ]),
          const SizedBox(height: 20),
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center,
            children: [5, 10, 20, 50].map((n) => GestureDetector(
              onTap: () => setState(() => _recipientCount = n),
              child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                      color: _recipientCount == n ? const Color(0xFFFF5A00) : Colors.white,
                      border: Border.all(color: _recipientCount == n
                          ? const Color(0xFFFF5A00) : const Color(0xFFE0E0E0)),
                      borderRadius: BorderRadius.circular(20)),
                  child: Text('$n', style: TextStyle(fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _recipientCount == n ? Colors.white : const Color(0xFF3A3A3A)))),
            )).toList(),
          ),
        ])),
        const SizedBox(height: 28),
        Container(padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFFF0FDF4),
                border: Border.all(color: const Color(0xFFBBF7D0)),
                borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.info_outline_rounded, size: 14, color: Color(0xFF059669)),
                SizedBox(width: 6),
                Text('What you\'ll fill in for each recipient:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF059669))),
              ]),
              const SizedBox(height: 8),
              ...['Name (required)', 'Phone (optional)', 'Street address (required)',
                'City (required)', 'UK Postcode (required)', 'Parcel size · type · weight'].map((t) =>
                  Padding(padding: const EdgeInsets.only(bottom: 4),
                      child: Row(children: [
                        Container(width: 4, height: 4,
                            margin: const EdgeInsets.only(right: 8, top: 1),
                            decoration: const BoxDecoration(color: Color(0xFF059669), shape: BoxShape.circle)),
                        Text(t, style: const TextStyle(fontSize: 11, color: Color(0xFF3A3A3A))),
                      ]))),
            ])),
      ]);

  Widget _buildStep2DataEntry() {
    final filledCount = _rows.where((r) => r.recipientName.isNotEmpty).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _header('Enter Recipient Data', 'Fill in details for each parcel'),
      Text('$filledCount of ${_rows.length} filled',
          style: const TextStyle(fontSize: 12, color: Color(0xFF9B9B9B))),
      const SizedBox(height: 6),
      GestureDetector(
        onTap: () => setState(() { for (final r in _rows) r.dispose(); _rows = []; _step = 1; }),
        child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: const Color(0xFFFFF5EE), borderRadius: BorderRadius.circular(8)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.edit_rounded, size: 13, color: Color(0xFFFF5A00)),
              SizedBox(width: 4),
              Text('Change count', style: TextStyle(fontSize: 12, color: Color(0xFFFF5A00), fontWeight: FontWeight.w600)),
            ])),
      ),
      const SizedBox(height: 16),
      Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(8)),
          child: const Row(children: [
            SizedBox(width: 28, child: Text('#', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF9B9B9B)))),
            Expanded(flex: 3, child: Text('Name *', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF9B9B9B)))),
            SizedBox(width: 8),
            Expanded(flex: 3, child: Text('Address *', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF9B9B9B)))),
            SizedBox(width: 8),
            Expanded(flex: 2, child: Text('City *', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF9B9B9B)))),
            SizedBox(width: 8),
            Expanded(flex: 2, child: Text('Postcode *', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF9B9B9B)))),
          ])),
      const SizedBox(height: 8),
      ..._rows.map((row) => _DataEntryRow(row: row, onChanged: () => setState(() {}))),
      const SizedBox(height: 16),
      Container(padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFFFF5EE),
              border: Border.all(color: const Color(0xFFFFDDCC)),
              borderRadius: BorderRadius.circular(10)),
          child: const Row(children: [
            Icon(Icons.inventory_2_outlined, size: 14, color: Color(0xFFFF5A00)),
            SizedBox(width: 8),
            Expanded(child: Text('All parcels use Small size · 1kg by default. Tap a row to change size & weight.',
                style: TextStyle(fontSize: 11, color: Color(0xFFFF5A00)))),
          ])),
    ]);
  }

  Widget _buildStep3Courier() {
    final valid     = _validRows;
    final allLoaded = valid.every((r) => !r.loadingRates);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _header('Choose Courier', 'Select a courier for each parcel'),
      const SizedBox(height: 8),
      if (_loadingAllRates) ...[
        const SizedBox(height: 4),
        Row(children: [
          const SizedBox(width: 12, height: 12,
              child: CircularProgressIndicator(color: Color(0xFFFF5A00), strokeWidth: 2)),
          const SizedBox(width: 8),
          Text('Loading rates for ${valid.where((r) => r.loadingRates).length} parcels...',
              style: const TextStyle(fontSize: 12, color: Color(0xFF9B9B9B))),
        ]),
        const SizedBox(height: 12),
      ],
      if (allLoaded && !_loadingAllRates && valid.any((r) => r.rates.isNotEmpty)) ...[
        Row(children: [
          _QuickBtn('⚡ Cheapest for all', () => setState(() {
            for (final r in valid) { if (r.rates.isNotEmpty) r.selectedIdx = 0; }
          })),
          const SizedBox(width: 8),
          _QuickBtn('🚀 Fastest for all', () => setState(() {
            for (final r in valid) {
              if (r.rates.isEmpty) continue;
              int best = 0; int bestDays = r.rates[0].estimatedDays ?? 99;
              for (int i = 1; i < r.rates.length; i++) {
                final d = r.rates[i].estimatedDays ?? 99;
                if (d < bestDays) { bestDays = d; best = i; }
              }
              r.selectedIdx = best;
            }
          })),
        ]),
        const SizedBox(height: 16),
      ],
      ...valid.map((row) => _CourierCard(
        row: row,

        onSelect: (idx) {
          setState(() {
            row.selectedIdx = idx;

            /// 🔥 THIS LINE DOES THE MAGIC
            row.showRates = false;
          });
        },

        onRetry: () {
          _loadRatesForRow(row).then((_) => setState(() {}));
        },

        onToggle: () {
          setState(() {
            row.showRates = !row.showRates;
          });
        },
      )),
      if (allLoaded && valid.any((r) => r.selectedRate != null)) ...[
        const SizedBox(height: 16),
        Container(padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFFFFF5EE),
                border: Border.all(color: const Color(0xFFFFDDCC)),
                borderRadius: BorderRadius.circular(12)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Order Total', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
            Text('${valid.where((r) => r.selectedRate != null).length} parcels · fee varies by size',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF9B9B9B))),
              ]),
              Text('£${_totalSelected.toStringAsFixed(2)}',
                  style: const TextStyle( fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFFFF5A00))),
            ])),
      ],
    ]);
  }

  // Widget _buildStep4Payment() =>
  //     Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
  //       Container(
  //         width: double.infinity,
  //         decoration: BoxDecoration(color: const Color(0xFF6D28D9), borderRadius: BorderRadius.circular(16)),
  //         child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
  //           Container(
  //             padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
  //             decoration: BoxDecoration(
  //               color: Colors.white.withOpacity(0.08),
  //               borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
  //               border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.15))),
  //             ),
  //             child: Row(children: [
  //               Icon(Icons.inventory_2_outlined, size: 13, color: Colors.white.withOpacity(0.6)),
  //               const SizedBox(width: 6),
  //               Text('Bulk order summary', style: TextStyle(fontSize: 11, letterSpacing: 0.6,
  //                   fontWeight: FontWeight.w500, color: Colors.white.withOpacity(0.6))),
  //             ]),
  //           ),
  //           Padding(
  //             padding: const EdgeInsets.all(16),
  //             child: Column(children: [
  //               Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
  //                 Container(width: 40, height: 40,
  //                     decoration: BoxDecoration(color: Colors.white.withOpacity(0.15),
  //                         borderRadius: BorderRadius.circular(10)),
  //                     child: Icon(Icons.inventory_2_outlined, color: Colors.white.withOpacity(0.9), size: 20)),
  //                 const SizedBox(width: 12),
  //                 Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
  //                   Text('${_validRows.length} Parcel Labels',
  //                       style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
  //                   const SizedBox(height: 2),
  //                   Text('Incl. service fee (varies by size)',
  //                       style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.65))),
  //                 ])),
  //               ]),
  //               // Replace the existing test mode hint container with:
  //               if (!_useLivePayment)
  //                 Container(
  //                   padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
  //                   decoration: BoxDecoration(
  //                       color: const Color(0xFFF3F0FF),
  //                       borderRadius: BorderRadius.circular(10),
  //                       border: Border.all(color: const Color(0xFFDDD6FE))),
  //                   child: const Row(children: [
  //                     Icon(Icons.science_outlined, size: 15, color: Color(0xFF6D28D9)),
  //                     SizedBox(width: 8),
  //                     Expanded(child: Text(
  //                       'Test mode  ·  Use any card number  ·  Payment always succeeds',
  //                       style: TextStyle(fontSize: 11, color: Color(0xFF6D28D9), height: 1.4),
  //                     )),
  //                   ]),
  //                 ),
  //               const SizedBox(height: 14),
  //               Container(
  //                 padding: const EdgeInsets.only(top: 14),
  //                 decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.white.withOpacity(0.15)))),
  //                 child: Row(children: [
  //                   Expanded(child: Column(children: [
  //                     Text('Labels', style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.55))),
  //                     const SizedBox(height: 4),
  //                     Text('${_validRows.length}', style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.85))),
  //                   ])),
  //                   Container(width: 0.5, height: 28, color: Colors.white.withOpacity(0.2)),
  //                   Expanded(child: Column(children: [
  //                     Text('Service fee (varies by size)', style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.55))),
  //                     const SizedBox(height: 4),
  //                     Text('£${(_totalSelected - _validRows.fold(0.0, (s, r) => s + (r.selectedRate?.price ?? 0))).toStringAsFixed(2)}',
  //                         style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.85))),
  //                   ])),
  //                   Container(width: 0.5, height: 28, color: Colors.white.withOpacity(0.2)),
  //                   Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
  //                     Text('Total', style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.55))),
  //                     const SizedBox(height: 2),
  //                     Text('£${_totalSelected.toStringAsFixed(2)}',
  //                         style: const TextStyle( fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
  //                   ])),
  //                 ]),
  //               ),
  //             ]),
  //           ),
  //         ]),
  //       ),
  //       const SizedBox(height: 20),
  //       Container(
  //         decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
  //             border: Border.all(color: const Color(0xFFF0F0F0)),
  //             boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 24, offset: const Offset(0, 6))]),
  //         child: Column(children: [
  //           Container(
  //             padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
  //             decoration: const BoxDecoration(color: Color(0xFFFAFAFA),
  //                 borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
  //                 border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0)))),
  //             child: Row(children: [
  //               Container(width: 38, height: 38,
  //                   decoration: BoxDecoration(color: const Color(0xFF059669).withOpacity(0.1), shape: BoxShape.circle),
  //                   child: const Icon(Icons.lock_rounded, color: Color(0xFF059669), size: 19)),
  //               const SizedBox(width: 12),
  //               const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
  //                 Text('Card Details', style: TextStyle( fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
  //                 Text('256-bit SSL · Powered by Stripe', style: TextStyle(fontSize: 11, color: Color(0xFF059669))),
  //               ])),
  //               Row(children: [
  //                 _BrandBadge('VISA', const Color(0xFF1A1F71)),
  //                 const SizedBox(width: 4),
  //                 _BrandBadge('MC', const Color(0xFFEB001B)),
  //               ]),
  //             ]),
  //           ),
  //           Padding(padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
  //               child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
  //                 const Text('Card Number', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF9B9B9B), letterSpacing: 0.5)),
  //                 const SizedBox(height: 8),
  //                 Container(
  //                   decoration: BoxDecoration(color: const Color(0xFFF8F8F8), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE8E8E8))),
  //                   child: TextFormField(
  //                     controller: _cardNumberCtrl, keyboardType: TextInputType.number, maxLength: 22,
  //                     style: const TextStyle(fontSize: 16, color: Color(0xFF1A1A1A), fontFamily: 'monospace', letterSpacing: 2),
  //                     decoration: const InputDecoration(
  //                       hintText: '1234  5678  9012  3456',
  //                       hintStyle: TextStyle(color: Color(0xFFB0B0B0), fontSize: 14, letterSpacing: 1, fontFamily: 'monospace'),
  //                       border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
  //                       counterText: '',
  //                       suffixIcon: Padding(padding: EdgeInsets.only(right: 12),
  //                           child: Icon(Icons.credit_card_rounded, color: Color(0xFFB0B0B0), size: 20)),
  //                       suffixIconConstraints: BoxConstraints(minWidth: 0, minHeight: 0),
  //                     ),
  //                     inputFormatters: [FilteringTextInputFormatter.digitsOnly, _CardNumberFormatter()],
  //                     onChanged: (_) => setState(() {}),
  //                   ),
  //                 ),
  //                 const SizedBox(height: 14),
  //                 Row(children: [
  //                   Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
  //                     const Text('Expiry Date', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF9B9B9B), letterSpacing: 0.5)),
  //                     const SizedBox(height: 8),
  //                     Container(
  //                       decoration: BoxDecoration(color: const Color(0xFFF8F8F8), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE8E8E8))),
  //                       child: TextFormField(
  //                         controller: _expiryCtrl, keyboardType: TextInputType.number, maxLength: 5,
  //                         style: const TextStyle(fontSize: 16, color: Color(0xFF1A1A1A), fontFamily: 'monospace', letterSpacing: 2),
  //                         decoration: const InputDecoration(hintText: 'MM/YY',
  //                             hintStyle: TextStyle(color: Color(0xFFB0B0B0), fontSize: 14, letterSpacing: 1),
  //                             border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14), counterText: ''),
  //                         inputFormatters: [FilteringTextInputFormatter.digitsOnly, _ExpiryFormatter()],
  //                         onChanged: (_) => setState(() {}),
  //                       ),
  //                     ),
  //                   ])),
  //                   const SizedBox(width: 12),
  //                   Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
  //                     const Text('CVC', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF9B9B9B), letterSpacing: 0.5)),
  //                     const SizedBox(height: 8),
  //                     Container(
  //                       decoration: BoxDecoration(color: const Color(0xFFF8F8F8), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE8E8E8))),
  //                       child: TextFormField(
  //                         controller: _cvcCtrl, keyboardType: TextInputType.number, maxLength: 3, obscureText: true,
  //                         style: const TextStyle(fontSize: 16, color: Color(0xFF1A1A1A), letterSpacing: 6),
  //                         decoration: const InputDecoration(hintText: '•••',
  //                             hintStyle: TextStyle(color: Color(0xFFB0B0B0), fontSize: 18, letterSpacing: 4),
  //                             border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14), counterText: '',
  //                             suffixIcon: Padding(padding: EdgeInsets.only(right: 12),
  //                                 child: Icon(Icons.lock_outline_rounded, color: Color(0xFFB0B0B0), size: 18)),
  //                             suffixIconConstraints: BoxConstraints(minWidth: 0, minHeight: 0)),
  //                         inputFormatters: [FilteringTextInputFormatter.digitsOnly],
  //                         onChanged: (_) => setState(() {}),
  //                       ),
  //                     ),
  //                   ])),
  //                 ]),
  //                 const SizedBox(height: 20),
  //                 Container(padding: const EdgeInsets.all(16),
  //                     decoration: BoxDecoration(color: const Color(0xFFF0FDF4), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFBBF7D0))),
  //                     child: Column(children: [
  //                       Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
  //                         Text('Shipping labels (${_validRows.length})', style: const TextStyle(fontSize: 13, color: Color(0xFF3A3A3A))),
  //                         Text('£${(_validRows.fold(0.0, (s, r) => s + (r.selectedRate?.price ?? 0))).toStringAsFixed(2)}',
  //                             style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A))),
  //                       ]),
  //                       const SizedBox(height: 8),
  //                       Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
  //                         Text('Service fee (varies by size)', style: const TextStyle(fontSize: 13, color: Color(0xFF3A3A3A))),
  //                         Text('£${(_totalSelected - _validRows.fold(0.0, (s, r) => s + (r.selectedRate?.price ?? 0))).toStringAsFixed(2)}',
  //                             style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A))),
  //                       ]),
  //                       const Padding(padding: EdgeInsets.symmetric(vertical: 10),
  //                           child: Divider(height: 1, color: Color(0xFFBBF7D0))),
  //                       Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
  //                         const Text('Total charged today', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
  //                         Text('£${_totalSelected.toStringAsFixed(2)}',
  //                             style: const TextStyle( fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF059669))),
  //                       ]),
  //                     ])),
  //                 const SizedBox(height: 14),
  //               ])),
  //         ]),
  //       ),
  //       if (_paymentError.isNotEmpty) ...[
  //         const SizedBox(height: 14),
  //         Container(
  //           padding: const EdgeInsets.all(14),
  //           decoration: BoxDecoration(
  //               color: Colors.red.withOpacity(0.05),
  //               border: Border.all(color: Colors.red.withOpacity(0.2)),
  //               borderRadius: BorderRadius.circular(12)),
  //           child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
  //             const Row(children: [
  //               Icon(Icons.cancel_rounded, color: Colors.red, size: 18),
  //               SizedBox(width: 8),
  //               Text('Payment Failed', style: TextStyle(
  //                   fontSize: 14, fontWeight: FontWeight.w700, color: Colors.red)),
  //             ]),
  //             const SizedBox(height: 6),
  //             Text(_paymentError, style: const TextStyle(fontSize: 12, color: Colors.red)),
  //             const SizedBox(height: 8),
  //             const Text(
  //               'A confirmation email has been sent. No charges were made to your account.',
  //               style: TextStyle(fontSize: 11, color: Color(0xFF9B9B9B)),
  //             ),
  //           ]),
  //         ),
  //       ],
  //       const SizedBox(height: 24),
  //       SizedBox(width: double.infinity, height: 58,
  //           child: ElevatedButton(
  //             onPressed: _paymentLoading || _paymentConfirmed ? null : _processPayment,
  //             style: ElevatedButton.styleFrom(
  //                 backgroundColor: const Color(0xFF059669), foregroundColor: Colors.white,
  //                 disabledBackgroundColor: const Color(0xFF059669).withOpacity(0.4),
  //                 elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  //                 textStyle: const TextStyle( fontSize: 17, fontWeight: FontWeight.w800)),
  //             child: _paymentLoading
  //                 ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
  //               SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)),
  //               SizedBox(width: 12),
  //               Text('Processing payment...'),
  //             ])
  //                 : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
  //               const Icon(Icons.lock_rounded, size: 18, color: Colors.white),
  //               const SizedBox(width: 8),
  //               Text('Pay £${_totalSelected.toStringAsFixed(2)} securely'),
  //             ]),
  //           )),
  //       const SizedBox(height: 12),
  //       const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
  //         Icon(Icons.verified_user_outlined, size: 12, color: Color(0xFFB0B0B0)),
  //         SizedBox(width: 4),
  //         Text('Stripe  ·  PCI DSS compliant  ·  256-bit SSL', style: TextStyle(fontSize: 10, color: Color(0xFFB0B0B0))),
  //       ]),
  //     ]);

  Widget _buildStep4Payment() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Bulk Order Summary Card ──────────────────────────
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
              color: const Color(0xFF6D28D9),
              borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.15))),
              ),
              child: Row(children: [
                Icon(Icons.inventory_2_outlined, size: 13,
                    color: Colors.white.withOpacity(0.6)),
                const SizedBox(width: 6),
                Text('Bulk order summary',
                    style: TextStyle(fontSize: 11, letterSpacing: 0.6,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withOpacity(0.6))),
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
                        borderRadius: BorderRadius.circular(10)),
                    child: Icon(Icons.inventory_2_outlined,
                        color: Colors.white.withOpacity(0.9), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${_validRows.length} Parcel Labels',
                            style: const TextStyle(fontSize: 14,
                                fontWeight: FontWeight.w600, color: Colors.white)),
                        const SizedBox(height: 2),
                        Text('Incl. service fee (varies by size)',
                            style: TextStyle(fontSize: 12,
                                color: Colors.white.withOpacity(0.65))),
                      ])),
                ]),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.only(top: 14),
                  decoration: BoxDecoration(
                      border: Border(
                          top: BorderSide(color: Colors.white.withOpacity(0.15)))),
                  child: Row(children: [
                    Expanded(child: Column(children: [
                      Text('Labels', style: TextStyle(fontSize: 11,
                          color: Colors.white.withOpacity(0.55))),
                      const SizedBox(height: 4),
                      Text('${_validRows.length}', style: TextStyle(
                          fontSize: 13, color: Colors.white.withOpacity(0.85))),
                    ])),
                    Container(width: 0.5, height: 28,
                        color: Colors.white.withOpacity(0.2)),
                    Expanded(child: Column(children: [
                      Text('Service fee', style: TextStyle(fontSize: 11,
                          color: Colors.white.withOpacity(0.55))),
                      const SizedBox(height: 4),
                      Text(
                        '£${(_totalSelected - _validRows.fold(0.0, (s, r) => s + (r.selectedRate?.price ?? 0))).toStringAsFixed(2)}',
                        style: TextStyle(fontSize: 13,
                            color: Colors.white.withOpacity(0.85)),
                      ),
                    ])),
                    Container(width: 0.5, height: 28,
                        color: Colors.white.withOpacity(0.2)),
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('Total', style: TextStyle(fontSize: 11,
                              color: Colors.white.withOpacity(0.55))),
                          const SizedBox(height: 2),
                          Text('£${_totalSelected.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                        ])),
                  ]),
                ),
              ]),
            ),
          ]),
        ),

        const SizedBox(height: 20),

        // // ── Address summary ──────────────────────────────────
        // Container(
        //   padding: const EdgeInsets.all(14),
        //   decoration: BoxDecoration(color: Colors.white,
        //       border: Border.all(color: const Color(0xFFEEEEEE)),
        //       borderRadius: BorderRadius.circular(12)),
        //   child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        //     const Text('Sender', style: TextStyle(fontSize: 11,
        //         fontWeight: FontWeight.w700, color: Color(0xFF9B9B9B),
        //         letterSpacing: 0.8)),
        //     const SizedBox(height: 6),
        //     Text(_sNameCtrl.text.trim(), style: const TextStyle(fontSize: 13,
        //         fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A))),
        //     Text('${_sCityCtrl.text.trim()}, ${_formatUkPc(_sPcCtrl.text)}',
        //         style: const TextStyle(fontSize: 11, color: Color(0xFF6B6B6B))),
        //     Text(_sEmailCtrl.text.trim(),
        //         style: const TextStyle(fontSize: 11, color: Color(0xFF6B6B6B))),
        //   ]),
        // ),

        const SizedBox(height: 20),

        // ── Trust badges ─────────────────────────────────────
        const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.lock_rounded, size: 14, color: Color(0xFF059669)),
          SizedBox(width: 6),
          Text('Secured by Stripe · 256-bit SSL · PCI DSS compliant',
              style: TextStyle(fontSize: 11, color: Color(0xFF6B6B6B))),
        ]),

        const SizedBox(height: 20),

        // // ── Error ────────────────────────────────────────────
        // if (_paymentError.isNotEmpty) ...[
        //   Container(
        //     padding: const EdgeInsets.all(12),
        //     decoration: BoxDecoration(
        //         color: Colors.red.withOpacity(0.05),
        //         border: Border.all(color: Colors.red.withOpacity(0.2)),
        //         borderRadius: BorderRadius.circular(10)),
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
            onPressed: _paymentLoading || _paymentConfirmed
                ? null
                : _processPayment,
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                const Color(0xFF059669).withOpacity(0.4),
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                textStyle: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w800)),
            child: _paymentLoading
                ? const Row(mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5)),
                  SizedBox(width: 12),
                  Text('Processing...'),
                ])
                : Row(mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_rounded, size: 18, color: Colors.white),
                  const SizedBox(width: 8),
                  Text('Pay £${_totalSelected.toStringAsFixed(2)} securely'),
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

  Widget _buildStep5Processing() {
    final valid   = _validRows;
    final done    = _successCount + _failedCount;
    final pct     = valid.isEmpty ? 0.0 : done / valid.length;
    final current = _currentIdx < valid.length ? valid[_currentIdx] : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _header('Generating Labels', 'Please keep the app open'),
      const SizedBox(height: 28),
      Center(child: SizedBox(width: 140, height: 140,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox(width: 140, height: 140,
                child: CircularProgressIndicator(value: pct, strokeWidth: 10,
                    backgroundColor: const Color(0xFFEEEEEE), color: const Color(0xFFFF5A00))),
            Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('$done', style: const TextStyle( fontSize: 34, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
              Text('of ${valid.length}', style: const TextStyle(fontSize: 13, color: Color(0xFF9B9B9B))),
            ]),
          ]))),
      const SizedBox(height: 24),
      if (current != null)
        Container(padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFEEEEEE)), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Color(0xFFFF5A00), strokeWidth: 2)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Creating label for ${current.recipientName}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A))),
                Text('via ${current.selectedRate?.carrier ?? '...'} · ${current.recipientCity}',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF9B9B9B))),
              ])),
            ])),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: _StatCard('Done', '$_successCount', const Color(0xFF059669))),
        const SizedBox(width: 8),
        Expanded(child: _StatCard('Failed', '$_failedCount', Colors.red)),
        const SizedBox(width: 8),
        Expanded(child: _StatCard('Left', '$_pendingCount', const Color(0xFF6D28D9))),
      ]),
      const SizedBox(height: 16),
      ..._validRows.where((r) => r.status != 'pending').take(20).map((r) => _ResultRow(r)),
    ]);
  }

  Widget _buildStep6Done() => Column(children: [
    const SizedBox(height: 20),
    Container(width: 80, height: 80,
        decoration: BoxDecoration(color: const Color(0xFF059669).withOpacity(0.1), shape: BoxShape.circle),
        child: const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF059669), size: 44)),
    const SizedBox(height: 16),
    const Text('Batch Complete!', style: TextStyle( fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
    const SizedBox(height: 8),
    Text('$_successCount of ${_validRows.length} labels generated',
        style: const TextStyle(fontSize: 14, color: Color(0xFF6B6B6B))),
    const SizedBox(height: 20),
    Container(width: double.infinity, padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFEEEEEE)), borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Expanded(child: _SumTile(Icons.check_circle_outline_rounded, 'Created', '$_successCount', const Color(0xFF059669))),
          Container(width: 1, height: 50, color: const Color(0xFFEEEEEE)),
          Expanded(child: _SumTile(Icons.error_outline_rounded, 'Failed', '$_failedCount',
              _failedCount > 0 ? Colors.red : const Color(0xFF9B9B9B))),
          Container(width: 1, height: 50, color: const Color(0xFFEEEEEE)),
          Expanded(child: _SumTile(Icons.payments_outlined, 'Paid', '£${_totalPaid.toStringAsFixed(2)}', const Color(0xFF6D28D9))),
        ])),
    const SizedBox(height: 14),
    if (_sendingInvoice || _invoiceSent)
      _StatusTile(_sendingInvoice, _invoiceSent, Icons.receipt_long_rounded,
          'Invoice', _sEmailCtrl.text.trim(), const Color(0xFF6D28D9)),
    if (_sendingLabels || _labelsSent)
      _StatusTile(_sendingLabels, _labelsSent, Icons.mark_email_read_rounded,
          'Labels', _sEmailCtrl.text.trim(), const Color(0xFF059669)),
    if (_successCount > 0) ...[
      const SizedBox(height: 4),
      Container(width: double.infinity, padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFEEEEEE)), borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFDC2626), size: 16),
              SizedBox(width: 8),
              Text('Download Labels', style: TextStyle( fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
            ]),
            const SizedBox(height: 12),
            ..._validRows.where((r) => r.status == 'success' && r.labelUrl.isNotEmpty)
                .map((r) => GestureDetector(
              onTap: () => _downloadBulkLabel(r.labelUrl, r.trackingNumber, r.recipientName),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: const Color(0xFFFFF5EE),
                    border: Border.all(color: const Color(0xFFFFDDCC)), borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  const Icon(Icons.download_rounded, color: Color(0xFFFF5A00), size: 16),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r.recipientName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A))),
                    Text('${r.carrier} · ${r.trackingNumber}',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: Color(0xFF9B9B9B))),
                  ])),
                  const Icon(Icons.download_rounded, size: 13, color: Color(0xFFFF5A00)),
                ]),
              ),
            )),
          ])),
      const SizedBox(height: 14),
    ],
    SizedBox(width: double.infinity, height: 48,
        child: ElevatedButton.icon(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.home_outlined, size: 18),
          label: const Text('Back to Dashboard'),
          style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF5A00), foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              textStyle: const TextStyle( fontSize: 15, fontWeight: FontWeight.w700)),
        )),
  ]);

  Widget _buildBottomBar() {
    String label; VoidCallback? onTap;
    if (_step == 0) {
      label = 'Continue →';
      onTap = () { if (_sKey.currentState?.validate() ?? false) setState(() => _step = 1); };
    } else if (_step == 1) {
      label = 'Create $_recipientCount Row${_recipientCount > 1 ? "s" : ""} →';
      onTap = _createRows;
    } else if (_step == 2) {
      final filled = _rows.where((r) => r.recipientName.isNotEmpty).length;
      label = filled > 0 ? 'Check & Confirm →' : 'Fill in at least 1 row';
      onTap = filled > 0 ? _validateAndConfirm : null;
    } else if (_step == 3) {
      final allLoaded   = _validRows.every((r) => !r.loadingRates);
      final anySelected = _validRows.any((r) => r.selectedRate != null);
      label = 'Proceed to Payment →';
      onTap = (allLoaded && anySelected && !_loadingAllRates) ? () => setState(() => _step = 4) : null;
    } else {
      label = ''; onTap = null;
    }
    if (_step == 4 || _step >= 5) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFEEEEEE)))),
      child: Row(children: [
        if (_step > 0 && _step < 4) ...[
          Expanded(flex: 1, child: GestureDetector(
            onTap: () => setState(() => _step--),
            child: Container(height: 48,
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFE0E0E0)), borderRadius: BorderRadius.circular(10)),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.arrow_back_ios, size: 14, color: Color(0xFF6B6B6B)),
                  Text('Previous', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF6B6B6B))),
                ])),
          )),
          const SizedBox(width: 12),
        ],
        Expanded(flex: 2, child: SizedBox(height: 48,
            child: ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF5A00), foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFFFDDCC),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  textStyle: const TextStyle( fontSize: 14, fontWeight: FontWeight.w700)),
              child: _loadingAllRates
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(label),
            ))),
      ]),
    );
  }
  Future<void> _downloadBulkLabel(String url, String trackingNumber, String recipientName) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const SizedBox(width: 16, height: 16,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
          const SizedBox(width: 12),
          Expanded(child: Text('Downloading label for $recipientName...')),
        ]),
        backgroundColor: const Color(0xFF6D28D9),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 30),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );

    try {
      if (Platform.isAndroid) {
        final status = await Permission.storage.request();
        if (!status.isGranted && !status.isLimited) {
          await Permission.manageExternalStorage.request();
        }
      }

      final safeName = recipientName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final fileName = 'SwiftLabel_${safeName}_${trackingNumber.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}.pdf';
      String filePath;

      if (Platform.isAndroid) {
        filePath = '/storage/emulated/0/Download/$fileName';
      } else {
        final dir = await getApplicationDocumentsDirectory();
        filePath = '${dir.path}/$fileName';
      }

      final dio = Dio();
      await dio.download(url, filePath);

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text('${recipientName}\'s label saved!')),
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
                await launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView);
              }
            },
          ),
        ),
      );

      final result = await OpenFilex.open(filePath);
      if (result.type != ResultType.done && mounted) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      debugPrint('[BulkDownload] Error: $e');
      if (!mounted) return;
      try {
        await launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView);
      } catch (_) {
        _showSnack('Could not download label. Try again.', isError: true);
      }
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : const Color(0xFFFF5A00),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  Widget _header(String t, String s) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(t, style: const TextStyle( fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
    const SizedBox(height: 4),
    Text(s, style: const TextStyle(fontSize: 13, color: Color(0xFF9B9B9B))),
  ]);

  String? _req(String? v) => (v?.isEmpty ?? true) ? 'Required' : null;
}

// =============================================================================
// DATA ENTRY ROW WIDGET
// =============================================================================

class _DataEntryRow extends StatefulWidget {
  final BulkRow row; final VoidCallback onChanged;
  const _DataEntryRow({required this.row, required this.onChanged});
  @override State<_DataEntryRow> createState() => _DataEntryRowState();
}

class _DataEntryRowState extends State<_DataEntryRow> {
  bool _expanded = false;
  static const _sizes   = ['xs','sm','md','lg'];
  static const _slabels = ['XS','Small','Medium','Large'];
  static const _types   = ['Clothing','Electronics','Documents','Books','Fragile','Gifts','Other'];

  @override
  Widget build(BuildContext context) {
    final row      = widget.row;
    final hasError = !row.isValid && row.recipientName.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
          color: hasError ? Colors.red.withOpacity(0.03) : Colors.white,
          border: Border.all(color: hasError ? Colors.red.withOpacity(0.3) : const Color(0xFFEEEEEE)),
          borderRadius: BorderRadius.circular(10)),
      child: Column(children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            Container(width: 22, height: 22,
                decoration: BoxDecoration(color: const Color(0xFFFFF5EE), borderRadius: BorderRadius.circular(5)),
                child: Center(child: Text('${row.rowNum}',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFFFF5A00))))),
            const SizedBox(width: 6),
            Expanded(flex: 3, child: _InlineField(ctrl: row.nameCtrl, hint: 'Full name', onChanged: widget.onChanged)),
            const SizedBox(width: 6),
            Expanded(flex: 3, child: _InlineField(ctrl: row.addressCtrl, hint: 'Street address', onChanged: widget.onChanged)),
            const SizedBox(width: 6),
            Expanded(flex: 2, child: _InlineField(ctrl: row.cityCtrl, hint: 'City', onChanged: widget.onChanged)),
            const SizedBox(width: 6),
            Expanded(flex: 2, child: _InlineField(
              ctrl: row.postcodeCtrl, hint: 'E1 6AN',
              caps: TextCapitalization.characters,
              hasError: !row.postcodeValid && row.postcodeCtrl.text.isNotEmpty,
              onChanged: widget.onChanged,
            )),
            const SizedBox(width: 4),
            GestureDetector(onTap: () => setState(() => _expanded = !_expanded),
                child: Icon(_expanded ? Icons.keyboard_arrow_up_rounded : Icons.tune_rounded,
                    size: 18, color: const Color(0xFF9B9B9B))),
          ]),
        ),
        if (_expanded) ...[
          const Divider(height: 1, color: Color(0xFFF5F5F5)),
          Padding(padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(children: [
                Row(children: [
                  const SizedBox(width: 28),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Phone (optional)', style: TextStyle(fontSize: 10, color: Color(0xFF9B9B9B))),
                    const SizedBox(height: 4),
                    _InlineField(ctrl: row.phoneCtrl, hint: '+44 7700 900000',
                        type: TextInputType.phone, onChanged: widget.onChanged),
                  ])),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  const SizedBox(width: 28),
                  const Text('Size:', style: TextStyle(fontSize: 11, color: Color(0xFF6B6B6B))),
                  const SizedBox(width: 8),
                  ...List.generate(_sizes.length, (i) => GestureDetector(
                    onTap: () { setState(() => row.parcelSize = _sizes[i]); widget.onChanged(); },
                    child: Container(margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                            color: row.parcelSize == _sizes[i] ? const Color(0xFFFF5A00) : Colors.white,
                            border: Border.all(color: row.parcelSize == _sizes[i] ? const Color(0xFFFF5A00) : const Color(0xFFE0E0E0)),
                            borderRadius: BorderRadius.circular(16)),
                        child: Text(_slabels[i], style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                            color: row.parcelSize == _sizes[i] ? Colors.white : const Color(0xFF3A3A3A)))),
                  )),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  const SizedBox(width: 28),
                  const Text('Type:', style: TextStyle(fontSize: 11, color: Color(0xFF6B6B6B))),
                  const SizedBox(width: 8),
                  Expanded(child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: _types.map((t) => GestureDetector(
                      onTap: () { setState(() => row.parcelType = t); widget.onChanged(); },
                      child: Container(margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                              color: row.parcelType == t ? const Color(0xFFFF5A00) : Colors.white,
                              border: Border.all(color: row.parcelType == t ? const Color(0xFFFF5A00) : const Color(0xFFE0E0E0)),
                              borderRadius: BorderRadius.circular(14)),
                          child: Text(t, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                              color: row.parcelType == t ? Colors.white : const Color(0xFF3A3A3A)))),
                    )).toList()),
                  )),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  const SizedBox(width: 28),
                  const Text('Weight (kg):', style: TextStyle(fontSize: 11, color: Color(0xFF6B6B6B))),
                  const SizedBox(width: 8),
                  SizedBox(width: 80, child: _InlineField(
                    ctrl: row.weightCtrl, hint: '1.0',
                    type: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                    onChanged: widget.onChanged,
                  )),
                  const SizedBox(width: 6),
                  const Text('kg', style: TextStyle(fontSize: 11, color: Color(0xFF9B9B9B))),
                ]),
              ])),
        ],
        if (hasError && row.validationError != null)
          Padding(padding: const EdgeInsets.fromLTRB(40, 0, 12, 8),
              child: Text(row.validationError!, style: const TextStyle(fontSize: 10, color: Colors.red))),
      ]),
    );
  }
}

class _InlineField extends StatelessWidget {
  final TextEditingController ctrl; final String hint;
  final TextInputType type; final VoidCallback onChanged;
  final TextCapitalization caps; final bool hasError;
  final List<TextInputFormatter> inputFormatters;
  const _InlineField({required this.ctrl, required this.hint,
    required this.onChanged, this.type = TextInputType.text,
    this.caps = TextCapitalization.none, this.hasError = false,
    this.inputFormatters = const []});
  @override Widget build(BuildContext context) => TextField(
    controller: ctrl, keyboardType: type, textCapitalization: caps,
    style: const TextStyle(fontSize: 12, color: Color(0xFF1A1A1A)),
    inputFormatters: inputFormatters, onChanged: (_) => onChanged(),
    decoration: InputDecoration(
      hintText: hint, hintStyle: const TextStyle(color: Color(0xFFCCCCCC), fontSize: 12),
      filled: true, fillColor: hasError ? Colors.red.withOpacity(0.04) : const Color(0xFFF8F8F8),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFFE8E8E8))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: hasError ? Colors.red.withOpacity(0.4) : const Color(0xFFE8E8E8))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Color(0xFFFF5A00), width: 1.5)),
      isDense: true,
    ),
  );
}

// =============================================================================
// SHARED WIDGETS
// =============================================================================

class _CourierCard extends StatelessWidget {
  final BulkRow row; final ValueChanged<int> onSelect; final VoidCallback onRetry;final VoidCallback onToggle;
  const _CourierCard({required this.row, required this.onSelect, required this.onRetry, required this.onToggle});

  @override Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(
        color: row.serviceUnavailable ? const Color(0xFFFFF8F0) : Colors.white,
        border: Border.all(color: row.serviceUnavailable ? const Color(0xFFFFDDCC) : const Color(0xFFEEEEEE)),
        borderRadius: BorderRadius.circular(12)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Row(children: [
            Container(width: 26, height: 26,
                decoration: BoxDecoration(color: const Color(0xFFFFF5EE), borderRadius: BorderRadius.circular(7)),
                child: Center(child: Text('${row.rowNum}',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFFFF5A00))))),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(row.recipientName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A))),
              Text('${row.recipientCity} · ${row.recipientPostcode} · ${row.weightKg}kg',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF9B9B9B))),
            ])),
            if (row.selectedRate != null)
                Text('£${(row.selectedRate!.price + ServiceFee.domestic(row.parcelSize)).toStringAsFixed(2)}',
                  style: const TextStyle( fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFFFF5A00))),
          ])),
      const Divider(height: 1, color: Color(0xFFF5F5F5)),
      Column(
        children: [

          /// 🔹 HEADER (always visible)
          GestureDetector(
            onTap: onToggle,
            child: Container(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [

                        /// Parcel title
                        Text(
                          'Parcel ${row.rowNum}',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700),
                        ),

                        const SizedBox(height: 4),

                        /// ✅ SHOW SELECTED WHEN COLLAPSED
                        if (!row.showRates)
                          if (row.selectedRate != null)
                            Text(
                              '${row.selectedRate!.carrier} · £${(row.selectedRate!.price + ServiceFee.domestic(row.parcelSize)).toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF6B6B6B)),
                            )
                          else
                            const Text(
                              'Select courier',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFFB0B0B0)),
                            ),
                      ],
                    ),
                  ),

                  /// Arrow
                  Icon(
                    row.showRates
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                  ),
                ],
              ),
            ),
          ),

          /// 🔹 EXPAND ONLY THIS PART
          if (row.showRates) ...[

            /// 🔹 YOUR ORIGINAL CODE (UNCHANGED)
            if (row.loadingRates)
              const Padding(
                padding: EdgeInsets.all(14),
                child: Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        color: Color(0xFFFF5A00),
                        strokeWidth: 2,
                      ),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Getting live prices...',
                      style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF9B9B9B)),
                    ),
                  ],
                ),
              ),

            if (row.serviceUnavailable)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.do_not_disturb_alt_rounded,
                          color: Color(0xFFCC4400), size: 16),
                      SizedBox(width: 8),
                      Text(
                        'No service available',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFCC4400)),
                      ),
                    ]),
                    const SizedBox(height: 8),

                    GestureDetector(
                      onTap: onRetry,
                      child: Container(
                        width: double.infinity,
                        padding:
                        const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: const Color(0xFFFF5A00)
                                  .withOpacity(0.5)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisAlignment:
                          MainAxisAlignment.center,
                          children: [
                            Icon(Icons.refresh_rounded,
                                size: 14,
                                color: Color(0xFFFF5A00)),
                            SizedBox(width: 6),
                            Text(
                              'Retry',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFFF5A00)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            if (!row.loadingRates && row.rates.isNotEmpty)
              ...row.rates.asMap().entries.map((e) {
                final idx = e.key;
                final rate = e.value;
                final sel = idx == row.selectedIdx;

                return GestureDetector(
                  onTap: () {
                    onSelect(idx);
                    onToggle();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    color: sel
                        ? const Color(0xFFFFFBE6)
                        : Colors.transparent,
                    child: Row(
                      children: [
                        Icon(
                          sel
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_unchecked_rounded,
                          size: 17,
                          color: sel
                              ? const Color(0xFFFF5A00)
                              : const Color(0xFFCCCCCC),
                        ),
                        const SizedBox(width: 10),
                        _BulkCarrierLogo(
                            carrier: rate.carrier,
                            color: rate.color),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                            CrossAxisAlignment.start,
                            children: [
                              Text(
                                rate.carrier,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: sel
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: sel
                                      ? const Color(0xFFFF5A00)
                                      : const Color(0xFF1A1A1A),
                                ),
                              ),
                              Text(
                                '${rate.service} · ${rate.daysLabel}',
                                style: const TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF9B9B9B)),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '£${(rate.price + ServiceFee.domestic(row.parcelSize)).toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: sel
                                ? const Color(0xFFFF5A00)
                                : const Color(0xFF3A3A3A),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),

            const SizedBox(height: 4),
          ],
        ],
      )
    ]),
  );
}

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

class _BulkCarrierLogo extends StatelessWidget {
  final String carrier; final Color color;
  const _BulkCarrierLogo({required this.carrier, required this.color});
  static const _assets = <String, String>{
    'Royal Mail': 'assets/carriers/royal_mail.png', 'Parcelforce Royal Mail': 'assets/carriers/parcelforce.png',
    'Parcelforce': 'assets/carriers/parcelforce.png', 'Evri': 'assets/carriers/evri.png',
    'Evri (Hermes)': 'assets/carriers/evri.png', 'DPD UK': 'assets/carriers/dpd.png',
    'DPD': 'assets/carriers/dpd.png', 'Yodel': 'assets/carriers/yodel.png',
    'FedEx UK': 'assets/carriers/fedex.png', 'FedEx': 'assets/carriers/fedex.png',
    'DHL Express MyDHL API': 'assets/carriers/dhl.png', 'DHL Express': 'assets/carriers/dhl.png',
    'DHL': 'assets/carriers/dhl.png', 'UPS': 'assets/carriers/ups.png',
    'GlobalPost': 'assets/carriers/globalpost.png', 'Stamps.com': 'assets/carriers/globalpost.png',
    'ShipStation Carrier Services': 'assets/carriers/globalpost.png', 'InPost': 'assets/carriers/globalpost.png',
  };
  static const _abbr = <String, String>{
    'Royal Mail': 'RM', 'Parcelforce Royal Mail': 'PF', 'Parcelforce': 'PF',
    'Evri': 'EV', 'Evri (Hermes)': 'EV', 'DPD UK': 'DPD', 'DPD': 'DPD',
    'Yodel': 'YDL', 'FedEx UK': 'FedEx', 'FedEx': 'FedEx',
    'DHL Express MyDHL API': 'DHL', 'DHL Express': 'DHL', 'DHL': 'DHL',
    'UPS': 'UPS', 'GlobalPost': 'GP', 'Stamps.com': 'STP',
    'ShipStation Carrier Services': 'SS', 'InPost': 'IN',
  };
  @override
  Widget build(BuildContext context) {
    final assetPath = _assets[carrier];
    final abbr = _abbr[carrier] ?? carrier.substring(0, carrier.length > 2 ? 2 : carrier.length);
    final fs   = abbr.length >= 5 ? 7.0 : abbr.length == 4 ? 8.0 : 10.0;
    return Container(
      width: 36, height: 24,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(5), border: Border.all(color: const Color(0xFFEEEEEE))),
      padding: const EdgeInsets.all(2),
      child: assetPath != null
          ? Image.asset(assetPath, fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Center(child: Text(abbr, style: TextStyle(fontSize: fs, fontWeight: FontWeight.w800, color: color))))
          : Center(child: Text(abbr, style: TextStyle(fontSize: fs, fontWeight: FontWeight.w800, color: color))),
    );
  }
}

class _ConfirmStat extends StatelessWidget {
  final String value, label; final Color color;
  const _ConfirmStat(this.value, this.label, this.color);
  @override Widget build(BuildContext context) => Expanded(child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(color: color.withOpacity(0.08), border: Border.all(color: color.withOpacity(0.2)), borderRadius: BorderRadius.circular(10)),
      child: Column(children: [
        Text(value, style: TextStyle( fontSize: 20, fontWeight: FontWeight.w800, color: color)),
        Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF9B9B9B))),
      ])));
}

class _StatusTile extends StatelessWidget {
  final bool loading, done; final IconData icon; final String label, email; final Color color;
  const _StatusTile(this.loading, this.done, this.icon, this.label, this.email, this.color);
  @override Widget build(BuildContext context) => Container(
      margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.withOpacity(0.05), border: Border.all(color: color.withOpacity(0.3)), borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        loading ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: color, strokeWidth: 2))
            : Icon(icon, color: color, size: 18),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(loading ? 'Sending $label...' : '$label sent ✓',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
          Text(done ? '$label emailed to $email' : 'Sending...',
              style: const TextStyle(fontSize: 11, color: Color(0xFF9B9B9B))),
        ])),
      ]));
}

class _Field extends StatelessWidget {
  final String label, hint; final TextEditingController ctrl;
  final TextInputType type; final String? Function(String?)? validator;
  final TextCapitalization caps;
  const _Field({required this.label, required this.ctrl, required this.hint,
    this.type = TextInputType.text, this.validator, this.caps = TextCapitalization.none});
  @override Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF6B6B6B))),
    const SizedBox(height: 6),
    TextFormField(controller: ctrl, keyboardType: type, textCapitalization: caps, validator: validator,
        style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A1A)),
        decoration: InputDecoration(hintText: hint, hintStyle: const TextStyle(color: Color(0xFFB0B0B0), fontSize: 13),
            filled: true, fillColor: Colors.white, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFFF5A00), width: 1.5)),
            errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.red)))),
  ]);
}

class _ResultRow extends StatelessWidget {
  final BulkRow row; const _ResultRow(this.row, {super.key});
  @override Widget build(BuildContext context) {
    final isOk  = row.status == 'success';
    final color = isOk ? const Color(0xFF059669) : row.hasError ? Colors.red : const Color(0xFF9B9B9B);
    return Container(margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
            color: isOk ? const Color(0xFFF0FDF4) : Colors.white,
            border: Border.all(color: color.withOpacity(0.2)), borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          if (row.status == 'processing')
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Color(0xFFFF5A00), strokeWidth: 2))
          else if (isOk)
            const Icon(Icons.check_circle_rounded, color: Color(0xFF059669), size: 16)
          else if (row.hasError)
              const Icon(Icons.error_outline_rounded, color: Colors.red, size: 16)
            else
              const Icon(Icons.radio_button_unchecked_rounded, color: Color(0xFFE0E0E0), size: 16),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(row.recipientName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A))),
            if (isOk) Text(row.trackingNumber, style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: Color(0xFF059669))),
            if (row.hasError) Text(row.errorMsg, style: const TextStyle(fontSize: 10, color: Colors.red), maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
          if (isOk) Text('£${row.price.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF6D28D9))),
        ]));
  }
}

class _QuickBtn extends StatelessWidget {
  final String label; final VoidCallback onTap;
  const _QuickBtn(this.label, this.onTap);
  @override Widget build(BuildContext context) => GestureDetector(onTap: onTap,
      child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFFF5A00).withOpacity(0.4)), borderRadius: BorderRadius.circular(20)),
          child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFFF5A00)))));
}

class _StatCard extends StatelessWidget {
  final String label, value; final Color color;
  const _StatCard(this.label, this.value, this.color);
  @override Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(color: color.withOpacity(0.06), border: Border.all(color: color.withOpacity(0.2)), borderRadius: BorderRadius.circular(10)),
      child: Column(children: [
        Text(value, style: TextStyle( fontSize: 22, fontWeight: FontWeight.w800, color: color)),
        Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF9B9B9B))),
      ]));
}

class _SumTile extends StatelessWidget {
  final IconData icon; final String label, value; final Color color;
  const _SumTile(this.icon, this.label, this.value, this.color);
  @override Widget build(BuildContext context) => Column(children: [
    Icon(icon, color: color, size: 22),
    const SizedBox(height: 6),
    Text(value, style: TextStyle( fontSize: 16, fontWeight: FontWeight.w800, color: color)),
    Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF9B9B9B))),
  ]);
}

class _ErrorCard extends StatelessWidget {
  final String msg; const _ErrorCard(this.msg);
  @override Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.red.withOpacity(0.05), border: Border.all(color: Colors.red.withOpacity(0.2)), borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        const Icon(Icons.error_outline_rounded, color: Colors.red, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(msg, style: const TextStyle(fontSize: 12, color: Colors.red))),
      ]));
}

class _BrandBadge extends StatelessWidget {
  final String label; final Color color;
  const _BrandBadge(this.label, this.color);
  @override Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(4), border: Border.all(color: color.withOpacity(0.2))),
      child: Text(label, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: color, letterSpacing: 0.5)));
}

class _CardNumberFormatter extends TextInputFormatter {
  @override TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue nv) {
    final digits = nv.text.replaceAll(' ', '');
    final buf = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && i % 4 == 0) buf.write('  ');
      buf.write(digits[i]);
    }
    final str = buf.toString();
    return nv.copyWith(text: str, selection: TextSelection.collapsed(offset: str.length));
  }
}

class _ExpiryFormatter extends TextInputFormatter {
  @override TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue nv) {
    final digits = nv.text.replaceAll('/', '');
    String str = digits;
    if (digits.length >= 2) str = '${digits.substring(0, 2)}/${digits.substring(2)}';
    return nv.copyWith(text: str, selection: TextSelection.collapsed(offset: str.length));
  }
}

