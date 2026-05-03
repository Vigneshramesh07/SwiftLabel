import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:swift_label/screens/send_parcel.dart';
import 'package:swift_label/screens/shipmentDetails_screen.dart';
import 'package:swift_label/screens/track_parcel.dart';
import 'package:swift_label/screens/your_shipment_screen.dart';
import '../providers/auth_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/parcel_provider.dart';
import '../widgets/marquee_banner.dart';
import 'admin_dashboard_screen.dart';
import 'dropoff_locations_screen.dart';
import 'profile_screen.dart';
import 'bulk_order_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PriceResult model
// ─────────────────────────────────────────────────────────────────────────────

class PriceResult {
  final String carrier, service, days, currency, carrierImage;
  final double price;
  const PriceResult({
    required this.carrier,
    required this.service,
    required this.price,
    required this.days,
    this.currency     = 'GBP',
    this.carrierImage = '',
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Carrier colour lookup (shared by calculator UI)
// ─────────────────────────────────────────────────────────────────────────────

const _kCarrierColors = <String, Color>{
  'Royal Mail':                   Color(0xFFE30613),
  'Parcelforce Royal Mail':       Color(0xFF003087),
  'Evri':                         Color(0xFF8B5CF6),
  'DPD UK':                       Color(0xFFE8001C),
  'DHL Express MyDHL API':        Color(0xFFFFC300),
  'UPS':                          Color(0xFF351C15),
  'FedEx UK':                     Color(0xFF4D148C),
  'Yodel':                        Color(0xFF6D28D9),
  'GlobalPost':                   Color(0xFF0284C7),
  'Stamps.com':                   Color(0xFF0284C7),
  'ShipStation Carrier Services': Color(0xFF0284C7),
  'InPost':                       Color(0xFFF5C400),
  // legacy keys kept for backward compat
  'DPD':        Color(0xFFE8001C),
  'DHL Express':Color(0xFFFFC300),
  'DHL':        Color(0xFFFFC300),
  'Parcelforce':Color(0xFF003087),
  'FedEx':      Color(0xFF4D148C),
  'Evri (Hermes)': Color(0xFF8B5CF6),
};

Color _carrierColor(String carrier) =>
    _kCarrierColors[carrier] ?? const Color(0xFF6B6B6B);

// ─────────────────────────────────────────────────────────────────────────────
// DashboardScreen
// ─────────────────────────────────────────────────────────────────────────────

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;

  // ── Calculator state ─────────────────────────────────────────
  final _fromCtrl   = TextEditingController();
  final _toCtrl     = TextEditingController();
  final _weightCtrl = TextEditingController(text: '1.0');
  String _selectedSize  = 'sm';
  bool   _isCalculating = false;
  bool   _showPrices    = false;
  String _calcError     = '';
  List<PriceResult> _calcResults = [];

  // ── Static carrier list ───────────────────────────────────────
  final List<Map<String, dynamic>> _carriers = [
    {'name': 'Royal Mail',             'addr': 'Tracked 24 · Tracked 48 · Special Delivery',  'color': const Color(0xFFE30613), 'tag': 'Tracked 24/48'},
    {'name': 'Parcelforce Royal Mail', 'addr': 'Express 24 · Express 48 · Worldwide',          'color': const Color(0xFF003087), 'tag': 'Express 24'},
    {'name': 'Evri',                   'addr': 'Next Day · Standard · Economy',                'color': const Color(0xFF8B5CF6), 'tag': 'Next Day'},
    {'name': 'DPD UK',                 'addr': 'DPD Classic · DPD Express · Sunday Delivery',  'color': const Color(0xFFE8001C), 'tag': 'Same Day'},
    {'name': 'Yodel',                  'addr': 'Yodel Xpect · Yodel Direct',                   'color': const Color(0xFF6D28D9), 'tag': 'Next Day'},
    {'name': 'FedEx UK',               'addr': 'FedEx UK · International Priority',            'color': const Color(0xFF4D148C), 'tag': 'Express'},
    {'name': 'DHL Express MyDHL API',  'addr': 'Express Worldwide · Express 12:00',            'color': const Color(0xFFFFC300), 'tag': 'Worldwide'},
    {'name': 'UPS',                    'addr': 'UPS Standard · UPS Express · UPS Saver',       'color': const Color(0xFF351C15), 'tag': 'Express'},
    {'name': 'GlobalPost',             'addr': 'GlobalPost Economy · GlobalPost Priority',     'color': const Color(0xFF0284C7), 'tag': 'International'},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final email = context.read<AuthProvider>().email;
      if (email.isNotEmpty) {
        await Future.wait([
          context.read<ProfileProvider>().loadProfile(email),
          context.read<ParcelProvider>().getShipments(email),
        ]);
      }
    });
  }

