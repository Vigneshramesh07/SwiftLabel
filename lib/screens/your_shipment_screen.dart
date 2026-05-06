// lib/screens/your_shipments_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/auth_provider.dart';
import '../providers/parcel_provider.dart';
import 'shipmentDetails_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Bulk Order Model
// ─────────────────────────────────────────────────────────────────────────────

class BulkOrder {
  final String id, batchName, userEmail, status;
  final String senderName, senderCity, senderPostcode;
  final int totalParcels, processed, failed;
  final double totalCost;
  final DateTime createdAt;

  const BulkOrder({
    required this.id,
    required this.batchName,
    required this.userEmail,
    required this.status,
    required this.senderName,
    required this.senderCity,
    required this.senderPostcode,
    required this.totalParcels,
    required this.processed,
    required this.failed,
    required this.totalCost,
    required this.createdAt,
  });

  factory BulkOrder.fromJson(Map<String, dynamic> j) => BulkOrder(
    id:             j['id']?.toString()              ?? '',
    batchName:      j['batch_name']?.toString()      ?? 'Batch',
    userEmail:      j['user_email']?.toString()      ?? '',
    status:         j['status']?.toString()          ?? 'completed',
    senderName:     j['sender_name']?.toString()     ?? '',
    senderCity:     j['sender_city']?.toString()     ?? '',
    senderPostcode: j['sender_postcode']?.toString() ?? '',
    totalParcels:   (j['total_parcels'] as num?)?.toInt()  ?? 0,
    processed:      (j['processed']     as num?)?.toInt()  ?? 0,
    failed:         (j['failed']        as num?)?.toInt()  ?? 0,
    totalCost:      (j['total_cost']    as num?)?.toDouble() ?? 0,
    createdAt:      j['created_at'] != null
        ? DateTime.parse(j['created_at'])
        : DateTime.now(),
  );

  Color get statusColor {
    switch (status) {
      case 'completed': return const Color(0xFF059669);
      case 'partial':   return const Color(0xFFD97706);
      case 'failed':    return Colors.red;
      default:          return const Color(0xFF6D28D9);
    }
  }

  String get statusLabel {
    switch (status) {
      case 'completed':  return 'Completed';
      case 'partial':    return 'Partial';
      case 'failed':     return 'Failed';
      case 'processing': return 'Processing';
      default:           return 'Completed';
    }
  }

  int get successCount => (processed - failed).clamp(0, totalParcels);
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class YourShipmentsScreen extends StatefulWidget {
  const YourShipmentsScreen({super.key});
  @override
  State<YourShipmentsScreen> createState() => _YourShipmentsScreenState();
}

class _YourShipmentsScreenState extends State<YourShipmentsScreen>
    with SingleTickerProviderStateMixin {

  late TabController _tabCtrl;

  final _searchCtrl    = TextEditingController();
  String _searchQuery  = '';
  String _activeFilter = 'All';
  String _sortBy       = 'Newest';

  static const _filters = ['All', 'Active', 'Delivered', 'Pending', 'International'];

  final _supabase     = Supabase.instance.client;
  List<BulkOrder> _bulkOrders  = [];
  bool            _loadingBulk = false;
  String          _bulkError   = '';

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    // Load bulk orders immediately on screen open
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadBulkOrders());
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBulkOrders() async {
    final email = context.read<AuthProvider>().email.trim().toLowerCase();
    if (email.isEmpty) return;
    if (mounted) setState(() { _loadingBulk = true; _bulkError = ''; });

    try {
      final data = await _supabase
          .from('bulk_orders')
          .select()
          .eq('user_email', email)
          .order('created_at', ascending: false);

      final list = (data as List)
          .map((j) => BulkOrder.fromJson(j as Map<String, dynamic>))
          .toList();

      if (mounted) setState(() => _bulkOrders = list);
      debugPrint('[Bulk] loaded ${list.length} orders');
    } catch (e) {
      debugPrint('[Bulk] error: $e');
      if (mounted) setState(() => _bulkError = 'Could not load bulk orders.');
    }

    if (mounted) setState(() => _loadingBulk = false);
  }

