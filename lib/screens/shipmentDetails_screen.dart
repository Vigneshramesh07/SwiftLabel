import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:swift_label/screens/track_parcel.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/auth_provider.dart';
import '../providers/parcel_provider.dart';

class ShipmentDetailScreen extends StatefulWidget {
  final Shipment shipment;
  const ShipmentDetailScreen({super.key, required this.shipment});

  @override
  State<ShipmentDetailScreen> createState() => _ShipmentDetailScreenState();
}

class _ShipmentDetailScreenState extends State<ShipmentDetailScreen> {
  bool _isSendingEmail = false;
  bool _emailSent      = false;

  Shipment get s => widget.shipment;

  static const _anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRqcmplZW1hYWN1bWVwaW1qbHRnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQxMjE2NjAsImV4cCI6MjA4OTY5NzY2MH0.gtBcFu-J48mPDk_S9ukfVdW-7gUmabGatmJ1g1_5zzo';

  Future<void> _downloadLabel() async {
    if (s.labelUrl.isEmpty) { _snack('Label URL not available.', isError: true); return; }
    final uri = Uri.parse(s.labelUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _snack('Could not open label.', isError: true);
    }
  }

  void _trackParcel() {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => TrackParcelScreen(initialTrackingNumber: s.trackingNumber),
    ));
  }

  Future<void> _sendLabelEmail() async {
    final email = context.read<AuthProvider>().email;
    if (email.isEmpty) { _snack('No email found.', isError: true); return; }
    if (s.labelUrl.isEmpty) { _snack('No label URL available.', isError: true); return; }

    setState(() { _isSendingEmail = true; });
    try {
      final res = await http.post(
        Uri.parse('https://tjrjeemaacumepimjltg.supabase.co/functions/v1/send-label-email'),
        headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer $_anonKey' },
        body: jsonEncode({
          'email': email, 'trackingNumber': s.trackingNumber,
          'labelUrl': s.labelUrl, 'carrier': s.carrier,
          'service': s.service, 'recipientName': s.recipientName,
          'recipientCity': s.recipientCity,
        }),
      ).timeout(const Duration(seconds: 15));
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['success'] == true) {
        setState(() { _emailSent = true; });
        _snack('Label sent to $email ✓');
      } else {
        _snack(data['error'] ?? 'Failed to send email.', isError: true);
      }
    } catch (e) {
      _snack('Network error. Please try again.', isError: true);
    }
    setState(() { _isSendingEmail = false; });
  }

  void _copyTracking() {
    Clipboard.setData(ClipboardData(text: s.trackingNumber));
    _snack('Tracking number copied!');
  }

  // ── Show fullscreen QR ────────────────────────────────────────
  void _showFullscreenQR() {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Scan to Open Label', style: TextStyle(
                fontFamily: 'Syne', fontSize: 16,
                fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
            const SizedBox(height: 6),
            const Text('Point your phone camera at this QR code',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Color(0xFF9B9B9B))),
            const SizedBox(height: 10),
            // Full size QR

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
            const SizedBox(height: 10),
            QrImageView(
              data: s.labelUrl,
              version: QrVersions.auto,
              size: 260,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Color(0xFF1A1A1A)),
              dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Color(0xFF1A1A1A)),
            ),
            const SizedBox(height: 16),
            Text(s.trackingNumber, style: const TextStyle(
                fontFamily: 'monospace', fontSize: 13,
                fontWeight: FontWeight.w700, color: Color(0xFF6B6B6B),
                letterSpacing: 1)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF6B6B6B),
                  side: const BorderSide(color: Color(0xFFE0E0E0)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Close'),
              )),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _downloadLabel();
                  },
                  icon: const Icon(Icons.download_rounded, size: 16, color: Colors.white),
                  label: const Text(
                    'Download',
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6D28D9),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              )
            ]),
          ]),
        ),
      ),
    );
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : const Color(0xFF059669),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F7),
      body: SafeArea(child: Column(children: [
        // Nav
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: const BoxDecoration(color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE)))),
          child: Row(children: [
            Container(width: 30, height: 30,
                decoration: BoxDecoration(color: const Color(0xFFFF5A00),
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.inventory_2_outlined, color: Colors.white, size: 16)),
            const SizedBox(width: 8),
            const Text('SwiftLabel', style: TextStyle(fontFamily: 'Syne',
                fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
            const Spacer(),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: const Row(children: [
                Icon(Icons.arrow_back_ios, size: 14, color: Color(0xFF6B6B6B)),
                Text('Back', style: TextStyle(fontSize: 13, color: Color(0xFF6B6B6B))),
              ]),
            ),
          ]),
        ),

        Expanded(child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 4),

            // Title + status
            const Text('Shipment Details', style: TextStyle(fontFamily: 'Syne',
                fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                  color: s.statusColor.withOpacity(0.1),
                  border: Border.all(color: s.statusColor.withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(20)),
              child: Text(s.statusLabel, style: TextStyle(fontSize: 12,
                  fontWeight: FontWeight.w600, color: s.statusColor)),
            ),
            const SizedBox(height: 20),

            // Carrier banner
            Container(
              width: double.infinity, padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [s.carrierColor.withOpacity(0.85), s.carrierColor],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: s.carrierColor.withOpacity(0.3),
                    blurRadius: 16, offset: const Offset(0, 6))],
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(s.carrier, style: const TextStyle(fontFamily: 'Syne',
                      fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),

                ]),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.white24,
                      borderRadius: BorderRadius.circular(20)),
                  child: Text(s.service, style: const TextStyle(fontSize: 11,
                      color: Colors.white, fontWeight: FontWeight.w500)),
                ),
                const SizedBox(height: 16),
                const Text('TRACKING NUMBER', style: TextStyle(fontSize: 10,
                    color: Colors.white70, letterSpacing: 1, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Row(children: [
                  Expanded(child: Text(s.trackingNumber, style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 17, fontWeight: FontWeight.w800,
                      color: Colors.white, letterSpacing: 1.5))),
                  GestureDetector(
                    onTap: _copyTracking,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.white24,
                          borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.copy_rounded, color: Colors.white, size: 16),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                Text('Booked on ${_fmtDate(s.createdAt)}',
                    style: const TextStyle(fontSize: 12, color: Colors.white70)),
              ]),
            ),

            const SizedBox(height: 16),

            // Action buttons
            Row(children: [
              Expanded(child: _Btn(icon: Icons.download_rounded,
                  label: 'Download Label', color: const Color(0xFF6D28D9),
                  onTap: s.labelUrl.isNotEmpty ? _downloadLabel : null)),
              const SizedBox(width: 10),
              Expanded(child: _Btn(icon: Icons.location_on_outlined,
                  label: 'Track Parcel', color: const Color(0xFFFF5A00),
                  onTap: _trackParcel)),
            ]),

            const SizedBox(height: 10),

            // Send to email
            SizedBox(
              width: double.infinity, height: 50,
              child: OutlinedButton.icon(
                onPressed: _isSendingEmail || _emailSent ? null : _sendLabelEmail,
                icon: _isSendingEmail
                    ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(
                        color: Color(0xFF059669), strokeWidth: 2))
                    : Icon(_emailSent
                    ? Icons.mark_email_read_rounded
                    : Icons.forward_to_inbox_rounded,
                    size: 18,
                    color: _emailSent
                        ? const Color(0xFF059669) : const Color(0xFF6B6B6B)),
                label: Text(
                  _emailSent ? 'Label sent to your email ✓'
                      : _isSendingEmail ? 'Sending...'
                      : 'Send Label to My Email',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                      color: _emailSent
                          ? const Color(0xFF059669) : const Color(0xFF3A3A3A)),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: _emailSent
                      ? const Color(0xFF059669) : const Color(0xFFDDDDDD)),
                  backgroundColor: _emailSent
                      ? const Color(0xFFF0FDF4) : Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // FROM / TO
            Row(children: [
              Expanded(child: _AddressCard(label: 'FROM', name: s.senderName,
                  city: s.senderCity, postcode: s.senderPostcode)),
              const SizedBox(width: 10),
              Expanded(child: _AddressCard(label: 'TO', name: s.recipientName,
                  city: s.recipientCity, postcode: s.recipientPostcode)),
            ]),

            const SizedBox(height: 16),

            // Parcel + price
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white,
                  border: Border.all(color: const Color(0xFFEEEEEE)),
                  borderRadius: BorderRadius.circular(14)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Parcel & Pricing', style: TextStyle(fontFamily: 'Syne',
                    fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
                const SizedBox(height: 12),
                _Row('Size',    s.parcelSize.isEmpty ? '—' : s.parcelSize),
                _Row('Type',    s.parcelType.isEmpty ? '—' : s.parcelType),
                _Row('Carrier', s.carrier),
                _Row('Service', s.service),
                const Divider(height: 20),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Total Paid', style: TextStyle(fontFamily: 'Syne',
                      fontSize: 14, fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A1A))),
                  Text('£${s.price.toStringAsFixed(2)}', style: const TextStyle(
                      fontFamily: 'Syne', fontSize: 16, fontWeight: FontWeight.w800,
                      color: Color(0xFF6D28D9))),
                ]),
              ]),
            ),

            const SizedBox(height: 16),

            // ── QR Code Card — REAL QR pointing to label URL ────
            if (s.labelUrl.isNotEmpty)
              Container(
                width: double.infinity, padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.white,
                    border: Border.all(color: const Color(0xFFEEEEEE)),
                    borderRadius: BorderRadius.circular(14)),
                child: Column(children: [
                  // Section title
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Scan Digital Label', style: TextStyle(
                            fontFamily: 'Syne', fontSize: 14,
                            fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
                        GestureDetector(
                          onTap: _showFullscreenQR,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6D28D9).withOpacity(0.08),
                              border: Border.all(color: const Color(0xFF6D28D9)
                                  .withOpacity(0.3)),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.fullscreen_rounded, size: 14,
                                      color: Color(0xFF6D28D9)),
                                  SizedBox(width: 4),
                                  Text('Expand', style: TextStyle(fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF6D28D9))),
                                ]),
                          ),
                        ),
                      ]),
                  const SizedBox(height: 8),
                  Container(
                      alignment: Alignment.center,
                      child: const Text('Scan this QR code yourself, or show it to the staff at your drop-off point.',textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Color(0xFF6B6B6B)))),
                  const SizedBox(height: 16),
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

                  // ── REAL QR Code — data = labelUrl ──────────
                  GestureDetector(
                    onTap: _showFullscreenQR, // tap to expand
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: const Color(0xFFEEEEEE),
                            width: 2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: QrImageView(
                        // ← The QR encodes the label PDF URL
                        // Scan it → opens the Shippo label PDF
                        data: s.labelUrl,
                        version: QrVersions.auto,
                        size: 180,
                        backgroundColor: Colors.white,
                        eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: Color(0xFF1A1A1A)),
                        dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: Color(0xFF1A1A1A)),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),
                  const Text('📱 Scan to open label PDF on any device',
                      style: TextStyle(fontSize: 12, color: Color(0xFF6B6B6B))),
                  const SizedBox(height: 4),
                  const Text('Tap the QR to expand fullscreen',
                      style: TextStyle(fontSize: 11, color: Color(0xFFB0B0B0))),

                  const SizedBox(height: 16),

                  // Download button
                  SizedBox(width: double.infinity, height: 46,
                      child: ElevatedButton.icon(
                        onPressed: _downloadLabel,
                        icon: const Icon(Icons.download_rounded,
                            size: 18, color: Colors.white),
                        label: const Text('Download Label PDF'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6D28D9),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          textStyle: const TextStyle(fontFamily: 'Syne',
                              fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                      )),
                ]),
              ),

            const SizedBox(height: 40),
          ]),
        )),
      ])),
    );
  }

  Widget _Row(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF9B9B9B))),
      Text(value, style: const TextStyle(fontSize: 13,
          fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A))),
    ]),
  );

  String _fmtDate(DateTime dt) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${dt.day} ${m[dt.month-1]} ${dt.year}';
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────

class _Btn extends StatelessWidget {
  final IconData icon; final String label;
  final Color color; final VoidCallback? onTap;
  const _Btn({required this.icon, required this.label,
    required this.color, this.onTap});

  @override
  Widget build(BuildContext context) => SizedBox(height: 60,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color, foregroundColor: Colors.white,
          disabledBackgroundColor: color.withOpacity(0.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 10),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 20, color: Colors.white),
          const SizedBox(height: 4),
          Text(label, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11,
                  fontWeight: FontWeight.w600, height: 1.2)),
        ]),
      ));
}

class _AddressCard extends StatelessWidget {
  final String label, name, city, postcode;
  const _AddressCard({required this.label, required this.name,
    required this.city, required this.postcode});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Colors.white,
        border: Border.all(color: const Color(0xFFEEEEEE)),
        borderRadius: BorderRadius.circular(12)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
          color: Color(0xFF9B9B9B), letterSpacing: 0.8)),
      const SizedBox(height: 6),
      Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
          color: Color(0xFF1A1A1A)), maxLines: 1, overflow: TextOverflow.ellipsis),
      Text('$city, $postcode',
          style: const TextStyle(fontSize: 12, color: Color(0xFF6B6B6B))),
    ]),
  );
}