  @override
  void dispose() {
    _fromCtrl.dispose();
    _toCtrl.dispose();
    _weightCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────
  bool get _samePostcode {
    final a = _fromCtrl.text.trim().replaceAll(' ', '').toLowerCase();
    final b = _toCtrl.text.trim().replaceAll(' ', '').toLowerCase();
    return a == b && a.length >= 5;
  }

  bool get _calcEnabled =>
      _fromCtrl.text.trim().length >= 5 &&
          _toCtrl.text.trim().length >= 5 &&
          !_samePostcode;

  void _resetCalc() => setState(() { _showPrices = false; _calcError = ''; });

  // ── Live price fetch via ShipEngine ──────────────────────────
  Future<void> _calculatePrices() async {
    if (!_calcEnabled) return;
    setState(() {
      _isCalculating = true;
      _showPrices    = false;
      _calcError     = '';
      _calcResults   = [];
    });

    try {
      const baseUrl = 'https://tjrjeemaacumepimjltg.supabase.co/functions/v1/shipengine-courier';
      const anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRqcmplZW1hYWN1bWVwaW1qbHRnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQxMjE2NjAsImV4cCI6MjA4OTY5NzY2MH0.gtBcFu-J48mPDk_S9ukfVdW-7gUmabGatmJ1g1_5zzo';

      final from   = _fromCtrl.text.trim().toUpperCase().replaceAll(' ', '');
      final to     = _toCtrl.text.trim().toUpperCase().replaceAll(' ', '');
      final weight = double.tryParse(_weightCtrl.text.trim()) ?? 1.0;

      final res = await http.post(
        Uri.parse(baseUrl),
        headers: {
          'Content-Type':  'application/json',
          'Authorization': 'Bearer $anonKey',
        },
        body: jsonEncode({
          'action':        'get_rates',
          'international': false,
          'toCountry':     'GB',
          'shipment': {
            'sender': {
              'name':     'SwiftLabel User',
              'address':  '1 High Street',
              'city':     'London',
              'postcode': from,
              'country':  'GB',
              'phone':    '07700000000',
              'email':    '',
            },
            'recipient': {
              'name':     'Recipient',
              'address':  '1 High Street',
              'city':     'London',
              'postcode': to,
              'country':  'GB',
              'phone':    '07700000000',
              'email':    '',
            },
            'parcel': {
              'size':      _selectedSize,
              'weight_kg': weight,
            },
          },
        }),
      ).timeout(const Duration(seconds: 25));

      final data = jsonDecode(res.body);

      if (res.statusCode == 200 && data['success'] == true) {
        final List raw = data['rates'] ?? [];
        final results  = <PriceResult>[];
        for (final r in raw) {
          final price = (double.tryParse(r['price']?.toString() ?? '') ?? 0.0) + 0.40;
          if (price <= 0.40) continue;
          final days = r['estimatedDays'];
          String daysStr = '';
          if (days != null) {
            final d = int.tryParse(days.toString());
            daysStr = d != null ? (d == 1 ? '1 day' : '$d days') : days.toString();
          }
          results.add(PriceResult(
            carrier:  r['carrier']  ?? 'Carrier',
            service:  r['service']  ?? 'Standard',
            price:    price,
            days:     daysStr,
            currency: r['currency'] ?? 'GBP',
          ));
        }
        results.sort((a, b) => a.price.compareTo(b.price));
        setState(() {
          _calcResults = results;
          _showPrices  = results.isNotEmpty;
          if (results.isEmpty) _calcError = 'No rates returned for this route.';
        });
      } else {
        setState(() {
          _calcError = data['error'] ?? 'Could not retrieve live rates.';
        });
      }
    } catch (e) {
      setState(() {
        _calcError = e.toString().replaceFirst('Exception: ', '');
      });
    }

    setState(() { _isCalculating = false; });
  }

  // ── Navigation ────────────────────────────────────────────────
  void _goToSend() => Navigator.push(context,
      MaterialPageRoute(builder: (_) => const SendParcelScreen())).then((_) {
    final email = context.read<AuthProvider>().email;
    if (email.isNotEmpty) context.read<ParcelProvider>().getShipments(email);
  });
  void _goToTrack()         => Navigator.push(context, MaterialPageRoute(builder: (_) => const TrackParcelScreen()));
  void _gotoAllShipment()   => Navigator.push(context, MaterialPageRoute(builder: (_) => const YourShipmentsScreen()));
  void _goToProfile()       => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
  void _goToBulk()          => Navigator.push(context, MaterialPageRoute(builder: (_) => const BulkOrderScreen()));
  void _goToDetail(Shipment s) => Navigator.push(context, MaterialPageRoute(builder: (_) => ShipmentDetailScreen(shipment: s)));
  void _goToDropOff()       => Navigator.push(context, MaterialPageRoute(builder: (_) => const DropOffLocationsScreen()));

  // ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final email       = context.read<AuthProvider>().email;
    final profile     = context.watch<ProfileProvider>();
    final parcel      = context.watch<ParcelProvider>();
    final displayName = profile.fullName.isNotEmpty
        ? profile.fullName.split(' ')[0]
        : email.isNotEmpty ? email.split('@')[0] : 'there';

    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F7),
      body: SafeArea(child: Column(children: [
        _DashboardNav(
          email: email, initials: profile.initials, avatarUrl: profile.avatarUrl,
          onSendTap: _goToSend, onTrackTap: _goToTrack, onProfileTap: _goToProfile,
        ),
        Expanded(child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 28),

            Text('Hi, $displayName 👋',
                style: const TextStyle(fontSize: 22, color: Color(0xFF6B6B6B),
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            const Text('What are you shipping today?',
                style: TextStyle(fontFamily: 'Syne', fontSize: 22,
                    fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
            const SizedBox(height: 10),
            const MarqueeBanner(),
            const SizedBox(height: 24),

            // ── Profile completion banner ─────────────────────
            if (!profile.isProfileComplete) ...[
              GestureDetector(
                onTap: _goToProfile,
                child: Container(
                  width: double.infinity, padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: const Color(0xFFFFF5EE),
                      border: Border.all(color: const Color(0xFFFFDDCC)),
                      borderRadius: BorderRadius.circular(12)),
                  child: const Row(children: [
                    Icon(Icons.person_add_outlined, size: 18, color: Color(0xFFFF5A00)),
                    SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Complete your profile', style: TextStyle(fontSize: 13,
                          fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A))),
                      Text('Add your details to speed up sending parcels',
                          style: TextStyle(fontSize: 11, color: Color(0xFF9B9B9B))),
                    ])),
                    Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFFFF5A00)),
                  ]),
                ),
              ),
              const SizedBox(height: 16),
            ],

            _buildHeroCard(parcel),
            const SizedBox(height: 24),
            _buildCalculator(),
            const SizedBox(height: 28),

            // ── Quick Actions ─────────────────────────────────
            const _SectionTitle(title: 'Quick Actions'),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: _ActionCard(
                  icon: Icons.send_rounded, label: 'Send Parcel',
                  subtitle: 'Book a collection',
                  color: const Color(0xFFFF5A00), bgColor: const Color(0xFFFFF5EE),
                  borderColor: const Color(0xFFFFDDCC), onTap: _goToSend)),
              const SizedBox(width: 12),
              Expanded(child: _ActionCard(
                  icon: Icons.search_rounded, label: 'Track Parcel',
                  subtitle: 'Real-time updates',
                  color: const Color(0xFF0284C7), bgColor: const Color(0xFFEFF6FF),
                  borderColor: const Color(0xFFBFDBFE), onTap: _goToTrack)),
            ]),
            const SizedBox(height: 12),
            _ActionCardWide(
              icon: Icons.store_mall_directory_rounded,
              label: 'Drop Off Locations',
              subtitle: 'Find nearby parcel drop-off points',
              color: const Color(0xFF059669),
              bgColor: const Color(0xFFF0FDF4),
              borderColor: const Color(0xFFBBF7D0),
              onTap: _goToDropOff,
            ),
            const SizedBox(height: 12),
            _ActionCardWide(
              icon: Icons.layers_rounded, label: 'Bulk Orders',
              subtitle: 'Ship multiple parcels at once',
              color: const Color(0xFF7C3AED), bgColor: const Color(0xFFF5F3FF),
              borderColor: const Color(0xFFDDD6FE), onTap: _goToBulk,
            ),

            const SizedBox(height: 28),

            // ── UK Carriers ───────────────────────────────────
            const _SectionTitle(title: 'UK Parcel Services'),
            const SizedBox(height: 4),
            const Text('Trusted carriers we work with',
                style: TextStyle(fontSize: 13, color: Color(0xFF9B9B9B))),
            const SizedBox(height: 14),
            ..._carriers.map((c) => _CarrierCard(
                name: c['name'], address: c['addr'],
                color: c['color'], tag: c['tag'], onTap: _goToSend)),

            const SizedBox(height: 28),

            // ── Recent Shipments ──────────────────────────────
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const _SectionTitle(title: 'Recent Shipments'),
              GestureDetector(onTap: _gotoAllShipment,
                  child: const Text('View all', style: TextStyle(fontSize: 13,
                      color: Color(0xFFFF5A00), fontWeight: FontWeight.w600))),
            ]),
            const SizedBox(height: 14),

            if (parcel.isLoadingShipments)
              const Center(child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(color: Color(0xFFFF5A00), strokeWidth: 2),
              )),

            if (!parcel.isLoadingShipments && parcel.recentShipments.isEmpty)
              Container(
                width: double.infinity, padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: Colors.white,
                    border: Border.all(color: const Color(0xFFEEEEEE)),
                    borderRadius: BorderRadius.circular(12)),
                child: Column(children: [
                  const Icon(Icons.inventory_2_outlined, size: 40, color: Color(0xFFE0E0E0)),
                  const SizedBox(height: 10),
                  const Text('No shipments yet', style: TextStyle(fontFamily: 'Syne',
                      fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF9B9B9B))),
                  const SizedBox(height: 4),
                  const Text('Send your first parcel to see it here',
                      style: TextStyle(fontSize: 12, color: Color(0xFFB0B0B0))),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _goToSend,
                    icon: const Icon(Icons.send_rounded, size: 16),
                    label: const Text('Send a Parcel'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF5A00),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      textStyle: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ]),
              ),

            if (!parcel.isLoadingShipments && parcel.recentShipments.isNotEmpty)
              ...parcel.recentShipments.take(5).map((s) =>
                  _RealShipmentItem(shipment: s, onTap: () => _goToDetail(s))),

            if (!parcel.isLoadingShipments && parcel.recentShipments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(child: TextButton.icon(
                  onPressed: () => parcel.getShipments(email),
                  icon: const Icon(Icons.refresh_rounded, size: 14),
                  label: const Text('Refresh'),
                  style: TextButton.styleFrom(foregroundColor: const Color(0xFF9B9B9B),
                      textStyle: const TextStyle(fontSize: 12)),
                )),
              ),

            const SizedBox(height: 32),
          ]),
        )),
      ])),

      bottomNavigationBar: Container(
        decoration: const BoxDecoration(color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFEEEEEE)))),
        child: NavigationBar(
          backgroundColor: Colors.white, elevation: 0,
          selectedIndex: _selectedIndex,
          onDestinationSelected: (i) {
            switch (i) {
              case 0: setState(() => _selectedIndex = 0); break;
              case 1: _goToSend();    break;
              case 2: _goToTrack();   break;
              case 3: _goToBulk();    break;
              case 4: _goToProfile(); break;
            }
          },
          indicatorColor: const Color(0xFFFF5A00).withOpacity(0.1),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined,   color: Color(0xFF9B9B9B)),
                selectedIcon: Icon(Icons.home_rounded,   color: Color(0xFFFF5A00)), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.send_outlined,   color: Color(0xFF9B9B9B)),
                selectedIcon: Icon(Icons.send_rounded,   color: Color(0xFFFF5A00)), label: 'Send'),
            NavigationDestination(icon: Icon(Icons.search_outlined, color: Color(0xFF9B9B9B)),
                selectedIcon: Icon(Icons.search_rounded, color: Color(0xFFFF5A00)), label: 'Track'),
            NavigationDestination(icon: Icon(Icons.layers_outlined, color: Color(0xFF9B9B9B)),
                selectedIcon: Icon(Icons.layers_rounded, color: Color(0xFFFF5A00)), label: 'Bulk'),
            NavigationDestination(icon: Icon(Icons.person_outline,  color: Color(0xFF9B9B9B)),
                selectedIcon: Icon(Icons.person_rounded, color: Color(0xFFFF5A00)), label: 'Profile'),
          ],
        ),
      ),
    );
  }

  // ── Hero card ─────────────────────────────────────────────────
  Widget _buildHeroCard(ParcelProvider parcel) {
    final active = parcel.recentShipments.where((s) => s.status != 'delivered').toList();
    final latest = active.isNotEmpty ? active.first : null;

    if (latest == null) {
      return GestureDetector(
        onTap: _goToSend,
        child: Container(
          width: double.infinity, padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFFFF7A2F), Color(0xFFFF5A00)],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: const Color(0xFFFF5A00).withOpacity(0.25),
                blurRadius: 20, offset: const Offset(0, 8))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('SEND A PARCEL', style: TextStyle(fontSize: 10,
                fontWeight: FontWeight.w600, letterSpacing: 1.2, color: Colors.white70)),
            const SizedBox(height: 10),
            const Text('Ship anything, anywhere in the UK',
                style: TextStyle(fontFamily: 'Syne', fontSize: 18,
                    fontWeight: FontWeight.w800, color: Colors.white)),
            const SizedBox(height: 4),
            const Text('Compare live rates from Royal Mail, Evri, DPD & more',
                style: TextStyle(fontSize: 13, color: Colors.white70)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(20)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.send_rounded, size: 14, color: Colors.white),
                SizedBox(width: 6),
                Text('Send Now', style: TextStyle(fontSize: 13,
                    color: Colors.white, fontWeight: FontWeight.w600)),
              ]),
            ),
          ]),
        ),
      );
    }

    return GestureDetector(
      onTap: () => _goToDetail(latest),
      child: Container(
        width: double.infinity, padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: [latest.carrierColor.withOpacity(0.85), latest.carrierColor],
              begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: latest.carrierColor.withOpacity(0.25),
              blurRadius: 20, offset: const Offset(0, 8))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('ACTIVE SHIPMENT', style: TextStyle(fontSize: 10,
                fontWeight: FontWeight.w600, letterSpacing: 1.2, color: Colors.white70)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(20)),
              child: Text(latest.statusLabel,
                  style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w500)),
            ),
          ]),
          const SizedBox(height: 10),
          Text('To ${latest.recipientName}', style: const TextStyle(fontFamily: 'Syne',
              fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
          const SizedBox(height: 4),
          Text('${latest.carrier} · ${latest.service} · ${latest.recipientCity}',
              style: const TextStyle(fontSize: 13, color: Colors.white70)),
          const SizedBox(height: 16),
          Row(children: [
            GestureDetector(onTap: () => _goToDetail(latest),
                child: const _CardChip(icon: Icons.download_rounded, label: 'Download Label')),
            const SizedBox(width: 8),
            GestureDetector(onTap: _goToTrack,
                child: const _CardChip(icon: Icons.search_rounded, label: 'Track Parcel')),
          ]),
        ]),
      ),
    );
  }

  // ── Price Calculator ──────────────────────────────────────────
  Widget _buildCalculator() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F0FF),
        border: Border.all(color: const Color(0xFFDDD6FE)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Header ────────────────────────────────────────────
        Row(children: [
          const Icon(Icons.calculate_outlined, size: 16, color: Color(0xFF6D28D9)),
          const SizedBox(width: 6),
          const Text('Instant Price Calculator', style: TextStyle(fontSize: 13,
              fontWeight: FontWeight.w700, color: Color(0xFF6D28D9))),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(color: const Color(0xFF059669),
                borderRadius: BorderRadius.circular(20)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.circle, size: 6, color: Colors.white),
              SizedBox(width: 4),
              Text('LIVE', style: TextStyle(fontSize: 9, color: Colors.white,
                  fontWeight: FontWeight.w700, letterSpacing: 0.8)),
            ]),
          ),
        ]),
        const SizedBox(height: 14),

        // ── Postcode row ──────────────────────────────────────
        Row(children: [
          Expanded(child: _CalcField(
            ctrl: _fromCtrl, hint: 'SW1A 1AA', label: 'From',
            onChanged: (_) => _resetCalc(),
          )),
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              width: 28, height: 28,
              decoration: BoxDecoration(
                  color: const Color(0xFF6D28D9).withOpacity(0.1),
                  shape: BoxShape.circle),
              child: const Icon(Icons.swap_horiz_rounded, size: 16, color: Color(0xFF6D28D9)),
            ),
          ),
          Expanded(child: _CalcField(
            ctrl: _toCtrl, hint: 'M1 1AA', label: 'To',
            onChanged: (_) => _resetCalc(),
          )),
        ]),

        if (_samePostcode) ...[
          const SizedBox(height: 6),
          const Text('⚠️ Postcodes cannot be the same',
              style: TextStyle(fontSize: 11, color: Colors.red)),
        ],

        const SizedBox(height: 12),

        // ── Weight + Size row ─────────────────────────────────
        Row(children: [
          Expanded(child: _CalcField(
            ctrl: _weightCtrl, hint: '1.0', label: 'Weight (kg)',
            type: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => _resetCalc(),
          )),
          const SizedBox(width: 10),
          Expanded(child: _ParcelSizePicker(
            selected: _selectedSize,
            onChanged: (v) => setState(() { _selectedSize = v; _showPrices = false; }),
          )),
        ]),

        const SizedBox(height: 14),

        // ── Get Prices button ─────────────────────────────────
        SizedBox(
          width: double.infinity, height: 46,
          child: ElevatedButton.icon(
            onPressed: (_calcEnabled && !_isCalculating) ? _calculatePrices : null,
            icon: _isCalculating
                ? const SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.bolt_rounded, size: 18, color: Colors.white),
            label: Text(_isCalculating ? 'Fetching live prices…' : 'Get Live Prices'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6D28D9),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFBBB0E8),
              minimumSize: Size.zero,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
        ),

        // ── Error ─────────────────────────────────────────────
        if (_calcError.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.05),
              border: Border.all(color: Colors.red.withOpacity(0.2)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              const Icon(Icons.error_outline_rounded, color: Colors.red, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(_calcError,
                  style: const TextStyle(fontSize: 12, color: Colors.red))),
            ]),
          ),
        ],

        // ── Results ───────────────────────────────────────────
        if (_showPrices && _calcResults.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity, padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white,
                border: Border.all(color: const Color(0xFFDDD6FE)),
                borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              Row(children: [
                const Icon(Icons.local_shipping_outlined, size: 15, color: Color(0xFF059669)),
                const SizedBox(width: 6),
                const Text('Live Shipping Rates', style: TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
                const Spacer(),
                Text('${_calcResults.length} options',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF9B9B9B))),
              ]),
              const SizedBox(height: 10),

              ..._calcResults.asMap().entries.map((e) {
                final i      = e.key;
                final item   = e.value;
                final isBest = i == 0;
                final isFast = (int.tryParse(item.days.replaceAll(RegExp(r'[^0-9]'), '')) ?? 99) <= 1
                    && i <= 2;
                final dot = _carrierColor(item.carrier);

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isBest ? const Color(0xFFF0FDF4) : const Color(0xFFFAFAFA),
                    border: Border.all(color: isBest
                        ? const Color(0xFF059669).withOpacity(0.35)
                        : const Color(0xFFEEEEEE)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(children: [
                    // ── Carrier logo badge ──────────────────
                    _CarrierLogo(carrier: item.carrier, color: dot, width: 40, height: 28),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text(item.carrier, style: const TextStyle(fontSize: 13,
                            fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A))),
                        const SizedBox(width: 6),
                        if (isBest) _RateTag('Cheapest', const Color(0xFF059669)),
                        if (!isBest && isFast) _RateTag('Fast', const Color(0xFF0284C7)),
                      ]),
                      Text(
                        '${item.service}${item.days.isNotEmpty ? ' · ${item.days}' : ''}',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF9B9B9B)),
                      ),
                    ])),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('£${item.price.toStringAsFixed(2)}', style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800,
                          color: isBest ? const Color(0xFF059669) : const Color(0xFF6D28D9))),
                      if (item.currency != 'GBP')
                        Text(item.currency,
                            style: const TextStyle(fontSize: 9, color: Color(0xFFB0B0B0))),
                    ]),
                  ]),
                );
              }),

              const SizedBox(height: 6),
              const Text('💡 Live prices via ShipEngine. Final price confirmed at checkout.',
                  style: TextStyle(fontSize: 10, color: Color(0xFF9B9B9B))),
              const SizedBox(height: 10),

              // SizedBox(
              //   width: double.infinity, height: 40,
              //   child: ElevatedButton.icon(
              //     onPressed: _goToSend,
              //     icon: const Icon(Icons.send_rounded, size: 15, color: Colors.white),
              //     label: Text(
              //       'Book with ${_calcResults.first.carrier}'
              //           ' — £${_calcResults.first.price.toStringAsFixed(2)}',
              //     ),
              //     style: ElevatedButton.styleFrom(
              //       backgroundColor: const Color(0xFF6D28D9),
              //       foregroundColor: Colors.white, minimumSize: Size.zero,
              //       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              //       textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              //     ),
              //   ),
              // ),
            ]),
          ),
        ],
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Carrier Logo Badge — no network, always renders
// ─────────────────────────────────────────────────────────────────────────────

