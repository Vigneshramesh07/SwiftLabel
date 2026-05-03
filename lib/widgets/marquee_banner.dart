// lib/widgets/marquee_banner.dart

import 'dart:async';
import 'package:flutter/material.dart';

class MarqueeBanner extends StatefulWidget {
  final List<String> messages;
  final double speed;         // pixels per second
  final TextStyle? textStyle;
  final Color backgroundColor;
  final EdgeInsets padding;

  const MarqueeBanner({
    super.key,
    this.messages = const [
      '🚀 Ship Smart. Deliver Faster. Go Global.',
      '📦 UK & Worldwide Shipping in Seconds.',
      '⚡ Best Rates from Top Carriers.',
      '🌍 Label It. Ship It. Track It. Done.',
      '✈️ Domestic & International — One Tap Away.',
      '🔥 Fast Labels. Zero Hassle. Every Time.',
    ],
    this.speed           = 60.0,
    this.textStyle,
    this.backgroundColor = const Color(0xFFFFF5EE),
    this.padding         = const EdgeInsets.symmetric(vertical: 10),
  });

  @override
  State<MarqueeBanner> createState() => _MarqueeBannerState();
}

class _MarqueeBannerState extends State<MarqueeBanner> {
  late ScrollController _scrollController;
  Timer?  _timer;
  bool    _isScrolling = false;

  // Join all messages into one long string with separators
  String get _fullText =>
      widget.messages.join('     ✦     ') + '     ✦     ';

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    // Small delay to let widget build first
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScrolling());
  }

  void _startScrolling() {
    if (!mounted) return;
    _isScrolling = true;

    // Scroll interval — fires every 16ms (~60fps)
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!mounted || !_scrollController.hasClients) return;

      final maxScroll = _scrollController.position.maxScrollExtent;
      final current   = _scrollController.offset;

      if (current >= maxScroll) {
        // Jump back to start seamlessly
        _scrollController.jumpTo(0);
      } else {
        // Move by speed/60 pixels each frame
        _scrollController.jumpTo(current + (widget.speed / 60));
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: widget.backgroundColor,
      padding: widget.padding,
      child: SingleChildScrollView(
        controller:      _scrollController,
        scrollDirection: Axis.horizontal,
        physics:         const NeverScrollableScrollPhysics(), // auto only
        child: Row(children: [
          // Repeat text twice for seamless loop
          Text(
            _fullText + _fullText,
            style: widget.textStyle ?? const TextStyle(
              fontFamily:  'Syne',
              fontSize:    13,
              fontWeight:  FontWeight.w600,
              color:       Color(0xFFFF5A00),
              letterSpacing: 0.3,
            ),
          ),
        ]),
      ),
    );
  }
}