  List<Shipment> _filtered(List<Shipment> all) {
    var list = List<Shipment>.from(all);
    if (_activeFilter != 'All') {
      list = list.where((s) {
        final st = s.status.toLowerCase();
        switch (_activeFilter) {
          case 'Active':        return st != 'delivered';
          case 'Delivered':     return st == 'delivered';
          case 'Pending':       return st == 'pending' || st == 'label_created';
          case 'International': return s.isInternational;
          default:              return true;
        }
      }).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((s) =>
      s.trackingNumber.toLowerCase().contains(q) ||
          s.recipientName.toLowerCase().contains(q)  ||
          s.recipientCity.toLowerCase().contains(q)  ||
          s.carrier.toLowerCase().contains(q)        ||
          s.recipientCountry.toLowerCase().contains(q)).toList();
    }
    switch (_sortBy) {
      case 'Oldest': list.sort((a, b) => a.createdAt.compareTo(b.createdAt)); break;
      case 'Carrier': list.sort((a, b) => a.carrier.compareTo(b.carrier)); break;
      default: list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    return list;
  }

  int _countActive(List<Shipment> all) =>
      all.where((s) => s.status.toLowerCase() != 'delivered').length;
  int _countByStatus(List<Shipment> all, String status) =>
      all.where((s) => s.status.toLowerCase() == status.toLowerCase()).length;
  int _countPending(List<Shipment> all) =>
      all.where((s) { final st = s.status.toLowerCase(); return st == 'pending' || st == 'label_created'; }).length;
  int _countInternational(List<Shipment> all) =>
      all.where((s) => s.isInternational).length;

  void _goToDetail(Shipment s) => Navigator.push(
      context, MaterialPageRoute(builder: (_) => ShipmentDetailScreen(shipment: s)));

  void _openBatchDetail(BulkOrder b) => Navigator.push(
      context, MaterialPageRoute(builder: (_) => _BatchDetailScreen(batch: b)));

  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _SortSheet(
        current: _sortBy,
        onSelect: (v) => setState(() => _sortBy = v),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final email  = context.read<AuthProvider>().email;
    final parcel = context.watch<ParcelProvider>();
    final all = parcel.recentShipments
        .where((s) => s.source != 'bulk')
        .toList();
    final shown  = _filtered(all);

    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F7),
      body: SafeArea(child: Column(children: [

        _TopBar(onSort: _showSortSheet, sortLabel: _sortBy),

        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tabCtrl,
            labelColor: const Color(0xFFFF5A00),
            unselectedLabelColor: const Color(0xFF9B9B9B),
            indicatorColor: const Color(0xFFFF5A00),
            indicatorWeight: 2.5,
            labelStyle: const TextStyle(
                 fontSize: 13, fontWeight: FontWeight.w700),
            unselectedLabelStyle: const TextStyle(fontSize: 13),
            tabs: [
              Tab(text: 'Shipments (${all.length})'),
              Tab(text: 'Bulk Orders (${_bulkOrders.length})'),
            ],
          ),
        ),

        Expanded(child: TabBarView(
          controller: _tabCtrl,
          children: [

            // ── TAB 1: Individual Shipments ───────────────────
            Column(children: [
              if (all.isNotEmpty) _StatsStrip(
                total:         all.length,
                active:        _countActive(all),
                delivered:     _countByStatus(all, 'delivered'),
                pending:       _countPending(all),
                international: _countInternational(all),
              ),
              _SearchBar(ctrl: _searchCtrl,
                  onChanged: (v) => setState(() => _searchQuery = v)),
              _FilterChips(filters: _filters, active: _activeFilter,
                  all: all, onSelect: (f) => setState(() => _activeFilter = f)),
              Expanded(child: _buildShipmentsBody(parcel, all, shown, email)),
            ]),

            // ── TAB 2: Bulk Orders ────────────────────────────
            _buildBulkTab(email),
          ],
        )),
      ])),
    );
  }

  Widget _buildShipmentsBody(ParcelProvider parcel, List<Shipment> all,
      List<Shipment> shown, String email) {
    if (parcel.isLoadingShipments) {
      return const Center(child: CircularProgressIndicator(
          color: Color(0xFFFF5A00), strokeWidth: 2));
    }
    if (all.isEmpty) return _EmptyState(onRefresh: () => parcel.getShipments(email));
    if (shown.isEmpty) {
      return _NoResultsState(
        query:  _searchQuery,
        filter: _activeFilter,
        onClear: () => setState(() {
          _searchQuery  = '';
          _activeFilter = 'All';
          _searchCtrl.clear();
        }),
      );
    }
    return RefreshIndicator(
      color: const Color(0xFFFF5A00),
      onRefresh: () => parcel.getShipments(email),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        itemCount: shown.length + 1,
        itemBuilder: (ctx, i) {
          if (i == shown.length) {
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Center(child: Text(
                '${shown.length} shipment${shown.length == 1 ? '' : 's'} shown',
                style: const TextStyle(fontSize: 11, color: Color(0xFFB0B0B0)),
              )),
            );
          }
          final s           = shown[i];
          final showDivider = i == 0 || !_sameDay(shown[i - 1].createdAt, s.createdAt);
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (showDivider) _DateDivider(date: s.createdAt),
            _ShipmentCard(shipment: s, onTap: () => _goToDetail(s)),
          ]);
        },
      ),
    );
  }

  Widget _buildBulkTab(String email) {
    if (_loadingBulk) {
      return const Center(child: CircularProgressIndicator(
          color: Color(0xFFFF5A00), strokeWidth: 2));
    }
    if (_bulkError.isNotEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline_rounded, color: Colors.red, size: 40),
        const SizedBox(height: 12),
        Text(_bulkError, style: const TextStyle(fontSize: 13, color: Colors.red)),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _loadBulkOrders,
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('Retry'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF5A00),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ]));
    }
    if (_bulkOrders.isEmpty) {
      return RefreshIndicator(
        color: const Color(0xFFFF5A00),
        onRefresh: _loadBulkOrders,
        child: ListView(
          padding: const EdgeInsets.all(40),
          children: [Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 80, height: 80,
                decoration: BoxDecoration(color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(20)),
                child: const Icon(Icons.layers_outlined, size: 36,
                    color: Color(0xFFDDDDDD))),
            const SizedBox(height: 16),
            const Text('No bulk orders yet', style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
            const SizedBox(height: 6),
            const Text('Your bulk batch history will appear here.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Color(0xFF9B9B9B))),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loadBulkOrders,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Refresh'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF5A00),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ])],
        ),
      );
    }

    // ── Summary strip ─────────────────────────────────────────────
    final totalBatches  = _bulkOrders.length;
    final totalLabels   = _bulkOrders.fold(0, (s, b) => s + b.successCount);
    final totalSpent    = _bulkOrders.fold(0.0, (s, b) => s + b.totalCost);
    final completedCount = _bulkOrders.where((b) => b.status == 'completed').length;

    return RefreshIndicator(
      color: const Color(0xFFFF5A00),
      onRefresh: _loadBulkOrders,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        itemCount: _bulkOrders.length + 2, // +2 for summary header + footer
        itemBuilder: (_, i) {

          // ── Summary card at top ───────────────────────────────
          if (i == 0) {
            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Bulk Order Summary', style: TextStyle(
                     fontSize: 13,
                    fontWeight: FontWeight.w700, color: Colors.white)),
                const SizedBox(height: 14),
                Row(children: [
                  _BulkSummaryTile('$totalBatches', 'Batches',   const Color(0xFFFF5A00)),
                  _BulkSummaryTile('$totalLabels',  'Labels',    const Color(0xFF059669)),
                  _BulkSummaryTile('$completedCount', 'Done',    const Color(0xFF6D28D9)),
                  _BulkSummaryTile('£${totalSpent.toStringAsFixed(2)}', 'Spent', const Color(0xFFFFD700)),
                ]),
              ]),
            );
          }

          // ── Footer label ──────────────────────────────────────
          if (i == _bulkOrders.length + 1) {
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Center(child: Text(
                '$totalBatches batch${totalBatches == 1 ? '' : 'es'} · $totalLabels labels total',
                style: const TextStyle(fontSize: 11, color: Color(0xFFB0B0B0)),
              )),
            );
          }

          return _BulkOrderCard(
            order: _bulkOrders[i - 1],
            onTap: () => _openBatchDetail(_bulkOrders[i - 1]),
          );
        },
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
class _BulkSummaryTile extends StatelessWidget {
  final String value, label; final Color color;
  const _BulkSummaryTile(this.value, this.label, this.color);
  @override
  Widget build(BuildContext context) => Expanded(child: Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(value, style: TextStyle( fontSize: 18,
        fontWeight: FontWeight.w800, color: color),
        overflow: TextOverflow.ellipsis),
    Text(label, style: TextStyle(fontSize: 10,
        color: Colors.white.withOpacity(0.55))),
  ],
  ));
}

