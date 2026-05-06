// lib/screens/admin_dashboard_screen.dart
//
// Admin-only screen. Access controlled by email allowlist.
// Tabs: Users | Shipments | Bulk Orders | Reports
// Features:
//   - Stats overview (today/week/month: users, parcels, revenue, failures)
//   - Paginated user list with edit capability + per-user parcel & address drill-down
//   - Paginated global shipment list with status/carrier/source filters + label download
//   - Bulk Orders list with per-item drill-down + individual label download
//   - Monthly revenue reports (last 12 months) — copy to clipboard OR download as file
//   - Every admin action written to admin_logs table
//   - Admin-only access enforced via email allowlist

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// ── Admin allowlist ────────────────────────────────────────────────────────────
const _kAdminEmails = {
  'admin@swiftlabel.app',
  'swiftlabelsupport@gmail.com',
  'srivishal600@gmail.com',
  'lionel.vicky12341999@gmail.com',
};
bool isAdminEmail(String email) => _kAdminEmails.contains(email.toLowerCase().trim());

// ── Colours ──────────────────────────────────────────────────────────────────
const _kOrange    = Color(0xFFFF5A00);
const _kPurple    = Color(0xFF6D28D9);
const _kGreen     = Color(0xFF059669);
const _kGrey      = Color(0xFF9B9B9B);
const _kLightGrey = Color(0xFFB0B0B0);
const _kBorder    = Color(0xFFEEEEEE);
const _kBg        = Color(0xFFFAF9F7);
const _kCard      = Colors.white;

// ── Helpers ───────────────────────────────────────────────────────────────────
String _fmtDate(DateTime d) {
  const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  return '${d.day} ${m[d.month-1]} ${d.year}';
}
String _fmtDateTime(DateTime d) {
  const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  return '${d.day} ${m[d.month-1]} ${d.year} ${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
}
String _monthKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2,'0')}';
String _monthLabel(String key) {
  const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  final parts = key.split('-');
  return '${m[int.parse(parts[1])-1]} ${parts[0]}';
}

// ══════════════════════════════════════════════════════════════════════════════
// MODELS
// ══════════════════════════════════════════════════════════════════════════════

class AdminUser {
  final String id, email, fullName, phone, city, postcode, country, avatarUrl;
  final int    totalParcels;
  final double totalSpent;
  final DateTime joinedAt;
  const AdminUser({
    required this.id, required this.email, required this.fullName,
    required this.phone, required this.city, required this.postcode,
    required this.country, required this.avatarUrl,
    required this.totalParcels, required this.totalSpent, required this.joinedAt,
  });
  String get initials {
    final parts = fullName.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return fullName.isNotEmpty ? fullName[0].toUpperCase() : email[0].toUpperCase();
  }
  factory AdminUser.fromJson(Map<String, dynamic> j) => AdminUser(
    id:           j['id']           ?? '',
    email:        j['email']        ?? '',
    fullName:     j['full_name']    ?? '',
    phone:        j['phone']        ?? '',
    city:         j['city']         ?? '',
    postcode:     j['postcode']     ?? '',
    country:      j['country']      ?? '',
    avatarUrl:    j['avatar_url']   ?? '',
    totalParcels: (j['total_parcels'] ?? 0) as int,
    totalSpent:   ((j['total_spent']  ?? 0) as num).toDouble(),
    joinedAt:     j['created_at'] != null ? DateTime.parse(j['created_at']) : DateTime.now(),
  );
}

class AdminShipment {
  final String  id, trackingNumber, labelUrl, carrier, service;
  final String  userEmail, senderName, senderCity, senderPostcode;
  final String  recipientName, recipientCity, recipientPostcode, recipientCountry;
  final String  parcelSize, parcelType, status, source, trackingStatus;
  final double  price, weightKg, parcelValue;
  final bool    isInternational;
  final String? paymentIntentId, failureReason, lastLocation, labelId;
  final DateTime createdAt;
  final DateTime? lastTrackedAt, estimatedDelivery;

  const AdminShipment({
    required this.id, required this.trackingNumber, required this.labelUrl,
    required this.carrier, required this.service, required this.userEmail,
    required this.senderName, required this.senderCity, required this.senderPostcode,
    required this.recipientName, required this.recipientCity,
    required this.recipientPostcode, required this.recipientCountry,
    required this.parcelSize, required this.parcelType, required this.status,
    required this.source, required this.trackingStatus,
    required this.price, required this.weightKg, required this.parcelValue,
    required this.isInternational, required this.createdAt,
    this.paymentIntentId, this.failureReason, this.lastLocation, this.labelId,
    this.lastTrackedAt, this.estimatedDelivery,
  });

  factory AdminShipment.fromJson(Map<String, dynamic> j) => AdminShipment(
    id:                j['id']                ?? '',
    trackingNumber:    j['tracking_number']   ?? '',
    labelUrl:          j['label_url']         ?? '',
    carrier:           j['carrier']           ?? '',
    service:           j['service']           ?? '',
    userEmail:         j['user_email']        ?? '',
    senderName:        j['sender_name']       ?? '',
    senderCity:        j['sender_city']       ?? '',
    senderPostcode:    j['sender_postcode']   ?? '',
    recipientName:     j['recipient_name']    ?? '',
    recipientCity:     j['recipient_city']    ?? '',
    recipientPostcode: j['recipient_postcode'] ?? '',
    recipientCountry:  j['recipient_country'] ?? 'GB',
    parcelSize:        j['parcel_size']       ?? '',
    parcelType:        j['parcel_type']       ?? '',
    status:            j['status']            ?? '',
    source:            j['source']            ?? 'app',
    trackingStatus:    j['tracking_status']   ?? '',
    price:             ((j['price']        ?? 0) as num).toDouble(),
    weightKg:          ((j['weight_kg']    ?? 0) as num).toDouble(),
    parcelValue:       ((j['parcel_value'] ?? 0) as num).toDouble(),
    isInternational:   j['is_international']  ?? false,
    paymentIntentId:   j['stripe_payment_intent'],
    failureReason:     j['error_message'],
    lastLocation:      j['last_location'],
    labelId:           j['label_id'],
    createdAt:         j['created_at'] != null ? DateTime.parse(j['created_at']) : DateTime.now(),
    lastTrackedAt:     j['last_tracked_at'] != null ? DateTime.parse(j['last_tracked_at']) : null,
    estimatedDelivery: j['estimated_delivery'] != null ? DateTime.parse(j['estimated_delivery']) : null,
  );

  Color get statusColor {
    switch (status) {
      case 'delivered':     return _kGreen;
      case 'label_created': return _kPurple;
      case 'in_transit':    return _kOrange;
      case 'failed':        return Colors.red;
      default:              return _kGrey;
    }
  }
  String get statusLabel {
    switch (status) {
      case 'delivered':     return 'Delivered';
      case 'label_created': return 'Label Created';
      case 'in_transit':    return 'In Transit';
      case 'failed':        return 'Failed';
      default:              return status.replaceAll('_', ' ');
    }
  }
  Color get carrierColor {
    final c = carrier.toLowerCase();
    if (c.contains('royal'))  return const Color(0xFFE30613);
    if (c.contains('evri'))   return const Color(0xFF8B5CF6);
    if (c.contains('dpd'))    return const Color(0xFFE8001C);
    if (c.contains('yodel'))  return _kPurple;
    if (c.contains('parcel')) return const Color(0xFF003087);
    if (c.contains('fedex'))  return const Color(0xFF4D148C);
    return const Color(0xFF6B6B6B);
  }
}

class BulkOrder {
  final String id, userEmail, batchName, senderName, status;
  final int    totalParcels, processed, failed;
  final double totalCost;
  final DateTime createdAt;
  const BulkOrder({
    required this.id, required this.userEmail, required this.batchName,
    required this.senderName, required this.status,
    required this.totalParcels, required this.processed, required this.failed,
    required this.totalCost, required this.createdAt,
  });
  factory BulkOrder.fromJson(Map<String, dynamic> j) => BulkOrder(
    id:           j['id']           ?? '',
    userEmail:    j['user_email']   ?? '',
    batchName:    j['batch_name']   ?? '',
    senderName:   j['sender_name']  ?? '',
    status:       j['status']       ?? '',
    totalParcels: (j['total_parcels'] ?? 0) as int,
    processed:    (j['processed']   ?? 0) as int,
    failed:       (j['failed']      ?? 0) as int,
    totalCost:    ((j['total_cost'] ?? 0) as num).toDouble(),
    createdAt:    j['created_at'] != null ? DateTime.parse(j['created_at']) : DateTime.now(),
  );
  Color get statusColor {
    switch (status) {
      case 'completed':  return _kGreen;
      case 'processing': return _kOrange;
      case 'failed':     return Colors.red;
      case 'pending':    return _kPurple;
      default:           return _kGrey;
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ADMIN DASHBOARD SCREEN
// ══════════════════════════════════════════════════════════════════════════════

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});
  @override State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {

  final _sb = Supabase.instance.client;
  late TabController _tabs;

  // Stats
  Map<String, dynamic> _stats = {};
  bool _loadingStats = true;

  // Users
  final List<AdminUser> _users = [];
  bool _loadingUsers = false, _hasMoreUsers = true;
  int  _usersPage = 0;
  static const _pageSize = 50;

  // Shipments
  final List<AdminShipment> _shipments = [];
  bool _loadingShipments = false, _hasMoreShipments = true;
  int  _shipmentsPage = 0;
  String _statusFilter = 'all', _sourceFilter = 'all';
  bool   _intlFilter   = false;

  // Bulk Orders
  final List<BulkOrder> _bulkOrders = [];
  bool _loadingBulk = false, _hasMoreBulk = true;
  int  _bulkPage = 0;

  // Scroll
  final _userScroll     = ScrollController();
  final _shipmentScroll = ScrollController();
  final _bulkScroll     = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _tabs.addListener(_onTabChange);
    _loadStats();
    _loadUsers(reset: true);
    _loadShipments(reset: true);

    _userScroll.addListener(()     { if (_shouldLoad(_userScroll)     && !_loadingUsers)     _loadUsers(); });
    _shipmentScroll.addListener(() { if (_shouldLoad(_shipmentScroll) && !_loadingShipments) _loadShipments(); });
    _bulkScroll.addListener(()    { if (_shouldLoad(_bulkScroll)      && !_loadingBulk)      _loadBulkOrders(); });
  }

