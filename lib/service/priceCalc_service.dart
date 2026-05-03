import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// ─────────────────────────────────────────────────────────────────────────────
// PriceResult model
// ─────────────────────────────────────────────────────────────────────────────

class PriceResult {
  final String carrier;
  final String service;
  final String days;
  final double price;
  final String currency;
  final String carrierImage; // optional logo URL if API returns one

  const PriceResult({
    required this.carrier,
    required this.service,
    required this.price,
    required this.days,
    this.currency = 'GBP',
    this.carrierImage = '',
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// PriceCalculatorService
// ─────────────────────────────────────────────────────────────────────────────

class PriceCalculatorService {
  static const _baseUrl =
      'https://tjrjeemaacumepimjltg.supabase.co/functions/v1';

  static const _anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRqcmplZW1hYWN1bWVwaW1qbHRnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQxMjE2NjAsImV4cCI6MjA4OTY5NzY2MH0.gtBcFu-J48mPDk_S9ukfVdW-7gUmabGatmJ1g1_5zzo';

  static Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $_anonKey',
  };

  /// Fetches live shipping rates.
  /// Tries [compareRates] first (base44 function), falls back to [shippo-courier].
  static Future<List<PriceResult>> getRates({
    required String fromPostcode,
    required String toPostcode,
    required double weightKg,
    String parcelSize = 'sm', // sm | md | lg
  }) async {
    final from = fromPostcode.trim().toUpperCase().replaceAll(' ', '');
    final to   = toPostcode.trim().toUpperCase().replaceAll(' ', '');

    // ── Build the request body (covers both function signatures) ──
    final body = jsonEncode({
      // compareRates function style
      'action': 'compare_rates',
      'fromPostcode': from,
      'toPostcode': to,
      'weightKg': weightKg,
      'parcelSize': parcelSize,

      // shippo-courier / get_rates style (fallback)
      'shipment': {
        'sender': {
          'name':     'SwiftLabel User',
          'address':  '1 High Street',
          'city':     _cityFromPostcode(from),
          'postcode': from,
          'country':  'GB',
          'phone':    '07700000000',
          'email':    '',
        },
        'recipient': {
          'name':     'Recipient',
          'address':  '1 High Street',
          'city':     _cityFromPostcode(to),
          'postcode': to,
          'country':  'GB',
          'phone':    '07700000000',
          'email':    '',
        },
        'parcel': {
          'size':      parcelSize,
          'weight_kg': weightKg,
          'length':    _parcelDimensions(parcelSize)['length'],
          'width':     _parcelDimensions(parcelSize)['width'],
          'height':    _parcelDimensions(parcelSize)['height'],
        },
      },
    });

    // ── Try compareRates first ─────────────────────────────────────
    try {
      final res = await http
          .post(Uri.parse('$_baseUrl/compareRates'),
          headers: _headers, body: body)
          .timeout(const Duration(seconds: 20));

      debugPrint('[PriceCalc] compareRates → ${res.statusCode}: ${res.body}');

      if (res.statusCode == 200) {
        final parsed = _parseResponse(jsonDecode(res.body));
        if (parsed.isNotEmpty) return parsed;
      }
    } catch (e) {
      debugPrint('[PriceCalc] compareRates failed: $e');
    }

    // ── Fallback: shippo-courier with action=get_rates ─────────────
    try {
      final fallbackBody = jsonEncode({
        'action': 'get_rates',
        'shipment': jsonDecode(body)['shipment'],
      });

      final res = await http
          .post(Uri.parse('$_baseUrl/shippo-courier'),
          headers: _headers, body: fallbackBody)
          .timeout(const Duration(seconds: 20));

      debugPrint('[PriceCalc] shippo-courier → ${res.statusCode}: ${res.body}');

      if (res.statusCode == 200) {
        final parsed = _parseResponse(jsonDecode(res.body));
        if (parsed.isNotEmpty) return parsed;
      }
    } catch (e) {
      debugPrint('[PriceCalc] shippo-courier fallback failed: $e');
    }

    throw Exception('Could not retrieve live rates. Please try again.');
  }

  // ── Parse any of the possible response shapes ───────────────────
  static List<PriceResult> _parseResponse(dynamic data) {
    if (data == null) return [];

    // Success check — accept various shapes
    final isOk = data['success'] == true ||
        data['rates'] != null ||
        data['results'] != null ||
        data['data'] != null;
    if (!isOk) {
      final msg = data['error'] ?? data['message'] ?? 'Unknown error';
      throw Exception(msg.toString());
    }

    // The rates list may live under several keys
    final rawList = data['rates'] ??
        data['results'] ??
        data['data'] ??
        data['rateList'] ??
        data['shipping_rates'] ??
        [];

    if (rawList is! List || rawList.isEmpty) return [];

    final results = <PriceResult>[];

    for (final r in rawList) {
      if (r is! Map) continue;

      // ── Carrier name ── multiple possible keys
      final carrier = _str(r, [
        'carrier',
        'provider',
        'carrierName',
        'carrier_name',
        'courierName',
      ]) ??
          'Carrier';

      // ── Service name ── Shippo nests it under servicelevel.name
      String service = 'Standard';
      if (r['servicelevel'] is Map) {
        service = r['servicelevel']['name']?.toString() ?? 'Standard';
      } else {
        service = _str(r, [
          'service',
          'service_name',
          'serviceName',
          'serviceLevel',
          'product',
          'description',
        ]) ??
            'Standard';
      }

      // ── Price ── Shippo uses 'amount' as a string
      double price = 0.0;
      final priceRaw = r['price'] ?? r['amount'] ?? r['rate'] ?? r['cost'];
      if (priceRaw != null) {
        price = double.tryParse(priceRaw.toString()) ?? 0.0;
      }
      if (price <= 0) continue; // skip invalid rates

      // ── Estimated days
      String days = '';
      final daysRaw = r['estimatedDays'] ??
          r['estimated_days'] ??
          r['days'] ??
          r['transit_days'];
      if (daysRaw != null) {
        final d = int.tryParse(daysRaw.toString());
        days = d != null ? (d == 1 ? '1 day' : '$d days') : daysRaw.toString();
      }

      // ── Currency
      final currency =
          _str(r, ['currency', 'currency_local']) ?? 'GBP';

      // ── Logo / image
      final image =
          _str(r, ['carrierImage', 'carrier_image', 'logo', 'logoUrl']) ?? '';

      results.add(PriceResult(
        carrier: _friendlyCarrierName(carrier),
        service: service,
        price: price,
        days: days,
        currency: currency,
        carrierImage: image,
      ));
    }

    // Sort cheapest first
    results.sort((a, b) => a.price.compareTo(b.price));
    return results;
  }

  // ── Helpers ─────────────────────────────────────────────────────

  static String? _str(Map r, List<String> keys) {
    for (final k in keys) {
      final v = r[k];
      if (v != null && v.toString().isNotEmpty) return v.toString();
    }
    return null;
  }

  /// Makes carrier names human-readable regardless of what the API returns.
  static String _friendlyCarrierName(String raw) {
    const map = {
      'royal_mail':    'Royal Mail',
      'royalmail':     'Royal Mail',
      'rm':            'Royal Mail',
      'evri':          'Evri',
      'hermes':        'Evri',
      'myhermes':      'Evri',
      'dpd':           'DPD',
      'dpd_uk':        'DPD',
      'dhl':           'DHL',
      'dhl_express':   'DHL Express',
      'dhlexpress':    'DHL Express',
      'ups':           'UPS',
      'fedex':         'FedEx',
      'parcelforce':   'Parcelforce',
      'parcelforce_uk':'Parcelforce',
      'inpost':        'InPost',
      'yodel':         'Yodel',
      'amazon':        'Amazon Logistics',
    };
    return map[raw.toLowerCase().replaceAll(' ', '_')] ?? raw;
  }

  /// Rough city lookup from UK postcode prefix (avoids hardcoded "London"/"Manchester").
  static String _cityFromPostcode(String postcode) {
    final prefix = postcode.replaceAll(RegExp(r'\d.*'), '').toUpperCase();
    const map = {
      'SW': 'London',   'SE': 'London',   'N':  'London',   'NW': 'London',
      'W':  'London',   'WC': 'London',   'EC': 'London',   'E':  'London',
      'M':  'Manchester','B': 'Birmingham','LS': 'Leeds',
      'L':  'Liverpool', 'BS': 'Bristol',  'S':  'Sheffield',
      'EH': 'Edinburgh', 'G':  'Glasgow',  'CF': 'Cardiff',
      'BT': 'Belfast',   'NG': 'Nottingham','CV': 'Coventry',
      'OX': 'Oxford',    'CB': 'Cambridge','SO': 'Southampton',
      'PO': 'Portsmouth','BN': 'Brighton', 'CT': 'Canterbury',
      'MK': 'Milton Keynes', 'SL': 'Slough','RG': 'Reading',
      'GU': 'Guildford','KT': 'Kingston upon Thames',
      'TW': 'Twickenham','UB': 'Uxbridge','HA': 'Harrow',
      'EN': 'Enfield',   'IG': 'Ilford',   'RM': 'Romford',
      'DA': 'Dartford',  'BR': 'Bromley',  'CR': 'Croydon',
      'SM': 'Sutton',    'TN': 'Tonbridge',
      'ME': 'Medway',    'SS': 'Southend-on-Sea',
      'CO': 'Colchester','IP': 'Ipswich',  'NR': 'Norwich',
      'PE': 'Peterborough','LE': 'Leicester','DE': 'Derby',
      'ST': 'Stoke-on-Trent','TF': 'Telford','WV': 'Wolverhampton',
      'DY': 'Dudley',    'WS': 'Walsall',  'WR': 'Worcester',
      'HR': 'Hereford',  'GL': 'Gloucester','SN': 'Swindon',
      'BA': 'Bath',      'TA': 'Taunton',  'EX': 'Exeter',
      'PL': 'Plymouth',  'TR': 'Truro',    'TQ': 'Torquay',
      'DT': 'Dorchester','SP': 'Salisbury','BH': 'Bournemouth',
      'YO': 'York',      'HU': 'Hull',     'DN': 'Doncaster',
      'WF': 'Wakefield', 'HD': 'Huddersfield','HX': 'Halifax',
      'BD': 'Bradford',  'HG': 'Harrogate','TS': 'Middlesbrough',
      'DL': 'Darlington','NE': 'Newcastle upon Tyne',
      'SR': 'Sunderland','DH': 'Durham',   'CA': 'Carlisle',
      'LA': 'Lancaster', 'PR': 'Preston',  'FY': 'Blackpool',
      'BB': 'Blackburn', 'OL': 'Oldham',   'SK': 'Stockport',
      'CH': 'Chester',   'WA': 'Warrington','CW': 'Crewe',
      'SY': 'Shrewsbury','LL': 'Llandudno','SA': 'Swansea',
      'NP': 'Newport',   'LD': 'Llandrindod Wells',
      'AB': 'Aberdeen',  'DD': 'Dundee',   'KY': 'Kirkcaldy',
      'FK': 'Falkirk',   'KA': 'Kilmarnock','PA': 'Paisley',
      'ML': 'Motherwell','PH': 'Perth',    'HS': 'Stornoway',
      'ZE': 'Lerwick',   'KW': 'Wick',     'IV': 'Inverness',
    };
    return map[prefix] ?? 'United Kingdom';
  }

  static Map<String, dynamic> _parcelDimensions(String size) {
    switch (size) {
      case 'sm': return {'length': 20, 'width': 15, 'height': 5};
      case 'md': return {'length': 35, 'width': 25, 'height': 10};
      case 'lg': return {'length': 60, 'width': 40, 'height': 20};
      default:   return {'length': 20, 'width': 15, 'height': 5};
    }
  }
}