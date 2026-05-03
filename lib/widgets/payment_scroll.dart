import 'dart:async';
import 'package:flutter/material.dart';

class PaymentIconsRow extends StatefulWidget {
  const PaymentIconsRow();

  @override
  State<PaymentIconsRow> createState() => PaymentIconsRowState();
}

class PaymentIconsRowState extends State<PaymentIconsRow> {
  final _scrollCtrl = ScrollController();
  Timer? _timer;

  static const _methods = [
    'VISA', 'MC', 'AMEX', 'DISCOVER',
    'PayPal', 'Apple Pay', 'Google Pay', 'Klarna',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScroll());
  }

  void _startScroll() {
    _timer = Timer.periodic(const Duration(milliseconds: 30), (_) {
      if (!_scrollCtrl.hasClients) return;
      final max = _scrollCtrl.position.maxScrollExtent;
      final cur = _scrollCtrl.offset;
      if (cur >= max) {
        _scrollCtrl.jumpTo(0);
      } else {
        _scrollCtrl.jumpTo(cur + 1.0);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Duplicate for seamless loop
    final items = [..._methods, ..._methods];

    return SingleChildScrollView(
      controller: _scrollCtrl,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: Row(
        children: items.map((m) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFE0E0E0)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(m, style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: Color(0xFF3A3A3A),
          )),
        )).toList(),
      ),
    );
  }
}