  bool _shouldLoad(ScrollController sc) =>
      sc.hasClients && sc.position.pixels > sc.position.maxScrollExtent - 200;

  void _onTabChange() {
    if (!_tabs.indexIsChanging) return;
    if (_tabs.index == 2 && _bulkOrders.isEmpty) _loadBulkOrders(reset: true);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _userScroll.dispose(); _shipmentScroll.dispose(); _bulkScroll.dispose();
    super.dispose();
  }

  // ── Stats ────────────────────────────────────────────────────
  Future<void> _loadStats() async {
    setState(() => _loadingStats = true);
    try {
      final now        = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day).toIso8601String();
      final weekStart  = now.subtract(const Duration(days: 7)).toIso8601String();
      final monthStart = DateTime(now.year, now.month, 1).toIso8601String();

      final allShipments = await _sb.from('shipments').select('price, status, created_at, carrier, is_international, source');
      final allUsers     = await _sb.from('users').select('created_at');
      final bulkOrders   = await _sb.from('bulk_orders').select('total_cost, status');

      final today = allShipments.where((s) => (s['created_at'] ?? '').compareTo(todayStart) >= 0).toList();
      final week  = allShipments.where((s) => (s['created_at'] ?? '').compareTo(weekStart)  >= 0).toList();
      final month = allShipments.where((s) => (s['created_at'] ?? '').compareTo(monthStart) >= 0).toList();
      double rev(List l) => l.fold(0.0, (s, p) => s + ((p['price'] ?? 0) as num).toDouble());

      final carrierMap = <String, int>{};
      for (final s in allShipments) {
        final c = (s['carrier'] ?? 'Unknown') as String;
        carrierMap[c] = (carrierMap[c] ?? 0) + 1;
      }

      // Monthly breakdown (last 12 months)
      final monthlyMap = <String, Map<String, dynamic>>{};
      for (final s in allShipments) {
        if (s['created_at'] == null) continue;
        final d = DateTime.parse(s['created_at']);
        final key = _monthKey(d);
        monthlyMap[key] ??= {'parcels': 0, 'revenue': 0.0};
        monthlyMap[key]!['parcels'] = (monthlyMap[key]!['parcels'] as int) + 1;
        monthlyMap[key]!['revenue'] = (monthlyMap[key]!['revenue'] as double) + ((s['price'] ?? 0) as num).toDouble();
      }

      setState(() => _stats = {
        'total_users':   allUsers.length,
        'new_today':     allUsers.where((u) => (u['created_at'] ?? '').compareTo(todayStart) >= 0).length,
        'total_parcels': allShipments.length,
        'today_parcels': today.length,
        'week_parcels':  week.length,
        'month_parcels': month.length,
        'total_revenue': rev(allShipments),
        'today_revenue': rev(today),
        'week_revenue':  rev(week),
        'month_revenue': rev(month),
        'failed':        allShipments.where((s) => s['status'] == 'failed').length,
        'international': allShipments.where((s) => s['is_international'] == true).length,
        'bulk_total':    bulkOrders.length,
        'bulk_revenue':  bulkOrders.fold(0.0, (s, b) => s + ((b['total_cost'] ?? 0) as num).toDouble()),
        'carrier_map':   carrierMap,
        'monthly_map':   monthlyMap,
      });
    } catch (e) { debugPrint('[Admin] stats: $e'); }
    setState(() => _loadingStats = false);
  }

  // ── Users ────────────────────────────────────────────────────
  Future<void> _loadUsers({bool reset = false}) async {
    if (_loadingUsers) return;
    if (reset) { _users.clear(); _usersPage = 0; _hasMoreUsers = true; }
    if (!_hasMoreUsers) return;
    setState(() => _loadingUsers = true);
    try {
      final from = _usersPage * _pageSize;
      final profiles = await _sb.from('users')
          .select('id, email, full_name, phone, city, postcode, country, avatar_url, created_at')
          .order('created_at', ascending: false)
          .range(from, from + _pageSize - 1);

      final List<AdminUser> loaded = [];
      for (final p in profiles) {
        final email = p['email'] ?? '';
        final parcelsRes = await _sb.from('shipments').select('price').eq('user_email', email);
        final count = parcelsRes.length;
        final spent = parcelsRes.fold(0.0, (s, x) => s + ((x['price'] ?? 0) as num).toDouble());
        loaded.add(AdminUser(
          id: p['id'] ?? '', email: email,
          fullName: p['full_name'] ?? '', phone: p['phone'] ?? '',
          city: p['city'] ?? '', postcode: p['postcode'] ?? '',
          country: p['country'] ?? '', avatarUrl: p['avatar_url'] ?? '',
          totalParcels: count, totalSpent: spent,
          joinedAt: p['created_at'] != null ? DateTime.parse(p['created_at']) : DateTime.now(),
        ));
      }
      setState(() {
        _users.addAll(loaded);
        _usersPage++;
        _hasMoreUsers = profiles.length == _pageSize;
      });
    } catch (e) { debugPrint('[Admin] users: $e'); }
    setState(() => _loadingUsers = false);
  }

  // ── Shipments ────────────────────────────────────────────────
  Future<void> _loadShipments({bool reset = false}) async {
    if (_loadingShipments) return;
    if (reset) { _shipments.clear(); _shipmentsPage = 0; _hasMoreShipments = true; }
    if (!_hasMoreShipments) return;
    setState(() => _loadingShipments = true);
    try {
      final from = _shipmentsPage * _pageSize;
      var q = _sb.from('shipments').select('*');
      if (_statusFilter != 'all') q = q.eq('status', _statusFilter) as dynamic;
      if (_sourceFilter != 'all') q = q.eq('source', _sourceFilter) as dynamic;
      if (_intlFilter)            q = q.eq('is_international', true) as dynamic;
      final data = await q.order('created_at', ascending: false).range(from, from + _pageSize - 1);
      final loaded = (data as List).map((j) => AdminShipment.fromJson(j)).toList();
      setState(() {
        _shipments.addAll(loaded);
        _shipmentsPage++;
        _hasMoreShipments = loaded.length == _pageSize;
      });
    } catch (e) { debugPrint('[Admin] shipments: $e'); }
    setState(() => _loadingShipments = false);
  }

  // ── Bulk Orders ──────────────────────────────────────────────
  Future<void> _loadBulkOrders({bool reset = false}) async {
    if (_loadingBulk) return;
    if (reset) { _bulkOrders.clear(); _bulkPage = 0; _hasMoreBulk = true; }
    if (!_hasMoreBulk) return;
    setState(() => _loadingBulk = true);
    try {
      final from = _bulkPage * _pageSize;
      final data = await _sb.from('bulk_orders').select('*')
          .order('created_at', ascending: false)
          .range(from, from + _pageSize - 1);
      final loaded = (data as List).map((j) => BulkOrder.fromJson(j)).toList();
      setState(() {
        _bulkOrders.addAll(loaded);
        _bulkPage++;
        _hasMoreBulk = loaded.length == _pageSize;
      });
    } catch (e) { debugPrint('[Admin] bulk: $e'); }
    setState(() => _loadingBulk = false);
  }

  // ── Admin audit log ───────────────────────────────────────────
  Future<void> _logAdminAction(String action, String target, {Map<String, dynamic>? meta}) async {
    try {
      await _sb.from('admin_logs').insert({
        'admin_email': _sb.auth.currentUser?.email ?? 'unknown',
        'action':      action,
        'target':      target,
        if (meta != null) 'meta': meta.toString(),
        'created_at':  DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }

  // ── CSV Export — clipboard copy OR file download ──────────────
  Future<void> _downloadCSV(String filename, String content) async {
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _CsvDownloadSheet(
        filename: filename,
        content:  content,
        onCopy: () async {
          await Clipboard.setData(ClipboardData(text: content));
          await _logAdminAction('csv_copy', filename);
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(behavior: SnackBarBehavior.fixed, content: Text('Copied to clipboard ✓'), backgroundColor: _kGreen));
        },
        onFile: () async {
          // Write to the public Downloads folder.
          // MANAGE_EXTERNAL_STORAGE is declared in AndroidManifest so this works
          // on all Android versions without FileProvider or intent sharing.
          try {
            final downloadsDir = Directory('/storage/emulated/0/Download');
            final targetDir = await downloadsDir.exists()
                ? downloadsDir
                : Directory('/storage/emulated/0/Download')..createSync(recursive: true);
            final file = File('${targetDir.path}/$filename');
            await file.writeAsString(content);
            await _logAdminAction('csv_download', filename);
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  behavior: SnackBarBehavior.fixed,
                  backgroundColor: _kGreen,
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Saved to Downloads ✓',
                          style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
                      Text(filename,
                          style: const TextStyle(fontSize: 11, color: Colors.white70),
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ));
          } catch (e) {
            // Fallback: clipboard
            await Clipboard.setData(ClipboardData(text: content));
            await _logAdminAction('csv_copy_fallback', filename);
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  behavior: SnackBarBehavior.fixed,
                  backgroundColor: _kGreen,
                  content: Text('Copied to clipboard — paste into Excel or Google Sheets'),
                ));
          }
        },
      ),
    );
  }

  Future<void> _exportShipmentsCSV() async {
    final data = await _sb.from('shipments').select('*').order('created_at', ascending: false);
    final buf  = StringBuffer();
    buf.writeln('ID,Tracking,User Email,Recipient,City,Country,Carrier,Service,Status,Price,Weight,International,Source,Created');
    for (final s in data) {
      buf.writeln([s['id'],s['tracking_number'],s['user_email'],s['recipient_name'],
        s['recipient_city'],s['recipient_country'],s['carrier'],s['service'],s['status'],
        s['price'],s['weight_kg'],s['is_international'],s['source'],s['created_at']].join(','));
    }
    await _downloadCSV('shipments_${DateTime.now().millisecondsSinceEpoch}.csv', buf.toString());
  }

  Future<void> _exportUsersCSV() async {
    final data = await _sb.from('users').select('*').order('created_at', ascending: false);
    final buf  = StringBuffer();
    buf.writeln('ID,Email,Name,Phone,City,Postcode,Country,Joined');
    for (final u in data) {
      buf.writeln([u['id'],u['email'],u['full_name'],u['phone'],
        u['city'],u['postcode'],u['country'],u['created_at']].join(','));
    }
    await _downloadCSV('users_${DateTime.now().millisecondsSinceEpoch}.csv', buf.toString());
  }

  Future<void> _exportBulkCSV() async {
    final data = await _sb.from('bulk_orders').select('*').order('created_at', ascending: false);
    final buf  = StringBuffer();
    buf.writeln('ID,User,Batch,Sender,Status,Total,Processed,Failed,Cost,Created');
    for (final b in data) {
      buf.writeln([b['id'],b['user_email'],b['batch_name'],b['sender_name'],b['status'],
        b['total_parcels'],b['processed'],b['failed'],b['total_cost'],b['created_at']].join(','));
    }
    await _downloadCSV('bulk_orders_${DateTime.now().millisecondsSinceEpoch}.csv', buf.toString());
  }

  Future<void> _exportMonthlyReportCSV() async {
    final monthlyMap = Map<String, Map<String, dynamic>>.from(
        (_stats['monthly_map'] as Map? ?? {}).map((k,v) => MapEntry(k as String, Map<String,dynamic>.from(v as Map))));
    final sorted = monthlyMap.keys.toList()..sort();
    final buf    = StringBuffer();
    buf.writeln('Month,Parcels,Revenue (£)');
    for (final key in sorted) {
      final d = monthlyMap[key]!;
      buf.writeln('${_monthLabel(key)},${d['parcels']},${(d['revenue'] as double).toStringAsFixed(2)}');
    }
    await _downloadCSV('monthly_report_${DateTime.now().millisecondsSinceEpoch}.csv', buf.toString());
  }

  // ── Update user profile (with audit log) ─────────────────────
  Future<void> _updateUserProfile(String userId, Map<String, dynamic> fields) async {
    await _sb.from('users').update(fields).eq('id', userId);
    await _logAdminAction('update_user', 'user:$userId', meta: fields);
  }

  // ── Build ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(child: Column(children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          color: _kCard,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              GestureDetector(onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.arrow_back_ios, size: 16, color: Color(0xFF6B6B6B))),
              const SizedBox(width: 8),
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: _kOrange, borderRadius: BorderRadius.circular(6)),
                  child: const Text('ADMIN', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 1))),
              const SizedBox(width: 8),
              const Text('Dashboard', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
              const Spacer(),
              GestureDetector(onTap: _loadStats,
                  child: const Icon(Icons.refresh_rounded, size: 18, color: _kGrey)),
            ]),
            const SizedBox(height: 16),

            // Stats chips
            if (_loadingStats)
              const Padding(padding: EdgeInsets.only(bottom: 16),
                  child: LinearProgressIndicator(color: _kOrange, minHeight: 2))
            else ...[
              Row(children: [
                _StatChip('Users',   '${_stats['total_users']  ?? 0}', _kPurple),
                const SizedBox(width: 6),
                _StatChip('Parcels', '${_stats['total_parcels'] ?? 0}', _kOrange),
                const SizedBox(width: 6),
                _StatChip('Revenue', '£${((_stats['total_revenue'] ?? 0.0) as double).toStringAsFixed(0)}', _kGreen),
                const SizedBox(width: 6),
                _StatChip('Failed',  '${_stats['failed'] ?? 0}', Colors.red),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                _StatChip('Today',  '${_stats['today_parcels'] ?? 0} / £${((_stats['today_revenue'] ?? 0.0) as double).toStringAsFixed(0)}', _kOrange),
                const SizedBox(width: 6),
                _StatChip('Week',   '${_stats['week_parcels']  ?? 0} / £${((_stats['week_revenue']  ?? 0.0) as double).toStringAsFixed(0)}', _kPurple),
                const SizedBox(width: 6),
                _StatChip('Intl',   '${_stats['international'] ?? 0}', _kGreen),
                const SizedBox(width: 6),
                _StatChip('Bulk',   '${_stats['bulk_total']    ?? 0}', const Color(0xFF0EA5E9)),
              ]),
              const SizedBox(height: 10),
              if ((_stats['carrier_map'] as Map?)?.isNotEmpty == true)
                _CarrierBreakdownBar(carrierMap: Map<String, int>.from(_stats['carrier_map'] ?? {})),
            ],

            TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              unselectedLabelStyle: const TextStyle(fontSize: 11),
              labelColor: _kOrange,
              unselectedLabelColor: _kGrey,
              indicatorColor: _kOrange,
              tabs: const [
                Tab(text: 'Users'),
                Tab(text: 'Shipments'),
                Tab(text: 'Bulk Orders'),
                Tab(text: 'Reports'),
              ],
            ),
          ]),
        ),

        Expanded(child: TabBarView(controller: _tabs, children: [
          _buildUsersTab(),
          _buildShipmentsTab(),
          _buildBulkTab(),
          _buildReportsTab(),
        ])),
      ])),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // USERS TAB
  // ══════════════════════════════════════════════════════════════
  Widget _buildUsersTab() => RefreshIndicator(
    onRefresh: () => _loadUsers(reset: true),
    color: _kOrange,
    child: ListView.builder(
      controller: _userScroll,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      itemCount: _users.length + 1,
      itemBuilder: (_, i) {
        if (i == _users.length) return _loadMoreIndicator(_loadingUsers, _hasMoreUsers, _users.length, 'users');
        return _UserRow(
          user: _users[i],
          onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => _UserDetailPage(user: _users[i], onUpdate: _updateUserProfile))),
        );
      },
    ),
  );

  // ══════════════════════════════════════════════════════════════
  // SHIPMENTS TAB
  // ══════════════════════════════════════════════════════════════
  Widget _buildShipmentsTab() => Column(children: [
    Container(color: _kCard, padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(children: [
        SingleChildScrollView(scrollDirection: Axis.horizontal,
          child: Row(children: ['all','label_created','in_transit','delivered','failed'].map((f) {
            final label = f == 'all' ? 'All' : f == 'label_created' ? 'Label Created' : f == 'in_transit' ? 'In Transit' : f[0].toUpperCase() + f.substring(1);
            return _FilterChip(label: label, selected: _statusFilter == f,
                onTap: () { setState(() => _statusFilter = f); _loadShipments(reset: true); });
          }).toList()),
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            ...[['all','All'],['app','App'],['bulk','Bulk'],['api','API']].map((s) =>
                Padding(padding: const EdgeInsets.only(right: 6),
                    child: _FilterChip(label: s[1], selected: _sourceFilter == s[0],
                        onTap: () { setState(() => _sourceFilter = s[0]); _loadShipments(reset: true); }))),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () { setState(() => _intlFilter = !_intlFilter); _loadShipments(reset: true); },
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                      color: _intlFilter ? _kGreen : Colors.white,
                      border: Border.all(color: _intlFilter ? _kGreen : _kBorder),
                      borderRadius: BorderRadius.circular(20)),
                  child: Text('🌍 Intl', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                      color: _intlFilter ? Colors.white : const Color(0xFF6B6B6B)))),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _exportShipmentsCSV,
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: _kPurple.withOpacity(0.08),
                      border: Border.all(color: _kPurple.withOpacity(0.3)),
                      borderRadius: BorderRadius.circular(20)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.download_rounded, size: 12, color: _kPurple),
                    SizedBox(width: 4),
                    Text('CSV', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _kPurple)),
                  ])),
            ),
          ]),
        ),
      ]),
    ),
    const Divider(height: 1),
    Expanded(child: RefreshIndicator(
      onRefresh: () => _loadShipments(reset: true),
      color: _kOrange,
      child: ListView.builder(
        controller: _shipmentScroll,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        itemCount: _shipments.length + 1,
        itemBuilder: (_, i) {
          if (i == _shipments.length) return _loadMoreIndicator(_loadingShipments, _hasMoreShipments, _shipments.length, 'shipments');
          return _ShipmentRow(shipment: _shipments[i], onTap: () => _openShipment(_shipments[i]));
        },
      ),
    )),
  ]);

  // ══════════════════════════════════════════════════════════════
  // BULK ORDERS TAB
  // ══════════════════════════════════════════════════════════════
  Widget _buildBulkTab() => Column(children: [
    Container(color: _kCard, padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        GestureDetector(
          onTap: _exportBulkCSV,
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: _kPurple.withOpacity(0.08),
                  border: Border.all(color: _kPurple.withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(20)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.download_rounded, size: 12, color: _kPurple),
                SizedBox(width: 4),
                Text('Export CSV', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _kPurple)),
              ])),
        ),
      ]),
    ),
    const Divider(height: 1),
    Expanded(child: RefreshIndicator(
      onRefresh: () => _loadBulkOrders(reset: true),
      color: _kOrange,
      child: _bulkOrders.isEmpty && !_loadingBulk
          ? _emptyState(Icons.inventory_2_rounded, 'No bulk orders found')
          : ListView.builder(
        controller: _bulkScroll,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        itemCount: _bulkOrders.length + 1,
        itemBuilder: (_, i) {
          if (i == _bulkOrders.length) return _loadMoreIndicator(_loadingBulk, _hasMoreBulk, _bulkOrders.length, 'bulk orders');
          final b = _bulkOrders[i];
          return GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => _BulkOrderDetailPage(bulkOrder: b))),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: _kCard, border: Border.all(color: _kBorder), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Container(width: 44, height: 44,
                    decoration: BoxDecoration(
                        color: b.statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: b.statusColor.withOpacity(0.3))),
                    child: Center(child: Text('${b.totalParcels}',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: b.statusColor)))),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(b.batchName.isNotEmpty ? b.batchName : 'Bulk Order',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A))),
                  Text(b.userEmail, style: const TextStyle(fontSize: 11, color: _kGrey), overflow: TextOverflow.ellipsis),
                  Row(children: [
                    _MiniTag('${b.processed} ok', _kGreen),
                    const SizedBox(width: 4),
                    if (b.failed > 0) _MiniTag('${b.failed} failed', Colors.red),
                  ]),
                ])),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: b.statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                      child: Text(b.status, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: b.statusColor))),
                  const SizedBox(height: 4),
                  Text('£${b.totalCost.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _kPurple)),
                  Text(_fmtDate(b.createdAt), style: const TextStyle(fontSize: 10, color: _kLightGrey)),
                  const SizedBox(height: 2),
                  const Icon(Icons.chevron_right, size: 14, color: _kLightGrey),
                ]),
              ]),
            ),
          );
        },
      ),
    )),
  ]);

  // ══════════════════════════════════════════════════════════════
  // REPORTS TAB
  // ══════════════════════════════════════════════════════════════
  Widget _buildReportsTab() {
    final carrierMap   = Map<String, int>.from(_stats['carrier_map'] ?? {});
    final monthlyMap   = Map<String, Map<String, dynamic>>.from(
        (_stats['monthly_map'] as Map? ?? {}).map((k,v) => MapEntry(k as String, Map<String,dynamic>.from(v as Map))));
    final totalShipments = (_stats['total_parcels'] ?? 0) as int;

    // Last 12 months sorted descending
    final now = DateTime.now();
    final last12 = List.generate(12, (i) {
      final d = DateTime(now.year, now.month - i, 1);
      return _monthKey(d);
    });

    final maxRevMonth = last12.fold(0.0, (mx, k) => monthlyMap[k]?['revenue'] != null
        ? ((monthlyMap[k]!['revenue'] as double) > mx ? monthlyMap[k]!['revenue'] as double : mx)
        : mx);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Revenue summary cards
        const Text('Revenue Summary', style: TextStyle( fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Row(children: [
          _ReportCard('Today',      '£${((_stats['today_revenue'] ?? 0.0) as double).toStringAsFixed(2)}', '${_stats['today_parcels'] ?? 0} parcels', _kOrange),
          const SizedBox(width: 10),
          _ReportCard('This Week',  '£${((_stats['week_revenue']  ?? 0.0) as double).toStringAsFixed(2)}', '${_stats['week_parcels']  ?? 0} parcels', _kPurple),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _ReportCard('This Month', '£${((_stats['month_revenue'] ?? 0.0) as double).toStringAsFixed(2)}', '${_stats['month_parcels'] ?? 0} parcels', _kGreen),
          const SizedBox(width: 10),
          _ReportCard('Bulk Rev',   '£${((_stats['bulk_revenue']  ?? 0.0) as double).toStringAsFixed(2)}', '${_stats['bulk_total']    ?? 0} orders',  const Color(0xFF0EA5E9)),
        ]),

        const SizedBox(height: 28),

        // Monthly Revenue Chart
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Monthly Revenue', style: TextStyle( fontSize: 14, fontWeight: FontWeight.w700)),
          GestureDetector(
            onTap: _exportMonthlyReportCSV,
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: _kGreen.withOpacity(0.08),
                    border: Border.all(color: _kGreen.withOpacity(0.3)),
                    borderRadius: BorderRadius.circular(20)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.download_rounded, size: 12, color: _kGreen),
                  SizedBox(width: 4),
                  Text('Download', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _kGreen)),
                ])),
          ),
        ]),
        const SizedBox(height: 12),

        // Bar chart (last 12 months, newest first)
        ...last12.map((key) {
          final d       = monthlyMap[key];
          final revenue = (d?['revenue'] as double?) ?? 0.0;
          final parcels = (d?['parcels'] as int?)    ?? 0;
          final pct     = maxRevMonth > 0 ? revenue / maxRevMonth : 0.0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(_monthLabel(key), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A))),
                Row(children: [
                  Text('$parcels parcels', style: const TextStyle(fontSize: 11, color: _kGrey)),
                  const SizedBox(width: 12),
                  Text('£${revenue.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _kPurple)),
                ]),
              ]),
              const SizedBox(height: 5),
              ClipRRect(borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                      value: pct, minHeight: 10, color: _kOrange,
                      backgroundColor: const Color(0xFFF0F0F0))),
            ]),
          );
        }),

        const SizedBox(height: 28),

        // Carrier breakdown
        const Text('Carrier Breakdown', style: TextStyle( fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        ...carrierMap.entries.map((e) {
          final pct = totalShipments > 0 ? e.value / totalShipments : 0.0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(e.key, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                Text('${e.value}  (${(pct * 100).toStringAsFixed(1)}%)', style: const TextStyle(fontSize: 11, color: _kGrey)),
              ]),
              const SizedBox(height: 4),
              ClipRRect(borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: pct, minHeight: 8, color: _kPurple, backgroundColor: const Color(0xFFF0F0F0))),
            ]),
          );
        }),

        const SizedBox(height: 28),

        // Download all
        const Text('Download Reports', style: TextStyle( fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        _ExportButton('All Shipments (CSV)',   Icons.local_shipping_rounded, _kOrange,              _exportShipmentsCSV),
        const SizedBox(height: 8),
        _ExportButton('All Users (CSV)',        Icons.people_rounded,         _kPurple,              _exportUsersCSV),
        const SizedBox(height: 8),
        _ExportButton('Bulk Orders (CSV)',      Icons.inventory_2_rounded,    const Color(0xFF0EA5E9), _exportBulkCSV),
        const SizedBox(height: 8),
        _ExportButton('Monthly Report (CSV)',   Icons.bar_chart_rounded,      _kGreen,               _exportMonthlyReportCSV),
      ]),
    );
  }

  // ── Common helpers ────────────────────────────────────────────
  void _openShipment(AdminShipment s) => showModalBottomSheet(
    context: context, isScrollControlled: true, useSafeArea: true, backgroundColor: Colors.transparent,
    builder: (_) => _ShipmentDetailSheet(shipment: s),
  );

  Widget _loadMoreIndicator(bool loading, bool hasMore, int count, String label) {
    if (loading) return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator(color: _kOrange, strokeWidth: 2)));
    if (!hasMore && count > 0) return Padding(padding: const EdgeInsets.all(16), child: Center(child: Text('All $count $label loaded', style: const TextStyle(fontSize: 12, color: _kGrey))));
    return const SizedBox();
  }

  Widget _emptyState(IconData icon, String msg) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Icon(icon, size: 48, color: const Color(0xFFE0E0E0)),
    const SizedBox(height: 12),
    Text(msg, style: const TextStyle(fontSize: 13, color: _kGrey), textAlign: TextAlign.center),
  ]));
}

