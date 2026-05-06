// lib/screens/dropoff_locations_screen.dart

import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' hide Polygon;
import 'dart:ui' as ui;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

// ── Carrier service model ──────────────────────────────────────────────────

class CarrierService {
  final String key, carrier, service;
  const CarrierService({
    required this.key,
    required this.carrier,
    required this.service,
  });
}

const _kServices = [
  CarrierService(key: 'royal_mail',  carrier: 'Royal Mail',  service: 'Tracked 24/48'),
  CarrierService(key: 'evri',        carrier: 'Evri',        service: 'Next Day Parcel'),
  CarrierService(key: 'dpd',         carrier: 'DPD',         service: 'DPD Drop Off'),
  CarrierService(key: 'parcelforce', carrier: 'Parcelforce', service: 'Express 24/48'),
  CarrierService(key: 'yodel',       carrier: 'Yodel',       service: 'Yodel Direct'),
  CarrierService(key: 'inpost',      carrier: 'InPost',      service: 'InPost Locker'),
  CarrierService(key: 'fedex',       carrier: 'FedEx',       service: 'FedEx Drop Off'),
  CarrierService(key: 'ups',         carrier: 'UPS',         service: 'UPS Drop Off'),
];

// ── Drop-off point model ───────────────────────────────────────────────────

class DropOffPoint {
  final String id, name, address, city, postcode, carrier;
  final double lat, lng, distanceKm;
  final String? openingHours;
  const DropOffPoint({
    required this.id, required this.name, required this.address,
    required this.city, required this.postcode, required this.carrier,
    required this.lat, required this.lng, required this.distanceKm,
    this.openingHours,
  });

  LatLng get latLng => LatLng(lat, lng);

  Color get carrierColor {
    switch (carrier.toLowerCase()) {
      case 'royal mail':   return const Color(0xFFE30613);
      case 'evri':         return const Color(0xFF8B5CF6);
      case 'dpd':          return const Color(0xFFE8001C);
      case 'parcelforce':  return const Color(0xFF003087);
      case 'yodel':        return const Color(0xFF6D28D9);
      case 'fedex':        return const Color(0xFF4D148C);
      case 'inpost':       return const Color(0xFFFFB800);
      case 'ups':          return const Color(0xFF351C15);
      default:             return const Color(0xFF6B6B6B);
    }
  }

  String get distanceLabel => distanceKm < 1.0
      ? '${(distanceKm * 1000).round()}m'
      : '${distanceKm.toStringAsFixed(1)}km';
}

// ═════════════════════════════════════════════════════════════════════════════
// MAIN SCREEN
// ═════════════════════════════════════════════════════════════════════════════

class DropOffLocationsScreen extends StatefulWidget {
  const DropOffLocationsScreen({super.key});
  @override
  State<DropOffLocationsScreen> createState() => _DropOffState();
}

class _DropOffState extends State<DropOffLocationsScreen> {
  final _pcCtrl     = TextEditingController();
  final _mapCtrl    = MapController();
  final _scrollCtrl = ScrollController();

  bool    _pcValid   = false;
  bool    _pcLoading = false;
  String  _pcError   = '';
  double? _userLat, _userLng;
  String  _userCity  = '';

  int? _selectedIdx;
  CarrierService? get _selected =>
      _selectedIdx != null ? _kServices[_selectedIdx!] : null;

  List<DropOffPoint> _points = [];
  bool   _loading            = false;
  String _error              = '';
  bool   _hasResults         = false;
  bool   _mapExpanded        = false;
  DropOffPoint? _activePoint;

  // ── Carrier asset map ─────────────────────────────────────────
  static const _carrierAssets = <String, String>{
    'Royal Mail':  'assets/carriers/royal_mail.png',
    'Evri':        'assets/carriers/evri.png',
    'DPD':         'assets/carriers/dpd.png',
    'Parcelforce': 'assets/carriers/parcelforce.png',
    'Yodel':       'assets/carriers/yodel.png',
    'FedEx':       'assets/carriers/fedex.png',
    'InPost':      'assets/carriers/globalpost.png',
    'UPS':         'assets/carriers/ups.png',
  };

