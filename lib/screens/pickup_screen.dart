// lib/screens/pickup_screen.dart
//
// Shown after label is created when the selected service requires collection.
// Flow: send_parcel.dart → (if requires_pickup) → PickupScreen → Dashboard

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class PickupSlot {
  final String date;
  final String startTime;
  final String endTime;
  final String label;

  const PickupSlot({
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.label,
  });

  factory PickupSlot.fromJson(Map<String, dynamic> j) => PickupSlot(
    date:      j['date']       ?? '',
    startTime: j['start_time'] ?? '08:00',
    endTime:   j['end_time']   ?? '18:00',
    label:     j['label']      ?? j['date'] ?? '',
  );
}

class PickupScreen extends StatefulWidget {
  final String carrierId;
  final String carrierName;
  final String labelId;
  final String trackingNumber;
  final String labelUrl;
  final String senderName;
  final String senderPhone;
  final String senderEmail;
  final String senderAddress;
  final String senderCity;
  final String senderPostcode;

  const PickupScreen({
    super.key,
    required this.carrierId,
    required this.carrierName,
    required this.labelId,
    required this.trackingNumber,
    required this.labelUrl,
    required this.senderName,
    required this.senderPhone,
    required this.senderEmail,
    required this.senderAddress,
    required this.senderCity,
    required this.senderPostcode,
  });

  @override
  State<PickupScreen> createState() => _PickupScreenState();
}

class _PickupScreenState extends State<PickupScreen> {
  static const _baseUrl  = 'https://tjrjeemaacumepimjltg.supabase.co/functions/v1';
  static const _anonKey  =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRqcmplZW1hYWN1bWVwaW1qbHRnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQxMjE2NjAsImV4cCI6MjA4OTY5NzY2MH0.gtBcFu-J48mPDk_S9ukfVdW-7gUmabGatmJ1g1_5zzo';

  // ── State ─────────────────────────────────────────────────────
  List<PickupSlot> _slots         = [];
  PickupSlot?      _selectedSlot;
  String           _selectedWindow = 'morning'; // morning | afternoon | allday
  bool             _loadingSlots  = true;
  bool             _scheduling    = false;
  bool             _done          = false;
  String           _error         = '';
  String           _confirmationId = '';
  String           _notes         = '';

  final _notesCtrl = TextEditingController();

  // Time windows
  static const _windows = [
    {'key': 'morning',   'label': 'Morning',   'sub': '08:00 – 12:00', 'start': '08:00', 'end': '12:00'},
    {'key': 'afternoon', 'label': 'Afternoon',  'sub': '12:00 – 18:00', 'start': '12:00', 'end': '18:00'},
    {'key': 'allday',    'label': 'All day',    'sub': '08:00 – 18:00', 'start': '08:00', 'end': '18:00'},
  ];