// ─────────────────────────────────────────────────────────────────────────────
// Batch Detail Screen
// ─────────────────────────────────────────────────────────────────────────────

class _BatchDetailScreen extends StatefulWidget {
  final BulkOrder batch;
  const _BatchDetailScreen({required this.batch});
  @override
  State<_BatchDetailScreen> createState() => _BatchDetailScreenState();
}

class _BatchDetailScreenState extends State<_BatchDetailScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _labels = [];
  bool   _loading = true;
  String _error   = '';

  @override
  void initState() {
    super.initState();
    _loadLabels();
  }

  Future<void> _loadLabels() async {
    setState(() { _loading = true; _error = ''; });
    try {
      List<Map<String, dynamic>> data = [];

      // ── Primary: query by bulk_order_id ──────────────────────
      if (widget.batch.id.isNotEmpty) {
        try {
          final result = await _supabase
              .from('shipments')
              .select()
              .eq('bulk_order_id', widget.batch.id)
              .order('created_at', ascending: true);
          data = List<Map<String, dynamic>>.from(result as List);
          debugPrint('[Batch] bulk_order_id query: ${data.length} results');
        } catch (e) {
          debugPrint('[Batch] bulk_order_id column missing, using fallback: $e');
        }
      }

      // ── Fallback: sender_name + date range ────────────────────
      if (data.isEmpty) {
        debugPrint('[Batch] Falling back to sender_name + date query');
        final start = DateTime(
          widget.batch.createdAt.year,
          widget.batch.createdAt.month,
          widget.batch.createdAt.day,
        ).toIso8601String();
        final end = DateTime(
          widget.batch.createdAt.year,
          widget.batch.createdAt.month,
          widget.batch.createdAt.day,
          23, 59, 59,
        ).toIso8601String();

        final fallback = await _supabase
            .from('shipments')
            .select()
            .eq('user_email', widget.batch.userEmail)
            .eq('sender_name', widget.batch.senderName)
            .gte('created_at', start)
            .lte('created_at', end)
            .order('created_at', ascending: true);
        data = List<Map<String, dynamic>>.from(fallback as List);
        debugPrint('[Batch] Fallback query: ${data.length} results');
      }

      setState(() => _labels = data);
    } catch (e) {
      setState(() => _error = 'Could not load labels for this batch.');
      debugPrint('[Batch] load labels: $e');
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.batch;
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'];
    final dateStr =
        '${b.createdAt.day} ${months[b.createdAt.month - 1]} ${b.createdAt.year}';

    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F7),
      body: SafeArea(child: Column(children: [

        // ── Nav ───────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: const BoxDecoration(color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE)))),
          child: Row(children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(width: 36, height: 36,
                  decoration: BoxDecoration(color: const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.arrow_back_ios_new_rounded,
                      size: 16, color: Color(0xFF1A1A1A))),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(b.batchName, style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800,
                      color: Color(0xFF1A1A1A))),
                  Text(dateStr,
                      style: const TextStyle(fontSize: 11, color: Color(0xFF9B9B9B))),
                ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                  color: b.statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: b.statusColor.withOpacity(0.3))),
              child: Text(b.statusLabel, style: TextStyle(fontSize: 11,
                  fontWeight: FontWeight.w700, color: b.statusColor)),
            ),
          ]),
        ),

        // ── Summary strip ─────────────────────────────────────
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Row(children: [
            _BStat('${b.totalParcels}', 'Total',   const Color(0xFF6D28D9)),
            _bDivider(),
            _BStat('${b.successCount}', 'Success', const Color(0xFF059669)),
            _bDivider(),
            _BStat('${b.failed}',       'Failed',
                b.failed > 0 ? Colors.red : const Color(0xFF9B9B9B)),
            _bDivider(),
            _BStat(b.senderCity,        'From',    const Color(0xFF0284C7)),
          ]),
        ),

        // ── Labels list ───────────────────────────────────────
        Expanded(child: _loading
            ? const Center(child: CircularProgressIndicator(
            color: Color(0xFFFF5A00), strokeWidth: 2))
            : _error.isNotEmpty
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline_rounded,
              color: Colors.red, size: 36),
          const SizedBox(height: 10),
          Text(_error,
              style: const TextStyle(fontSize: 13, color: Colors.red)),
          const SizedBox(height: 14),
          ElevatedButton(
            onPressed: _loadLabels,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF5A00),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Retry'),
          ),
        ]))
            : _labels.isEmpty
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.inbox_outlined,
              size: 48, color: Color(0xFFDDDDDD)),
          const SizedBox(height: 12),
          const Text('No labels found for this batch.',
              style: TextStyle(fontSize: 13,
                  color: Color(0xFF9B9B9B))),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _loadLabels,
            icon: const Icon(Icons.refresh_rounded, size: 14),
            label: const Text('Refresh'),
            style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFFF5A00)),
          ),
        ]))
            : RefreshIndicator(
          color: const Color(0xFFFF5A00),
          onRefresh: _loadLabels,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            itemCount: _labels.length,
            itemBuilder: (_, i) => _BatchLabelCard(
              data: _labels[i],
              index: i + 1,
              onTap: () {
                final shipment = Shipment.fromJson(_labels[i]);
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) =>
                      ShipmentDetailScreen(shipment: shipment),
                ));
              },
            ),
          ),
        )),
      ])),
    );
  }

  Widget _bDivider() => Container(
      width: 1, height: 32,
      margin: const EdgeInsets.symmetric(horizontal: 14),
      color: const Color(0xFFEEEEEE));
}

