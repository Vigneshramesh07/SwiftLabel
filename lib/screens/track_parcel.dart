import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/tracking_provider.dart';

class TrackParcelScreen extends StatefulWidget {
  final String? initialTrackingNumber;
  const TrackParcelScreen({super.key, this.initialTrackingNumber});

  @override
  State<TrackParcelScreen> createState() => _TrackParcelScreenState();
}

class _TrackParcelScreenState extends State<TrackParcelScreen> {
  final _ctrl    = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    if (widget.initialTrackingNumber != null &&
        widget.initialTrackingNumber!.isNotEmpty) {
      _ctrl.text = widget.initialTrackingNumber!.toUpperCase();
      WidgetsBinding.instance.addPostFrameCallback((_) => _track());
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _track() async {
    if (_ctrl.text.trim().isEmpty) return;
    if (_formKey.currentState != null) {
      if (!_formKey.currentState!.validate()) return;
    }
    await context.read<TrackingProvider>().trackParcel(
        _ctrl.text.trim().toUpperCase());
  }

  void _clear() {
    _ctrl.clear();
    context.read<TrackingProvider>().reset();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<TrackingProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F7),
      body: SafeArea(child: Column(children: [
        // ── Top Nav ───────────────────────────────────────────
        Container(
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
            const Text('SwiftLabel', style: TextStyle(fontFamily: 'Syne',
                fontSize: 17, fontWeight: FontWeight.w800,
                color: Color(0xFF1A1A1A))),
            const Spacer(),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: const Row(children: [
                Icon(Icons.arrow_back_ios, size: 14, color: Color(0xFF6B6B6B)),
                Text('Back to Dashboard', style: TextStyle(fontSize: 13, color: Color(0xFF6B6B6B))),
              ]),
            ),
          ]),
        ),

        Expanded(child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 8),
            const Text('Track a Parcel', style: TextStyle(fontFamily: 'Syne',
                fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
            const SizedBox(height: 4),
            const Text('Enter your tracking number for real-time updates',
                style: TextStyle(fontSize: 13, color: Color(0xFF9B9B9B))),
            const SizedBox(height: 20),

            // ── Search card ────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  color: const Color(0xFFFFF5EE),
                  border: Border.all(color: const Color(0xFFFFDDCC)),
                  borderRadius: BorderRadius.circular(16)),
              child: Form(
                key: _formKey,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Tracking Number', style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: Color(0xFF3A3A3A))),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: TextFormField(
                      controller: _ctrl,
                      textCapitalization: TextCapitalization.characters,
                      style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A1A),
                          fontFamily: 'monospace', letterSpacing: 1.2),
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'e.g. RM123456789GB',
                        hintStyle: const TextStyle(color: Color(0xFFB0B0B0),
                            fontSize: 14, letterSpacing: 0),
                        filled: true, fillColor: Colors.white,
                        prefixIcon: const Icon(Icons.search_rounded,
                            size: 18, color: Color(0xFF9B9B9B)),
                        suffixIcon: _ctrl.text.isNotEmpty
                            ? GestureDetector(onTap: _clear,
                            child: const Icon(Icons.close_rounded,
                                size: 18, color: Color(0xFF9B9B9B)))
                            : null,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 13),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                                color: Color(0xFFFF5A00), width: 1.5)),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Enter a tracking number';
                        if (v.length < 6) return 'Too short';
                        return null;
                      },
                    )),
                    const SizedBox(width: 10),
                    SizedBox(width: 52, height: 52,
                        child: ElevatedButton(
                          onPressed: p.isLoading ? null : _track,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF5A00),
                            foregroundColor: Colors.white,
                            minimumSize: Size.zero, padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          child: p.isLoading
                              ? const SizedBox(height: 18, width: 18,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                              : const Icon(Icons.arrow_forward_rounded, size: 20,color: Colors.white),
                        )),
                  ]),
                  const SizedBox(height: 12),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    const Text('Supports:', style: TextStyle(
                        fontSize: 11, color: Color(0xFF9B9B9B))),
                    ...['Royal Mail','Evri','DPD','DHL','InPost','Yodel'].map((c) =>
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: Colors.white,
                              border: Border.all(color: const Color(0xFFE0E0E0)),
                              borderRadius: BorderRadius.circular(20)),
                          child: Text(c, style: const TextStyle(fontSize: 10,
                              fontWeight: FontWeight.w500, color: Color(0xFF6B6B6B))),
                        )),
                  ]),
                ]),
              ),
            ),

            // ── Error ─────────────────────────────────────────
            if (p.hasError) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.red.withOpacity(0.05),
                    border: Border.all(color: Colors.red.withOpacity(0.2)),
                    borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  const Icon(Icons.error_outline_rounded, color: Colors.red, size: 18),
                  const SizedBox(width: 10),
                  Expanded(child: Text(p.errorMessage,
                      style: const TextStyle(fontSize: 13, color: Colors.red))),
                ]),
              ),
            ],

            // ── Loading ───────────────────────────────────────
            if (p.isLoading) ...[
              const SizedBox(height: 40),
              const Center(child: Column(children: [
                CircularProgressIndicator(color: Color(0xFFFF5A00), strokeWidth: 2.5),
                SizedBox(height: 14),
                Text('Fetching live tracking info...',
                    style: TextStyle(fontSize: 13, color: Color(0xFF9B9B9B))),
              ])),
            ],

            // ── Result ────────────────────────────────────────
            if (p.result != null) ...[
              const SizedBox(height: 24),

              // ── TEST MODE BANNER (shown for mock tracking numbers) ──
              if (p.result!.isMock) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F0FF),
                    border: Border.all(color: const Color(0xFFDDD6FE)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(children: [
                    const Icon(Icons.science_outlined,
                        size: 18, color: Color(0xFF6D28D9)),
                    const SizedBox(width: 10),
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Test Mode — Mock Tracking',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                              color: Color(0xFF6D28D9))),
                      const SizedBox(height: 2),
                      const Text(
                        'This is a test label. Real tracking will be available '
                            'once you switch to production mode and add funds to ShipEngine.',
                        style: TextStyle(fontSize: 11, color: Color(0xFF7C3AED), height: 1.4),
                      ),
                    ])),
                  ]),
                ),
                const SizedBox(height: 14),
              ],

              _StatusBanner(status: p.result!.status),
              const SizedBox(height: 14),
              _ParcelInfoCard(result: p.result!),
              const SizedBox(height: 14),
              if (p.result!.events.isNotEmpty)
                _TrackingTimeline(events: p.result!.events),
              const SizedBox(height: 14),
              _ActionButtons(onRefresh: _track),
            ],

            // ── Empty state ───────────────────────────────────
            if (p.result == null && !p.hasError && !p.isLoading) ...[
              const SizedBox(height: 28),
              _TipCard(),
            ],

            const SizedBox(height: 40),
          ]),
        )),
      ])),
    );
  }
}

