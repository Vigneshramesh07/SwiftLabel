import 'dart:async';
import 'package:flutter/material.dart';

class AutoScrollBadges extends StatefulWidget {
  const AutoScrollBadges();

  @override
  State<AutoScrollBadges> createState() => AutoScrollBadgesState();
}

class AutoScrollBadgesState extends State<AutoScrollBadges> {
  final _scrollCtrl = ScrollController();
  Timer? _timer;

  static const _badges = [
    '✓ Label in Under 30 Seconds',
    '✓ No Account Required',
    '✓ Instant Download',
    '✓ Secure Payment',
    '✓ Real-Time Tracking',
    '✓ All Major Couriers',
  ];

  @override
  void initState() {
    super.initState();
    // Start auto-scroll after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScroll());
  }

  void _startScroll() {
    _timer = Timer.periodic(const Duration(milliseconds: 30), (_) {
      if (!_scrollCtrl.hasClients) return;

      final max = _scrollCtrl.position.maxScrollExtent;
      final current = _scrollCtrl.offset;

      if (current >= max) {
        // Jump silently back to start and continue
        _scrollCtrl.jumpTo(0);
      } else {
        _scrollCtrl.jumpTo(current + 1.5);
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
    // Duplicate badges so the loop feels seamless
    final items = [..._badges, ..._badges];

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        controller: _scrollCtrl,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(), // disable manual scroll
        child: Row(
          children: items.map((badge) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _badge(badge),
          )).toList(),
        ),
      ),
    );
  }

  Widget _badge(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        color: Color(0xFF059669),
        fontWeight: FontWeight.w500,
      ),
    );
  }
}