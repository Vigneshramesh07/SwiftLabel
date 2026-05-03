import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class DocumentScreen extends StatelessWidget {
  final String title;
  final String content;

  const DocumentScreen({
    super.key,
    required this.title,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: Markdown(
        data: content,
        padding: const EdgeInsets.all(16),
        styleSheet: MarkdownStyleSheet(
          h1: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          h2: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          p: const TextStyle(fontSize: 14, height: 1.6),
          listBullet: const TextStyle(fontSize: 14),
        ),
      ),
    );
  }
}