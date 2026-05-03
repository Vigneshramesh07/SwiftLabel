// lib/widgets/recepients_Screen.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:swift_label/widgets/state_pickerSheet.dart';
import '../service/country_data.dart';
import 'country_pickerSheet.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Availability result
// ─────────────────────────────────────────────────────────────────────────────

enum _AvailStatus { idle, checking, available, unavailable, error }

// ─────────────────────────────────────────────────────────────────────────────
// Step2Controller
// ─────────────────────────────────────────────────────────────────────────────

class Step2Controller {
  final formKey = GlobalKey<FormState>();

  final nameCtrl   = TextEditingController();
  final phoneCtrl  = TextEditingController();
  final pcCtrl     = TextEditingController();
  final zipCtrl    = TextEditingController();
  final streetCtrl = TextEditingController();
  final doorCtrl   = TextEditingController();
  final cityCtrl   = TextEditingController();
  final stateCtrl  = TextEditingController();

  bool          isInternational = false;
  CountryEntry? selectedCountry;
  String?       selectedState;
  bool          pcValid = false;

  // Availability state — read by send_parcel.dart to block Continue
  _AvailStatus availStatus   = _AvailStatus.idle;
  int          availCount    = 0;
  String       availError    = '';

  bool get serviceAvailable =>
      availStatus == _AvailStatus.available && availCount > 0;

  bool get serviceChecked =>
      availStatus != _AvailStatus.idle &&
          availStatus != _AvailStatus.checking;

  String get dialCode =>
      isInternational ? (selectedCountry?.dialCode ?? '+?') : '+44';

  String get fullPhone => '$dialCode ${phoneCtrl.text.trim()}';

  String get postcode =>
      isInternational ? zipCtrl.text.trim() : pcCtrl.text.trim().toUpperCase();

  String get state => selectedState ?? stateCtrl.text.trim();

  bool get hasStateDropdown =>
      isInternational && (selectedCountry?.states.isNotEmpty ?? false);

  void dispose() {
    nameCtrl.dispose();
    phoneCtrl.dispose();
    pcCtrl.dispose();
    zipCtrl.dispose();
    streetCtrl.dispose();
    doorCtrl.dispose();
    cityCtrl.dispose();
    stateCtrl.dispose();
  }

  void resetCountry() {
    selectedCountry = null;
    selectedState   = null;
    stateCtrl.clear();
    zipCtrl.clear();
    availStatus = _AvailStatus.idle;
    availCount  = 0;
    availError  = '';
  }

  void resetAvailability() {
    availStatus = _AvailStatus.idle;
    availCount  = 0;
    availError  = '';
  }

  bool validate(BuildContext context) {
    final formOk = formKey.currentState?.validate() ?? false;
    if (!formOk) return false;
    if (isInternational && selectedCountry == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please select a destination country.'),
        backgroundColor: Color(0xFFFF5A00),
        behavior: SnackBarBehavior.floating,
      ));
      return false;
    }
    return true;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RecipientDetailsStep widget
// ─────────────────────────────────────────────────────────────────────────────

class RecipientDetailsStep extends StatefulWidget {
  final Step2Controller controller;

  /// Sender postcode needed to call Shippo for availability
  final String senderPostcode;

  const RecipientDetailsStep({
    super.key,
    required this.controller,
    required this.senderPostcode,
  });

  @override
  State<RecipientDetailsStep> createState() => _RecipientDetailsStepState();
}

class _RecipientDetailsStepState extends State<RecipientDetailsStep> {
  Step2Controller get c => widget.controller;

  // ── Postcode lookup state ─────────────────────────────────────
  bool         _pcLookingUp      = false;
  bool         _pcLookedUp       = false;
  String       _pcError          = '';
  List<String> _streetList       = [];
  String?      _selectedStreet;
  Timer?       _pcDebounce;

  // ── Shippo endpoints ──────────────────────────────────────────
  static const _baseUrl    = 'https://tjrjeemaacumepimjltg.supabase.co/functions/v1';
  static const _shippoUrl  = '$_baseUrl/shippo-courier';
  static const _compareUrl = '$_baseUrl/compareRates';
  static const _anonKey    =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRqcmplZW1hYWN1bWVwaW1qbHRnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQxMjE2NjAsImV4cCI6MjA4OTY5NzY2MH0.gtBcFu-J48mPDk_S9ukfVdW-7gUmabGatmJ1g1_5zzo';