class _CarrierLogo extends StatelessWidget {
  final String carrier;
  final Color  color;
  final double width;
  final double height;

  const _CarrierLogo({
    required this.carrier,
    required this.color,
    this.width  = 52,
    this.height = 36,
  });

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
  // Fallback abbreviations if asset somehow missing
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
    final abbr      = _abbr[carrier] ?? carrier.substring(0, carrier.length > 3 ? 3 : carrier.length).toUpperCase();
    final fs        = abbr.length >= 5 ? 7.0 : abbr.length == 4 ? 9.0 : 11.0;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(8),
        border:       Border.all(color: const Color(0xFFEEEEEE)),
      ),
      padding: const EdgeInsets.all(4),
      child: assetPath != null
          ? Image.asset(
        assetPath,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Center(
          child: Text(abbr,
            style: TextStyle(fontSize: fs, fontWeight: FontWeight.w800,
                color: color, letterSpacing: -0.3),
          ),
        ),
      )
          : Center(
        child: Text(abbr,
          style: TextStyle(fontSize: fs, fontWeight: FontWeight.w800,
              color: color, letterSpacing: -0.3),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small rate tag chip
// ─────────────────────────────────────────────────────────────────────────────

class _RateTag extends StatelessWidget {
  final String label;
  final Color  color;
  const _RateTag(this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(right: 4),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
    child: Text(label, style: const TextStyle(fontSize: 9, color: Colors.white,
        fontWeight: FontWeight.w700)),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Parcel size picker
// ─────────────────────────────────────────────────────────────────────────────

class _ParcelSizePicker extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;
  const _ParcelSizePicker({required this.selected, required this.onChanged});

  static const _sizes = [
    {'key': 'sm', 'label': 'Small',  'sub': '≤2 kg'},
    {'key': 'md', 'label': 'Medium', 'sub': '≤10 kg'},
    {'key': 'lg', 'label': 'Large',  'sub': '≤30 kg'},
  ];

  @override
  Widget build(BuildContext context) => Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Parcel Size', style: TextStyle(fontSize: 10,
        fontWeight: FontWeight.w600, color: Color(0xFF6B6B6B))),
    const SizedBox(height: 4),
    Row(children: _sizes.map((s) {
      final active = s['key'] == selected;
      return Expanded(child: GestureDetector(
        onTap: () => onChanged(s['key']!),
        child: Container(
          margin: const EdgeInsets.only(right: 4),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF6D28D9) : Colors.white,
            border: Border.all(color: active
                ? const Color(0xFF6D28D9) : const Color(0xFFDDD6FE)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(children: [
            Text(s['label']!, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                color: active ? Colors.white : const Color(0xFF3A3A3A))),
            Text(s['sub']!, style: TextStyle(fontSize: 9,
                color: active ? Colors.white70 : const Color(0xFF9B9B9B))),
          ]),
        ),
      ));
    }).toList()),
  ]);
}