// ══════════════════════════════════════════════════════════════════════════════
// SMALL REUSABLE WIDGETS
// ══════════════════════════════════════════════════════════════════════════════

class _StatChip extends StatelessWidget {
  final String label, value; final Color color;
  const _StatChip(this.label, this.value, this.color);
  @override Widget build(BuildContext context) => Expanded(child: Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(color: color.withOpacity(0.07), border: Border.all(color: color.withOpacity(0.2)), borderRadius: BorderRadius.circular(10)),
      child: Column(children: [
        Text(value, style: TextStyle( fontSize: 13, fontWeight: FontWeight.w800, color: color), maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(label, style: const TextStyle(fontSize: 8, color: _kGrey)),
      ])));
}

class _FilterChip extends StatelessWidget {
  final String label; final bool selected; final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected, required this.onTap});
  @override Widget build(BuildContext context) => GestureDetector(onTap: onTap,
      child: Container(margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
              color: selected ? _kOrange : Colors.white,
              border: Border.all(color: selected ? _kOrange : const Color(0xFFE0E0E0)),
              borderRadius: BorderRadius.circular(20)),
          child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
              color: selected ? Colors.white : const Color(0xFF6B6B6B)))));
}

class _MiniTag extends StatelessWidget {
  final String text; final Color color;
  const _MiniTag(this.text, this.color);
  @override Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
      child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)));
}