  static const _headers = {
    'Content-Type':  'application/json',
    'Authorization': 'Bearer $_anonKey',
  };

  @override
  void dispose() {
    _pcDebounce?.cancel();
    super.dispose();
  }

  bool _validUkPc(String v) =>
      RegExp(r'^[A-Z]{1,2}\d[A-Z\d]? ?\d[A-Z]{2}$', caseSensitive: false)
          .hasMatch(v.trim());

  String _formatUkPc(String raw) {
    final clean = raw.trim().toUpperCase().replaceAll(' ', '');
    if (clean.length >= 5) {
      return '${clean.substring(0, clean.length - 3)} ${clean.substring(clean.length - 3)}';
    }
    return raw.trim().toUpperCase();
  }

  // ── Postcode field onChange ───────────────────────────────────
  void _onPostcodeChanged(String value) {
    _pcDebounce?.cancel();
    setState(() {
      c.pcValid        = false;
      _pcLookedUp      = false;
      _pcError         = '';
      _streetList      = [];
      _selectedStreet  = null;
      c.streetCtrl.clear();
      c.cityCtrl.clear();
      c.resetAvailability();
    });

    final cleaned = value.trim().replaceAll(' ', '').toUpperCase();
    if (cleaned.length < 5) return;

    _pcDebounce = Timer(const Duration(milliseconds: 600), () {
      _lookupPostcode(cleaned);
    });
  }

