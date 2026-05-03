// lib/widgets/postcode_lookup_field.dart
//
// PostcodeLookupField — UK postcode autocomplete with address pre-fill
//
// Uses postcodes.io (free, no API key needed):
//   GET https://api.postcodes.io/postcodes/{postcode}  → lat/lng/admin/district
//   GET https://api.postcodes.io/postcodes/{postcode}/autocomplete → suggestions
//
// Callback `onAddressSelected` fires with:
//   postcode  → formatted "SW1A 1AA"
//   city      → admin_district (e.g. "Westminster")
//   street    → thoroughfare if available, else district
//   district  → parliamentary_constituency

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// ── Data model returned to parent ─────────────────────────────────────────────

class PostcodeResult {
  final String postcode;   // "SW1A 1AA"
  final String city;       // admin_district — "Westminster"
  final String district;   // admin_ward or parliamentary_constituency
  final String county;     // admin_county
  final String country;    // "England" / "Scotland" / "Wales" / "Northern Ireland"
  const PostcodeResult({
    required this.postcode,
    required this.city,
    required this.district,
    required this.county,
    required this.country,
  });
}

// ── Widget ────────────────────────────────────────────────────────────────────

class PostcodeLookupField extends StatefulWidget {
  /// Called when user finishes entering a valid postcode and we've looked it up
  final void Function(PostcodeResult result) onAddressSelected;

  /// Called on every raw text change (for validation state)
  final void Function(String value)? onChanged;

  /// Pre-populate the field with an existing postcode
  final String? initialValue;

  /// Form validator — return error string or null
  final String? Function(String?)? validator;

  final String label;
  final String hint;

  const PostcodeLookupField({
    super.key,
    required this.onAddressSelected,
    this.onChanged,
    this.initialValue,
    this.validator,
    this.label = 'Postcode *',
    this.hint  = 'e.g. SW1A 1AA',
  });

  @override
  State<PostcodeLookupField> createState() => _PostcodeLookupFieldState();
}

class _PostcodeLookupFieldState extends State<PostcodeLookupField> {
  final _ctrl   = TextEditingController();
  final _focus  = FocusNode();

  // Autocomplete suggestions (partial postcode → list of full postcodes)
  List<String> _suggestions = [];
  bool _loadingSuggestions  = false;

  // Lookup result state
  bool   _isValid      = false;
  bool   _isLooking    = false;
  bool   _lookupDone   = false;
  String _lookupError  = '';
  PostcodeResult? _result;

  Timer?  _debounce;