class _CarrierBreakdownBar extends StatelessWidget {
  final Map<String, int> carrierMap;
  const _CarrierBreakdownBar({required this.carrierMap});
  @override Widget build(BuildContext context) {
    final total  = carrierMap.values.fold(0, (a, b) => a + b);
    if (total == 0) return const SizedBox();
    final colors = [_kOrange, _kPurple, _kGreen, const Color(0xFF0EA5E9), Colors.red, const Color(0xFFEC4899)];
    int ci = 0;
    return Padding(padding: const EdgeInsets.only(bottom: 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Carriers', style: TextStyle(fontSize: 9, color: _kGrey)),
      const SizedBox(height: 4),
      ClipRRect(borderRadius: BorderRadius.circular(4),
        child: Row(children: carrierMap.entries.map((e) {
          final c = colors[ci++ % colors.length];
          return Expanded(flex: e.value, child: Tooltip(message: '${e.key}: ${e.value}',
              child: Container(height: 8, color: c)));
        }).toList()),
      ),
    ]));
  }
}

class _ReportCard extends StatelessWidget {
  final String title, value, sub; final Color color;
  const _ReportCard(this.title, this.value, this.sub, this.color);
  @override Widget build(BuildContext context) => Expanded(child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.withOpacity(0.07), border: Border.all(color: color.withOpacity(0.2)), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 11, color: _kGrey)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle( fontSize: 18, fontWeight: FontWeight.w800, color: color)),
        Text(sub,   style: const TextStyle(fontSize: 10, color: _kGrey)),
      ])));
}