  @override
  void dispose() {
    _pcCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Postcode validation ───────────────────────────────────────
  bool _validUkPc(String v) =>
      RegExp(r'^[A-Z]{1,2}[0-9][A-Z0-9]? ?[0-9][A-Z]{2}$',
          caseSensitive: false).hasMatch(v.trim());

  // ── Geocode postcode via postcodes.io ─────────────────────────
  Future<void> _geocode() async {
    final pc = _pcCtrl.text.trim().toUpperCase().replaceAll(' ', '');
    setState(() {
      _pcLoading = true; _pcError = ''; _hasResults = false;
      _points = []; _activePoint = null;
    });
    try {
      final res = await http
          .get(Uri.parse('https://api.postcodes.io/postcodes/$pc'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body)['result'];
        setState(() {
          _userLat  = (d['latitude']  as num).toDouble();
          _userLng  = (d['longitude'] as num).toDouble();
          _userCity = d['admin_district'] ?? '';
          _pcValid  = true;
          _pcError  = '';
        });
      } else {
        setState(() { _pcValid = false; _pcError = 'Postcode not found.'; });
      }
    } catch (_) {
      setState(() { _pcValid = false; _pcError = 'Network error.'; });
    }
    setState(() => _pcLoading = false);
  }

  // ── Fetch via Overpass API ────────────────────────────────────
  Future<void> _fetch() async {
    if (_userLat == null || _selected == null) return;
    setState(() {
      _loading = true; _error = ''; _points = [];
      _hasResults = false; _activePoint = null; _mapExpanded = false;
    });
    final lat     = _userLat!;
    final lng     = _userLng!;
    final carrier = _selected!.carrier;
    try {
      final query = _buildQuery(carrier, lat, lng, 3000);
      final res = await http.post(
        Uri.parse('https://overpass-api.de/api/interpreter'),
        body: query,
      ).timeout(const Duration(seconds: 18));

      List<DropOffPoint> pts = [];
      if (res.statusCode == 200) {
        for (final el in (jsonDecode(res.body)['elements'] as List? ?? [])) {
          final eLat = (el['lat'] as num?)?.toDouble()
              ?? (el['center']?['lat'] as num?)?.toDouble();
          final eLng = (el['lon'] as num?)?.toDouble()
              ?? (el['center']?['lon'] as num?)?.toDouble();
          if (eLat == null || eLng == null) continue;
          final d = _dist(lat, lng, eLat, eLng);
          if (d > 5.0) continue;
          final t = el['tags'] as Map? ?? {};
          pts.add(DropOffPoint(
            id:           'osm_${el['id']}',
            name:         (t['name'] ?? t['brand'] ?? _defaultName(carrier)).toString(),
            address:      _addr(t),
            city:         (t['addr:city'] ?? t['addr:town'] ?? _userCity).toString(),
            postcode:     (t['addr:postcode'] ?? '').toString(),
            carrier:      carrier,
            lat:          eLat,
            lng:          eLng,
            distanceKm:   d,
            openingHours: t['opening_hours']?.toString(),
          ));
          if (pts.length >= 20) break;
        }
      }
      pts.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
      if (pts.isEmpty) pts = _mock(carrier, lat, lng);

      setState(() { _points = pts; _hasResults = true; _loading = false; });

      if (pts.isNotEmpty) {
        await Future.delayed(const Duration(milliseconds: 300));
        _mapCtrl.move(LatLng(lat, lng), 14.0);
      }
    } catch (_) {
      final fb = _mock(carrier, lat, lng);
      setState(() {
        _points     = fb;
        _hasResults = fb.isNotEmpty;
        _error      = fb.isEmpty ? 'Could not load. Please try again.' : '';
        _loading    = false;
      });
      if (fb.isNotEmpty) {
        await Future.delayed(const Duration(milliseconds: 300));
        _mapCtrl.move(LatLng(lat, lng), 14.0);
      }
    }
  }

  String _buildQuery(String carrier, double lat, double lng, int r) {
    final c = '$lat,$lng';
    final t = <String>[];
    switch (carrier.toLowerCase()) {
      case 'royal mail':
        t.addAll([
          'node["amenity"="post_office"](around:$r,$c);',
          'way["amenity"="post_office"](around:$r,$c);',
          'node["brand"="Royal Mail"](around:$r,$c);',
          'node["operator"="Royal Mail"](around:$r,$c);',
        ]);
      case 'evri':
        t.addAll([
          'node["brand"="Evri"](around:$r,$c);',
          'node["brand"="Hermes"](around:$r,$c);',
          'node["operator"="Evri"](around:$r,$c);',
        ]);
      case 'dpd':
        t.addAll([
          'node["brand"="DPD"](around:$r,$c);',
          'node["operator"="DPD"](around:$r,$c);',
        ]);
      case 'inpost':
        t.addAll([
          'node["brand"="InPost"](around:$r,$c);',
          'node["amenity"="parcel_locker"](around:$r,$c);',
        ]);
      case 'yodel':
        t.addAll([
          'node["brand"="Yodel"](around:$r,$c);',
          'node["operator"="Yodel"](around:$r,$c);',
        ]);
      case 'fedex':
        t.addAll([
          'node["brand"="FedEx"](around:$r,$c);',
          'node["operator"="FedEx"](around:$r,$c);',
        ]);
      case 'ups':
        t.addAll([
          'node["brand"="UPS"](around:$r,$c);',
          'node["operator"="UPS"](around:$r,$c);',
        ]);
      default:
        t.addAll([
          'node["amenity"="post_office"](around:$r,$c);',
          'node["amenity"="parcel_locker"](around:$r,$c);',
        ]);
    }
    return '[out:json][timeout:15];(${t.join('')});out center;';
  }

  String _addr(Map t) {
    final p = <String>[];
    if (t['addr:housenumber'] != null) p.add(t['addr:housenumber'].toString());
    if (t['addr:street']      != null) p.add(t['addr:street'].toString());
    return p.join(' ');
  }

  String _defaultName(String c) => '$c Drop-Off Point';

  double _dist(double la1, double lo1, double la2, double lo2) {
    final dLa = (la2 - la1) * math.pi / 180;
    final dLo = (lo2 - lo1) * math.pi / 180;
    final a   = math.sin(dLa / 2) * math.sin(dLa / 2)
        + math.cos(la1 * math.pi / 180) * math.cos(la2 * math.pi / 180)
            * math.sin(dLo / 2) * math.sin(dLo / 2);
    return 6371 * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  List<DropOffPoint> _mock(String carrier, double lat, double lng) {
    final rng   = math.Random(37);
    final names = _mockNames(carrier);
    final pts   = <DropOffPoint>[];
    for (int i = 0; i < names.length; i++) {
      final dLa = (rng.nextDouble() - 0.5) * 0.04;
      final dLo = (rng.nextDouble() - 0.5) * 0.06;
      pts.add(DropOffPoint(
        id:           'mock_$i',
        name:         names[i][0],
        address:      names[i][1],
        city:         _userCity,
        postcode:     _pcCtrl.text.trim().toUpperCase(),
        carrier:      carrier,
        lat:          lat + dLa,
        lng:          lng + dLo,
        distanceKm:   _dist(lat, lng, lat + dLa, lng + dLo),
        openingHours: names[i].length > 2 ? names[i][2] : null,
      ));
    }
    pts.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    return pts;
  }

  List<List<String>> _mockNames(String c) {
    switch (c.toLowerCase()) {
      case 'royal mail':
        return [
          ['Post Office – High Street',    '12 High Street',         'Mon-Fri 9am-5:30pm, Sat 9am-12:30pm'],
          ['Post Office – Market Square',  '3 Market Square',        'Mon-Sat 8:30am-6pm'],
          ['Royal Mail Delivery Office',   'Industrial Estate Road', 'Mon-Fri 7am-7pm, Sat 7am-1pm'],
          ['Post Office – Church Road',    '67 Church Road',         'Mon-Sun 7am-10pm'],
          ['Post Office – London Road',    '145 London Road',        'Mon-Sat 6am-8pm'],
        ];
      case 'evri':
        return [
          ['Evri ParcelShop – Tesco Express',     '8 Victoria Road',  'Mon-Sun 6am-11pm'],
          ['Evri ParcelShop – Co-op',             '23 Maple Avenue',  'Mon-Sun 7am-10pm'],
          ['Evri ParcelShop – Newsagent',         '99 Station Road',  'Mon-Sat 6am-9pm'],
          ['Evri ParcelShop – Convenience Store', '15 Park Lane',     'Mon-Sun 7am-11pm'],
          ['Evri ParcelShop – Spar',              '34 Queens Street', 'Mon-Sun 6:30am-10pm'],
        ];
      case 'dpd':
        return [
          ['DPD Pickup – Sainsburys Local', '5 Bridge Street',    'Mon-Sun 7am-11pm'],
          ['DPD Pickup – Boots',            '2 The Parade',       'Mon-Sat 8:30am-6pm'],
          ['DPD Pickup – WHSmith',          '14 Shopping Centre', 'Mon-Sat 9am-5:30pm'],
          ['DPD Pickup – Argos',            '27 Retail Park',     'Mon-Sat 9am-8pm'],
        ];
      case 'inpost':
        return [
          ['InPost Locker – Tesco Car Park', 'Tesco Extra, Ring Road', '24/7'],
          ['InPost Locker – Asda',           'Asda Superstore',        '24/7'],
          ['InPost Locker – Morrisons',      'Morrisons Car Park',     '24/7'],
          ['InPost Locker – Train Station',  'Central Station',        '24/7'],
          ['InPost Locker – Retail Park',    'Riverside Retail Park',  '24/7'],
        ];
      case 'ups':
        return [
          ['UPS Access Point – Convenience Store', '5 High Road',     'Mon-Sat 8am-8pm'],
          ['UPS Access Point – Newsagent',         '12 Station Road', 'Mon-Sun 7am-9pm'],
          ['UPS Access Point – Supermarket',       '34 London Road',  'Mon-Sun 7am-10pm'],
        ];
      default:
        return [
          ['$c Drop-Off Point 1', '10 Main Street', 'Mon-Sat 9am-6pm'],
          ['$c Drop-Off Point 2', '45 Park Road',   'Mon-Fri 8am-7pm'],
          ['$c Drop-Off Point 3', '22 Church Lane', 'Mon-Sun 8am-9pm'],
        ];
    }
  }

  // ── Show map app picker ───────────────────────────────────────
  Future<void> _showMapPicker(DropOffPoint p) async {
    final name = Uri.encodeComponent(p.name);
    final lat  = p.lat;
    final lng  = p.lng;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 36, height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
                color: const Color(0xFFE0E0E0),
                borderRadius: BorderRadius.circular(2)),
          ),
          const Text('Get Directions via', style: TextStyle(
             fontSize: 15,
            fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A),
          )),
          const SizedBox(height: 16),
          _MapAppTile(
            icon: Icons.map_rounded,
            color: const Color(0xFF4285F4),
            label: 'Google Maps',
            subtitle: 'Opens in Google Maps app or browser',
            onTap: () async {
              Navigator.pop(context);
              final appUrl = Uri.parse(
                  'comgooglemaps://?q=$name&center=$lat,$lng&zoom=16');
              final webUrl = Uri.parse(
                  'https://www.google.com/maps/search/?api=1&query=$lat,$lng');
              if (await canLaunchUrl(appUrl)) {
                await launchUrl(appUrl);
              } else {
                await launchUrl(webUrl, mode: LaunchMode.externalApplication);
              }
            },
          ),
          const SizedBox(height: 10),
          _MapAppTile(
            icon: Icons.apple_rounded,
            color: const Color(0xFF1A1A1A),
            label: 'Apple Maps',
            subtitle: 'Opens in Apple Maps',
            onTap: () async {
              Navigator.pop(context);
              final url = Uri.parse(
                  'https://maps.apple.com/?q=$name&ll=$lat,$lng&z=16');
              await launchUrl(url, mode: LaunchMode.externalApplication);
            },
          ),
          const SizedBox(height: 10),
          _MapAppTile(
            icon: Icons.navigation_rounded,
            color: const Color(0xFF05C8F7),
            label: 'Waze',
            subtitle: 'Opens in Waze',
            onTap: () async {
              Navigator.pop(context);
              final wazeApp = Uri.parse('waze://?ll=$lat,$lng&navigate=yes');
              final wazeWeb = Uri.parse(
                  'https://waze.com/ul?ll=$lat,$lng&navigate=yes');
              if (await canLaunchUrl(wazeApp)) {
                await launchUrl(wazeApp);
              } else {
                await launchUrl(wazeWeb, mode: LaunchMode.externalApplication);
              }
            },
          ),
        ]),
      ),
    );
  }

  void _onMarkerTap(DropOffPoint p) {
    setState(() => _activePoint = p);
    _mapCtrl.move(LatLng(p.lat, p.lng), 15.5);
    _showDetail(p);
  }

  // ─────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F7),
      body: SafeArea(child: Column(children: [

        // ── Top nav ───────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
          ),
          child: Row(children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: const Icon(Icons.arrow_back_ios, size: 16, color: Color(0xFF6B6B6B)),
            ),
            const SizedBox(width: 10),
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF059669),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.store_mall_directory_rounded,
                  color: Colors.white, size: 17),
            ),
            const SizedBox(width: 10),
            const Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Drop Off Locations', style: TextStyle(
                   fontSize: 17,
                  fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
              Text('Find nearby parcel drop-off points',
                  style: TextStyle(fontSize: 11, color: Color(0xFF9B9B9B))),
            ])),
          ]),
        ),

        Expanded(child: SingleChildScrollView(
          controller: _scrollCtrl,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // ── Search panel ──────────────────────────────────
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                const Text('Your Postcode', style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600,
                    color: Color(0xFF6B6B6B))),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _pcCtrl,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                      letterSpacing: 1.0, color: Color(0xFF1A1A1A)),
                  onChanged: (v) {
                    final up = v.toUpperCase();
                    if (v != up) {
                      _pcCtrl.value = _pcCtrl.value.copyWith(
                          text: up,
                          selection: TextSelection.collapsed(offset: up.length));
                    }
                    setState(() {
                      _pcValid = false; _hasResults = false; _pcError = '';
                    });
                    if (_validUkPc(up)) _geocode();
                  },
                  decoration: InputDecoration(
                    hintText: 'e.g. SW1A 1AA',
                    hintStyle: const TextStyle(color: Color(0xFFB0B0B0),
                        fontSize: 13, fontWeight: FontWeight.w400, letterSpacing: 0),
                    filled: true, fillColor: const Color(0xFFF8F8F8),
                    prefixIcon: const Icon(Icons.location_on_outlined,
                        color: Color(0xFF059669), size: 18),
                    suffixIcon: _pcLoading
                        ? const Padding(padding: EdgeInsets.all(12),
                        child: SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Color(0xFF059669))))
                        : _pcValid
                        ? const Icon(Icons.check_circle_rounded,
                        color: Color(0xFF059669), size: 20)
                        : null,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 13),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                            color: _pcError.isNotEmpty
                                ? Colors.red
                                : _pcValid
                                ? const Color(0xFF059669)
                                : const Color(0xFFE0E0E0),
                            width: _pcValid ? 1.5 : 1)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                            color: Color(0xFF059669), width: 1.5)),
                  ),
                ),
                if (_pcError.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(_pcError,
                      style: const TextStyle(fontSize: 11, color: Colors.red)),
                ],
                if (_pcValid && _userCity.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('📍 $_userCity', style: const TextStyle(
                      fontSize: 11, color: Color(0xFF059669),
                      fontWeight: FontWeight.w500)),
                ],

                const SizedBox(height: 14),

                const Text('Parcel Service', style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600,
                    color: Color(0xFF6B6B6B))),
                const SizedBox(height: 6),

                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F8F8),
                    border: Border.all(
                        color: _selectedIdx != null
                            ? const Color(0xFF059669)
                            : const Color(0xFFE0E0E0),
                        width: _selectedIdx != null ? 1.5 : 1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: _selectedIdx,
                      isExpanded: true,
                      dropdownColor: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded,
                          color: Color(0xFF6B6B6B)),
                      hint: const Row(children: [
                        Icon(Icons.local_shipping_outlined,
                            size: 16, color: Color(0xFFB0B0B0)),
                        SizedBox(width: 8),
                        Text('Select a carrier service',
                            style: TextStyle(
                                color: Color(0xFFB0B0B0), fontSize: 13)),
                      ]),

                      // ── Items with logo ───────────────────
                      items: List.generate(_kServices.length, (i) {
                        final s         = _kServices[i];
                        final assetPath = _carrierAssets[s.carrier];
                        return DropdownMenuItem<int>(
                          value: i,
                          child: Row(children: [
                            _DropdownLogo(
                                carrier: s.carrier, assetPath: assetPath),
                            const SizedBox(width: 10),
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(s.carrier, style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600,
                                    color: Color(0xFF1A1A1A))),
                                Text(s.service, style: const TextStyle(
                                    fontSize: 11, color: Color(0xFF9B9B9B))),
                              ],
                            )),
                          ]),
                        );
                      }),

                      // ── Selected item with logo ───────────
                      selectedItemBuilder: (_) =>
                          List.generate(_kServices.length, (i) {
                            final s         = _kServices[i];
                            final assetPath = _carrierAssets[s.carrier];
                            return Align(
                              alignment: Alignment.centerLeft,
                              child: Row(children: [
                                _DropdownLogo(
                                    carrier: s.carrier, assetPath: assetPath),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text('${s.carrier} · ${s.service}',
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 13, fontWeight: FontWeight.w600,
                                          color: Color(0xFF1A1A1A))),
                                ),
                              ]),
                            );
                          }),

                      onChanged: (v) => setState(() {
                        _selectedIdx = v;
                        _hasResults  = false;
                        _points      = [];
                        _mapExpanded = false;
                      }),
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                SizedBox(
                  width: double.infinity, height: 50,
                  child: ElevatedButton(
                    onPressed: (_pcValid && _selectedIdx != null && !_loading)
                        ? _fetch
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFFBBF7D0),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(
                           fontSize: 15,
                          fontWeight: FontWeight.w700),
                    ),
                    child: _loading
                        ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(width: 18, height: 18,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2.5)),
                          SizedBox(width: 10),
                          Text('Finding locations…'),
                        ])
                        : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_rounded,
                              size: 18, color: Colors.white),
                          SizedBox(width: 8),
                          Text('Find Drop-Off Points'),
                        ]),
                  ),
                ),
              ]),
            ),

            // ── Error banner ──────────────────────────────────
            if (_error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.05),
                    border: Border.all(color: Colors.red.withOpacity(0.2)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(children: [
                    const Icon(Icons.error_outline_rounded,
                        color: Colors.red, size: 15),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.red))),
                  ]),
                ),
              ),

            // ── Map + results ─────────────────────────────────
            if (_hasResults && _points.isNotEmpty) ...[
              const SizedBox(height: 12),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  const Icon(Icons.location_on_rounded,
                      color: Color(0xFF059669), size: 15),
                  const SizedBox(width: 6),
                  Expanded(child: Text(
                    '${_points.length} ${_selected?.carrier} locations near '
                        '${_pcCtrl.text.trim().toUpperCase()}',
                    style: const TextStyle(fontSize: 12,
                        fontWeight: FontWeight.w600, color: Color(0xFF059669)),
                  )),
                  GestureDetector(
                    onTap: () =>
                        setState(() => _mapExpanded = !_mapExpanded),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF059669).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(_mapExpanded
                            ? Icons.fullscreen_exit_rounded
                            : Icons.fullscreen_rounded,
                            size: 16, color: const Color(0xFF059669)),
                        const SizedBox(width: 4),
                        Text(_mapExpanded ? 'Collapse' : 'Full Screen',
                            style: const TextStyle(fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF059669))),
                      ]),
                    ),
                  ),
                ]),
              ),

              const SizedBox(height: 8),

              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                height: _mapExpanded
                    ? MediaQuery.of(context).size.height * 0.72
                    : 280,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFDDDDDD)),
                  boxShadow: [BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 12, offset: const Offset(0, 4))],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(children: [

                  FlutterMap(
                    mapController: _mapCtrl,
                    options: MapOptions(
                      initialCenter: _userLat != null
                          ? LatLng(_userLat!, _userLng!)
                          : const LatLng(51.5, -0.12),
                      initialZoom: 14.0,
                      minZoom: 10.0,
                      maxZoom: 20.0,
                      interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.all),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                        'https://mt{s}.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
                        subdomains: const ['0', '1', '2', '3'],
                        userAgentPackageName: 'com.swiftlabel.app',
                        maxZoom: 20,
                      ),
                      MarkerLayer(markers: [
                        if (_userLat != null)
                          Marker(
                            point: LatLng(_userLat!, _userLng!),
                            width: 44, height: 44,
                            child: _UserDot(),
                          ),
                        ..._points.asMap().entries.map((e) {
                          final i      = e.key;
                          final p      = e.value;
                          final active = _activePoint?.id == p.id;
                          return Marker(
                            point:     p.latLng,
                            width:     active ? 52 : 40,
                            height:    active ? 60 : 48,
                            alignment: Alignment.topCenter,
                            child: GestureDetector(
                              onTap: () => _onMarkerTap(p),
                              child: _MapPin(
                                  rank: i + 1,
                                  color: p.carrierColor,
                                  active: active),
                            ),
                          );
                        }),
                      ]),
                    ],
                  ),

                  Positioned(right: 10, bottom: 10,
                    child: Column(children: [
                      _MapBtn(Icons.add, () => _mapCtrl.move(
                          _mapCtrl.camera.center,
                          (_mapCtrl.camera.zoom + 1).clamp(10, 20))),
                      const SizedBox(height: 4),
                      _MapBtn(Icons.remove, () => _mapCtrl.move(
                          _mapCtrl.camera.center,
                          (_mapCtrl.camera.zoom - 1).clamp(10, 20))),
                      const SizedBox(height: 4),
                      _MapBtn(Icons.my_location_rounded, () {
                        if (_userLat != null) {
                          _mapCtrl.move(
                              LatLng(_userLat!, _userLng!), 14.5);
                        }
                      }),
                    ]),
                  ),

                  if (_activePoint != null)
                    Positioned(left: 10, bottom: 10, right: 60,
                      child: GestureDetector(
                        onTap: () => _showDetail(_activePoint!),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [BoxShadow(
                                color: Colors.black.withOpacity(0.12),
                                blurRadius: 10,
                                offset: const Offset(0, 3))],
                            border: Border.all(
                                color: _activePoint!.carrierColor
                                    .withOpacity(0.4)),
                          ),
                          child: Row(children: [
                            Container(width: 8, height: 8,
                                decoration: BoxDecoration(
                                    color: _activePoint!.carrierColor,
                                    shape: BoxShape.circle)),
                            const SizedBox(width: 8),
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_activePoint!.name,
                                    style: const TextStyle(fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF1A1A1A)),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                Text(_activePoint!.distanceLabel,
                                    style: const TextStyle(fontSize: 10,
                                        color: Color(0xFF059669),
                                        fontWeight: FontWeight.w600)),
                              ],
                            )),
                            const Icon(Icons.chevron_right_rounded,
                                size: 16, color: Color(0xFF9B9B9B)),
                          ]),
                        ),
                      ),
                    ),
                ]),
              ),

              const SizedBox(height: 16),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  const Text('Nearby Locations', style: TextStyle(
                       fontSize: 14,
                      fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
                  const Spacer(),
                  Text('${_points.length} found',
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF9B9B9B))),
                ]),
              ),
              const SizedBox(height: 8),

              ..._points.asMap().entries.map((e) => Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: _PointCard(
                  point:  e.value,
                  rank:   e.key + 1,
                  active: _activePoint?.id == e.value.id,
                  onTap: () {
                    setState(() => _activePoint = e.value);
                    _mapCtrl.move(e.value.latLng, 15.5);
                    _scrollCtrl.animateTo(0,
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOut);
                    _showDetail(e.value);
                  },
                  onMaps: () => _showMapPicker(e.value),
                ),
              )),

              const SizedBox(height: 24),
            ],

            // ── Empty state ───────────────────────────────────
            if (!_hasResults && !_loading && _error.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(32, 40, 32, 40),
                  child: Column(children: [
                    Container(width: 80, height: 80,
                        decoration: const BoxDecoration(
                            color: Color(0xFFF0FDF4), shape: BoxShape.circle),
                        child: const Icon(Icons.store_mall_directory_rounded,
                            size: 40, color: Color(0xFF059669))),
                    const SizedBox(height: 18),
                    const Text('Find Drop-Off Points', style: TextStyle(
                         fontSize: 16,
                        fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
                    const SizedBox(height: 8),
                    const Text(
                      'Enter your postcode and choose a carrier\n'
                          'to see nearby drop-off locations on the map.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 13, color: Color(0xFF9B9B9B), height: 1.6),
                    ),
                  ]),
                ),
              ),
          ]),
        )),
      ])),
    );
  }

  // ── Detail bottom sheet ───────────────────────────────────────
  void _showDetail(DropOffPoint p) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 36, height: 4,
              decoration: BoxDecoration(
                  color: const Color(0xFFE0E0E0),
                  borderRadius: BorderRadius.circular(2)))),
          Row(children: [
            Container(width: 46, height: 46,
                decoration: BoxDecoration(
                    color: p.carrierColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.store_mall_directory_rounded,
                    color: p.carrierColor, size: 24)),
            const SizedBox(width: 12),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name, style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1A1A))),
              Text(p.carrier, style: TextStyle(fontSize: 12,
                  color: p.carrierColor, fontWeight: FontWeight.w600)),
            ])),
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color: const Color(0xFF059669).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20)),
                child: Text(p.distanceLabel, style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700,
                    color: Color(0xFF059669)))),
          ]),
          const SizedBox(height: 16),
          _Tile(Icons.location_on_outlined, 'Address',
              p.address.isNotEmpty
                  ? '${p.address}${p.postcode.isNotEmpty ? ", ${p.postcode}" : ""}'
                  : 'Near ${_pcCtrl.text.trim().toUpperCase()}'),
          if (p.openingHours != null)
            _Tile(Icons.access_time_rounded, 'Opening Hours', p.openingHours!),
          _Tile(Icons.local_shipping_outlined, 'Carrier',
              '${p.carrier} · ${_selected?.service ?? ""}'),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _showMapPicker(p);
              },
              icon: const Icon(Icons.map_rounded, size: 16,
                  color: Color(0xFF059669)),
              label: const Text('Get Directions'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF059669),
                side: const BorderSide(color: Color(0xFF059669)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            )),
            const SizedBox(width: 12),
            Expanded(child: ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.check_rounded, size: 16, color: Colors.white),
              label: const Text('Select'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
                foregroundColor: Colors.white, elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                textStyle: const TextStyle(
                     fontWeight: FontWeight.w700),
              ),
            )),
          ]),
        ]),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// SMALL WIDGETS
