import 'package:flutter/material.dart';

import 'text_classes.dart';

class SavedTextPage extends StatelessWidget {
  const SavedTextPage({
    super.key,
    required this.text,
    required this.onBack,
    required this.onEdit,
    required this.body,
  });

  final SavedText text;
  final VoidCallback onBack;
  final VoidCallback onEdit;
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
      actions: [
        IconButton(
          tooltip: 'Edit name or text',
          onPressed: onEdit,
          icon: const Icon(Icons.edit),
        ),
      ],
    ),
    body: body,
  );
}