class _ExportButton extends StatelessWidget {
  final String label; final IconData icon; final Color color; final VoidCallback onTap;
  const _ExportButton(this.label, this.icon, this.color, this.onTap);
  @override Widget build(BuildContext context) => GestureDetector(onTap: onTap,
      child: Container(padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: color.withOpacity(0.07), border: Border.all(color: color.withOpacity(0.2)), borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 10),
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
            const Spacer(),
            Icon(Icons.download_rounded, size: 14, color: color),
          ])));
}

// ══════════════════════════════════════════════════════════════════════════════
// USER ROW
// ══════════════════════════════════════════════════════════════════════════════

class _UserRow extends StatelessWidget {
  final AdminUser user; final VoidCallback onTap;
  const _UserRow({required this.user, required this.onTap});
  @override Widget build(BuildContext context) => GestureDetector(onTap: onTap,
      child: Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: _kCard, border: Border.all(color: _kBorder), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(shape: BoxShape.circle,
                color: _kOrange.withOpacity(0.1), border: Border.all(color: _kOrange.withOpacity(0.3)),
                image: user.avatarUrl.isNotEmpty ? DecorationImage(image: NetworkImage(user.avatarUrl), fit: BoxFit.cover) : null),
                child: user.avatarUrl.isEmpty ? Center(child: Text(user.initials, style: const TextStyle( fontSize: 14, fontWeight: FontWeight.w700, color: _kOrange))) : null),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(user.fullName.isNotEmpty ? user.fullName : user.email,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A))),
              Text(user.email, style: const TextStyle(fontSize: 11, color: _kGrey), overflow: TextOverflow.ellipsis),
              if (user.city.isNotEmpty)
                Text('${user.city}${user.country.isNotEmpty ? " · ${user.country}" : ""}',
                    style: const TextStyle(fontSize: 11, color: _kLightGrey)),
            ])),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${user.totalParcels} parcel${user.totalParcels != 1 ? "s" : ""}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _kPurple)),
              Text('£${user.totalSpent.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _kGreen)),
              const SizedBox(height: 4),
              const Icon(Icons.chevron_right, size: 16, color: _kLightGrey),
            ]),
          ])));
}

// ══════════════════════════════════════════════════════════════════════════════
// SHIPMENT ROW
// ══════════════════════════════════════════════════════════════════════════════

class _ShipmentRow extends StatelessWidget {
  final AdminShipment shipment; final VoidCallback onTap;
  const _ShipmentRow({required this.shipment, required this.onTap});
  @override Widget build(BuildContext context) {
    final s = shipment;
    return GestureDetector(onTap: onTap,
        child: Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: _kCard, border: Border.all(color: _kBorder), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: s.carrierColor, shape: BoxShape.circle)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(s.trackingNumber, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A), fontFamily: 'monospace'), overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 8),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: s.statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                      child: Text(s.statusLabel, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: s.statusColor))),
                  if (s.isInternational) ...[const SizedBox(width: 4), const Text('🌍', style: TextStyle(fontSize: 10))],
                ]),
                const SizedBox(height: 3),
                Text(s.userEmail, style: const TextStyle(fontSize: 10, color: _kGrey), overflow: TextOverflow.ellipsis),
                Text('To ${s.recipientName} · ${s.recipientCity}${s.isInternational ? " · ${s.recipientCountry}" : ""}',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF6B6B6B))),
                if (s.status == 'failed' && s.failureReason != null)
                  Text('⚠ ${s.failureReason}', style: const TextStyle(fontSize: 10, color: Colors.red), maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('£${s.price.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _kPurple)),
                Text(_fmtDate(s.createdAt), style: const TextStyle(fontSize: 10, color: _kLightGrey)),
                const SizedBox(height: 4),
                const Icon(Icons.chevron_right, size: 14, color: _kLightGrey),
              ]),
            ])));
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// USER DETAIL PAGE — view + edit profile, view shipments + addresses
// ══════════════════════════════════════════════════════════════════════════════

class _UserDetailPage extends StatefulWidget {
  final AdminUser user;
  final Future<void> Function(String userId, Map<String, dynamic> fields) onUpdate;
  const _UserDetailPage({required this.user, required this.onUpdate});
  @override State<_UserDetailPage> createState() => _UserDetailPageState();
}

class _UserDetailPageState extends State<_UserDetailPage> with SingleTickerProviderStateMixin {
  final _sb = Supabase.instance.client;
  List<AdminShipment> _parcels   = [];
  List<Map<String,dynamic>> _addresses = [];
  bool _loading = true, _hasMore = true;
  int  _page = 0;
  late TabController _tabs;
  final _scroll = ScrollController();