// ═════════════════════════════════════════════════════════════════════════════

// ── Carrier logo in dropdown ──────────────────────────────────────────────

class _DropdownLogo extends StatelessWidget {
  final String  carrier;
  final String? assetPath;
  const _DropdownLogo({required this.carrier, required this.assetPath});

  static const _abbr = <String, String>{
    'Royal Mail':  'RM',
    'Evri':        'EV',
    'DPD':         'DPD',
    'Parcelforce': 'PF',
    'Yodel':       'YDL',
    'FedEx':       'FedEx',
    'InPost':      'IN',
    'UPS':         'UPS',
  };

  static const _colors = <String, Color>{
    'Royal Mail':  Color(0xFFE30613),
    'Evri':        Color(0xFF8B5CF6),
    'DPD':         Color(0xFFE8001C),
    'Parcelforce': Color(0xFF003087),
    'Yodel':       Color(0xFF6D28D9),
    'FedEx':       Color(0xFF4D148C),
    'InPost':      Color(0xFFFFB800),
    'UPS':         Color(0xFF351C15),
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[carrier] ?? const Color(0xFF6B6B6B);
    final abbr  = _abbr[carrier]
        ?? carrier.substring(0, carrier.length > 2 ? 2 : carrier.length);
    final fs    = abbr.length >= 5 ? 7.0 : abbr.length == 4 ? 8.0 : 10.0;

    return Container(
      width: 40, height: 28,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      padding: const EdgeInsets.all(3),
      child: assetPath != null
          ? Image.asset(
        assetPath!,
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

// ── Map app picker tile ───────────────────────────────────────────────────

class _MapAppTile extends StatelessWidget {
  final IconData     icon;
  final Color        color;
  final String       label, subtitle;
  final VoidCallback onTap;
  const _MapAppTile({required this.icon, required this.color,
    required this.label, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8F8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Row(children: [
        Container(width: 40, height: 40,
            decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 20)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 14,
                  fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
              Text(subtitle, style: const TextStyle(
                  fontSize: 11, color: Color(0xFF9B9B9B))),
            ])),
        const Icon(Icons.chevron_right_rounded,
            color: Color(0xFFB0B0B0), size: 18),
      ]),
    ),
  );
}

// ── User location blue dot ────────────────────────────────────────────────

class _UserDot extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(child: Container(
    width: 22, height: 22,
    decoration: BoxDecoration(
      color: const Color(0xFF1565C0),
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 3),
      boxShadow: [BoxShadow(
          color: const Color(0xFF1565C0).withOpacity(0.4),
          blurRadius: 8, spreadRadius: 2)],
    ),
  ));
}

