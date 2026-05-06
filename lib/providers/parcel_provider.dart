// lib/providers/parcel_provider.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utilis/service_fee.dart';

// ── Models ────────────────────────────────────────────────────────

class ParcelSize {
  final String id, name, maxWeight, dimensions, examples;
  const ParcelSize({
    required this.id, required this.name, required this.maxWeight,
    required this.dimensions, required this.examples,
  });
}

class CourierRate {
  final String rateId, carrier, service, currency, dropoff;
  final String? carrierId, serviceCode;
  final double price;
  final int?   estimatedDays;

  const CourierRate({
    required this.rateId, required this.carrier, required this.service,
    required this.price,  required this.currency,
    this.carrierId, this.serviceCode,
    this.estimatedDays, this.dropoff = 'Drop-off',
  });

  Color get carrierColor {
    final c = carrier.toLowerCase();
    if (c.contains('royal mail'))  return const Color(0xFFE30613);
    if (c.contains('evri'))        return const Color(0xFF8B5CF6);
    if (c.contains('dpd'))         return const Color(0xFFE8001C);
    if (c.contains('fedex'))       return const Color(0xFF4D148C);
    if (c.contains('globalpost'))  return const Color(0xFF0284C7);
    if (c.contains('yodel'))       return const Color(0xFF6D28D9);
    if (c.contains('parcelforce')) return const Color(0xFF003087);
    if (c.contains('ups'))         return const Color(0xFF351C15);
    if (c.contains('dhl'))         return const Color(0xFFFFC300);
    return const Color(0xFF6B6B6B);
  }

  String get deliveryLabel {
    if (estimatedDays == null) return service;
    if (estimatedDays! <= 1)   return 'Next day';
    return '$estimatedDays–${estimatedDays! + 1} days';
  }
}

// ── Shipment model ────────────────────────────────────────────────

class Shipment {
  final String id;
  final String trackingNumber;
  final String labelUrl;
  final String carrier;
  final String service;
  final String senderName;
  final String senderCity;
  final String senderPostcode;
  final String recipientName;
  final String recipientCity;
  final String recipientPostcode;
  final String recipientCountry;
  final String parcelSize;
  final String parcelType;
  final double price;
  final String status;
  final String source;
  final DateTime createdAt;

  const Shipment({
    required this.id,
    required this.trackingNumber,
    required this.labelUrl,
    required this.carrier,
    required this.service,
    required this.senderName,
    required this.senderCity,
    required this.senderPostcode,
    required this.recipientName,
    required this.recipientCity,
    required this.recipientPostcode,
    this.recipientCountry = 'GB',
    required this.parcelSize,
    required this.parcelType,
    required this.price,
    required this.status,
    this.source = '',
    required this.createdAt,
  });

  static const double markup = 0.40;

  factory Shipment.fromJson(Map<String, dynamic> j) => Shipment(
    id:                j['id']                 ?? '',
    trackingNumber:    j['tracking_number']     ?? '',
    labelUrl:          j['label_url']           ?? '',
    carrier:           j['carrier']             ?? 'Unknown',
    service:           j['service']             ?? 'Standard',
    senderName:        j['sender_name']         ?? '',
    senderCity:        j['sender_city']         ?? '',
    senderPostcode:    j['sender_postcode']      ?? '',
    recipientName:     j['recipient_name']       ?? '',
    recipientCity:     j['recipient_city']       ?? '',
    recipientPostcode: j['recipient_postcode']   ?? '',
    recipientCountry:  _readCountry(j),
    parcelSize:        j['parcel_size']          ?? '',
    parcelType:        j['parcel_type']          ?? '',
    price:             ((j['price'] ?? 0) as num).toDouble() + markup,
    status:            j['status']              ?? 'label_created',
    source:            j['source']?.toString()  ?? '',
    createdAt:         j['created_at'] != null
        ? DateTime.parse(j['created_at'])
        : DateTime.now(),
  );

  static String _readCountry(Map<String, dynamic> j) {
    final v = j['recipient_country'] ?? j['recipientCountry'] ?? j['country'];
    if (v != null && v.toString().trim().isNotEmpty) {
      return v.toString().trim().toUpperCase();
    }
    if (j['is_international'] == true) return 'INTL';
    return 'GB';
  }

  bool get isInternational => recipientCountry != 'GB';