  // ── Postcode lookup via postcodes.io ──────────────────────────
  Future<void> _lookupPostcode(String postcode) async {
    setState(() { _pcLookingUp = true; _pcError = ''; });

    try {
      final res = await http.get(
        Uri.parse('https://api.postcodes.io/postcodes/$postcode'),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(res.body);

      if (res.statusCode != 200 || data['status'] != 200) {
        setState(() {
          _pcError      = 'Invalid postcode. Please check and try again.';
          _pcLookingUp  = false;
        });
        return;
      }

      final result = data['result'];
      final city   = result['admin_district'] ??
          result['parish']  ??
          result['region']  ??
          'Unknown';

      final formatted = _formatUkPc(postcode);

      setState(() {
        c.pcCtrl.text   = formatted;
        c.cityCtrl.text = city;
        c.pcValid       = true;
        _pcLookedUp     = true;
      });

      // Check same-as-sender
      final normalize = (String s) =>
          s.trim().toUpperCase().replaceAll(' ', '');
      if (normalize(formatted) == normalize(widget.senderPostcode)) {
        setState(() {
          c.pcValid   = false;
          _pcLookedUp = false;
          _pcError    = 'Recipient postcode must differ from sender';
          _pcLookingUp = false;
        });
        return;
      }

      final lat = result['latitude']  as double?;
      final lng = result['longitude'] as double?;
      if (lat != null && lng != null) {
        await _loadNearbyStreets(lat, lng);
      }

      // Trigger availability check once city is set
      c.resetAvailability();

    } on TimeoutException {
      setState(() { _pcError = 'Request timed out. Please try again.'; });
    } on SocketException {
      setState(() { _pcError = 'No internet connection.'; });
    } catch (e) {
      debugPrint('[RecipPC] lookup error: $e');
      setState(() { _pcError = 'Could not look up postcode.'; });
    }

    setState(() { _pcLookingUp = false; });
  }

  // ── Nearby streets (Nominatim + Overpass) ────────────────────
  Future<void> _loadNearbyStreets(double lat, double lng) async {
    try {
      final Set<String> streets = {};

      // 1. Reverse geocode for the primary road
      final revRes = await http.get(
        Uri.parse(
          'https://nominatim.openstreetmap.org/reverse'
              '?lat=$lat&lon=$lng'
              '&format=json&addressdetails=1&zoom=16',
        ),
        headers: {'User-Agent': 'SwiftLabel Flutter App'},
      ).timeout(const Duration(seconds: 10));

      if (revRes.statusCode == 200) {
        final addr = (jsonDecode(revRes.body) as Map)['address'];
        final road = addr?['road'] ?? addr?['street'] ?? addr?['path'];
        if (road != null) streets.add(road.toString());
      }

      // 2. Nominatim bounded search (~400 m box)
      const delta = 0.004;
      final bbox  = '${lng - delta},${lat - delta},${lng + delta},${lat + delta}';

      final searchRes = await http.get(
        Uri.parse(
          'https://nominatim.openstreetmap.org/search'
              '?q=road&format=json&addressdetails=1&limit=50'
              '&bounded=1&viewbox=$bbox',
        ),
        headers: {'User-Agent': 'SwiftLabel Flutter App'},
      ).timeout(const Duration(seconds: 10));

      if (searchRes.statusCode == 200) {
        final List items = jsonDecode(searchRes.body);
        for (final item in items) {
          final addr = item['address'] as Map?;
          final road = addr?['road'] ?? addr?['street'] ?? addr?['path'];
          if (road != null && road.toString().isNotEmpty) {
            streets.add(road.toString());
          }
          final display = item['display_name']?.toString() ?? '';
          if (display.isNotEmpty) {
            final segment = display.split(',').first.trim();
            if (segment.isNotEmpty && !segment.contains(RegExp(r'\d{3}'))) {
              streets.add(segment);
            }
          }
        }
      }

      // 3. Overpass API — most reliable for actual road names
      final overpassRes = await http.post(
        Uri.parse('https://overpass-api.de/api/interpreter'),
        body: '[out:json][timeout:12];'
            'way(around:400,$lat,$lng)[highway][name];'
            'out tags;',
      ).timeout(const Duration(seconds: 14));

      if (overpassRes.statusCode == 200) {
        final elements =
            (jsonDecode(overpassRes.body) as Map)['elements'] as List? ?? [];
        for (final el in elements) {
          final name = el['tags']?['name'];
          if (name != null && name.toString().isNotEmpty) {
            streets.add(name.toString());
          }
        }
      }

      final sorted = streets.toList()..sort();
      if (mounted) {
        setState(() {
          _streetList = sorted.isNotEmpty ? sorted : [];
        });
      }
    } catch (e) {
      debugPrint('[RecipPC] street lookup error: $e');
      // Silently fail — user can type manually
    }
  }

  // ── Check service availability ────────────────────────────────
  Future<void> _checkAvailability() async {
    final toPostcode = c.postcode;
    final toCountry  = c.selectedCountry?.code ?? 'GB';
    final toCity     = c.cityCtrl.text.trim();

    if (toCity.isEmpty && toPostcode.isEmpty) return;

    setState(() {
      c.availStatus = _AvailStatus.checking;
      c.availCount  = 0;
      c.availError  = '';
    });

    try {
      List<dynamic> rates = [];

      if (c.isInternational) {
        try {
          final res = await http.post(
            Uri.parse(_compareUrl),
            headers: _headers,
            body: jsonEncode({
              'action':        'compare_rates',
              'fromPostcode':  widget.senderPostcode,
              'toPostcode':    toPostcode,
              'toCountry':     toCountry,
              'toState':       c.state,
              'toCity':        toCity,
              'weightKg':      1.0,
              'parcelSize':    'sm',
              'international': true,
              'shipment': {
                'sender': {
                  'name': 'Sender', 'address': '1 High Street',
                  'city': 'London', 'postcode': widget.senderPostcode,
                  'country': 'GB', 'phone': '07700000000', 'email': '',
                },
                'recipient': {
                  'name': c.nameCtrl.text.trim().isNotEmpty
                      ? c.nameCtrl.text.trim() : 'Recipient',
                  'address': '1 Main Street',
                  'city':     toCity.isNotEmpty ? toCity : 'City',
                  'postcode': toPostcode.isNotEmpty ? toPostcode : '00000',
                  'state':    c.state,
                  'country':  toCountry,
                  'phone':    '00000000000', 'email': '',
                },
                'parcel': {'size': 'sm', 'weight_kg': 1.0},
              },
            }),
          ).timeout(const Duration(seconds: 20));

          final data = jsonDecode(res.body);
          if (res.statusCode == 200) {
            rates = data['rates'] ?? data['results'] ?? data['data'] ?? [];
          }
        } catch (_) {}

        if (rates.isEmpty) {
          final res = await http.post(
            Uri.parse(_shippoUrl),
            headers: _headers,
            body: jsonEncode({
              'action':        'get_rates',
              'international': true,
              'toCountry':     toCountry,
              'shipment': {
                'sender': {
                  'name': 'Sender', 'address': '1 High Street',
                  'city': 'London', 'postcode': widget.senderPostcode,
                  'country': 'GB', 'phone': '07700000000', 'email': '',
                },
                'recipient': {
                  'name':     'Recipient',
                  'address':  '1 Main Street',
                  'city':     toCity.isNotEmpty ? toCity : 'City',
                  'postcode': toPostcode.isNotEmpty ? toPostcode : '00000',
                  'state':    c.state,
                  'country':  toCountry,
                  'phone':    '00000000000', 'email': '',
                },
                'parcel': {'size': 'sm', 'weight_kg': 1.0},
              },
            }),
          ).timeout(const Duration(seconds: 20));

          final data = jsonDecode(res.body);
          if (res.statusCode == 200 && data['success'] == true) {
            rates = data['rates'] ?? [];
          }
        }
      } else {
        if (toPostcode.length < 5) {
          setState(() => c.availStatus = _AvailStatus.idle);
          return;
        }
        final res = await http.post(
          Uri.parse(_shippoUrl),
          headers: _headers,
          body: jsonEncode({
            'action': 'get_rates',
            'shipment': {
              'sender': {
                'name': 'Sender', 'address': '1 High Street',
                'city': 'London', 'postcode': widget.senderPostcode,
                'country': 'GB', 'phone': '07700000000', 'email': '',
              },
              'recipient': {
                'name':     'Recipient',
                'address':  '1 Main Street',
                'city':     toCity.isNotEmpty ? toCity : 'City',
                'postcode': toPostcode,
                'country':  'GB',
                'phone':    '07700000000', 'email': '',
              },
              'parcel': {'size': 'sm', 'weight_kg': 1.0},
            },
          }),
        ).timeout(const Duration(seconds: 20));

        final data = jsonDecode(res.body);
        if (res.statusCode == 200 && data['success'] == true) {
          rates = data['rates'] ?? [];
        }
      }

      final validRates = rates
          .where((r) =>
      r is Map &&
          double.tryParse(
              (r['price'] ?? r['amount'] ?? '0').toString()) != null &&
          (double.tryParse(
              (r['price'] ?? r['amount'] ?? '0').toString()) ?? 0) > 0)
          .toList();

      setState(() {
        c.availCount  = validRates.length;
        c.availStatus = validRates.isNotEmpty
            ? _AvailStatus.available
            : _AvailStatus.unavailable;
      });
    } catch (e) {
      setState(() {
        c.availStatus = _AvailStatus.error;
        c.availError  = 'Could not check availability. You can still continue.';
      });
      debugPrint('[Step2] availability check error: $e');
    }
  }

  void _toggleInternational() {
    setState(() {
      c.isInternational   = !c.isInternational;
      c.resetCountry();
      c.pcValid           = false;
      _pcLookedUp         = false;
      _pcError            = '';
      _streetList         = [];
      _selectedStreet     = null;
      c.streetCtrl.clear();
      c.cityCtrl.clear();
      c.pcCtrl.clear();
    });
  }

  void _openCountryPicker() {
    CountryPickerSheet.show(
      context,
      selected: c.selectedCountry,
      onSelected: (country) {
        setState(() {
          c.selectedCountry = country;
          c.selectedState   = null;
          c.stateCtrl.clear();
          c.resetAvailability();
        });
      },
    );
  }

  void _openStatePicker() {
    StatePickerSheet.show(
      context,
      countryName: c.selectedCountry?.name ?? '',
      countryFlag: c.selectedCountry?.flag ?? '',
      states:      c.selectedCountry?.states ?? [],
      selected:    c.selectedState,
      onSelected:  (s) => setState(() => c.selectedState = s),
    );
  }

  // ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final hasStates = c.hasStateDropdown;

    return Form(
      key: c.formKey,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Header ────────────────────────────────────────────────
        const Text('Step 2: Recipient Details',
            style: TextStyle(fontFamily: 'Syne', fontSize: 18,
                fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
        const SizedBox(height: 4),
        const Text('Where should we deliver?',
            style: TextStyle(fontSize: 13, color: Color(0xFF9B9B9B))),
        const SizedBox(height: 16),

        // ── International toggle ──────────────────────────────────
        GestureDetector(
          onTap: _toggleInternational,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: c.isInternational
                  ? const Color(0xFFEFF6FF) : const Color(0xFFFFF5EE),
              border: Border.all(
                color: c.isInternational
                    ? const Color(0xFF0284C7) : const Color(0xFFFFDDCC),
                width: c.isInternational ? 1.5 : 1,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 24, height: 24,
                decoration: BoxDecoration(
                  color: c.isInternational
                      ? const Color(0xFF0284C7) : Colors.white,
                  border: Border.all(
                    color: c.isInternational
                        ? const Color(0xFF0284C7) : const Color(0xFFDDDDDD),
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: c.isInternational
                    ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 12),
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: c.isInternational
                      ? const Color(0xFF0284C7).withOpacity(0.1)
                      : const Color(0xFFFF5A00).withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  c.isInternational
                      ? Icons.public_rounded : Icons.location_on_outlined,
                  size: 20,
                  color: c.isInternational
                      ? const Color(0xFF0284C7) : const Color(0xFFFF5A00),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  c.isInternational
                      ? 'International Delivery' : 'Domestic (UK only)',
                  style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700,
                    color: c.isInternational
                        ? const Color(0xFF0284C7) : const Color(0xFF1A1A1A),
                  ),
                ),
                Text(
                  c.isInternational
                      ? 'Shipping outside the United Kingdom'
                      : 'Tap to send internationally',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF9B9B9B)),
                ),
              ])),
              Text(
                c.isInternational
                    ? (c.selectedCountry?.flag ?? '🌍') : '🇬🇧',
                style: const TextStyle(fontSize: 22),
              ),
            ]),
          ),
        ),

        // ── International info banner ─────────────────────────────
        if (c.isInternational) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              border: Border.all(color: const Color(0xFFFFD54F)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(children: [
              Icon(Icons.info_outline_rounded, size: 15, color: Color(0xFFF59E0B)),
              SizedBox(width: 8),
              Expanded(child: Text(
                'International rates from DHL, FedEx, UPS & more — '
                    'customs may apply at destination.',
                style: TextStyle(fontSize: 11, color: Color(0xFF92400E), height: 1.4),
              )),
            ]),
          ),
        ],

        const SizedBox(height: 18),

        // ── Country picker ────────────────────────────────────────
        if (c.isInternational) ...[
          const _Label('Destination Country *'),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: _openCountryPicker,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(
                  color: c.selectedCountry != null
                      ? const Color(0xFF0284C7) : const Color(0xFFE0E0E0),
                  width: c.selectedCountry != null ? 1.5 : 1,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                if (c.selectedCountry != null) ...[
                  Text(c.selectedCountry!.flag,
                      style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(c.selectedCountry!.name,
                        style: const TextStyle(fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1A1A1A))),
                    Text('${c.selectedCountry!.dialCode} · ${c.selectedCountry!.code}',
                        style: const TextStyle(fontSize: 11,
                            color: Color(0xFF9B9B9B))),
                  ])),
                ] else ...[
                  const Icon(Icons.public_rounded,
                      size: 20, color: Color(0xFFB0B0B0)),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('Select destination country',
                      style: TextStyle(fontSize: 14, color: Color(0xFFB0B0B0)))),
                ],
                const Icon(Icons.keyboard_arrow_down_rounded,
                    size: 20, color: Color(0xFF9B9B9B)),
              ]),
            ),
          ),
          const SizedBox(height: 14),
        ],

        // ── Name + Phone ──────────────────────────────────────────
        Row(children: [
          Expanded(child: _FormField(
            label: 'Full Name *',
            ctrl: c.nameCtrl,
            hint: 'John Smith',
            validator: (v) => (v?.isEmpty ?? true) ? 'Required' : null,
          )),
          const SizedBox(width: 10),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            const _Label('Phone '),
            const SizedBox(height: 6),
            Row(children: [
              GestureDetector(
                onTap: c.isInternational ? _openCountryPicker : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 13),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: const Color(0xFFE0E0E0)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                      c.isInternational
                          ? (c.selectedCountry?.dialCode ?? '+?') : '+44',
                      style: const TextStyle(fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1A1A)),
                    ),
                    if (c.isInternational) ...[
                      const SizedBox(width: 3),
                      const Icon(Icons.arrow_drop_down_rounded,
                          size: 16, color: Color(0xFF9B9B9B)),
                    ],
                  ]),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(child: TextFormField(
                controller: c.phoneCtrl,
                keyboardType: TextInputType.phone,
                style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A1A)),
                decoration: _inputDec('07700 900000'),
              )),
            ]),
          ])),
        ]),

        const SizedBox(height: 12),

        // ── UK Postcode with lookup + street dropdown ─────────────
        if (!c.isInternational) ...[
          _buildUkPostcodeField(),
          const SizedBox(height: 12),
          _buildStreetField(),
        ],

        // ── International ZIP ─────────────────────────────────────
        if (c.isInternational) ...[
          _FormField(
            label: 'ZIP / Postal Code',
            ctrl: c.zipCtrl,
            hint: c.selectedCountry?.code == 'US' ? '10001' : '00000',
          ),
          const SizedBox(height: 12),
          // International street — plain text only
          _FormField(
            label: 'Street / Address Line *',
            ctrl: c.streetCtrl,
            hint: '123 Main Street',
            validator: (v) => (v?.isEmpty ?? true) ? 'Required' : null,
          ),
        ],

        const SizedBox(height: 12),

        // ── Door + City ───────────────────────────────────────────
        Row(children: [
          if (!c.isInternational) ...[
            Expanded(child: _FormField(
              label: 'Door / No. *',
              ctrl: c.doorCtrl,
              hint: '1',
              validator: (v) => (v?.isEmpty ?? true) ? 'Required' : null,
            )),
            const SizedBox(width: 10),
          ],
          Expanded(child: _buildCityField()),
          if (c.isInternational) ...[
            const SizedBox(width: 10),
            Expanded(child: _FormField(
              label: 'Door / No.',
              ctrl: c.doorCtrl,
              hint: '42',
            )),
          ],
        ]),

        // ── State dropdown ────────────────────────────────────────
        if (hasStates) ...[
          const SizedBox(height: 12),
          const _Label('State / Province *'),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: _openStatePicker,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(
                  color: c.selectedState != null
                      ? const Color(0xFF0284C7) : const Color(0xFFE0E0E0),
                  width: c.selectedState != null ? 1.5 : 1,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                Expanded(child: Text(
                  c.selectedState ?? 'Select state / province',
                  style: TextStyle(
                    fontSize: 14,
                    color: c.selectedState != null
                        ? const Color(0xFF1A1A1A) : const Color(0xFFB0B0B0),
                    fontWeight: c.selectedState != null
                        ? FontWeight.w600 : FontWeight.w400,
                  ),
                )),
                const Icon(Icons.keyboard_arrow_down_rounded,
                    size: 20, color: Color(0xFF9B9B9B)),
              ]),
            ),
          ),
        ],

        // ── Free-text state ───────────────────────────────────────
        if (c.isInternational && c.selectedCountry != null && !hasStates) ...[
          const SizedBox(height: 12),
          _FormField(
            label: 'State / Region (optional)',
            ctrl: c.stateCtrl,
            hint: 'e.g. Bavaria',
          ),
        ],

        const SizedBox(height: 20),

        const SizedBox(height: 12),

        // ── AVAILABILITY RESULT BANNER ────────────────────────────
        if (c.availStatus == _AvailStatus.available) ...[
          _AvailBanner(
            icon: Icons.check_circle_rounded,
            iconColor: const Color(0xFF059669),
            bgColor: const Color(0xFFF0FDF4),
            borderColor: const Color(0xFFBBF7D0),
            title: '${c.availCount} service${c.availCount == 1 ? '' : 's'} available',
            subtitle: c.isInternational
                ? 'DHL, FedEx, UPS & more ship to ${c.selectedCountry?.name ?? 'this destination'}'
                : 'Royal Mail, Evri, DPD & more deliver to this postcode',
            titleColor: const Color(0xFF059669),
          ),
        ],

        if (c.availStatus == _AvailStatus.unavailable) ...[
          _AvailBanner(
            icon: Icons.cancel_rounded,
            iconColor: Colors.red,
            bgColor: Colors.red.withOpacity(0.05),
            borderColor: Colors.red.withOpacity(0.2),
            title: 'No services available',
            subtitle: c.isInternational
                ? 'We could not find courier services for ${c.selectedCountry?.name ?? 'this destination'}. Please check the details or try a different country.'
                : 'No couriers found for this postcode. Please check the postcode and try again.',
            titleColor: Colors.red,
          ),
        ],

        if (c.availStatus == _AvailStatus.error) ...[
          _AvailBanner(
            icon: Icons.warning_amber_rounded,
            iconColor: const Color(0xFFF59E0B),
            bgColor: const Color(0xFFFFF8E1),
            borderColor: const Color(0xFFFFD54F),
            title: 'Could not check availability',
            subtitle: c.availError.isNotEmpty
                ? c.availError
                : 'You can still continue — services will be shown in the next step.',
            titleColor: const Color(0xFFF59E0B),
          ),
        ],

        const SizedBox(height: 8),
      ]),
    );
  }

  // ── UK Postcode field with spinner & verified tick ────────────
  Widget _buildUkPostcodeField() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _Label('Postcode *'),
      const SizedBox(height: 6),
      TextFormField(
        controller: c.pcCtrl,
        textCapitalization: TextCapitalization.characters,
        style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A1A)),
        onChanged: _onPostcodeChanged,
        validator: (v) {
          if (v?.isEmpty ?? true) return 'Required';
          if (!_validUkPc(v!)) return 'Enter a valid UK postcode';
          final normalize = (String s) =>
              s.trim().toUpperCase().replaceAll(' ', '');
          if (normalize(v) == normalize(widget.senderPostcode)) {
            return 'Recipient postcode must differ from sender';
          }
          return null;
        },
        decoration: InputDecoration(
          hintText: 'e.g. M1 1AA',
          hintStyle: const TextStyle(color: Color(0xFFB0B0B0), fontSize: 13),
          filled: true,
          fillColor: Colors.white,
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          suffixIcon: _pcLookingUp
              ? const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(
                    color: Color(0xFF0284C7), strokeWidth: 2),
              ))
              : c.pcValid
              ? const Icon(Icons.check_circle_rounded,
              color: Color(0xFF059669), size: 20)
              : null,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                  color: c.pcValid
                      ? const Color(0xFF059669)
                      : _pcError.isNotEmpty
                      ? Colors.red
                      : const Color(0xFFE0E0E0))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
              const BorderSide(color: Color(0xFF0284C7), width: 1.5)),
          errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.red)),
        ),
      ),
      if (_pcError.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(_pcError,
            style: const TextStyle(fontSize: 11, color: Colors.red)),
      ],
      if (c.pcValid && !_pcLookingUp) ...[
        const SizedBox(height: 4),
        const Text(
          '✓ Postcode verified — city and streets auto-filled',
          style: TextStyle(fontSize: 11, color: Color(0xFF059669)),
        ),
      ],
    ]);
  }

  // ── Street field — dropdown when streets available, text otherwise
  Widget _buildStreetField() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _Label('Street / Address Line *'),
      const SizedBox(height: 6),
      if (_streetList.isNotEmpty)
        DropdownButtonFormField<String>(
          value: _selectedStreet,
          isExpanded: true,
          hint: const Text('Select your street',
              style: TextStyle(color: Color(0xFFB0B0B0), fontSize: 14)),
          style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A1A)),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.signpost_outlined,
                size: 17, color: Color(0xFF9B9B9B)),
            filled: true,
            fillColor: Colors.white,
            contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                const BorderSide(color: Color(0xFF0284C7), width: 1.5)),
          ),
          items: [
            ..._streetList.map((s) => DropdownMenuItem(
                value: s,
                child: Text(s, overflow: TextOverflow.ellipsis))),
            const DropdownMenuItem(
              value: '__manual__',
              child: Text('✏️ Enter manually',
                  style: TextStyle(
                      color: Color(0xFF0284C7),
                      fontWeight: FontWeight.w600)),
            ),
          ],
          onChanged: (val) {
            setState(() {
              if (val == '__manual__') {
                _selectedStreet = null;
                _streetList     = [];
                c.streetCtrl.clear();
              } else {
                _selectedStreet    = val;
                c.streetCtrl.text  = val ?? '';
              }
            });
          },
          validator: (v) =>
          (v == null || v.isEmpty || v == '__manual__')
              ? 'Please select a street'
              : null,
        )
      else
        TextFormField(
          controller: c.streetCtrl,
          style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A1A)),
          validator: (v) => (v?.isEmpty ?? true) ? 'Required' : null,
          decoration: InputDecoration(
            hintText: 'e.g. Piccadilly',
            hintStyle:
            const TextStyle(color: Color(0xFFB0B0B0), fontSize: 13),
            prefixIcon: const Icon(Icons.signpost_outlined,
                size: 17, color: Color(0xFF9B9B9B)),
            filled: true,
            fillColor: Colors.white,
            contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                const BorderSide(color: Color(0xFF0284C7), width: 1.5)),
            errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.red)),
          ),
        ),
      if (c.pcValid && _streetList.isEmpty && !_pcLookingUp) ...[
        const SizedBox(height: 4),
        const Text('Type your street name above',
            style: TextStyle(fontSize: 11, color: Color(0xFF9B9B9B))),
      ],
    ]);
  }

  // ── City field — auto-filled with magic wand indicator ────────
  Widget _buildCityField() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _Label('City *'),
      const SizedBox(height: 6),
      TextFormField(
        controller: c.cityCtrl,
        style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A1A)),
        validator: (v) => (v?.isEmpty ?? true) ? 'Required' : null,
        decoration: InputDecoration(
          hintText: c.isInternational ? 'New York' : 'Manchester',
          hintStyle: const TextStyle(color: Color(0xFFB0B0B0), fontSize: 13),
          filled: true,
          fillColor: c.pcValid && !c.isInternational
              ? const Color(0xFFF5FFF5)
              : Colors.white,
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          suffixIcon: c.pcValid &&
              !c.isInternational &&
              c.cityCtrl.text.isNotEmpty
              ? Tooltip(
              message: 'Auto-filled from postcode',
              child: const Icon(Icons.auto_awesome_rounded,
                  size: 16, color: Color(0xFF059669)))
              : null,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                  color: c.pcValid && !c.isInternational
                      ? const Color(0xFF059669).withOpacity(0.5)
                      : const Color(0xFFE0E0E0))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
              const BorderSide(color: Color(0xFF0284C7), width: 1.5)),
          errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.red)),
        ),
      ),
      if (c.pcValid && !c.isInternational && c.cityCtrl.text.isNotEmpty) ...[
        const SizedBox(height: 4),
        const Text('✨ Auto-filled from postcode — you can edit if needed',
            style: TextStyle(fontSize: 11, color: Color(0xFF059669))),
      ],
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Availability banner widget
// ─────────────────────────────────────────────────────────────────────────────

