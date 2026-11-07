import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:archive/archive.dart';

import 'about_page.dart';
import 'settings_page.dart';
import 'text_classes.dart';

enum _MenuAction { settings, about }

class SavedTextsPage extends StatelessWidget {
  const SavedTextsPage({
    super.key,
    required this.texts,
    required this.error,
    required this.darkMode,
    required this.onDarkModeChanged,
    required this.onErrorDismissed,
    required this.onAdd,
    required this.onOpen,
    required this.onExport,
    required this.onDelete,
  });

  final List<SavedText> texts;
  final String? error;
  final bool darkMode;
  final ValueChanged<bool> onDarkModeChanged;
  final VoidCallback onErrorDismissed;
  final VoidCallback onAdd;
  final ValueChanged<SavedText> onOpen;
  final ValueChanged<SavedText> onExport;
  final ValueChanged<SavedText> onDelete;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('My texts'),
      actions: [
        PopupMenuButton<_MenuAction>(
          tooltip: 'More options',
          onSelected: (action) {
            switch (action) {
              case _MenuAction.settings:
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SettingsPage(
                      darkMode: darkMode,
                      onDarkModeChanged: onDarkModeChanged,
                    ),
                  ),
                );
              case _MenuAction.about:
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AboutPage()),
                );
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: _MenuAction.settings, child: Text('Settings')),
            PopupMenuItem(value: _MenuAction.about, child: Text('About')),
          ],
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: onAdd,
      icon: const Icon(Icons.add),
      label: const Text('Add text'),
    ),
    body: Column(
      children: [
        if (error != null)
          MaterialBanner(
            content: Text(error!),
            actions: [
              TextButton(
                onPressed: onErrorDismissed,
                child: const Text('Dismiss'),
              ),
            ],
          ),
        Expanded(
          child: texts.isEmpty
              ? const Center(
                  child: Text('Add a text to start practicing your reading.'),
                )
              : ListView.builder(
                  itemCount: texts.length,
                  itemBuilder: (context, index) {
                    final text = texts[index];
                    return ListTile(
                      title: Text(text.name),
                      subtitle: Text(
                        text.transcript.isEmpty
                            ? 'No transcript yet'
                            : 'Transcript saved',
                      ),
                      onTap: () => onOpen(text),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Save ${text.name}',
                            icon: const Icon(Icons.save_outlined),
                            onPressed: () => onExport(text),
                          ),
                          IconButton(
                            tooltip: 'Delete ${text.name}',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => onDelete(text),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    ),
  );
}

String safeExportName(String name) {
  var folderName = name
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
      .replaceAll(RegExp(r'[. ]+$'), '');
  if (folderName.isEmpty) folderName = 'text';
  if (RegExp(
    r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)',
    caseSensitive: false,
  ).hasMatch(folderName)) {
    folderName = '_$folderName';
  }
  return folderName;
}

Uint8List createSavedTextArchive(SavedText text) {
  final folderName = safeExportName(text.name);
  final archive = Archive()
    ..addFile(ArchiveFile.string('$folderName/original.txt', text.content))
    ..addFile(
      ArchiveFile.string('$folderName/transcript.txt', text.transcript),
    );
  return ZipEncoder().encodeBytes(archive);
}