// ─────────────────────────────────────────────────────────────────────────────
// Real shipment row
// ─────────────────────────────────────────────────────────────────────────────

class _RealShipmentItem extends StatelessWidget {
  final Shipment     shipment;
  final VoidCallback onTap;
  const _RealShipmentItem({required this.shipment, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = shipment;
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'];
    final date = '${s.createdAt.day} ${months[s.createdAt.month - 1]} ${s.createdAt.year}';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white,
            border: Border.all(color: const Color(0xFFEEEEEE)),
            borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          _ShipmentCarrierLogo(carrier: s.carrier, color: s.carrierColor),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.trackingNumber, style: const TextStyle(fontSize: 12,
                fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A),
                fontFamily: 'monospace'), overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text('To ${s.recipientName} · ${s.recipientCity}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF9B9B9B)),
                overflow: TextOverflow.ellipsis),
            Text(s.carrier, style: TextStyle(fontSize: 11,
                color: s.carrierColor, fontWeight: FontWeight.w500)),
          ])),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: s.statusColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20)),
              child: Text(s.statusLabel, style: TextStyle(fontSize: 10,
                  color: s.statusColor, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 4),
            Text(date, style: const TextStyle(fontSize: 10, color: Color(0xFFB0B0B0))),
            const SizedBox(height: 2),
            const Icon(Icons.chevron_right, size: 14, color: Color(0xFFB0B0B0)),
          ]),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dashboard nav bar