  String get statusLabel {
    switch (status) {
      case 'label_created':     return 'Label Created';
      case 'in_transit':        return 'In Transit';
      case 'out_for_delivery':  return 'Out for Delivery';
      case 'delivered':         return 'Delivered';
      case 'exception':         return 'Exception';
      case 'voided':            return 'Voided';
      case 'processing':        return 'Processing';
      default:                  return 'Label Created';
    }
  }

  Color get statusColor {
    switch (status) {
      case 'delivered':         return const Color(0xFF059669);
      case 'in_transit':        return const Color(0xFFFF5A00);
      case 'out_for_delivery':  return const Color(0xFF0284C7);
      case 'exception':         return Colors.red;
      case 'voided':            return const Color(0xFF9B9B9B);
      case 'processing':        return const Color(0xFF6D28D9);
      default:                  return const Color(0xFF6D28D9);
    }
  }

  Color get carrierColor {
    final c = carrier.toLowerCase();
    if (c.contains('royal mail'))  return const Color(0xFFE30613);
    if (c.contains('evri'))        return const Color(0xFF8B5CF6);
    if (c.contains('dpd'))         return const Color(0xFFE8001C);
    if (c.contains('fedex'))       return const Color(0xFF4D148C);
    if (c.contains('globalpost'))  return const Color(0xFF0284C7);
    if (c.contains('yodel'))       return const Color(0xFF6D28D9);
    if (c.contains('parcelforce')) return const Color(0xFF003087);
    if (c.contains('ups'))         return const Color(0xFF351C15);
    if (c.contains('dhl'))         return const Color(0xFFFFC300);
    return const Color(0xFF6B6B6B);
  }
}

// ── Provider ──────────────────────────────────────────────────────

class ParcelProvider extends ChangeNotifier {

  static const _baseUrl   = 'https://tjrjeemaacumepimjltg.supabase.co/functions/v1';
  static const _engineUrl = '$_baseUrl/shipengine-courier';
  static const _anonKey   =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRqcmplZW1hYWN1bWVwaW1qbHRnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQxMjE2NjAsImV4cCI6MjA4OTY5NzY2MH0.gtBcFu-J48mPDk_S9ukfVdW-7gUmabGatmJ1g1_5zzo';

  final _supabase = Supabase.instance.client;

  // ── Step 1 — Sender ───────────────────────────────────────────
  String senderName     = '';
  String senderPhone    = '';
  String senderEmail    = '';
  String senderPostcode = '';
  String senderStreet   = '';
  String senderDoor     = '';
  String senderCity     = '';

  // ── Step 2 — Recipient ────────────────────────────────────────
  String recipName     = '';
  String recipPhone    = '';
  String recipPostcode = '';
  String recipStreet   = '';
  String recipDoor     = '';
  String recipCity     = '';

  // ── International ─────────────────────────────────────────────
  bool   isInternational  = false;
  String recipCountryCode = 'GB';
  String recipCountryName = 'United Kingdom';
  String recipState       = '';
  String recipZip         = '';

  // ── Step 3 — Parcel ───────────────────────────────────────────
  String selectedSizeId     = '';
  String selectedParcelType = '';
  String weightKg           = '';
  String parcelValueGbp     = '';

  // ── Step 4 — Courier ─────────────────────────────────────────
  String       selectedRateId = '';
  CourierRate? selectedRate;
  String       sortMode       = 'cheapest';

  List<CourierRate> liveRates      = [];
  bool              isLoadingRates = false;
  String            ratesError     = '';

  // Submit
  bool   isLoading          = false;
  bool   isSubmitted        = false;
  bool   requiresPickup     = false;
  String lastTrackingNumber = '';
  String lastLabelUrl       = '';
  String lastLabelId        = '';
  String errorMessage       = '';

  // Shipments
  List<Shipment> recentShipments    = [];
  bool           isLoadingShipments = false;

  // Realtime
  RealtimeChannel? _shipmentsChannel;