class _AvailBanner extends StatelessWidget {
  final IconData icon;
  final Color iconColor, bgColor, borderColor, titleColor;
  final String title, subtitle;

  const _AvailBanner({
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    required this.borderColor,
    required this.title,
    required this.subtitle,
    required this.titleColor,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: bgColor,
      border: Border.all(color: borderColor),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: iconColor, size: 22),
      const SizedBox(width: 12),
      Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700, color: titleColor)),
        const SizedBox(height: 3),
        Text(subtitle, style: const TextStyle(
            fontSize: 11, color: Color(0xFF6B6B6B), height: 1.4)),
      ])),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

InputDecoration _inputDec(String hint) => InputDecoration(
  hintText: hint,
  hintStyle: const TextStyle(color: Color(0xFFB0B0B0), fontSize: 13),
  filled: true, fillColor: Colors.white,
  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFF6D28D9), width: 1.5)),
  errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Colors.red)),
);

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
          color: Color(0xFF6B6B6B)));
}

class _FormField extends StatelessWidget {
  final String label, hint;
  final TextEditingController ctrl;
  final TextInputType type;
  final String? Function(String?)? validator;

  const _FormField({
    required this.label, required this.ctrl, required this.hint,
    this.type = TextInputType.text, this.validator,
  });

  @override
  Widget build(BuildContext context) => Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
    _Label(label),
    const SizedBox(height: 6),
    TextFormField(
      controller: ctrl, keyboardType: type, validator: validator,
      style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A1A)),
      decoration: _inputDec(hint),
    ),
  ]);
}