// ── Drop-off pin marker ───────────────────────────────────────────────────

class _MapPin extends StatelessWidget {
  final int rank; final Color color; final bool active;
  const _MapPin({required this.rank, required this.color, required this.active});

  @override
  Widget build(BuildContext context) {
    final size = active ? 52.0 : 40.0;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: size * 0.7, height: size * 0.7,
        decoration: BoxDecoration(
          color: color, shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: active ? 3 : 2),
          boxShadow: [BoxShadow(color: color.withOpacity(0.45),
              blurRadius: active ? 12 : 6, offset: const Offset(0, 3))],
        ),
        child: Center(child: Text('$rank', style: TextStyle(
            fontSize: active ? 13 : 11,
            fontWeight: FontWeight.w900, color: Colors.white))),
      ),
      CustomPaint(size: const Size(10, 6), painter: _PinTail(color)),
    ]);
  }
}

class _PinTail extends CustomPainter {
  final Color color;
  const _PinTail(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }
  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

// ── Zoom control button ───────────────────────────────────────────────────

class _MapBtn extends StatelessWidget {
  final IconData icon; final VoidCallback onTap;
  const _MapBtn(this.icon, this.onTap);

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 34, height: 34,
      decoration: BoxDecoration(color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(0.15), blurRadius: 4)]),
      child: Icon(icon, size: 18, color: const Color(0xFF1A1A1A)),
    ),
  );
}