  // ── Static data ───────────────────────────────────────────────
  static const List<ParcelSize> sizes = [
    ParcelSize(id: 'xs', name: 'Extra Small', maxWeight: 'max 1kg',
        dimensions: 'Up to 15×11×1cm',   examples: 'Phone case · Small book'),
    ParcelSize(id: 'sm', name: 'Small Parcel', maxWeight: 'max 2kg',
        dimensions: 'Up to 45×35×16cm',  examples: 'T-shirt · Shoes · Small electronics'),
    ParcelSize(id: 'md', name: 'Medium Parcel', maxWeight: 'max 10kg',
        dimensions: 'Up to 61×46×46cm',  examples: 'Laptop · Jeans · Kitchen items'),
    ParcelSize(id: 'lg', name: 'Large Parcel', maxWeight: 'max 30kg',
        dimensions: 'Up to 120×60×60cm', examples: 'Guitar · Monitor · Multiple items'),
  ];

  static const List<String> parcelTypes = [
    'Clothing', 'Electronics', 'Documents', 'Books', 'Fragile', 'Gifts', 'Other',
  ];

  static const Map<String, double> sizeWeightLimits = {
    'xs': 1.0,
    'sm': 2.0,
    'md': 10.0,
    'lg': 30.0,
  };

  // ── Getters ───────────────────────────────────────────────────
  ParcelSize? get selectedSize =>
      selectedSizeId.isEmpty ? null
          : sizes.firstWhere((s) => s.id == selectedSizeId);

  List<CourierRate> get sortedRates {
    final list = List<CourierRate>.from(liveRates);
    if (sortMode == 'fastest') {
      list.sort((a, b) =>
          (a.estimatedDays ?? 99).compareTo(b.estimatedDays ?? 99));
    } else {
      list.sort((a, b) => a.price.compareTo(b.price));
    }
    return list;
  }

  double get serviceFee =>
      selectedRate == null ? 0
          : ServiceFee.get(selectedSizeId, isInternational: isInternational);

  double get shippingCost => selectedRate?.price ?? 0;
  double get totalCost    => shippingCost + serviceFee;

  // ── FIX: use zip for international, postcode for domestic ─────
  String get _resolvedPostcode =>
      isInternational && recipZip.isNotEmpty ? recipZip : recipPostcode;

  Map<String, String> get _headers => {
    'Content-Type':  'application/json',
    'Authorization': 'Bearer $_anonKey',
  };

  // ── FIX: always send country code explicitly in recipient ─────
  Map<String, dynamic> get _shipmentPayload => {
    'sender': {
      'name':     senderName,
      'address':  '$senderDoor $senderStreet'.trim(),
      'city':     senderCity,
      'postcode': senderPostcode,
      'country':  'GB',
      'phone':    senderPhone.isNotEmpty ? senderPhone : '07700000000',
      'email':    senderEmail,
    },
    'recipient': {
      'name':    recipName,
      'address': '$recipDoor $recipStreet'.trim(),
      'city':    recipCity,
      // FIX: always send resolved postcode/zip
      'postcode': _resolvedPostcode,
      // FIX: always send state (required for US/CA/AU etc.)
      'state':   recipState,
      // FIX: explicitly send country code — edge function reads this
      'country': recipCountryCode.isNotEmpty ? recipCountryCode : 'GB',
      'phone':   recipPhone.isNotEmpty ? recipPhone : '07700000000',
      'email':   '',
    },
    'parcel': {
      'size':      selectedSizeId,
      'weight_kg': double.tryParse(weightKg) ?? 1.0,
    },
  };