  // Edit fields
  bool _editing = false, _saving = false;
  late TextEditingController _nameCtrl, _phoneCtrl, _cityCtrl, _postcodeCtrl, _countryCtrl;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    final u = widget.user;
    _nameCtrl     = TextEditingController(text: u.fullName);
    _phoneCtrl    = TextEditingController(text: u.phone);
    _cityCtrl     = TextEditingController(text: u.city);
    _postcodeCtrl = TextEditingController(text: u.postcode);
    _countryCtrl  = TextEditingController(text: u.country);
    _load();
    _loadAddresses();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 200 && !_loading && _hasMore) _load();
    });
  }

  @override
  void dispose() {
    _tabs.dispose(); _scroll.dispose();
    _nameCtrl.dispose(); _phoneCtrl.dispose();
    _cityCtrl.dispose(); _postcodeCtrl.dispose(); _countryCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading && !reset) return;
    if (reset) { _parcels.clear(); _page = 0; _hasMore = true; }
    setState(() => _loading = true);
    try {
      final from = _page * 50;
      final data = await _sb.from('shipments').select('*')
          .eq('user_email', widget.user.email).order('created_at', ascending: false).range(from, from + 49);
      final loaded = (data as List).map((j) => AdminShipment.fromJson(j)).toList();
      setState(() { _parcels.addAll(loaded); _page++; _hasMore = data.length == 50; });
    } catch (e) { debugPrint('user parcels: $e'); }
    setState(() => _loading = false);
  }

  Future<void> _loadAddresses() async {
    try {
      final data = await _sb.from('addresses').select('*').eq('user_id', widget.user.id);
      setState(() => _addresses = List<Map<String,dynamic>>.from(data));
    } catch (e) { debugPrint('addresses: $e'); }
  }

  Future<void> _saveProfile() async {
    setState(() => _saving = true);
    try {
      await widget.onUpdate(widget.user.id, {
        'full_name': _nameCtrl.text.trim(),
        'phone':     _phoneCtrl.text.trim(),
        'city':      _cityCtrl.text.trim(),
        'postcode':  _postcodeCtrl.text.trim(),
        'country':   _countryCtrl.text.trim(),
      });
      setState(() => _editing = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(behavior: SnackBarBehavior.fixed, content: Text('Profile updated'), backgroundColor: _kGreen));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(behavior: SnackBarBehavior.fixed, content: Text('Error: $e'), backgroundColor: Colors.red));
    }
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(child: Column(children: [
        Container(color: _kCard, padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: Column(children: [
            Row(children: [
              GestureDetector(onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.arrow_back_ios, size: 16, color: Color(0xFF6B6B6B))),
              const SizedBox(width: 8),
              const Text('User Profile', style: TextStyle( fontSize: 18, fontWeight: FontWeight.w800)),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() { _editing = !_editing; }),
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                        color: _editing ? Colors.red.withOpacity(0.08) : _kOrange.withOpacity(0.08),
                        border: Border.all(color: _editing ? Colors.red.withOpacity(0.3) : _kOrange.withOpacity(0.3)),
                        borderRadius: BorderRadius.circular(20)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(_editing ? Icons.close_rounded : Icons.edit_rounded, size: 12, color: _editing ? Colors.red : _kOrange),
                      const SizedBox(width: 4),
                      Text(_editing ? 'Cancel' : 'Edit', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _editing ? Colors.red : _kOrange)),
                    ])),
              ),
            ]),
            const SizedBox(height: 16),

            // Avatar + info
            Row(children: [
              Container(width: 56, height: 56, decoration: BoxDecoration(shape: BoxShape.circle,
                  color: _kOrange.withOpacity(0.1), border: Border.all(color: _kOrange.withOpacity(0.3)),
                  image: u.avatarUrl.isNotEmpty ? DecorationImage(image: NetworkImage(u.avatarUrl), fit: BoxFit.cover) : null),
                  child: u.avatarUrl.isEmpty ? Center(child: Text(u.initials, style: const TextStyle( fontSize: 18, fontWeight: FontWeight.w700, color: _kOrange))) : null),
              const SizedBox(width: 14),
              Expanded(child: _editing
              // Edit mode
                  ? Column(children: [
                _EditField(ctrl: _nameCtrl,     label: 'Full Name'),
                const SizedBox(height: 6),
                _EditField(ctrl: _phoneCtrl,    label: 'Phone', keyboard: TextInputType.phone),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(child: _EditField(ctrl: _cityCtrl,     label: 'City')),
                  const SizedBox(width: 6),
                  Expanded(child: _EditField(ctrl: _postcodeCtrl, label: 'Postcode')),
                ]),
                const SizedBox(height: 6),
                _EditField(ctrl: _countryCtrl, label: 'Country'),
              ])
              // View mode
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(u.fullName.isNotEmpty ? u.fullName : u.email,
                    style: const TextStyle( fontSize: 16, fontWeight: FontWeight.w800)),
                Text(u.email, style: const TextStyle(fontSize: 12, color: _kGrey)),
                if (u.phone.isNotEmpty) Text(u.phone, style: const TextStyle(fontSize: 12, color: _kGrey)),
                if (u.city.isNotEmpty)  Text('${u.city}, ${u.postcode}, ${u.country}', style: const TextStyle(fontSize: 12, color: _kLightGrey)),
              ])),
            ]),

            if (_editing) ...[
              const SizedBox(height: 12),
              SizedBox(width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _saveProfile,
                  style: ElevatedButton.styleFrom(backgroundColor: _kOrange,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  child: _saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Save Changes', style: TextStyle(color: Colors.white,  fontWeight: FontWeight.w700)),
                ),
              ),
            ],

            const SizedBox(height: 14),
            Row(children: [
              _UserStat('Parcels', '${u.totalParcels}', _kPurple),
              const SizedBox(width: 8),
              _UserStat('Spent', '£${u.totalSpent.toStringAsFixed(2)}', _kGreen),
              const SizedBox(width: 8),
              _UserStat('Joined', _fmtDate(u.joinedAt), _kOrange),
            ]),
            const SizedBox(height: 12),
            TabBar(
              controller: _tabs,
              labelStyle: const TextStyle( fontSize: 12, fontWeight: FontWeight.w700),
              unselectedLabelStyle: const TextStyle(fontSize: 12),
              labelColor: _kOrange, unselectedLabelColor: _kGrey, indicatorColor: _kOrange,
              tabs: const [Tab(text: 'Shipments'), Tab(text: 'Addresses'), Tab(text: 'Info')],
            ),
          ]),
        ),
        const Divider(height: 1),
        Expanded(child: TabBarView(controller: _tabs, children: [
          // Shipments
          RefreshIndicator(onRefresh: () => _load(reset: true), color: _kOrange,
            child: ListView.builder(controller: _scroll, padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              itemCount: _parcels.length + 1,
              itemBuilder: (_, i) {
                if (i == _parcels.length) {
                  if (_loading) return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator(color: _kOrange, strokeWidth: 2)));
                  if (!_hasMore && _parcels.isNotEmpty) return Padding(padding: const EdgeInsets.all(16), child: Center(child: Text('All ${_parcels.length} shipments', style: const TextStyle(fontSize: 12, color: _kGrey))));
                  return const SizedBox();
                }
                return _ShipmentRow(shipment: _parcels[i], onTap: () => showModalBottomSheet(
                    context: context, isScrollControlled: true, useSafeArea: true, backgroundColor: Colors.transparent,
                    builder: (_) => _ShipmentDetailSheet(shipment: _parcels[i])));
              },
            ),
          ),
          // Addresses
          _addresses.isEmpty
              ? const Center(child: Text('No saved addresses', style: TextStyle(fontSize: 13, color: _kGrey)))
              : ListView.builder(padding: const EdgeInsets.all(16), itemCount: _addresses.length,
              itemBuilder: (_, i) {
                final a = _addresses[i];
                return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: _kCard, border: Border.all(color: _kBorder), borderRadius: BorderRadius.circular(12)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        const Icon(Icons.location_on_rounded, size: 14, color: _kOrange),
                        const SizedBox(width: 6),
                        Expanded(child: Text('${a['address_line1'] ?? ''}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                        if (a['is_default'] == true) _MiniTag('Default', _kGreen),
                      ]),
                      if ((a['address_line2'] ?? '').isNotEmpty) Text('${a['address_line2']}', style: const TextStyle(fontSize: 12, color: _kGrey)),
                      Text('${a['city'] ?? ''}, ${a['postcode'] ?? ''}, ${a['country'] ?? ''}', style: const TextStyle(fontSize: 12, color: _kGrey)),
                    ]));
              }),
          // Account info
          SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _InfoTile('User ID',    u.id,                       copyable: true),
            _InfoTile('Email',      u.email,                    copyable: true),
            _InfoTile('Full Name',  u.fullName.isNotEmpty ? u.fullName : '—'),
            _InfoTile('Phone',      u.phone.isNotEmpty    ? u.phone    : '—'),
            _InfoTile('City',       u.city.isNotEmpty     ? u.city     : '—'),
            _InfoTile('Postcode',   u.postcode.isNotEmpty ? u.postcode : '—'),
            _InfoTile('Country',    u.country.isNotEmpty  ? u.country  : '—'),
            _InfoTile('Joined',     _fmtDate(u.joinedAt)),
            _InfoTile('Total Parcels', '${u.totalParcels}'),
            _InfoTile('Total Spent',   '£${u.totalSpent.toStringAsFixed(2)}'),
          ])),
        ])),
      ])),
    );
  }
}

class _EditField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final TextInputType? keyboard;
  const _EditField({required this.ctrl, required this.label, this.keyboard});
  @override Widget build(BuildContext context) => TextField(
      controller: ctrl, keyboardType: keyboard,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        labelText: label, labelStyle: const TextStyle(fontSize: 11, color: _kGrey),
        isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        filled: true, fillColor: const Color(0xFFF8F8F8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kBorder)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kOrange, width: 1.5)),
      ));
}

class _InfoTile extends StatelessWidget {
  final String label, value; final bool copyable;
  const _InfoTile(this.label, this.value, {this.copyable = false});
  @override Widget build(BuildContext context) => Container(
      margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: _kCard, border: Border.all(color: _kBorder), borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Text(label, style: const TextStyle(fontSize: 11, color: _kGrey)),
        const SizedBox(width: 12),
        Expanded(child: Text(value, textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A)),
            overflow: TextOverflow.ellipsis)),
        if (copyable) ...[
          const SizedBox(width: 8),
          GestureDetector(onTap: () => Clipboard.setData(ClipboardData(text: value)),
              child: const Icon(Icons.copy_rounded, size: 14, color: _kGrey)),
        ],
      ]));
}

class _UserStat extends StatelessWidget {
  final String label, value; final Color color;
  const _UserStat(this.label, this.value, this.color);
  @override Widget build(BuildContext context) => Expanded(child: Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(color: color.withOpacity(0.07), border: Border.all(color: color.withOpacity(0.2)), borderRadius: BorderRadius.circular(8)),
      child: Column(children: [
        Text(value, style: TextStyle( fontSize: 11, fontWeight: FontWeight.w800, color: color), maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(label, style: const TextStyle(fontSize: 9, color: _kGrey)),
      ])));
}

// ══════════════════════════════════════════════════════════════════════════════
// BULK ORDER DETAIL PAGE — items list + per-item label download
// ══════════════════════════════════════════════════════════════════════════════

class _BulkOrderDetailPage extends StatefulWidget {
  final BulkOrder bulkOrder;
  const _BulkOrderDetailPage({required this.bulkOrder});
  @override State<_BulkOrderDetailPage> createState() => _BulkOrderDetailPageState();
}

class _BulkOrderDetailPageState extends State<_BulkOrderDetailPage> {
  final _sb = Supabase.instance.client;
  List<Map<String,dynamic>> _items = [];
  // Resolved full shipments keyed by item index (loaded lazily via tracking_number)
  final Map<int, AdminShipment> _shipments = {};
  bool _loading = true;