class _BStat extends StatelessWidget {
  final String value, label; final Color color;
  const _BStat(this.value, this.label, this.color);
  @override
  Widget build(BuildContext context) => Expanded(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(value, style: TextStyle( fontSize: 16,
        fontWeight: FontWeight.w800, color: color),
        overflow: TextOverflow.ellipsis),
    Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF9B9B9B))),
  ]));
}

// ─────────────────────────────────────────────────────────────────────────────
// Batch Label Card — tappable, navigates to ShipmentDetailScreen
// ─────────────────────────────────────────────────────────────────────────────

class _BatchLabelCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final int                  index;
  final VoidCallback         onTap;
  const _BatchLabelCard({
    required this.data,
    required this.index,
    required this.onTap,
  });

  static const _carrierAssets = <String, String>{
    'Royal Mail':                   'assets/carriers/royal_mail.png',
    'Parcelforce Royal Mail':       'assets/carriers/parcelforce.png',
    'Parcelforce':                  'assets/carriers/parcelforce.png',
    'Evri':                         'assets/carriers/evri.png',
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

  Color _carrierColor(String carrier) {
    final c = carrier.toLowerCase();
    if (c.contains('royal'))      return const Color(0xFFE30613);
    if (c.contains('evri'))       return const Color(0xFF8B5CF6);
    if (c.contains('dpd'))        return const Color(0xFFE8001C);
    if (c.contains('yodel'))      return const Color(0xFF6D28D9);
    if (c.contains('parcel'))     return const Color(0xFF003087);
    if (c.contains('fedex'))      return const Color(0xFF4D148C);
    if (c.contains('dhl'))        return const Color(0xFFFFC300);
    if (c.contains('ups'))        return const Color(0xFF351C15);
    if (c.contains('globalpost')) return const Color(0xFF0284C7);
    return const Color(0xFF6B6B6B);
  }

  @override
  Widget build(BuildContext context) {
    final carrier   = data['carrier']?.toString()            ?? 'Carrier';
    final tracking  = data['tracking_number']?.toString()    ?? '';
    final labelUrl  = data['label_url']?.toString()          ?? '';
    final recipName = data['recipient_name']?.toString()     ?? '';
    final recipCity = data['recipient_city']?.toString()     ?? '';
    final recipPc   = data['recipient_postcode']?.toString() ?? '';
    final service   = data['service']?.toString()            ?? '';
    final price     = (data['price'] as num?)?.toDouble()    ?? 0;
    final color     = _carrierColor(carrier);
    final assetPath = _carrierAssets[carrier];

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFEEEEEE)),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03),
              blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Column(children: [

          // ── Main row ───────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [

              // Index badge
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                    color: const Color(0xFFFFF5EE),
                    borderRadius: BorderRadius.circular(8)),
                child: Center(child: Text('$index', style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w800,
                    color: Color(0xFFFF5A00)))),
              ),
              const SizedBox(width: 10),

              // Carrier logo
              Container(
                width: 40, height: 28,
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFEEEEEE))),
                padding: const EdgeInsets.all(3),
                child: assetPath != null
                    ? Image.asset(assetPath, fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Center(child: Text(
                        carrier.substring(0, carrier.length > 2 ? 2 : carrier.length),
                        style: TextStyle(fontSize: 8,
                            fontWeight: FontWeight.w800, color: color))))
                    : Center(child: Text(
                    carrier.substring(0, carrier.length > 2 ? 2 : carrier.length),
                    style: TextStyle(fontSize: 8,
                        fontWeight: FontWeight.w800, color: color))),
              ),
              const SizedBox(width: 10),

              // Details
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(recipName, style: const TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
                const SizedBox(height: 2),
                Text('$recipCity · $recipPc',
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF9B9B9B))),
                Text('$carrier · $service',
                    style: TextStyle(fontSize: 11, color: color,
                        fontWeight: FontWeight.w500)),
              ])),

              // Price + status + chevron
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('£${price.toStringAsFixed(2)}', style: const TextStyle(
                     fontSize: 14,
                    fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
                if (tracking.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: const Color(0xFF059669).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6)),
                    child: const Text('Label ready', style: TextStyle(
                        fontSize: 9, fontWeight: FontWeight.w700,
                        color: Color(0xFF059669))),
                  ),
                ],
                const SizedBox(height: 4),
                const Icon(Icons.chevron_right_rounded,
                    size: 16, color: Color(0xFFB0B0B0)),
              ]),
            ]),
          ),

          // ── Tracking + download strip ──────────────────────
          if (tracking.isNotEmpty)
            Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFF2F2F2))),
                borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12)),
              ),
              child: Row(children: [

                // Tracking
                Expanded(child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  child: Row(children: [
                    const Icon(Icons.qr_code_rounded,
                        size: 13, color: Color(0xFF9B9B9B)),
                    const SizedBox(width: 6),
                    Expanded(child: Text(tracking,
                        style: const TextStyle(fontFamily: 'monospace',
                            fontSize: 11, color: Color(0xFF6B6B6B)),
                        overflow: TextOverflow.ellipsis)),
                  ]),
                )),

                // Download
                if (labelUrl.isNotEmpty)
                  GestureDetector(
                    onTap: () async {
                      final uri = Uri.parse(labelUrl);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri,
                            mode: LaunchMode.externalApplication);
                      }
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 12),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                          color: const Color(0xFF6D28D9),
                          borderRadius: BorderRadius.circular(8)),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.download_rounded,
                            size: 13, color: Colors.white),
                        SizedBox(width: 5),
                        Text('Label', style: TextStyle(fontSize: 11,
                            fontWeight: FontWeight.w700, color: Colors.white)),
                      ]),
                    ),
                  ),

                // View details
                GestureDetector(
                  onTap: onTap,
                  child: Container(
                    margin: const EdgeInsets.only(right: 12),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                        color: const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(8)),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.open_in_new_rounded,
                          size: 12, color: Color(0xFF6B6B6B)),
                      SizedBox(width: 4),
                      Text('Details', style: TextStyle(fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6B6B6B))),
                    ]),
                  ),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bulk Order Card