// ── Drop-off point list card ──────────────────────────────────────────────

class _PointCard extends StatelessWidget {
  final DropOffPoint point; final int rank; final bool active;
  final VoidCallback onTap, onMaps;
  const _PointCard({required this.point, required this.rank,
    required this.active, required this.onTap, required this.onMaps});

  @override
  Widget build(BuildContext context) {
    final p = point;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: active ? p.carrierColor.withOpacity(0.04) : Colors.white,
          border: Border.all(
              color: active
                  ? p.carrierColor.withOpacity(0.4)
                  : const Color(0xFFEEEEEE),
              width: active ? 1.5 : 1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Container(width: 34, height: 34,
              decoration: BoxDecoration(
                  color: p.carrierColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(9)),
              child: Center(child: Text('$rank', style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800,
                  color: p.carrierColor)))),
          const SizedBox(width: 12),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.name, style: const TextStyle(fontSize: 13,
                fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A)),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(p.address.isNotEmpty ? p.address : p.city,
                style: const TextStyle(fontSize: 11, color: Color(0xFF6B6B6B)),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            if (p.openingHours != null) ...[
              const SizedBox(height: 2),
              Row(children: [
                const Icon(Icons.access_time_rounded,
                    size: 10, color: Color(0xFF9B9B9B)),
                const SizedBox(width: 3),
                Expanded(child: Text(p.openingHours!, style: const TextStyle(
                    fontSize: 10, color: Color(0xFF9B9B9B)),
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
            ],
          ])),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: const Color(0xFF059669).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20)),
                child: Text(p.distanceLabel, style: const TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w700,
                    color: Color(0xFF059669)))),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: onMaps,
              child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(8)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.map_rounded, size: 12,
                        color: Color(0xFF0284C7)),
                    SizedBox(width: 3),
                    Text('Maps', style: TextStyle(fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0284C7))),
                  ])),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ── Detail info tile ──────────────────────────────────────────────────────

class _Tile extends StatelessWidget {
  final IconData icon; final String label, value;
  const _Tile(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(children: [
      Container(width: 32, height: 32,
          decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 16, color: const Color(0xFF059669))),
      const SizedBox(width: 10),
      Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(fontSize: 10, color: Color(0xFF9B9B9B))),
        Text(value, style: const TextStyle(fontSize: 12,
            fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A))),
      ])),
    ]),
  );
}