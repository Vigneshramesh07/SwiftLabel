// lib/widgets/country_picker_sheet.dart

import 'package:flutter/material.dart';
import '../service/country_data.dart';

class CountryPickerSheet extends StatefulWidget {
  final CountryEntry? selected;
  final ValueChanged<CountryEntry> onSelected;

  const CountryPickerSheet({
    super.key,
    this.selected,
    required this.onSelected,
  });

  /// Call this to open the sheet
  static Future<void> show(
      BuildContext context, {
        CountryEntry? selected,
        required ValueChanged<CountryEntry> onSelected,
      }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CountryPickerSheet(
        selected: selected,
        onSelected: onSelected,
      ),
    );
  }

  @override
  State<CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<CountryPickerSheet> {
  String _query = '';

  List<CountryEntry> get _filtered => _query.isEmpty
      ? kCountries
      : kCountries
      .where((c) =>
  c.name.toLowerCase().contains(_query.toLowerCase()) ||
      c.code.toLowerCase().contains(_query.toLowerCase()) ||
      c.dialCode.contains(_query))
      .toList();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(children: [
        // Handle
        Container(
          width: 40, height: 4,
          decoration: BoxDecoration(
            color: const Color(0xFFDDDDDD),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 16),

        // Title
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Select Country',
            style: TextStyle(
              fontFamily: 'Syne', fontSize: 17,
              fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Search
        TextField(
          autofocus: true,
          onChanged: (v) => setState(() => _query = v),
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Search country…',
            hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFB0B0B0)),
            prefixIcon: const Icon(Icons.search_rounded,
                size: 18, color: Color(0xFF9B9B9B)),
            filled: true,
            fillColor: const Color(0xFFF5F5F5),
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 10),

        // List
        Expanded(
          child: _filtered.isEmpty
              ? const Center(
            child: Text('No countries found',
                style: TextStyle(fontSize: 14, color: Color(0xFF9B9B9B))),
          )
              : ListView.builder(
            itemCount: _filtered.length,
            itemBuilder: (_, i) {
              final c = _filtered[i];
              final isSel = widget.selected?.code == c.code;
              return ListTile(
                contentPadding:
                const EdgeInsets.symmetric(vertical: 2),
                leading: Text(c.flag,
                    style: const TextStyle(fontSize: 24)),
                title: Text(
                  c.name,
                  style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600,
                    color: isSel
                        ? const Color(0xFF0284C7)
                        : const Color(0xFF1A1A1A),
                  ),
                ),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(c.dialCode,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF9B9B9B))),
                  if (isSel) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.check_circle_rounded,
                        size: 18, color: Color(0xFF0284C7)),
                  ],
                ]),
                onTap: () {
                  Navigator.pop(context);
                  widget.onSelected(c);
                },
              );
            },
          ),
        ),

        const SizedBox(height: 16),
      ]),
    );
  }
}