import 'dart:async';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
    required this.onEdit,
    required this.onSelectedTextChanged,
    required this.detailPageRevision,
    required this.textPageBuilder,
    required this.onErrorChanged,
    required this.onTextsChanged,
  });

  final List<SavedText> texts;
  final String? error;
  final bool darkMode;
  final ValueChanged<bool> onDarkModeChanged;
  final VoidCallback onErrorDismissed;
  final Future<SavedText?> Function() onAdd;
  final Future<SavedText?> Function(SavedText) onEdit;
  final ValueChanged<SavedText?> onSelectedTextChanged;
  final ValueListenable<int> detailPageRevision;
  final Widget Function(SavedText) textPageBuilder;
  final ValueChanged<String?> onErrorChanged;
  final Future<void> Function(List<SavedText>) onTextsChanged;

  Future<void> _addText(BuildContext context) async {
    final text = await onAdd();
    if (text != null && context.mounted) _openText(context, text);
  }

  void _openText(BuildContext context, SavedText text) {
    onSelectedTextChanged(text);
    unawaited(
      Navigator.of(context)
          .push(
            MaterialPageRoute<void>(
              builder: (_) => ValueListenableBuilder<int>(
                valueListenable: detailPageRevision,
                builder: (context, _, _) => textPageBuilder(text),
              ),
            ),
          )
          .whenComplete(() => onSelectedTextChanged(null)),
    );
  }

  Future<void> _exportText(BuildContext context, SavedText text) async {
    try {
      final fileName = '${safeExportName(text.name)}.zip';
      final savedFile = await FilePicker.saveFile(
        fileName: fileName,
        bytes: createSavedTextArchive(text),
        mimeType: 'application/zip',
        dialogTitle: 'Save ${text.name}',
      );
      if (savedFile == null || !context.mounted) return;
      onErrorChanged(null);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Saved $fileName')));
    } catch (error) {
      if (context.mounted) {
        onErrorChanged('Could not save "${text.name}": $error');
      }
    }
  }

  Future<void> _deleteText(BuildContext context, SavedText text) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete text?'),
        content: Text('“${text.name}” and its transcript will be deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await onTextsChanged(texts.where((item) => item.id != text.id).toList());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Mo sgriobtaichean (My scripts)'),
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
      onPressed: () => _addText(context),
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
                      onTap: () => _openText(context, text),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Edit ${text.name}',
                            icon: const Icon(Icons.edit),
                            onPressed: () => onEdit(text),
                          ),
                          IconButton(
                            tooltip: 'Save ${text.name}',
                            icon: const Icon(Icons.save_outlined),
                            onPressed: () => _exportText(context, text),
                          ),
                          IconButton(
                            tooltip: 'Delete ${text.name}',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _deleteText(context, text),
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
