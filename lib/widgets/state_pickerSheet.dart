// lib/widgets/state_picker_sheet.dart

import 'package:flutter/material.dart';

class StatePickerSheet extends StatefulWidget {
  final String countryName;
  final String countryFlag;
  final List<String> states;
  final String? selected;
  final ValueChanged<String> onSelected;

  const StatePickerSheet({
    super.key,
    required this.countryName,
    required this.countryFlag,
    required this.states,
    this.selected,
    required this.onSelected,
  });

  /// Call this to open the sheet
  static Future<void> show(
      BuildContext context, {
        required String countryName,
        required String countryFlag,
        required List<String> states,
        String? selected,
        required ValueChanged<String> onSelected,
      }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatePickerSheet(
        countryName: countryName,
        countryFlag: countryFlag,
        states: states,
        selected: selected,
        onSelected: onSelected,
      ),
    );
  }

  @override
  State<StatePickerSheet> createState() => _StatePickerSheetState();
}

class _StatePickerSheetState extends State<StatePickerSheet> {
  String _query = '';

  List<String> get _filtered => _query.isEmpty
      ? widget.states
      : widget.states
      .where((s) => s.toLowerCase().contains(_query.toLowerCase()))
      .toList();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
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

        // Title + country badge
        Align(
          alignment: Alignment.centerLeft,
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text(
              'Select State / Province',
              style: TextStyle(
                fontFamily: 'Syne', fontSize: 17,
                fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.countryFlag} ${widget.countryName}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF9B9B9B)),
            ),
          ]),
        ),
        const SizedBox(height: 12),

        // Search
        TextField(
          autofocus: true,
          onChanged: (v) => setState(() => _query = v),
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Search state / province…',
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
            child: Text('No states found',
                style: TextStyle(fontSize: 14, color: Color(0xFF9B9B9B))),
          )
              : ListView.builder(
            itemCount: _filtered.length,
            itemBuilder: (_, i) {
              final s = _filtered[i];
              final isSel = widget.selected == s;
              return ListTile(
                contentPadding:
                const EdgeInsets.symmetric(vertical: 2),
                title: Text(
                  s,
                  style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600,
                    color: isSel
                        ? const Color(0xFF0284C7)
                        : const Color(0xFF1A1A1A),
                  ),
                ),
                trailing: isSel
                    ? const Icon(Icons.check_circle_rounded,
                    size: 18, color: Color(0xFF0284C7))
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  widget.onSelected(s);
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