// ─────────────────────────────────────────────────────────────────────────────

class _DashboardNav extends StatelessWidget {
  final String email, initials, avatarUrl;
  final VoidCallback onSendTap, onTrackTap, onProfileTap;
  const _DashboardNav({
    required this.email,
    required this.initials,
    required this.avatarUrl,
    required this.onSendTap,
    required this.onTrackTap,
    required this.onProfileTap,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
    ),
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
      const Text('SwiftLabel', style: TextStyle(
        fontFamily: 'Syne', fontSize: 17,
        fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A),
      )),
      const Spacer(),

      if (isAdminEmail(email)) ...[
        GestureDetector(
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const AdminDashboardScreen())),
          child: Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFFF5A00).withOpacity(0.08),
              border: Border.all(color: const Color(0xFFFF5A00).withOpacity(0.3)),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.admin_panel_settings_rounded,
                color: Color(0xFFFF5A00), size: 18),
          ),
        ),
        const SizedBox(width: 10),
      ],

      GestureDetector(
        onTap: onProfileTap,
        child: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFFF5A00).withOpacity(0.1),
            border: Border.all(color: const Color(0xFFFF5A00).withOpacity(0.3)),
            image: avatarUrl.isNotEmpty
                ? DecorationImage(image: NetworkImage(avatarUrl), fit: BoxFit.cover)
                : null,
          ),
          child: avatarUrl.isEmpty
              ? Center(child: Text(initials, style: const TextStyle(
            fontFamily: 'Syne', fontSize: 13,
            fontWeight: FontWeight.w700, color: Color(0xFFFF5A00),
          )))
              : null,
        ),
      ),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Calculator text field
