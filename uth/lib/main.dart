import 'dart:io';

import 'package:flutter/material.dart';

import 'transcribe_page.dart';

void main() => runApp(const MyApp());

class MyApp extends StatefulWidget {
  const MyApp({
    super.key,
    this.documentsDirectoryProvider,
  });

  final Future<Directory> Function()? documentsDirectoryProvider;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _darkMode = false;

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
    home: TranscribePage(
      documentsDirectoryProvider: widget.documentsDirectoryProvider,
      darkMode: _darkMode,
      onDarkModeChanged: (value) => setState(() => _darkMode = value),
    ),
  );
}