  static const _purple = Color(0xFF6D28D9);
  static const _green  = Color(0xFF059669);
  static const _orange = Color(0xFFFF5A00);

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null && widget.initialValue!.isNotEmpty) {
      _ctrl.text = widget.initialValue!;
      _isValid   = _validUkPc(widget.initialValue!);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose(); _focus.dispose(); _debounce?.cancel();
    super.dispose();
  }

  bool _validUkPc(String v) =>
      RegExp(r'^[A-Z]{1,2}[0-9][A-Z0-9]? ?[0-9][A-Z]{2}$',
          caseSensitive: false).hasMatch(v.trim());

  String _formatUkPc(String v) {
    final clean = v.trim().toUpperCase().replaceAll(' ', '');
    if (clean.length >= 5) {
      return '${clean.substring(0, clean.length - 3)} ${clean.substring(clean.length - 3)}';
    }
    return v.trim().toUpperCase();
  }

  // ── Autocomplete: fetch suggestions for partial postcode ──────────────────
  Future<void> _fetchSuggestions(String partial) async {
    final q = partial.trim().replaceAll(' ', '').toUpperCase();
    if (q.length < 2) { setState(() => _suggestions = []); return; }
    setState(() => _loadingSuggestions = true);
    try {
      final res = await http.get(
        Uri.parse('https://api.postcodes.io/postcodes/$q/autocomplete'),
      ).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data   = jsonDecode(res.body);
        final result = data['result'];
        final list   = (result is List) ? result.cast<String>() : <String>[];
        setState(() => _suggestions = list.take(6).toList());
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingSuggestions = false);
  }

  // ── Full lookup: call postcodes.io with a complete postcode ───────────────
  Future<void> _lookup(String postcode) async {
    final pc = _formatUkPc(postcode);
    setState(() {
      _isLooking   = true;
      _lookupDone  = false;
      _lookupError = '';
      _result      = null;
      _suggestions = [];
    });
    try {
      final res = await http.get(
        Uri.parse('https://api.postcodes.io/postcodes/${Uri.encodeComponent(pc)}'),
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body)['result'] as Map<String, dynamic>?;
        if (data != null) {
          final result = PostcodeResult(
            postcode: data['postcode']                    as String? ?? pc,
            city:     data['admin_district']              as String? ?? data['parliamentary_constituency'] as String? ?? '',
            district: data['admin_ward']                  as String? ?? data['parliamentary_constituency']  as String? ?? '',
            county:   data['admin_county']                as String? ?? data['region']                      as String? ?? '',
            country:  data['country']                     as String? ?? 'England',
          );
          setState(() {
            _result     = result;
            _lookupDone = true;
            _isValid    = true;
            _ctrl.text  = result.postcode; // auto-format
          });
          widget.onAddressSelected(result);
        } else {
          setState(() => _lookupError = 'Postcode not found.');
        }
      } else if (res.statusCode == 404) {
        setState(() => _lookupError = 'Postcode "$pc" not found. Please check and try again.');
      } else {
        setState(() => _lookupError = 'Could not look up postcode. Check your connection.');
      }
    } catch (_) {
      setState(() => _lookupError = 'Network error — postcode lookup failed.');
    }
    if (mounted) setState(() => _isLooking = false);
  }

  void _onTextChanged(String v) {
    // Auto-uppercase
    final up = v.toUpperCase();
    if (v != up) {
      _ctrl.value = _ctrl.value.copyWith(
        text: up, selection: TextSelection.collapsed(offset: up.length),
      );
    }

    final valid = _validUkPc(up);
    setState(() {
      _isValid    = valid;
      _lookupDone = false;
      _result     = null;
      _lookupError = '';
    });

    widget.onChanged?.call(up);

    _debounce?.cancel();

    if (valid) {
      // Full valid postcode — lookup after short delay
      _debounce = Timer(const Duration(milliseconds: 500), () => _lookup(up));
    } else if (up.replaceAll(' ', '').length >= 2) {
      // Partial — fetch autocomplete suggestions
      _debounce = Timer(const Duration(milliseconds: 300), () => _fetchSuggestions(up));
    } else {
      setState(() => _suggestions = []);
    }
  }

  void _pickSuggestion(String pc) {
    _ctrl.text = pc;
    _ctrl.selection = TextSelection.collapsed(offset: pc.length);
    setState(() { _suggestions = []; _isValid = true; });
    _lookup(pc);
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

      // ── Label ──────────────────────────────────────────────────────────────
      Text(widget.label, style: const TextStyle(
          fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF6B6B6B))),
      const SizedBox(height: 6),

      // ── Text field ────────────────────────────────────────────────────────
      TextFormField(
        controller:            _ctrl,
        focusNode:             _focus,
        textCapitalization:    TextCapitalization.characters,
        style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A1A),
            fontWeight: FontWeight.w500, letterSpacing: 0.5),
        onChanged:   _onTextChanged,
        validator:   widget.validator,
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: const TextStyle(color: Color(0xFFB0B0B0), fontSize: 13),
          filled:    true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          // Status suffix icon
          suffixIcon: _isLooking
              ? const Padding(padding: EdgeInsets.all(12),
              child: SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: _purple)))
              : _lookupDone && _result != null
              ? const Icon(Icons.check_circle_rounded, color: _green, size: 20)
              : _lookupError.isNotEmpty
              ? const Icon(Icons.error_outline_rounded, color: Colors.red, size: 20)
              : _isValid
              ? const Icon(Icons.search_rounded, color: _purple, size: 20)
              : null,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: _lookupDone && _result != null
                    ? _green
                    : _lookupError.isNotEmpty
                    ? Colors.red
                    : _isValid ? _purple : const Color(0xFFE0E0E0),
                width: (_lookupDone || _lookupError.isNotEmpty || _isValid) ? 1.5 : 1,
              )),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _orange, width: 1.5)),
          errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.red)),
        ),
      ),

      // ── Autocomplete dropdown ─────────────────────────────────────────────
      if (_suggestions.isNotEmpty) ...[
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFDDD6FE), width: 1.5),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06),
                blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: Column(
            children: _suggestions.asMap().entries.map((e) {
              final idx = e.key; final pc = e.value;
              return GestureDetector(
                onTap: () => _pickSuggestion(pc),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: idx < _suggestions.length - 1
                        ? const Border(bottom: BorderSide(color: Color(0xFFF0EDFF)))
                        : null,
                    borderRadius: idx == 0
                        ? const BorderRadius.vertical(top: Radius.circular(9))
                        : idx == _suggestions.length - 1
                        ? const BorderRadius.vertical(bottom: Radius.circular(9))
                        : BorderRadius.zero,
                  ),
                  child: Row(children: [
                    Container(width: 28, height: 28,
                        decoration: BoxDecoration(
                            color: const Color(0xFFF3F0FF),
                            borderRadius: BorderRadius.circular(7)),
                        child: const Icon(Icons.location_on_rounded, size: 14, color: _purple)),
                    const SizedBox(width: 10),
                    Text(pc, style: const TextStyle(fontSize: 13,
                        fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A))),
                    const Spacer(),
                    const Icon(Icons.north_west_rounded, size: 12, color: Color(0xFF9B9B9B)),
                  ]),
                ),
              );
            }).toList(),
          ),
        ),
      ],

      // ── Loading suggestions indicator ─────────────────────────────────────
      if (_loadingSuggestions && _suggestions.isEmpty) ...[
        const SizedBox(height: 6),
        const Row(children: [
          SizedBox(width: 12, height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: _purple)),
          SizedBox(width: 6),
          Text('Finding postcodes…', style: TextStyle(fontSize: 11, color: Color(0xFF9B9B9B))),
        ]),
      ],

      // ── Address result card ───────────────────────────────────────────────
      if (_lookupDone && _result != null) ...[
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            border: Border.all(color: const Color(0xFF059669).withOpacity(0.3)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            Container(width: 32, height: 32,
                decoration: BoxDecoration(
                    color: const Color(0xFF059669).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.location_on_rounded,
                    color: _green, size: 16)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_result!.postcode, style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
              Text(
                [
                  if (_result!.city.isNotEmpty)     _result!.city,
                  if (_result!.county.isNotEmpty)    _result!.county,
                  if (_result!.country.isNotEmpty)   _result!.country,
                ].join(', '),
                style: const TextStyle(fontSize: 11, color: Color(0xFF059669)),
              ),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                  color: _green.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
              child: const Text('Found', style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w700, color: _green)),
            ),
          ]),
        ),
      ],

      // ── Error message ─────────────────────────────────────────────────────
      if (_lookupError.isNotEmpty) ...[
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.05),
              border: Border.all(color: Colors.red.withOpacity(0.2)),
              borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            const Icon(Icons.error_outline_rounded, color: Colors.red, size: 14),
            const SizedBox(width: 6),
            Expanded(child: Text(_lookupError,
                style: const TextStyle(fontSize: 11, color: Colors.red))),
          ]),
        ),
      ],

      // ── Valid but not yet looked up hint ──────────────────────────────────
      if (_isValid && !_lookupDone && !_isLooking && _lookupError.isEmpty) ...[
        const SizedBox(height: 4),
        const Text('✓ Valid format — looking up address…',
            style: TextStyle(fontSize: 11, color: _purple)),
      ],
    ]);
  }
}