// ─────────────────────────────────────────────────────────────────────────────

class _BulkOrderCard extends StatelessWidget {
  final BulkOrder    order;
  final VoidCallback onTap;
  const _BulkOrderCard({required this.order, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final b = order;
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'];
    final dateStr =
        '${b.createdAt.day} ${months[b.createdAt.month - 1]} ${b.createdAt.year}';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFEEEEEE)),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03),
              blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(children: [

          // ── Header ─────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF5EE),
              borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(14)),
              border: Border(bottom: BorderSide(
                  color: const Color(0xFFFF5A00).withOpacity(0.15))),
            ),
            child: Row(children: [
              Container(width: 30, height: 30,
                  decoration: BoxDecoration(
                      color: const Color(0xFFFF5A00).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.layers_rounded,
                      color: Color(0xFFFF5A00), size: 16)),
              const SizedBox(width: 10),
              Expanded(child: Text(b.batchName, style: const TextStyle(
                   fontSize: 14,
                  fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A)))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: b.statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: b.statusColor.withOpacity(0.3))),
                child: Text(b.statusLabel, style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w700,
                    color: b.statusColor)),
              ),
            ]),
          ),

          // ── Stats ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(children: [
              _BulkStat('${b.totalParcels}', 'Parcels',  const Color(0xFF6D28D9)),
              _BulkStat('${b.successCount}', 'Labels OK', const Color(0xFF059669)),
              if (b.failed > 0)
                _BulkStat('${b.failed}', 'Failed', Colors.red),
              _BulkStat('£${b.totalCost.toStringAsFixed(2)}', 'Paid', const Color(0xFF059669)),
              const Spacer(),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(dateStr, style: const TextStyle(
                    fontSize: 11, color: Color(0xFF9B9B9B))),
                const SizedBox(height: 2),
                Text(b.senderName, style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600,
                    color: Color(0xFF6B6B6B))),
              ]),
            ]),
          ),

          // ── Footer ─────────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFF2F2F2))),
              borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(14)),
            ),
            child: Row(children: [
              Expanded(child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.receipt_long_outlined,
                      size: 13, color: Color(0xFF6B6B6B)),
                  const SizedBox(width: 5),
                  Text('View ${b.successCount} labels',
                      style: const TextStyle(fontSize: 11,
                          color: Color(0xFF6B6B6B),
                          fontWeight: FontWeight.w500)),
                ]),
              )),
              Container(width: 1, height: 36, color: const Color(0xFFF2F2F2)),
              Expanded(child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.open_in_new_rounded,
                          size: 13, color: Color(0xFFFF5A00)),
                      SizedBox(width: 5),
                      Text('Open Batch', style: TextStyle(fontSize: 11,
                          color: Color(0xFFFF5A00),
                          fontWeight: FontWeight.w600)),
                    ]),
              )),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _BulkStat extends StatelessWidget {
  final String value, label; final Color color;
  const _BulkStat(this.value, this.label, this.color);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value, style: TextStyle( fontSize: 18,
          fontWeight: FontWeight.w800, color: color)),
      Text(label, style: const TextStyle(
          fontSize: 10, color: Color(0xFF9B9B9B))),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Top bar
