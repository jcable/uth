import 'package:flutter/material.dart';

import 'text_classes.dart';

class SavedTextPage extends StatelessWidget {
  const SavedTextPage({
    super.key,
    required this.text,
    required this.onBack,
    required this.body,
  });

  final SavedText text;
  final VoidCallback onBack;
  final Widget body;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        tooltip: 'Back to texts',
        onPressed: onBack,
        icon: const Icon(Icons.arrow_back),
      ),
      title: Text(text.name, maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
    body: body,
  );
}