  // ── GET SHIPMENTS ─────────────────────────────────────────────
  Future<void> getShipments(String userEmail) async {
    if (userEmail.isEmpty) return;
    isLoadingShipments = true;
    notifyListeners();
    try {
      final data = await _supabase
          .from('shipments')
          .select()
          .eq('user_email', userEmail)
          .or('source.eq.single,source.is.null')
          .order('created_at', ascending: false);
      recentShipments = (data as List)
          .map((j) => Shipment.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[ParcelProvider] getShipments error: $e');
    }
    isLoadingShipments = false;
    notifyListeners();

    // ── Realtime subscription ──────────────────────────────────
    _shipmentsChannel?.unsubscribe();
    _shipmentsChannel = _supabase
        .channel('shipments:$userEmail')
        .onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'shipments',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'user_email',
        value: userEmail,
      ),
      callback: (payload) {
        debugPrint('[Realtime] shipment updated: ${payload.newRecord}');
        final updated = Shipment.fromJson(
            payload.newRecord as Map<String, dynamic>);
        final idx = recentShipments.indexWhere((s) => s.id == updated.id);
        if (idx != -1) {
          recentShipments[idx] = updated;
        } else {
          recentShipments.insert(0, updated);
        }
        notifyListeners();
      },
    ).subscribe();
  }

  void disposeRealtime() {
    _shipmentsChannel?.unsubscribe();
    _shipmentsChannel = null;
  }

  // ── GET RATES ─────────────────────────────────────────────────
  Future<void> getRates() async {
    isLoadingRates = true;
    liveRates      = [];
    ratesError     = '';
    selectedRateId = '';
    selectedRate   = null;
    notifyListeners();

    try {
      // FIX: ensure country code is always uppercase and valid
      final countryCode = recipCountryCode.trim().toUpperCase();
      final intl        = countryCode != 'GB';

      debugPrint('[ParcelProvider] getRates → ${intl ? "INTL" : "DOMESTIC"} '
          'GB → $countryCode  zip=$recipZip  postcode=$recipPostcode');

      final payload = _shipmentPayload;

      // FIX: double-check country is set correctly in payload
      (payload['recipient'] as Map<String, dynamic>)['country'] = countryCode;

      final res = await http.post(
        Uri.parse(_engineUrl),
        headers: _headers,
        body: jsonEncode({
          'action':        'get_rates',
          'international': intl,           // FIX: use derived value not stored
          'toCountry':     countryCode,    // FIX: send explicit country code
          'shipment':      payload,
        }),
      ).timeout(const Duration(seconds: 30));

      final data = jsonDecode(res.body);
      debugPrint('[ParcelProvider] get_rates ${res.statusCode}: ${res.body}');

      if (res.statusCode == 200 && data['success'] == true) {
        liveRates = _parseRates(data['rates']);
      } else {
        ratesError = data['error'] ?? data['detail'] ?? 'Failed to get rates.';
      }
    } catch (e) {
      ratesError = 'Network error. Please try again.';
      debugPrint('[ParcelProvider] getRates error: $e');
    }

    if (liveRates.isEmpty && ratesError.isEmpty) {
      final countryCode = recipCountryCode.trim().toUpperCase();
      final intl        = countryCode != 'GB';
      ratesError = intl
          ? 'No international rates found for $recipCountryName. '
          'Please check the destination address details.'
          : 'No domestic rates available for this route. '
          'Please check the postcode.';
    }

    isLoadingRates = false;
    notifyListeners();
  }

  // ── Parse rates ───────────────────────────────────────────────
  List<CourierRate> _parseRates(dynamic raw) {
    if (raw == null || raw is! List || raw.isEmpty) return [];
    final out = <CourierRate>[];
    for (final r in raw) {
      if (r is! Map) continue;
      final price = double.tryParse(r['price']?.toString() ?? '') ?? 0.0;
      if (price <= 0) continue;
      out.add(CourierRate(
        rateId:        r['rateId']?.toString()   ?? '',
        carrier:       r['carrier']?.toString()  ?? 'Carrier',
        service:       r['service']?.toString()  ?? 'Standard',
        price:         price,
        currency:      r['currency']?.toString() ?? 'GBP',
        estimatedDays: r['estimatedDays'] != null
            ? int.tryParse(r['estimatedDays'].toString()) : null,
        carrierId:     r['carrierId']?.toString(),
        serviceCode:   r['serviceCode']?.toString(),
        dropoff:       r['dropoff']?.toString() ?? 'Drop-off',
      ));
    }
    out.sort((a, b) => a.price.compareTo(b.price));
    return out;
  }

  // ── BUY LABEL ─────────────────────────────────────────────────
  Future<void> buyLabel({required String userEmail}) async {
    if (selectedRate == null) {
      errorMessage = 'Please select a courier first.';
      notifyListeners();
      return;
    }
    isLoading    = true;
    errorMessage = '';
    notifyListeners();

    try {
      final countryCode = recipCountryCode.trim().toUpperCase();
      final intl        = countryCode != 'GB';

      debugPrint('[ParcelProvider] buyLabel carrier=${selectedRate!.carrier} '
          'intl=$intl country=$countryCode');

      final payload = _shipmentPayload;
      (payload['recipient'] as Map<String, dynamic>)['country'] = countryCode;

      final res = await http.post(
        Uri.parse(_engineUrl),
        headers: _headers,
        body: jsonEncode({
          'action':        'create_label',
          'rateId':        selectedRate!.rateId,
          'carrier':       selectedRate!.carrier,
          'carrierId':     selectedRate!.carrierId,
          'serviceCode':   selectedRate!.serviceCode,
          'international': intl,
          'toCountry':     countryCode,
          'shipment':      payload,
        }),
      ).timeout(const Duration(seconds: 30));

      final data = jsonDecode(res.body);
      debugPrint('[ParcelProvider] create_label ${res.statusCode}: ${res.body}');

      if (res.statusCode == 200 && data['success'] == true) {
        lastTrackingNumber = data['tracking_number'] ?? '';
        lastLabelUrl       = data['label_url']       ?? '';
        lastLabelId        = data['label_id']        ?? '';
        requiresPickup     = data['requires_pickup'] == true;
        isSubmitted        = true;
        await _saveShipmentToSupabase(userEmail: userEmail, data: data);
        await getShipments(userEmail);
        if (lastTrackingNumber.isNotEmpty) {
          await _startTracking(lastTrackingNumber, selectedRate!.carrier);
        }
        debugPrint('[ParcelProvider] ✓ Label: $lastTrackingNumber');
      } else {
        errorMessage = data['error'] ?? 'Failed to purchase label.';
        isSubmitted  = false;
      }
    } catch (e) {
      errorMessage = 'Network error. Please try again.';
      isSubmitted  = false;
      debugPrint('[ParcelProvider] buyLabel error: $e');
    }

    isLoading = false;
    notifyListeners();
  }

  // ── Start tracking ────────────────────────────────────────────
  Future<void> _startTracking(String trackingNumber, String carrierName) async {
    const carrierCodeMap = {
      'Royal Mail': 'stamps_com', 'Parcelforce Royal Mail': 'stamps_com',
      'Parcelforce': 'stamps_com', 'Evri': 'evri',
      'DPD UK': 'dpd', 'DPD': 'dpd',
      'FedEx UK': 'fedex', 'FedEx': 'fedex',
      'DHL Express MyDHL API': 'dhl_express', 'DHL Express': 'dhl_express',
      'DHL': 'dhl_express', 'UPS': 'ups',
      'Yodel': 'yodel', 'GlobalPost': 'globalpost',
    };
    try {
      await http.post(
        Uri.parse(_engineUrl),
        headers: _headers,
        body: jsonEncode({
          'action':        'start_tracking',
          'trackingNumber': trackingNumber,
          'carrierCode':    carrierCodeMap[carrierName] ?? 'stamps_com',
        }),
      ).timeout(const Duration(seconds: 10));
      debugPrint('[ParcelProvider] ✓ Tracking started: $trackingNumber');
    } catch (e) {
      debugPrint('[ParcelProvider] ⚠ Start tracking error (non-fatal): $e');
    }
  }

  // ── Save to Supabase ──────────────────────────────────────────
  Future<void> _saveShipmentToSupabase({
    required String userEmail,
    required Map<String, dynamic> data,
  }) async {
    final countryCode = recipCountryCode.trim().toUpperCase();
    final intl        = countryCode != 'GB';

    final coreRow = {
      'user_email':         userEmail,
      'tracking_number':    lastTrackingNumber,
      'label_url':          lastLabelUrl,
      'carrier':            data['carrier']   ?? selectedRate!.carrier,
      'service':            data['service']   ?? selectedRate!.service,
      'sender_name':        senderName,
      'sender_address':     '$senderDoor $senderStreet'.trim(),
      'sender_city':        senderCity,
      'sender_postcode':    senderPostcode,
      'recipient_name':     recipName,
      'recipient_address':  '$recipDoor $recipStreet'.trim(),
      'recipient_city':     recipCity,
      'recipient_postcode': _resolvedPostcode,
      'parcel_size':        selectedSize?.name ?? selectedSizeId,
      'parcel_type':        selectedParcelType,
      'weight_kg':          double.tryParse(weightKg) ?? 1.0,
      'parcel_value':       double.tryParse(parcelValueGbp) ?? 0,
      'price':              totalCost,
      'currency':           'GBP',
      'estimated_days':     selectedRate!.estimatedDays,
      'status':             'label_created',
    };

    String? insertedId;
    try {
      final result = await _supabase
          .from('shipments').insert(coreRow).select('id').single();
      insertedId = result['id']?.toString();
      debugPrint('[ParcelProvider] ✓ Core shipment saved (id=$insertedId)');
    } catch (e) {
      debugPrint('[ParcelProvider] ✗ Core save failed: $e');
      return;
    }

    if (insertedId != null) {
      try {
        await _supabase.from('shipments').update({
          'recipient_country': countryCode,
          'recipient_state':   recipState,
          'is_international':  intl,
        }).eq('id', insertedId);
        debugPrint('[ParcelProvider] ✓ International fields saved');
      } catch (e) {
        debugPrint(
          '[ParcelProvider] ⚠ International fields not saved: $e\n'
              'Run this SQL:\n'
              '  ALTER TABLE shipments ADD COLUMN IF NOT EXISTS recipient_country text DEFAULT \'GB\';\n'
              '  ALTER TABLE shipments ADD COLUMN IF NOT EXISTS recipient_state text DEFAULT \'\';\n'
              '  ALTER TABLE shipments ADD COLUMN IF NOT EXISTS is_international boolean DEFAULT false;',
        );
      }
    }
  }

  // ── Setters ───────────────────────────────────────────────────
  void setSenderDetails({
    required String name,   required String phone,
    required String email,  required String postcode,
    required String street, required String door,
    required String city,
  }) {
    senderName=name; senderPhone=phone; senderEmail=email;
    senderPostcode=postcode; senderStreet=street;
    senderDoor=door; senderCity=city;
    notifyListeners();
  }

  void setRecipientDetails({
    required String name,     required String phone,
    required String postcode, required String street,
    required String door,     required String city,
    bool   international = false,
    String countryCode   = 'GB',
    String countryName   = 'United Kingdom',
    String state         = '',
    String zip           = '',
  }) {
    recipName    = name;
    recipPhone   = phone;
    recipPostcode= postcode;
    recipStreet  = street;
    recipDoor    = door;
    recipCity    = city;
    // FIX: always derive isInternational from countryCode, not the flag
    recipCountryCode = countryCode.trim().toUpperCase().isNotEmpty
        ? countryCode.trim().toUpperCase() : 'GB';
    recipCountryName = countryName;
    isInternational  = recipCountryCode != 'GB';
    recipState       = state;
    recipZip         = zip;
    notifyListeners();
  }

  void setSize(String id)       { selectedSizeId = id; notifyListeners(); }
  void setParcelType(String t)  { selectedParcelType = t; notifyListeners(); }
  void setWeight(String w)      { weightKg = w; notifyListeners(); }
  void setParcelValue(String v) { parcelValueGbp = v; notifyListeners(); }
  void setSortMode(String m)    { sortMode = m; notifyListeners(); }

  void selectRate(CourierRate rate) {
    selectedRateId = rate.rateId;
    selectedRate   = rate;
    notifyListeners();
  }

  String? validateWeightForSize() {
    if (selectedSizeId.isEmpty) return null;
    if (weightKg.isEmpty) return 'Please enter the parcel weight.';
    final weight = double.tryParse(weightKg);
    if (weight == null || weight <= 0) return 'Please enter a valid weight.';
    final max = sizeWeightLimits[selectedSizeId];
    if (max != null && weight > max) {
      final name = sizes.firstWhere((s) => s.id == selectedSizeId).name;
      return '$name max is ${max % 1 == 0 ? max.toInt() : max}kg. '
          'Please reduce weight or choose a larger size.';
    }
    return null;
  }

  void reset() {
    senderName=''; senderPhone=''; senderEmail='';
    senderPostcode=''; senderStreet=''; senderDoor=''; senderCity='';
    recipName=''; recipPhone=''; recipPostcode='';
    recipStreet=''; recipDoor=''; recipCity='';
    isInternational=false; recipCountryCode='GB';
    recipCountryName='United Kingdom'; recipState=''; recipZip='';
    selectedSizeId=''; selectedParcelType=''; weightKg=''; parcelValueGbp='';
    selectedRateId=''; selectedRate=null; sortMode='cheapest';
    liveRates=[]; isLoadingRates=false; ratesError='';
    isLoading=false; isSubmitted=false; requiresPickup=false;
    lastTrackingNumber=''; lastLabelUrl=''; lastLabelId=''; errorMessage='';
    notifyListeners();
  }
}