// ── Status Banner ─────────────────────────────────────────────────
class _StatusBanner extends StatelessWidget {
  final TrackingStatus status;
  const _StatusBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    final cfg = _config();
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: (cfg['color'] as Color).withOpacity(0.08),
          border: Border.all(color: (cfg['color'] as Color).withOpacity(0.2)),
          borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Icon(cfg['icon'] as IconData, color: cfg['color'] as Color, size: 30),
        const SizedBox(width: 14),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(cfg['label'] as String, style: TextStyle(fontFamily: 'Syne',
              fontSize: 18, fontWeight: FontWeight.w800,
              color: cfg['color'] as Color)),
          Text('Last updated: just now', style: TextStyle(fontSize: 12,
              color: (cfg['color'] as Color).withOpacity(0.7))),
        ]),
      ]),
    );
  }

  Map<String, dynamic> _config() {
    switch (status) {
      case TrackingStatus.delivered:
        return {'color': const Color(0xFF059669),
          'icon': Icons.check_circle_outline_rounded, 'label': 'Delivered'};
      case TrackingStatus.inTransit:
        return {'color': const Color(0xFFFF5A00),
          'icon': Icons.local_shipping_outlined, 'label': 'In Transit'};
      case TrackingStatus.outForDelivery:
        return {'color': const Color(0xFF0284C7),
          'icon': Icons.delivery_dining_outlined, 'label': 'Out for Delivery'};
      case TrackingStatus.processing:
        return {'color': const Color(0xFF6D28D9),
          'icon': Icons.inventory_2_outlined, 'label': 'Label Created'};
      case TrackingStatus.exception:
        return {'color': Colors.red,
          'icon': Icons.warning_amber_rounded, 'label': 'Delivery Exception'};
    }
  }
}