// ─────────────────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final VoidCallback onSort;
  final String sortLabel;
  const _TopBar({required this.onSort, required this.sortLabel});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    decoration: const BoxDecoration(color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE)))),
    child: Row(children: [
      GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(width: 36, height: 36,
            decoration: BoxDecoration(color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.arrow_back_ios_new_rounded,
                size: 16, color: Color(0xFF1A1A1A))),
      ),
      const SizedBox(width: 14),
      const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your Shipments', style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w800,
                color: Color(0xFF1A1A1A))),
            Text('All your parcel history',
                style: TextStyle(fontSize: 11, color: Color(0xFF9B9B9B))),
          ])),
      GestureDetector(
        onTap: onSort,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFEEEEEE))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.sort_rounded, size: 15, color: Color(0xFF6B6B6B)),
            const SizedBox(width: 5),
            Text(sortLabel, style: const TextStyle(fontSize: 12,
                color: Color(0xFF6B6B6B), fontWeight: FontWeight.w500)),
          ]),
        ),
      ),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Stats strip
// ─────────────────────────────────────────────────────────────────────────────

class _StatsStrip extends StatelessWidget {
  final int total, active, delivered, pending, international;
  const _StatsStrip({required this.total, required this.active,
    required this.delivered, required this.pending,
    required this.international});

  @override
  Widget build(BuildContext context) => Container(
    color: Colors.white,
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        _Stat(label: 'Total',     value: total,     color: const Color(0xFF1A1A1A)),
        _divider(),
        _Stat(label: 'Active',    value: active,    color: const Color(0xFF0284C7)),
        _divider(),
        _Stat(label: 'Delivered', value: delivered, color: const Color(0xFF059669)),
        _divider(),
        _Stat(label: 'Pending',   value: pending,   color: const Color(0xFFD97706)),
        if (international > 0) ...[
          _divider(),
          _Stat(label: 'Intl', value: international, color: const Color(0xFF7C3AED)),
        ],
      ]),
    ),
  );

  Widget _divider() => Container(
    width: 1, height: 28, margin: const EdgeInsets.symmetric(horizontal: 12),
    color: const Color(0xFFEEEEEE),
  );
}

class _Stat extends StatelessWidget {
  final String label; final int value; final Color color;
  const _Stat({required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text('$value', style: TextStyle( fontSize: 20,
        fontWeight: FontWeight.w800, color: color)),
    Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF9B9B9B),
        fontWeight: FontWeight.w500)),
  ]);
}