  @override
  void initState() {
    super.initState();
    _loadSlots();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Map<String, String> get _headers => {
    'Content-Type':  'application/json',
    'Authorization': 'Bearer $_anonKey',
  };

  // ── Load pickup slots ─────────────────────────────────────────
  Future<void> _loadSlots() async {
    setState(() { _loadingSlots = true; _error = ''; });
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/shipengine-courier'),
        headers: _headers,
        body: jsonEncode({
          'action':    'get_pickup_slots',
          'carrierId': widget.carrierId,
          'postcode':  widget.senderPostcode,
        }),
      ).timeout(const Duration(seconds: 20));

      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['success'] == true) {
        final raw = data['slots'] as List? ?? [];
        setState(() {
          _slots = raw.map((s) => PickupSlot.fromJson(s as Map<String, dynamic>)).toList();
          if (_slots.isNotEmpty) _selectedSlot = _slots.first;
        });
      } else {
        setState(() => _error = data['error'] ?? 'Could not load pickup slots.');
      }
    } catch (e) {
      setState(() => _error = 'Network error loading slots.');
      debugPrint('[PickupScreen] loadSlots error: $e');
    }
    setState(() => _loadingSlots = false);
  }

  // ── Schedule pickup ───────────────────────────────────────────
  Future<void> _schedulePickup() async {
    if (_selectedSlot == null) {
      _snack('Please select a pickup date.');
      return;
    }

    final window = _windows.firstWhere((w) => w['key'] == _selectedWindow);

    setState(() { _scheduling = true; _error = ''; });

    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/shipengine-courier'),
        headers: _headers,
        body: jsonEncode({
          'action':            'schedule_pickup',
          'carrierId':         widget.carrierId,
          'labelId':           widget.labelId,
          'pickupDate':        _selectedSlot!.date,
          'pickupWindowStart': window['start'],
          'pickupWindowEnd':   window['end'],
          'contactName':       widget.senderName,
          'contactPhone':      widget.senderPhone,
          'contactEmail':      widget.senderEmail,
          'addressLine1':      widget.senderAddress,
          'city':              widget.senderCity,
          'postcode':          widget.senderPostcode,
          'notes':             _notesCtrl.text.trim(),
        }),
      ).timeout(const Duration(seconds: 30));

      final data = jsonDecode(res.body);
      debugPrint('[PickupScreen] schedule_pickup response: ${res.body}');

      if (res.statusCode == 200 && data['success'] == true) {
        setState(() {
          _done           = true;
          _confirmationId = data['confirmation'] ?? data['pickup_id'] ?? '';
          _scheduling     = false;
        });
      } else {
        setState(() {
          _error     = data['error'] ?? 'Failed to schedule pickup. Please try again.';
          _scheduling = false;
        });
      }
    } catch (e) {
      setState(() { _error = 'Network error. Please try again.'; _scheduling = false; });
      debugPrint('[PickupScreen] schedulePickup error: $e');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F7),
      body: SafeArea(child: Column(children: [
        _buildTopNav(),
        Expanded(child: _done ? _buildSuccess() : _buildForm()),
      ])),
    );
  }

  // ── Top nav ───────────────────────────────────────────────────
  Widget _buildTopNav() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    decoration: const BoxDecoration(color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE)))),
    child: Row(children: [
      Container(width: 30, height: 30,
          decoration: BoxDecoration(color: const Color(0xFFFF5A00),
              borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.inventory_2_outlined, color: Colors.white, size: 16)),
      const SizedBox(width: 8),
      const Text('SwiftLabel', style: TextStyle(fontFamily: 'Syne', fontSize: 17,
          fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
      const Spacer(),
      if (!_done)
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: const Row(children: [
            Icon(Icons.arrow_back_ios, size: 14, color: Color(0xFF6B6B6B)),
            Text('Back', style: TextStyle(fontSize: 13, color: Color(0xFF6B6B6B))),
          ]),
        ),
    ]),
  );

  // ── Form ──────────────────────────────────────────────────────
  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Header
        Row(children: [
          Container(width: 44, height: 44,
              decoration: BoxDecoration(color: const Color(0xFF6D28D9).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.local_shipping_outlined,
                  color: Color(0xFF6D28D9), size: 22)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Schedule Pickup', style: TextStyle(
                fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
            Text('${widget.carrierName} will collect from your address',
                style: const TextStyle(fontSize: 13, color: Color(0xFF6B6B6B))),
          ])),
        ]),

        const SizedBox(height: 8),

        // Tracking number banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFBBF7D0))),
          child: Row(children: [
            const Icon(Icons.check_circle_outline_rounded, size: 16, color: Color(0xFF059669)),
            const SizedBox(width: 8),
            const Text('Label created · Tracking: ',
                style: TextStyle(fontSize: 12, color: Color(0xFF059669))),
            Expanded(child: Text(widget.trackingNumber,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                    color: Color(0xFF059669), fontFamily: 'monospace'),
                overflow: TextOverflow.ellipsis)),
          ]),
        ),

        const SizedBox(height: 24),

        // ── Pickup address ─────────────────────────────────────
        const Text('Pickup Address', style: TextStyle(
            fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white,
              border: Border.all(color: const Color(0xFFEEEEEE)),
              borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Container(width: 40, height: 40,
                decoration: BoxDecoration(color: const Color(0xFF6D28D9).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.location_on_outlined,
                    color: Color(0xFF6D28D9), size: 20)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.senderName, style: const TextStyle(fontSize: 13,
                  fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A))),
              Text(widget.senderAddress, style: const TextStyle(
                  fontSize: 12, color: Color(0xFF6B6B6B))),
              Text('${widget.senderCity}  ${widget.senderPostcode}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6B6B6B))),
              Text(widget.senderPhone, style: const TextStyle(
                  fontSize: 12, color: Color(0xFF9B9B9B))),
            ])),
          ]),
        ),

        const SizedBox(height: 24),

        // ── Select date ────────────────────────────────────────
        const Text('Select Pickup Date', style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
        const SizedBox(height: 10),

        if (_loadingSlots)
          const Center(child: Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: CircularProgressIndicator(
                color: Color(0xFF6D28D9), strokeWidth: 2.5),
          )),

        if (!_loadingSlots && _slots.isNotEmpty)
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              itemCount: _slots.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (ctx, i) {
                final slot = _slots[i];
                final sel  = _selectedSlot?.date == slot.date;
                // Parse label into parts: "Mon 7 Apr" → "Mon" + "7 Apr"
                final parts = slot.label.split(' ');
                final dayName = parts.isNotEmpty ? parts[0] : '';
                final dayNum  = parts.length > 1 ? parts[1] : '';
                final month   = parts.length > 2 ? parts[2] : '';
                return GestureDetector(
                  onTap: () => setState(() => _selectedSlot = slot),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 68,
                    decoration: BoxDecoration(
                      color: sel ? const Color(0xFF6D28D9) : Colors.white,
                      border: Border.all(
                          color: sel ? const Color(0xFF6D28D9) : const Color(0xFFE0E0E0),
                          width: sel ? 2 : 1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(dayName, style: TextStyle(fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: sel ? Colors.white70 : const Color(0xFF9B9B9B))),
                      Text(dayNum, style: TextStyle( fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: sel ? Colors.white : const Color(0xFF1A1A1A))),
                      Text(month, style: TextStyle(fontSize: 11,
                          color: sel ? Colors.white70 : const Color(0xFF6B6B6B))),
                    ]),
                  ),
                );
              },
            ),
          ),

        if (!_loadingSlots && _slots.isEmpty && _error.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFFFFF5EE),
                border: Border.all(color: const Color(0xFFFFDDCC)),
                borderRadius: BorderRadius.circular(10)),
            child: const Row(children: [
              Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFFFF5A00)),
              SizedBox(width: 8),
              Expanded(child: Text('No pickup slots available. Contact the carrier directly.',
                  style: TextStyle(fontSize: 12, color: Color(0xFFFF5A00)))),
            ]),
          ),

        const SizedBox(height: 24),

        // ── Select time window ─────────────────────────────────
        const Text('Pickup Time Window', style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
        const SizedBox(height: 10),
        Row(children: _windows.map((w) {
          final sel = _selectedWindow == w['key'];
          return Expanded(child: GestureDetector(
            onTap: () => setState(() => _selectedWindow = w['key']!),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: sel ? const Color(0xFF6D28D9) : Colors.white,
                border: Border.all(
                    color: sel ? const Color(0xFF6D28D9) : const Color(0xFFE0E0E0),
                    width: sel ? 2 : 1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(children: [
                Text(w['label']!, style: TextStyle(fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: sel ? Colors.white : const Color(0xFF1A1A1A))),
                const SizedBox(height: 2),
                Text(w['sub']!, style: TextStyle(fontSize: 10,
                    color: sel ? Colors.white70 : const Color(0xFF9B9B9B))),
              ]),
            ),
          ));
        }).toList()),

        const SizedBox(height: 24),

        // ── Notes ──────────────────────────────────────────────
        const Text('Notes for driver (optional)', style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF6B6B6B))),
        const SizedBox(height: 8),
        TextField(
          controller: _notesCtrl,
          maxLines: 3,
          style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A1A)),
          decoration: InputDecoration(
            hintText: 'e.g. Leave with neighbour, ring doorbell twice…',
            hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFB0B0B0)),
            filled: true, fillColor: Colors.white,
            contentPadding: const EdgeInsets.all(14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF6D28D9), width: 1.5)),
          ),
        ),

        // ── Error ──────────────────────────────────────────────
        if (_error.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.red.withOpacity(0.05),
                border: Border.all(color: Colors.red.withOpacity(0.2)),
                borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              const Icon(Icons.error_outline_rounded, color: Colors.red, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(_error,
                  style: const TextStyle(fontSize: 12, color: Colors.red))),
            ]),
          ),
        ],

        const SizedBox(height: 28),

        // ── Confirm button ─────────────────────────────────────
        SizedBox(
          width: double.infinity, height: 54,
          child: ElevatedButton(
            onPressed: (_scheduling || _selectedSlot == null) ? null : _schedulePickup,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6D28D9),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFF6D28D9).withOpacity(0.4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              textStyle: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700),
            ),
            child: _scheduling
                ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2.5)),
              SizedBox(width: 12),
              Text('Scheduling pickup…'),
            ])
                : Text(_selectedSlot != null
                ? 'Confirm Pickup — ${_selectedSlot!.label}'
                : 'Select a date to continue'),
          ),
        ),

        const SizedBox(height: 12),

        // Skip option
        Center(child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: const Text('Skip — I\'ll arrange pickup myself',
              style: TextStyle(fontSize: 13, color: Color(0xFF9B9B9B),
                  decoration: TextDecoration.underline)),
        )),

        const SizedBox(height: 24),
      ]),
    );
  }

  // ── Success screen ────────────────────────────────────────────
  Widget _buildSuccess() {
    final window = _windows.firstWhere((w) => w['key'] == _selectedWindow);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        const SizedBox(height: 20),

        // Success icon
        Container(width: 88, height: 88,
            decoration: BoxDecoration(
                color: const Color(0xFF059669).withOpacity(0.1),
                shape: BoxShape.circle),
            child: const Icon(Icons.check_circle_outline_rounded,
                color: Color(0xFF059669), size: 48)),

        const SizedBox(height: 20),
        const Text('Pickup Scheduled!', style: TextStyle(
            fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
        const SizedBox(height: 8),
        Text('${widget.carrierName} will collect your parcel',
            style: const TextStyle(fontSize: 14, color: Color(0xFF6B6B6B))),

        const SizedBox(height: 28),

        // Details card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.white,
              border: Border.all(color: const Color(0xFFEEEEEE)),
              borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            _DetailRow(
              icon: Icons.local_shipping_outlined,
              label: 'Carrier',
              value: widget.carrierName,
              color: const Color(0xFF6D28D9),
            ),
            const Divider(height: 20),
            _DetailRow(
              icon: Icons.calendar_today_outlined,
              label: 'Pickup date',
              value: _selectedSlot?.label ?? '',
              color: const Color(0xFF6D28D9),
            ),
            const Divider(height: 20),
            _DetailRow(
              icon: Icons.access_time_outlined,
              label: 'Time window',
              value: window['sub'] ?? '',
              color: const Color(0xFF6D28D9),
            ),
            const Divider(height: 20),
            _DetailRow(
              icon: Icons.location_on_outlined,
              label: 'Collection address',
              value: '${widget.senderAddress}, ${widget.senderCity} ${widget.senderPostcode}',
              color: const Color(0xFF6D28D9),
            ),
            if (_confirmationId.isNotEmpty) ...[
              const Divider(height: 20),
              _DetailRow(
                icon: Icons.confirmation_number_outlined,
                label: 'Confirmation ref',
                value: _confirmationId,
                color: const Color(0xFF059669),
              ),
            ],
          ]),
        ),

        const SizedBox(height: 16),

        // Tracking banner
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: const Color(0xFFF0FDF4),
              border: Border.all(color: const Color(0xFFBBF7D0)),
              borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            const Icon(Icons.qr_code_outlined, size: 18, color: Color(0xFF059669)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Tracking number', style: TextStyle(
                  fontSize: 11, color: Color(0xFF059669))),
              Text(widget.trackingNumber, style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700,
                  color: Color(0xFF059669), fontFamily: 'monospace')),
            ])),
          ]),
        ),

        const SizedBox(height: 24),

        // Back to dashboard
        SizedBox(
          width: double.infinity, height: 50,
          child: ElevatedButton.icon(
            onPressed: () {
              // Pop all the way back to dashboard
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            icon: const Icon(Icons.home_outlined, size: 18),
            label: const Text('Back to Dashboard'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6D28D9),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              textStyle: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Helper widget ─────────────────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   value;
  final Color    color;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(width: 36, height: 36,
          decoration: BoxDecoration(color: color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 18)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF9B9B9B))),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 14,
            fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A))),
      ])),
    ],
  );
}