// ── Parcel info ───────────────────────────────────────────────────
class _ParcelInfoCard extends StatelessWidget {
  final TrackingResult result;
  const _ParcelInfoCard({required this.result});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white,
        border: Border.all(color: const Color(0xFFEEEEEE)),
        borderRadius: BorderRadius.circular(14)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('Parcel Details', style: TextStyle(fontFamily: 'Syne',
            fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: result.courierColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(20)),
          child: Row(children: [
            Container(width: 8, height: 8,
                decoration: BoxDecoration(color: result.courierColor,
                    shape: BoxShape.circle)),
            const SizedBox(width: 5),
            Text(result.courier, style: TextStyle(fontSize: 11,
                fontWeight: FontWeight.w600, color: result.courierColor)),
          ]),
        ),
      ]),
      const SizedBox(height: 14),
      _DetailRow('Tracking No.', result.trackingNumber, mono: true),
      _DetailRow('Service',      result.service),
      if (result.origin.isNotEmpty && result.origin != 'Unknown')
        _DetailRow('From', result.origin),
      if (result.destination.isNotEmpty && result.destination != 'Unknown')
        _DetailRow('To', result.destination),
      _DetailRow('Est. Delivery', result.estimatedDelivery),
    ]),
  );

  Widget _DetailRow(String label, String value, {bool mono = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF9B9B9B))),
      Flexible(child: Text(value, textAlign: TextAlign.right,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
              color: const Color(0xFF1A1A1A),
              fontFamily: mono ? 'monospace' : null))),
    ]),
  );
}

// ── Timeline ──────────────────────────────────────────────────────
class _TrackingTimeline extends StatelessWidget {
  final List<TrackingEvent> events;
  const _TrackingTimeline({required this.events});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white,
        border: Border.all(color: const Color(0xFFEEEEEE)),
        borderRadius: BorderRadius.circular(14)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Tracking History', style: TextStyle(fontFamily: 'Syne',
          fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
      const SizedBox(height: 16),
      ...List.generate(events.length, (i) {
        final e       = events[i];
        final isFirst = i == 0;
        final isLast  = i == events.length - 1;
        return IntrinsicHeight(child: Row(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 24, child: Column(children: [
            Container(
              width: 12, height: 12,
              margin: const EdgeInsets.only(top: 3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isFirst ? const Color(0xFFFF5A00) : const Color(0xFFE0E0E0),
                border: isFirst ? Border.all(
                    color: const Color(0xFFFF5A00).withOpacity(0.3), width: 3) : null,
              ),
            ),
            if (!isLast) Expanded(child: Container(width: 1.5,
                color: const Color(0xFFEEEEEE),
                margin: const EdgeInsets.symmetric(vertical: 4))),
          ])),
          const SizedBox(width: 12),
          Expanded(child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.title, style: TextStyle(fontSize: 13,
                  fontWeight: isFirst ? FontWeight.w600 : FontWeight.w500,
                  color: isFirst ? const Color(0xFF1A1A1A) : const Color(0xFF3A3A3A))),
              const SizedBox(height: 2),
              if (e.location.isNotEmpty)
                Text(e.location, style: const TextStyle(
                    fontSize: 12, color: Color(0xFF9B9B9B))),
              if (e.timestamp.isNotEmpty)
                Text(e.timestamp, style: const TextStyle(
                    fontSize: 11, color: Color(0xFFB0B0B0))),
            ]),
          )),
        ]));
      }),
    ]),
  );
}

// ── Action Buttons ────────────────────────────────────────────────
class _ActionButtons extends StatelessWidget {
  final Future<void> Function() onRefresh;
  const _ActionButtons({required this.onRefresh});

  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: OutlinedButton.icon(
      onPressed: () {},
      icon: const Icon(Icons.share_outlined, size: 16, color: Color(0xFF3A3A3A)),
      label: const Text('Share'),
      style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF3A3A3A),
          side: const BorderSide(color: Color(0xFFE0E0E0)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(vertical: 12)),
    )),
    const SizedBox(width: 10),
    Expanded(child: ElevatedButton.icon(
      onPressed: onRefresh,
      icon: const Icon(Icons.refresh_rounded, size: 16, color: Colors.white),
      label: const Text('Refresh'),
      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF5A00),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(vertical: 12),
          textStyle: const TextStyle(fontFamily: 'Syne',
              fontSize: 14, fontWeight: FontWeight.w700)),
    )),
  ]);
}

// ── Tip card ──────────────────────────────────────────────────────
class _TipCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: const Color(0xFFF0FDF4),
        border: Border.all(color: const Color(0xFFBBF7D0)),
        borderRadius: BorderRadius.circular(12)),
    child: const Row(children: [
      Icon(Icons.lightbulb_outline_rounded, size: 16, color: Color(0xFF059669)),
      SizedBox(width: 10),
      Expanded(child: Text(
        'Your tracking number is on your confirmation email or parcel label.',
        style: TextStyle(fontSize: 12, color: Color(0xFF059669), height: 1.4),
      )),
    ]),
  );
}