// ─────────────────────────────────────────────────────────────────────────────
// Search bar
// ─────────────────────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  final TextEditingController ctrl;
  final ValueChanged<String> onChanged;
  const _SearchBar({required this.ctrl, required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
    color: Colors.white,
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
    child: TextField(
      controller: ctrl, onChanged: onChanged,
      style: const TextStyle(fontSize: 13, color: Color(0xFF1A1A1A)),
      decoration: InputDecoration(
        hintText: 'Search by tracking #, name, city, country or carrier…',
        hintStyle: const TextStyle(fontSize: 12, color: Color(0xFFB0B0B0)),
        prefixIcon: const Icon(Icons.search_rounded,
            size: 18, color: Color(0xFF9B9B9B)),
        suffixIcon: ctrl.text.isNotEmpty
            ? GestureDetector(
            onTap: () { ctrl.clear(); onChanged(''); },
            child: const Icon(Icons.close_rounded,
                size: 16, color: Color(0xFF9B9B9B)))
            : null,
        filled: true, fillColor: const Color(0xFFF5F5F5),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Filter chips
// ─────────────────────────────────────────────────────────────────────────────

class _FilterChips extends StatelessWidget {
  final List<String> filters;
  final String active;
  final List<Shipment> all;
  final ValueChanged<String> onSelect;
  const _FilterChips({required this.filters, required this.active,
    required this.all, required this.onSelect});

  int _count(String f) {
    switch (f) {
      case 'All':           return all.length;
      case 'Active':        return all.where((s) => s.status.toLowerCase() != 'delivered').length;
      case 'Delivered':     return all.where((s) => s.status.toLowerCase() == 'delivered').length;
      case 'Pending':       return all.where((s) { final st = s.status.toLowerCase(); return st == 'pending' || st == 'label_created'; }).length;
      case 'International': return all.where((s) => s.isInternational).length;
      default: return 0;
    }
  }

  Color _filterColor(String f) {
    switch (f) {
      case 'Active':        return const Color(0xFF0284C7);
      case 'Delivered':     return const Color(0xFF059669);
      case 'Pending':       return const Color(0xFFD97706);
      case 'International': return const Color(0xFF7C3AED);
      default:              return const Color(0xFFFF5A00);
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    color: Colors.white,
    padding: const EdgeInsets.only(bottom: 8),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(children: filters.map((f) {
        final isActive = f == active;
        final count    = _count(f);
        final fColor   = _filterColor(f);
        return GestureDetector(
          onTap: () => onSelect(f),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: isActive ? fColor : const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: isActive ? fColor : const Color(0xFFEEEEEE)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (f == 'International') ...[
                Icon(Icons.public_rounded, size: 12,
                    color: isActive ? Colors.white : fColor),
                const SizedBox(width: 4),
              ],
              Text(f, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                  color: isActive ? Colors.white : const Color(0xFF6B6B6B))),
              if (count > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: isActive
                        ? Colors.white.withOpacity(0.25)
                        : fColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('$count', style: TextStyle(fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: isActive ? Colors.white : fColor)),
                ),
              ],
            ]),
          ),
        );
      }).toList()),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Date divider
// ─────────────────────────────────────────────────────────────────────────────

class _DateDivider extends StatelessWidget {
  final DateTime date;
  const _DateDivider({required this.date});

  String _label() {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d     = DateTime(date.year, date.month, date.day);
    if (d == today) return 'Today';
    if (d == today.subtract(const Duration(days: 1))) return 'Yesterday';
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Row(children: [
      Text(_label(), style: const TextStyle(fontSize: 11,
          fontWeight: FontWeight.w700, color: Color(0xFF9B9B9B),
          letterSpacing: 0.3)),
      const SizedBox(width: 8),
      Expanded(child: Container(height: 1, color: const Color(0xFFEEEEEE))),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Shipment card
// ─────────────────────────────────────────────────────────────────────────────

class _ShipmentCard extends StatelessWidget {
  final Shipment     shipment;
  final VoidCallback onTap;
  const _ShipmentCard({required this.shipment, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = shipment;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(
            color: s.isInternational
                ? const Color(0xFF7C3AED).withOpacity(0.25)
                : const Color(0xFFEEEEEE),
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03),
              blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(children: [
          if (s.isInternational)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: const BoxDecoration(
                color: Color(0xFFF5F3FF),
                borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(14),
                    topRight: Radius.circular(14)),
              ),
              child: Row(children: [
                const Icon(Icons.public_rounded, size: 12,
                    color: Color(0xFF7C3AED)),
                const SizedBox(width: 6),
                Text('International · ${s.recipientCountry}',
                    style: const TextStyle(fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF7C3AED))),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Stack(alignment: Alignment.bottomRight, children: [
                _YourShipmentLogo(carrier: s.carrier, color: s.carrierColor),
                Container(width: 10, height: 10,
                    decoration: BoxDecoration(color: s.statusColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5))),
              ]),
              const SizedBox(width: 12),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(s.trackingNumber,
                      style: const TextStyle(fontSize: 12,
                          fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A),
                          fontFamily: 'monospace', letterSpacing: 0.3),
                      overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 8),
                  _StatusBadge(label: s.statusLabel, color: s.statusColor),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.person_outline_rounded,
                      size: 12, color: Color(0xFF9B9B9B)),
                  const SizedBox(width: 4),
                  Expanded(child: Text(
                    s.isInternational
                        ? '${s.recipientName} · ${s.recipientCity}, ${s.recipientCountry}'
                        : '${s.recipientName} · ${s.recipientCity}',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF6B6B6B)),
                    overflow: TextOverflow.ellipsis,
                  )),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  Container(width: 8, height: 8,
                      decoration: BoxDecoration(color: s.carrierColor,
                          shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  Text(s.carrier, style: TextStyle(fontSize: 11,
                      color: s.carrierColor, fontWeight: FontWeight.w900),
                      overflow: TextOverflow.ellipsis),
                ]),
                Text(s.service, style: TextStyle(fontSize: 11,
                    color: s.carrierColor, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis),
              ])),
              const Padding(padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.chevron_right_rounded,
                      size: 18, color: Color(0xFFB0B0B0))),
            ]),
          ),
          Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFF2F2F2))),
              borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(14)),
            ),
            child: Row(children: [
              Expanded(child: _CardAction(icon: Icons.download_outlined,
                  label: 'Label',   onTap: onTap)),
              Container(width: 1, height: 36, color: const Color(0xFFF2F2F2)),
              Expanded(child: _CardAction(icon: Icons.location_on_outlined,
                  label: 'Track',   onTap: onTap)),
              Container(width: 1, height: 36, color: const Color(0xFFF2F2F2)),
              Expanded(child: _CardAction(icon: Icons.open_in_new_rounded,
                  label: 'Details', onTap: onTap)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label; final Color color;
  const _StatusBadge({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.2))),
    child: Text(label, style: TextStyle(fontSize: 10, color: color,
        fontWeight: FontWeight.w700)),
  );
}