  @override
  void initState() { super.initState(); _loadItems(); }

  Future<void> _loadItems() async {
    setState(() => _loading = true);
    try {
      // Shipments are linked directly via shipments.bulk_order_id
      final data = await _sb
          .from('shipments')
          .select('*')
          .eq('bulk_order_id', widget.bulkOrder.id)
          .order('created_at', ascending: true);

      final shipmentList = (data as List)
          .map((j) => AdminShipment.fromJson(j))
          .toList();

      setState(() {
        _shipments.clear();
        for (int i = 0; i < shipmentList.length; i++) {
          _shipments[i] = shipmentList[i];
        }
        // Also populate _items from shipment data so the list renders
        _items = (data as List).map((j) => Map<String,dynamic>.from(j)).toList();
        _loading = false;
      });
    } catch (e) {
      debugPrint('[Bulk detail] error: $e');
      setState(() => _loading = false);
    }
  }

  // No separate resolve needed — shipments ARE the items
  Future<void> _resolveShipments(List<Map<String,dynamic>> items) async {}

  Future<void> _openLabel(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Color _carrierColor(String carrier) {
    final c = carrier.toLowerCase();
    if (c.contains('royal'))  return const Color(0xFFE30613);
    if (c.contains('evri'))   return const Color(0xFF8B5CF6);
    if (c.contains('dpd'))    return const Color(0xFFE8001C);
    if (c.contains('yodel'))  return _kPurple;
    if (c.contains('parcel')) return const Color(0xFF003087);
    if (c.contains('fedex'))  return const Color(0xFF4D148C);
    return _kGrey;
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'success':
      case 'delivered':     return _kGreen;
      case 'label_created': return _kPurple;
      case 'in_transit':    return _kOrange;
      case 'failed':        return Colors.red;
      case 'pending':       return _kOrange;
      default:              return _kGrey;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'success':       return 'Success';
      case 'delivered':     return 'Delivered';
      case 'label_created': return 'Label Created';
      case 'in_transit':    return 'In Transit';
      case 'failed':        return 'Failed';
      case 'pending':       return 'Pending';
      default:              return status.replaceAll('_', ' ');
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.bulkOrder;
    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(child: Column(children: [
        // ── Header ──────────────────────────────────────────────
        Container(color: _kCard, padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              GestureDetector(onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.arrow_back_ios, size: 16, color: Color(0xFF6B6B6B))),
              const SizedBox(width: 8),
              Expanded(child: Text(b.batchName.isNotEmpty ? b.batchName : 'Bulk Order',
                  style: const TextStyle( fontSize: 18, fontWeight: FontWeight.w800),
                  overflow: TextOverflow.ellipsis)),
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: b.statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                  child: Text(b.status, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: b.statusColor))),
            ]),
            const SizedBox(height: 6),
            Text(b.userEmail, style: const TextStyle(fontSize: 12, color: _kGrey)),
            Text(_fmtDate(b.createdAt), style: const TextStyle(fontSize: 11, color: _kLightGrey)),
            const SizedBox(height: 12),
            Row(children: [
              _UserStat('Total',  '${b.totalParcels}', _kPurple),
              const SizedBox(width: 6),
              _UserStat('OK',     '${b.processed}',    _kGreen),
              const SizedBox(width: 6),
              _UserStat('Failed', '${b.failed}',       Colors.red),
              const SizedBox(width: 6),
              _UserStat('Cost',   '£${b.totalCost.toStringAsFixed(2)}', _kOrange),
            ]),
          ]),
        ),
        const Divider(height: 1),

        // ── Items list ───────────────────────────────────────────
        if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator(color: _kOrange, strokeWidth: 2)))
        else if (_items.isEmpty)
          const Expanded(child: Center(child: Text('No shipments in this batch',
              style: TextStyle(fontSize: 13, color: _kGrey))))
        else
          Expanded(child: RefreshIndicator(
            onRefresh: _loadItems,
            color: _kOrange,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
              itemCount: _items.length,
              itemBuilder: (_, i) {
                final shipment  = _shipments[i]!; // always set since _items comes from shipments
                final item      = _items[i]; // raw map fallback
                final status    = shipment.status;
                final sc        = shipment.statusColor;
                final sl        = shipment.statusLabel;
                final carrier   = shipment.carrier;
                final service   = shipment.service;
                final labelUrl  = shipment.labelUrl;
                final price     = shipment.price;
                final tracking  = shipment.trackingNumber;
                final errMsg    = shipment.failureReason ?? '';
                final hasShipment = true;
                final tappable    = true;

                return GestureDetector(
                  onTap: tappable ? () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => _ShipmentDetailSheet(shipment: shipment),
                  ) : null,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _kCard,
                      border: Border.all(color: tappable ? _kOrange.withOpacity(0.3) : _kBorder),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      // ── Top row: name + status ─────────────────
                      Row(children: [
                        // Carrier dot
                        if (carrier.isNotEmpty) ...[
                          Container(width: 8, height: 8, decoration: BoxDecoration(
                              color: _carrierColor(carrier), shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                        ],
                        Expanded(child: Text(
                          shipment.recipientName,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A)),
                          overflow: TextOverflow.ellipsis,
                        )),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                              color: sc.withOpacity(0.1),
                              border: Border.all(color: sc.withOpacity(0.3)),
                              borderRadius: BorderRadius.circular(20)),
                          child: Text(sl, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: sc)),
                        ),
                      ]),
                      const SizedBox(height: 6),

                      // ── Address ────────────────────────────────
                      Row(children: [
                        const Icon(Icons.location_on_rounded, size: 12, color: _kGrey),
                        const SizedBox(width: 4),
                        Expanded(child: Text(
                          [
                            shipment.recipientCity,
                            shipment.recipientPostcode,
                            if (shipment.isInternational) shipment.recipientCountry,
                          ].where((s) => s.isNotEmpty).join(', '),
                          style: const TextStyle(fontSize: 11, color: _kGrey),
                          overflow: TextOverflow.ellipsis,
                        )),
                      ]),

                      // ── Carrier + service ──────────────────────
                      if (carrier.isNotEmpty || service.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(children: [
                          const Icon(Icons.local_shipping_rounded, size: 12, color: _kGrey),
                          const SizedBox(width: 4),
                          Text('$carrier${service.isNotEmpty ? "  ·  $service" : ""}',
                              style: const TextStyle(fontSize: 11, color: _kGrey)),
                        ]),
                      ],

                      // ── Tracking number ────────────────────────
                      if (tracking.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(children: [
                          const Icon(Icons.qr_code_rounded, size: 12, color: _kLightGrey),
                          const SizedBox(width: 4),
                          Expanded(child: Text(tracking,
                              style: const TextStyle(fontSize: 11, color: _kLightGrey, fontFamily: 'monospace'),
                              overflow: TextOverflow.ellipsis)),
                          // Copy tracking
                          GestureDetector(
                            onTap: () => Clipboard.setData(ClipboardData(text: tracking)),
                            child: const Icon(Icons.copy_rounded, size: 12, color: _kLightGrey),
                          ),
                        ]),
                      ],

                      // ── Parcel info ────────────────────────────
                      if (shipment.parcelSize.isNotEmpty || shipment.weightKg > 0) ...[
                        const SizedBox(height: 4),
                        Row(children: [
                          const Icon(Icons.inventory_2_rounded, size: 12, color: _kLightGrey),
                          const SizedBox(width: 4),
                          Text(
                            [
                              if (shipment.parcelSize.isNotEmpty) shipment.parcelSize.toUpperCase(),
                              if (shipment.weightKg > 0) '${shipment.weightKg} kg',
                              if (shipment.parcelValue > 0) 'Value: £${shipment.parcelValue.toStringAsFixed(2)}',
                            ].join('  ·  '),
                            style: const TextStyle(fontSize: 11, color: _kLightGrey),
                          ),
                        ]),
                      ],

                      // ── Error message ──────────────────────────
                      if (errMsg.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.05),
                              border: Border.all(color: Colors.red.withOpacity(0.2)),
                              borderRadius: BorderRadius.circular(6)),
                          child: Row(children: [
                            const Icon(Icons.error_outline_rounded, size: 12, color: Colors.red),
                            const SizedBox(width: 6),
                            Expanded(child: Text(errMsg,
                                style: const TextStyle(fontSize: 11, color: Colors.red),
                                maxLines: 2, overflow: TextOverflow.ellipsis)),
                          ]),
                        ),
                      ],

                      // ── Bottom row: price + label + chevron ────
                      const SizedBox(height: 8),
                      Row(children: [
                        if (price > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                                color: _kPurple.withOpacity(0.07),
                                borderRadius: BorderRadius.circular(6)),
                            child: Text('£${price.toStringAsFixed(2)}',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _kPurple)),
                          ),
                        const Spacer(),
                        // Label download
                        if (labelUrl.isNotEmpty)
                          GestureDetector(
                            onTap: () => _openLabel(labelUrl),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(color: _kPurple, borderRadius: BorderRadius.circular(8)),
                              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.download_rounded, size: 12, color: Colors.white),
                                SizedBox(width: 4),
                                Text('Label', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                              ]),
                            ),
                          ),
                        // All items resolved immediately from shipments query
                        // Tap for full details
                        if (hasShipment) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                                color: _kOrange.withOpacity(0.08),
                                border: Border.all(color: _kOrange.withOpacity(0.3)),
                                borderRadius: BorderRadius.circular(6)),
                            child: const Row(mainAxisSize: MainAxisSize.min, children: [
                              Text('Details', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _kOrange)),
                              SizedBox(width: 2),
                              Icon(Icons.chevron_right, size: 12, color: _kOrange),
                            ]),
                          ),
                        ],
                      ]),
                    ]),
                  ),
                );
              },
            ),
          )),
      ])),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SHIPMENT DETAIL BOTTOM SHEET