// ─────────────────────────────────────────────────────────────────────────────

class _CalcField extends StatelessWidget {
  final TextEditingController ctrl;
  final String hint, label;
  final TextInputType type;
  final ValueChanged<String>? onChanged;
  const _CalcField({required this.ctrl, required this.hint, required this.label,
    this.type = TextInputType.text, this.onChanged});

  @override
  Widget build(BuildContext context) => Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(fontSize: 10,
        fontWeight: FontWeight.w600, color: Color(0xFF6B6B6B))),
    const SizedBox(height: 4),
    TextFormField(
      controller: ctrl, keyboardType: type,
      textCapitalization: TextCapitalization.characters,
      onChanged: onChanged,
      inputFormatters: type != TextInputType.text
          ? [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))] : [],
      style: const TextStyle(fontSize: 12, color: Color(0xFF1A1A1A)),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 11, color: Color(0xFFB0B0B0)),
        filled: true, fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFDDD6FE))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFDDD6FE))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF6D28D9))),
      ),
    ),
  ]);
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared small widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});
  @override
  Widget build(BuildContext context) => Text(title,
      style: const TextStyle(fontFamily: 'Syne', fontSize: 16,
          fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A)));
}

class _CardChip extends StatelessWidget {
  final IconData icon; final String label;
  const _CardChip({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(20)),
    child: Row(children: [
      Icon(icon, size: 13, color: Colors.white), const SizedBox(width: 5),
      Text(label, style: const TextStyle(fontSize: 12,
          color: Colors.white, fontWeight: FontWeight.w500)),
    ]),
  );
}

