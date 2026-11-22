
import 'package:flutter/material.dart';

import 'saved_text_page.dart';
import 'saved_texts_page.dart';
import 'text_classes.dart';
import 'text_store.dart';

void main() => runApp(const MyApp());

class MyApp extends StatefulWidget {
  const MyApp({
    super.key,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _darkMode = false;
  List<SavedText> _texts = [];
  bool _loading = true;
  String? _error;
  final ValueNotifier<int> _detailPageRevision = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    loadTexts();
    _loading = false;
  }

  @override
  void dispose() {
    _detailPageRevision.dispose();
    super.dispose();
  }

  Widget _buildTextView(SavedText text) {
    return SavedTextPage(
      darkMode: _darkMode,
      text: text,
      onBack: () => Navigator.of(context).pop(),
      onAddTranscript: (SavedText updated) async => {
        await _updateText(updated)
      },
    );
  }

  Future<void> _openText(SavedText text) async {
    return 
      Navigator.of(context)
          .push(
            MaterialPageRoute<void>(
              builder: (_) => ValueListenableBuilder<int>(
                valueListenable: _detailPageRevision,
                builder: (context, _, _) => _buildTextView(text),
              ),
            ),
          )
          .whenComplete(() => {})
        ;
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Uth',
    theme: ThemeData(
      colorSchemeSeed: Colors.indigo,
      brightness: Brightness.light,
      useMaterial3: true,
    ),
    darkTheme: ThemeData(
      colorSchemeSeed: Colors.indigo,
      brightness: Brightness.dark,
      useMaterial3: true,
    ),
    themeMode: _darkMode ? ThemeMode.dark : ThemeMode.light,
    home: _loading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : SavedTextsPage(
              texts: _texts,
              error: _error,
              darkMode: _darkMode,
              onDarkModeChanged: (value) => setState(() => _darkMode = value),
              onErrorDismissed: () => _setState(() => _error = null),
              onAddText: _addText,
              onUpdateText: _updateText,
              onTextDeleted: _deleteText,
              detailPageRevision: _detailPageRevision,
              onErrorChanged: (error) => _setState(() => _error = error),
              onCreateUpdateTranscript: _openText,
            ),

  );

  void _setState(VoidCallback callback) {
    setState(callback);
    _detailPageRevision.value++;
  }

  Future<void> _addText(SavedText text) async {
    _setState(() {
      _texts = [..._texts, text];
    });
    await saveTexts(_texts);
  }

  Future<void> _updateText(SavedText updated) async {
    _setState(() {
      _texts = _texts
          .map((text) => text.id == updated.id ? updated : text)
          .toList();
    });
    await saveTexts(_texts);
  }

  Future<void> _deleteText(SavedText deleted) async {
    _setState(() {
      _texts = _texts
          .where((text) => text.id != deleted.id)
          .toList();
    });
    await saveTexts(_texts);
  }

}