// ══════════════════════════════════════════════════════════════════════════════

class _ShipmentDetailSheet extends StatelessWidget {
  final AdminShipment shipment;
  const _ShipmentDetailSheet({required this.shipment});

  @override Widget build(BuildContext context) {
    final s = shipment;
    return Container(
      decoration: const BoxDecoration(color: _kCard, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(margin: const EdgeInsets.only(top: 12), width: 36, height: 4,
            decoration: BoxDecoration(color: const Color(0xFFE0E0E0), borderRadius: BorderRadius.circular(2)))),
        Flexible(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 32), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Shipment Details', style: TextStyle( fontSize: 18, fontWeight: FontWeight.w800)),
              Text(_fmtDateTime(s.createdAt), style: const TextStyle(fontSize: 12, color: _kGrey)),
            ])),
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: s.statusColor.withOpacity(0.1), border: Border.all(color: s.statusColor.withOpacity(0.3)), borderRadius: BorderRadius.circular(20)),
                child: Text(s.statusLabel, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: s.statusColor))),
          ]),
          const SizedBox(height: 16),

          // Tracking box
          Container(padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFFF8F8F8), borderRadius: BorderRadius.circular(10), border: Border.all(color: _kBorder)),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Tracking Number', style: TextStyle(fontSize: 10, color: _kGrey)),
                  const SizedBox(height: 4),
                  Text(s.trackingNumber, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, fontFamily: 'monospace')),
                  if (s.trackingStatus.isNotEmpty) ...[const SizedBox(height: 4), Text('📍 ${s.trackingStatus}', style: const TextStyle(fontSize: 11, color: _kGrey))],
                  if (s.lastLocation != null) Text('Last: ${s.lastLocation}', style: const TextStyle(fontSize: 11, color: _kLightGrey)),
                  if (s.estimatedDelivery != null) Text('Est. delivery: ${_fmtDate(s.estimatedDelivery!)}', style: const TextStyle(fontSize: 11, color: _kGreen)),
                ])),
                GestureDetector(onTap: () => Clipboard.setData(ClipboardData(text: s.trackingNumber)),
                    child: const Icon(Icons.copy_rounded, size: 16, color: _kGrey)),
              ])),

          // Failure
          if (s.status == 'failed' && s.failureReason != null) ...[
            const SizedBox(height: 12),
            Container(padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.red.withOpacity(0.05), border: Border.all(color: Colors.red.withOpacity(0.2)), borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  const Icon(Icons.error_outline_rounded, color: Colors.red, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Failure Reason', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.red)),
                    Text(s.failureReason!, style: const TextStyle(fontSize: 12, color: Colors.red)),
                  ])),
                ])),
          ],
          const SizedBox(height: 16),

          _DetailSection('Shipping Info', [
            _DetailRow('Carrier',      s.carrier,                        s.carrierColor),
            _DetailRow('Service',      s.service),
            _DetailRow('Parcel Size',  s.parcelSize.toUpperCase()),
            _DetailRow('Content',      s.parcelType),
            _DetailRow('Weight',       '${s.weightKg} kg'),
            _DetailRow('Parcel Value', '£${s.parcelValue.toStringAsFixed(2)}'),
            _DetailRow('Price',        '£${s.price.toStringAsFixed(2)}',  _kGreen),
            if (s.isInternational) _DetailRow('Type', '🌍 International', _kGreen),
            _DetailRow('Source', s.source),
          ]),
          const SizedBox(height: 14),

          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: _AddressBox('FROM', s.senderName,    s.senderCity,    s.senderPostcode, _kPurple)),
            const SizedBox(width: 10),
            Expanded(child: _AddressBox('TO',   s.recipientName, s.recipientCity, '${s.recipientPostcode}${s.isInternational ? "\n${s.recipientCountry}" : ""}', _kOrange)),
          ]),
          const SizedBox(height: 14),

          _DetailSection('Payment', [
            _DetailRow('User Email', s.userEmail),
            if (s.paymentIntentId != null) _DetailRow('Payment ID', s.paymentIntentId!.length > 24 ? '${s.paymentIntentId!.substring(0,24)}…' : s.paymentIntentId!),
            if (s.labelId != null) _DetailRow('Label ID', s.labelId!),
          ]),

          if (s.labelUrl.isNotEmpty) ...[
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, height: 46,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final uri = Uri.parse(s.labelUrl);
                  if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
                },
                icon: const Icon(Icons.download_rounded, size: 16, color: Colors.white),
                label: const Text('Download Label PDF'),
                style: ElevatedButton.styleFrom(backgroundColor: _kPurple, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    textStyle: const TextStyle( fontSize: 14, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ]))),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SHARED DETAIL WIDGETS
// ══════════════════════════════════════════════════════════════════════════════

class _DetailSection extends StatelessWidget {
  final String title; final List<Widget> rows;
  const _DetailSection(this.title, this.rows);
  @override Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(title, style: const TextStyle( fontSize: 13, fontWeight: FontWeight.w700)),
    const SizedBox(height: 8),
    Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: const Color(0xFFF8F8F8), borderRadius: BorderRadius.circular(10), border: Border.all(color: _kBorder)),
        child: Column(children: rows)),
  ]);
}

class _DetailRow extends StatelessWidget {
  final String label, value; final Color? valueColor;
  const _DetailRow(this.label, this.value, [this.valueColor]);
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(fontSize: 12, color: _kGrey)),
        Flexible(child: Text(value, textAlign: TextAlign.right,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: valueColor ?? const Color(0xFF1A1A1A)))),
      ]));
}

class _AddressBox extends StatelessWidget {
  final String label, name, city, postcode; final Color color;
  const _AddressBox(this.label, this.name, this.city, this.postcode, this.color);
  @override Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withOpacity(0.05), border: Border.all(color: color.withOpacity(0.2)), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: color, letterSpacing: 0.8)),
        const SizedBox(height: 5),
        Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        Text('$city  $postcode', style: const TextStyle(fontSize: 11, color: Color(0xFF6B6B6B))),
      ]));
}

// ══════════════════════════════════════════════════════════════════════════════
// CSV DOWNLOAD SHEET — copy to clipboard OR download file
// ══════════════════════════════════════════════════════════════════════════════

class _CsvDownloadSheet extends StatelessWidget {
  final String filename, content;
  final VoidCallback onCopy, onFile;
  const _CsvDownloadSheet({
    required this.filename, required this.content,
    required this.onCopy,   required this.onFile,
  });

  @override
  Widget build(BuildContext context) {
    final lines = content.split('\n').length - 1; // rows excl. header
    return Container(
      decoration: const BoxDecoration(
          color: _kCard, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle
        Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(color: const Color(0xFFE0E0E0), borderRadius: BorderRadius.circular(2)))),

        // File info
        Container(padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFFF8F8F8),
                border: Border.all(color: _kBorder), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Container(width: 40, height: 40,
                  decoration: BoxDecoration(color: _kGreen.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: const Center(child: Text('CSV', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: _kGreen)))),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(filename, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A)), overflow: TextOverflow.ellipsis),
                Text('$lines rows', style: const TextStyle(fontSize: 11, color: _kGrey)),
              ])),
            ])),
        const SizedBox(height: 20),

        const Text('How would you like to export?',
            style: TextStyle( fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),

        // Copy to clipboard
        GestureDetector(
          onTap: () { Navigator.pop(context); onCopy(); },
          child: Container(width: double.infinity, padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: _kOrange.withOpacity(0.07),
                  border: Border.all(color: _kOrange.withOpacity(0.3)), borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                Container(width: 40, height: 40, decoration: BoxDecoration(color: _kOrange.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.copy_rounded, color: _kOrange, size: 18)),
                const SizedBox(width: 14),
                const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Copy to Clipboard', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
                  Text('Paste directly into Excel or Google Sheets', style: TextStyle(fontSize: 11, color: _kGrey)),
                ])),
                const Icon(Icons.chevron_right, size: 18, color: _kGrey),
              ])),
        ),
        const SizedBox(height: 10),

        // Download file
        GestureDetector(
          onTap: () { Navigator.pop(context); onFile(); },
          child: Container(width: double.infinity, padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: _kPurple.withOpacity(0.07),
                  border: Border.all(color: _kPurple.withOpacity(0.3)), borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                Container(width: 40, height: 40, decoration: BoxDecoration(color: _kPurple.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.download_rounded, color: _kPurple, size: 18)),
                const SizedBox(width: 14),
                const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Download File', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
                  Text('Save to Downloads folder on your device', style: TextStyle(fontSize: 11, color: _kGrey)),
                ])),
                const Icon(Icons.chevron_right, size: 18, color: _kGrey),
              ])),
        ),
        const SizedBox(height: 10),

        // Cancel
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(border: Border.all(color: _kBorder), borderRadius: BorderRadius.circular(14)),
              child: const Center(child: Text('Cancel', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _kGrey)))),
        ),
      ]),
    );
  }
}