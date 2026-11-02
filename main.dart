// Flutter client for the Modal Whisper endpoint (replaces Transcriber.kt).
//
// Setup:
//   flutter create whisper_app && cd whisper_app
//   flutter pub add record http path_provider
//   Replace lib/main.dart with this file.
//
// Android: android/app/src/main/AndroidManifest.xml (inside <manifest>):
//   <uses-permission android:name="android.permission.RECORD_AUDIO" />
//   <uses-permission android:name="android.permission.INTERNET" />
//   If the build complains, set minSdk to 23 in android/app/build.gradle(.kts).
//
// iOS: ios/Runner/Info.plist:
//   <key>NSMicrophoneUsageDescription</key>
//   <string>Used to record speech for transcription.</string>
//
// Security note: a token shipped inside the app can be extracted. Fine for a
// personal app; for a public app, put your own auth in front of Modal.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

// ---- CHANGE THESE ----
const endpointUrl = 'https://YOUR-WORKSPACE--whisper-transcribe-transcriber-transcribe.modal.run';
const apiToken = 'the-same-value-you-put-in-the-modal-secret';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Whisper Transcriber',
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        home: const TranscribePage(),
      );
}

class TranscribePage extends StatefulWidget {
  const TranscribePage({super.key});

  @override
  State<TranscribePage> createState() => _TranscribePageState();
}

class _TranscribePageState extends State<TranscribePage> {
  final _recorder = AudioRecorder();
  bool _recording = false;
  bool _loading = false;
  String _transcript = '';
  String? _error;

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      if (!await _recorder.hasPermission()) {
        setState(() => _error = 'Microphone permission denied');
        return;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 16000, // Whisper works at 16 kHz
          numChannels: 1, // mono
          bitRate: 64000,
        ),
        path: path,
      );
      setState(() {
        _recording = true;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = 'Could not start recording: $e');
    }
  }

  Future<void> _stopAndTranscribe() async {
    final path = await _recorder.stop();
    setState(() => _recording = false);
    if (path == null) {
      setState(() => _error = 'No recording was saved');
      return;
    }

    final file = File(path);
    setState(() => _loading = true);
    try {
      final text = await _transcribe(file);
      setState(() => _transcript = text);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
      if (await file.exists()) await file.delete();
    }
  }

  Future<String> _transcribe(File file) async {
    final bytes = await file.readAsBytes();
    // Long timeout: the first request after idle may wait for a GPU cold start.
    final response = await http
        .post(
          Uri.parse(endpointUrl),
          headers: {
            'Authorization': 'Bearer $apiToken',
            'Content-Type': 'audio/mp4',
          },
          body: bytes,
        )
        .timeout(const Duration(seconds: 180));

    final body = utf8.decode(response.bodyBytes);
    if (response.statusCode != 200) {
      throw Exception('Server error ${response.statusCode}: $body');
    }
    return (jsonDecode(body) as Map<String, dynamic>)['text'] as String;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Whisper Transcriber')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            FilledButton.icon(
              onPressed: _loading
                  ? null
                  : (_recording ? _stopAndTranscribe : _start),
              icon: Icon(_recording ? Icons.stop : Icons.mic),
              label: Text(_recording ? 'Stop & transcribe' : 'Record'),
            ),
            const SizedBox(height: 16),
            if (_loading) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 8),
              const Text('Transcribing… (first request may take longer)'),
            ],
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_transcript.isNotEmpty)
              Expanded(
                child: SingleChildScrollView(
                  child: SelectableText(
                    _transcript,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