class _ActionCard extends StatelessWidget {
  final IconData icon; final String label, subtitle;
  final Color color, bgColor, borderColor; final VoidCallback onTap;
  const _ActionCard({required this.icon, required this.label, required this.subtitle,
    required this.color, required this.bgColor, required this.borderColor, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: bgColor, border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 40, height: 40,
            decoration: BoxDecoration(color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 20)),
        const SizedBox(height: 12),
        Text(label, style: const TextStyle(fontFamily: 'Syne', fontSize: 14,
            fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
        const SizedBox(height: 2),
        Text(subtitle, style: const TextStyle(fontSize: 11, color: Color(0xFF9B9B9B))),
      ]),
    ),
  );
}

class _ActionCardWide extends StatelessWidget {
  final IconData icon; final String label, subtitle;
  final Color color, bgColor, borderColor; final VoidCallback onTap;
  const _ActionCardWide({required this.icon, required this.label, required this.subtitle,
    required this.color, required this.bgColor, required this.borderColor, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(onTap: onTap,
    child: Container(
      width: double.infinity, padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: bgColor, border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Container(width: 40, height: 40,
            decoration: BoxDecoration(color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 20)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontFamily: 'Syne', fontSize: 14,
              fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF9B9B9B))),
        ])),
        Icon(Icons.chevron_right, color: color.withOpacity(0.5)),
      ]),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Carrier card (UK Parcel Services section)
// ─────────────────────────────────────────────────────────────────────────────

class _CarrierCard extends StatelessWidget {
  final String name, address, tag;
  final Color  color;
  final VoidCallback onTap;
  const _CarrierCard({required this.name, required this.address,
    required this.color, required this.tag, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFEEEEEE)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        _CarrierLogo(carrier: name, color: color, width: 52, height: 36),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: const TextStyle(fontSize: 14,
              fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A))),
          const SizedBox(height: 2),
          Text(address, style: const TextStyle(fontSize: 12, color: Color(0xFF9B9B9B))),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color:        color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
            border:       Border.all(color: color.withOpacity(0.2)),
          ),
          child: Text(tag, style: TextStyle(fontSize: 11,
              color: color, fontWeight: FontWeight.w500)),
        ),
      ]),
    ),
  );
}

class _ShipmentCarrierLogo extends StatelessWidget {
  final String carrier;
  final Color  color;
  const _ShipmentCarrierLogo({required this.carrier, required this.color});

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
    'InPost':                       'assets/carriers/globalpost.png',
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
      width: 44, height: 44,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEEEEEE)),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 4, offset: const Offset(0, 2))],
      ),
      padding: const EdgeInsets.all(6),
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