class _CardAction extends StatelessWidget {
  final IconData icon; final String label; final VoidCallback onTap;
  const _CardAction({required this.icon, required this.label,
    required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(14), bottomRight: Radius.circular(14)),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 13, color: const Color(0xFF6B6B6B)),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 11,
            color: Color(0xFF6B6B6B), fontWeight: FontWeight.w500)),
      ]),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Sort sheet
// ─────────────────────────────────────────────────────────────────────────────

class _SortSheet extends StatelessWidget {
  final String current;
  final ValueChanged<String> onSelect;
  const _SortSheet({required this.current, required this.onSelect});

  static const _options = [
    {'label': 'Newest First', 'key': 'Newest',
      'icon': Icons.arrow_downward_rounded},
    {'label': 'Oldest First', 'key': 'Oldest',
      'icon': Icons.arrow_upward_rounded},
    {'label': 'By Carrier',   'key': 'Carrier',
      'icon': Icons.local_shipping_outlined},
  ];

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
    decoration: const BoxDecoration(color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 40, height: 4,
          decoration: BoxDecoration(color: const Color(0xFFDDDDDD),
              borderRadius: BorderRadius.circular(2))),
      const SizedBox(height: 16),
      const Align(alignment: Alignment.centerLeft,
          child: Text('Sort Shipments', style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w800,
              color: Color(0xFF1A1A1A)))),
      const SizedBox(height: 12),
      ..._options.map((opt) {
        final isActive = opt['key'] == current;
        return GestureDetector(
          onTap: () {
            Navigator.pop(context);
            onSelect(opt['key'] as String);
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isActive
                  ? const Color(0xFFFF5A00).withOpacity(0.06)
                  : const Color(0xFFF9F9F9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isActive
                  ? const Color(0xFFFF5A00).withOpacity(0.25)
                  : const Color(0xFFEEEEEE)),
            ),
            child: Row(children: [
              Icon(opt['icon'] as IconData, size: 18,
                  color: isActive
                      ? const Color(0xFFFF5A00) : const Color(0xFF6B6B6B)),
              const SizedBox(width: 12),
              Text(opt['label'] as String, style: TextStyle(fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isActive
                      ? const Color(0xFFFF5A00) : const Color(0xFF1A1A1A))),
              const Spacer(),
              if (isActive) const Icon(Icons.check_circle_rounded,
                  size: 18, color: Color(0xFFFF5A00)),
            ]),
          ),
        );
      }),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty states
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onRefresh;
  const _EmptyState({required this.onRefresh});
  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.all(40),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 80, height: 80,
          decoration: BoxDecoration(color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(20)),
          child: const Icon(Icons.inventory_2_outlined,
              size: 36, color: Color(0xFFDDDDDD))),
      const SizedBox(height: 16),
      const Text('No shipments yet', style: TextStyle(
          fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
      const SizedBox(height: 6),
      const Text('Your parcel history will appear here\nonce you send your first shipment.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Color(0xFF9B9B9B), height: 1.5)),
      const SizedBox(height: 24),
      ElevatedButton.icon(onPressed: onRefresh,
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('Refresh'),
          style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF5A00),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              textStyle: const TextStyle(fontWeight: FontWeight.w600))),
    ]),
  ));
}

class _NoResultsState extends StatelessWidget {
  final String query, filter;
  final VoidCallback onClear;
  const _NoResultsState({required this.query, required this.filter,
    required this.onClear});
  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.all(40),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.search_off_rounded, size: 48, color: Color(0xFFDDDDDD)),
      const SizedBox(height: 16),
      const Text('No matches found', style: TextStyle(
          fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
      const SizedBox(height: 6),
      Text(query.isNotEmpty
          ? 'No results for "$query"'
          : 'No "$filter" shipments found',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: Color(0xFF9B9B9B))),
      const SizedBox(height: 20),
      TextButton(onPressed: onClear,
          style: TextButton.styleFrom(foregroundColor: const Color(0xFFFF5A00)),
          child: const Text('Clear filters',
              style: TextStyle(fontWeight: FontWeight.w600))),
    ]),
  ));
}

// ─────────────────────────────────────────────────────────────────────────────
// Carrier logo widget
// ─────────────────────────────────────────────────────────────────────────────

class _YourShipmentLogo extends StatelessWidget {
  final String carrier;
  final Color  color;
  const _YourShipmentLogo({required this.carrier, required this.color});

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
    final abbr      = _abbr[carrier]
        ?? carrier.substring(0, carrier.length > 2 ? 2 : carrier.length);
    final fs        = abbr.length >= 5 ? 7.0 : abbr.length == 4 ? 8.0 : 10.0;

    return Container(
      width: 44, height: 44,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEEEEE)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
            blurRadius: 4, offset: const Offset(0, 2))],
      ),
      padding: const EdgeInsets.all(6),
      child: assetPath != null
          ? Image.asset(assetPath, fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Center(child: Text(abbr,
              style: TextStyle(fontSize: fs, fontWeight: FontWeight.w800,
                  color: color))))
          : Center(child: Text(abbr, style: TextStyle(fontSize: fs,
          fontWeight: FontWeight.w800, color: color))),
    );
  }
}