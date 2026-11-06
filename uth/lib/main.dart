import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pretty_diff_text/pretty_diff_text.dart';
import 'package:record/record.dart';

import 'auth/secrets.dart';

const endpointUrl =
    'https://jcable--whisper-transcribe-transcriber-transcribe.us-east.modal.run';

void main() => runApp(const MyApp());

enum _AppMenuAction { settings, about }

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.documentsDirectoryProvider});

  final Future<Directory> Function()? documentsDirectoryProvider;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _darkMode = false;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Utterance',
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

class _AboutPage extends StatelessWidget {
  const _AboutPage();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('About')),
    body: const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Utterance helps you practice reading aloud and compare your spoken words with the original text.',
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );
}

class _SettingsPage extends StatefulWidget {
  const _SettingsPage({
    required this.darkMode,
    required this.onDarkModeChanged,
  });

  final bool darkMode;
  final ValueChanged<bool> onDarkModeChanged;

  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
  late bool _darkMode = widget.darkMode;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: ListView(
      children: [
        SwitchListTile(
          title: const Text('Dark mode'),
          value: _darkMode,
          onChanged: (value) {
            setState(() => _darkMode = value);
            widget.onDarkModeChanged(value);
          },
        ),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('About'),
          onTap: () {
            Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const _AboutPage()));
          },
        ),
      ],
    ),
  );
}

class SavedText {
  const SavedText({
    required this.id,
    required this.name,
    required this.content,
    this.transcript = '',
  });

  final String id;
  final String name;
  final String content;
  final String transcript;

  SavedText copyWith({String? name, String? content, String? transcript}) =>
      SavedText(
        id: id,
        name: name ?? this.name,
        content: content ?? this.content,
        transcript: transcript ?? this.transcript,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'content': content,
    'transcript': transcript,
  };

  factory SavedText.fromJson(Map<String, dynamic> json) => SavedText(
    id: json['id'] as String,
    name: json['name'] as String,
    content: json['content'] as String,
    transcript: json['transcript'] as String? ?? '',
  );
}

String _safeExportName(String name) {
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
  final folderName = _safeExportName(text.name);
  final archive = Archive()
    ..addFile(ArchiveFile.string('$folderName/original.txt', text.content))
    ..addFile(
      ArchiveFile.string('$folderName/transcript.txt', text.transcript),
    );
  return ZipEncoder().encodeBytes(archive);
}

class TextDifference {
  const TextDifference({
    required this.start,
    required this.end,
    required this.transcript,
  });

  final int start;
  final int end;
  final String transcript;
}

class TextComparison {
  const TextComparison(this.differences);

  final List<TextDifference> differences;

  bool get matches => differences.isEmpty;
}

class _Word {
  const _Word(this.text, this.start, this.end, this.key);

  final String text;
  final int start;
  final int end;
  final String key;
}

enum _Edit { equal, substitute, delete, insert }

enum _TextViewMode { reveal, both, prettyDiff }

class ComparisonTextSpanBuilder {
  final _recognizers = <TapGestureRecognizer>[];

  List<TextSpan> build({
    required String original,
    required TextComparison comparison,
    required bool showTranscript,
    required Color revealColor,
    required Color revealUnderlineColor,
    required Color originalHighlightColor,
    required Color transcriptHighlightColor,
    void Function(TextDifference)? onDifferenceTap,
  }) {
    final spans = <TextSpan>[];
    var cursor = 0;
    var recognizerIndex = 0;
    for (final difference in comparison.differences) {
      if (difference.start < cursor || difference.end < difference.start) {
        throw StateError(
          'Text differences must be ordered and non-overlapping',
        );
      }
      if (difference.start > cursor) {
        spans.add(TextSpan(text: original.substring(cursor, difference.start)));
      }
      final originalSegment = original.substring(
        difference.start,
        difference.end,
      );
      if (showTranscript) {
        spans.add(
          TextSpan(
            text: originalSegment,
            style: TextStyle(backgroundColor: originalHighlightColor),
          ),
        );
        if (difference.transcript.isNotEmpty) {
          // spans.add(const TextSpan(text: ' '));
          spans.add(
            TextSpan(
              text: difference.transcript,
              style: TextStyle(backgroundColor: transcriptHighlightColor),
            ),
          );
        }
      } else {
        TapGestureRecognizer? recognizer;
        if (onDifferenceTap != null) {
          if (_recognizers.length == recognizerIndex) {
            _recognizers.add(TapGestureRecognizer());
          }
          recognizer = _recognizers[recognizerIndex++]
            ..onTap = () => onDifferenceTap(difference);
        }
        spans.add(
          TextSpan(
            text: originalSegment,
            style: TextStyle(
              backgroundColor: revealColor,
              decoration: TextDecoration.underline,
              decorationColor: revealUnderlineColor,
            ),
            recognizer: recognizer,
          ),
        );
      }
      cursor = difference.end;
    }
    while (_recognizers.length > recognizerIndex) {
      _recognizers.removeLast().dispose();
    }
    if (cursor < original.length) {
      spans.add(TextSpan(text: original.substring(cursor)));
    }
    if (original.isEmpty) {
      spans.add(const TextSpan(text: 'No text yet. Use Edit to paste text.'));
    }
    return spans;
  }

  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }
}

class _EditStep {
  const _EditStep(this.edit, this.originalIndex, this.transcriptIndex);

  final _Edit edit;
  final int? originalIndex;
  final int? transcriptIndex;
}

class _TextDraft {
  const _TextDraft(this.name, this.content);

  final String name;
  final String content;
}

class _TextEditorDialog extends StatefulWidget {
  const _TextEditorDialog({required this.existing});

  final SavedText? existing;

  @override
  State<_TextEditorDialog> createState() => _TextEditorDialogState();
}

class _TextEditorDialogState extends State<_TextEditorDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _contentController;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _contentController = TextEditingController(
      text: widget.existing?.content ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.existing == null ? 'Add text' : 'Edit text'),
    content: SizedBox(
      width: 520,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? 'Enter a name' : null,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _contentController,
              minLines: 8,
              maxLines: 14,
              decoration: const InputDecoration(
                labelText: 'Paste or enter text',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!_formKey.currentState!.validate()) return;
          Navigator.pop(
            context,
            _TextDraft(_nameController.text.trim(), _contentController.text),
          );
        },
        child: const Text('Save'),
      ),
    ],
  );
}

List<_Word> _words(String text) {
  final words = <_Word>[];
  for (final match in RegExp(r'\S+').allMatches(text)) {
    final raw = match.group(0)!;
    final key = StringBuffer();
    for (final character in raw.runes) {
      final value = String.fromCharCode(character).toLowerCase();
      if (RegExp(r'[\s.,!?]').hasMatch(value) || '"\'“”‘’'.contains(value)) {
        continue;
      }
      key.write(value);
    }
    if (key.isNotEmpty) {
      words.add(_Word(raw, match.start, match.end, key.toString()));
    }
  }
  return words;
}

List<_EditStep> _alignWords(List<_Word> original, List<_Word> transcript) {
  final rows = original.length + 1;
  final columns = transcript.length + 1;
  final costs = List.generate(rows, (_) => List<int>.filled(columns, 0));

  for (var i = 0; i < rows; i++) {
    costs[i][transcript.length] = original.length - i;
  }
  for (var j = 0; j < columns; j++) {
    costs[original.length][j] = transcript.length - j;
  }
  for (var i = original.length - 1; i >= 0; i--) {
    for (var j = transcript.length - 1; j >= 0; j--) {
      final replacementCost = original[i].key == transcript[j].key ? 0 : 1;
      costs[i][j] = [
        costs[i + 1][j + 1] + replacementCost,
        costs[i + 1][j] + 1,
        costs[i][j + 1] + 1,
      ].reduce((a, b) => a < b ? a : b);
    }
  }

  final steps = <_EditStep>[];
  var i = 0;
  var j = 0;
  while (i < original.length || j < transcript.length) {
    if (i < original.length &&
        j < transcript.length &&
        original[i].key == transcript[j].key) {
      steps.add(_EditStep(_Edit.equal, i++, j++));
      continue;
    }
    if (i < original.length &&
        j < transcript.length &&
        costs[i][j] == costs[i + 1][j + 1] + 1) {
      steps.add(_EditStep(_Edit.substitute, i++, j++));
    } else if (i < original.length && costs[i][j] == costs[i + 1][j] + 1) {
      steps.add(_EditStep(_Edit.delete, i++, null));
    } else {
      steps.add(_EditStep(_Edit.insert, null, j++));
    }
  }
  return steps;
}

TextComparison compareText(String original, String transcript) {
  if (transcript.isEmpty) return const TextComparison([]);

  final originalWords = _words(original);
  final transcriptWords = _words(transcript);
  final steps = _alignWords(originalWords, transcriptWords);
  final differences = <TextDifference>[];
  var index = 0;
  var originalPosition = 0;

  while (index < steps.length) {
    if (steps[index].edit == _Edit.equal) {
      originalPosition = steps[index].originalIndex! + 1;
      index++;
      continue;
    }

    final changedSteps = <_EditStep>[];
    while (index < steps.length && steps[index].edit != _Edit.equal) {
      changedSteps.add(steps[index++]);
    }

    final changedOriginal = changedSteps
        .where((step) => step.originalIndex != null)
        .map((step) => step.originalIndex!)
        .toList();
    final changedTranscript = changedSteps
        .where((step) => step.transcriptIndex != null)
        .map((step) => step.transcriptIndex!)
        .toList();
    if (originalWords.isEmpty) continue;

    final firstOriginal = changedOriginal.isEmpty
        ? originalPosition.clamp(0, originalWords.length - 1).toInt()
        : changedOriginal.first;
    final lastOriginal = changedOriginal.isEmpty
        ? firstOriginal
        : changedOriginal.last;
    final anchor = firstOriginal.clamp(0, originalWords.length - 1).toInt();
    final start = changedOriginal.isEmpty
        ? originalWords[anchor].start
        : originalWords[firstOriginal].start;
    final end = changedOriginal.isEmpty
        ? originalWords[anchor].end
        : originalWords[lastOriginal].end;
    final transcriptExcerpt = changedTranscript.isEmpty
        ? ''
        : transcript.substring(
            transcriptWords[changedTranscript.first].start,
            transcriptWords[changedTranscript.last].end,
          );
    differences.add(
      TextDifference(start: start, end: end, transcript: transcriptExcerpt),
    );
    if (changedOriginal.isNotEmpty) {
      originalPosition = changedOriginal.last + 1;
    }
  }
  return TextComparison(differences);
}

class TranscribePage extends StatefulWidget {
  const TranscribePage({
    super.key,
    this.documentsDirectoryProvider,
    required this.darkMode,
    required this.onDarkModeChanged,
  });

  final Future<Directory> Function()? documentsDirectoryProvider;
  final bool darkMode;
  final ValueChanged<bool> onDarkModeChanged;

  @override
  State<TranscribePage> createState() => _TranscribePageState();
}

class _TranscribePageState extends State<TranscribePage> {
  AudioRecorder? _recorder;
  AudioPlayer? _player;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  final _spanBuilder = ComparisonTextSpanBuilder();
  List<SavedText> _texts = [];
  String? _selectedId;
  String? _pendingAudioPath;
  String? _error;
  TextSelection? _selection;
  TextSelection? _recordingSelection;
  TextComparison _comparison = const TextComparison([]);
  bool _loading = true;
  bool _recording = false;
  bool _playing = false;
  bool _transcribing = false;
  _TextViewMode _viewMode = _TextViewMode.reveal;

  AudioRecorder get _audioRecorder => _recorder ??= AudioRecorder();

  SavedText? get _selected {
    for (final text in _texts) {
      if (text.id == _selectedId) return text;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadTexts();
  }

  @override
  void dispose() {
    _spanBuilder.dispose();
    final pendingPath = _pendingAudioPath;
    if (pendingPath != null) {
      final file = File(pendingPath);
      if (file.existsSync()) file.deleteSync();
    }
    _playerStateSubscription?.cancel();
    _player?.dispose();
    _recorder?.dispose();
    super.dispose();
  }

  Future<File> _textsFile() async {
    final directory =
        await (widget.documentsDirectoryProvider?.call() ??
            getApplicationDocumentsDirectory());
    return File('${directory.path}/saved_texts.json');
  }

  Future<void> _loadTexts() async {
    try {
      final file = await _textsFile();
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString()) as List<dynamic>;
        _texts = decoded
            .map((item) => SavedText.fromJson(item as Map<String, dynamic>))
            .toList();
      }
    } catch (error) {
      _error = 'Could not load saved texts: $error';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveTexts() async {
    try {
      final file = await _textsFile();
      await file.writeAsString(
        jsonEncode(_texts.map((text) => text.toJson()).toList()),
      );
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not save texts: $error');
    }
  }

  Future<void> _exportText(SavedText text) async {
    try {
      final fileName = '${_safeExportName(text.name)}.zip';
      final savedFile = await FilePicker.saveFile(
        fileName: fileName,
        bytes: createSavedTextArchive(text),
        mimeType: 'application/zip',
        dialogTitle: 'Save ${text.name}',
      );
      if (savedFile == null || !mounted) return;
      setState(() => _error = null);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Saved $fileName')));
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not save "${text.name}": $error');
      }
    }
  }

  Future<void> _editText({SavedText? existing}) async {
    final draft = await showDialog<_TextDraft>(
      context: context,
      builder: (context) => _TextEditorDialog(existing: existing),
    );
    if (draft == null || !mounted) return;

    if (existing == null) {
      final text = SavedText(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: draft.name,
        content: draft.content,
      );
      setState(() {
        _texts = [..._texts, text];
        _selectedId = text.id;
        _selection = null;
        _comparison = compareText(text.content, text.transcript);
      });
    } else {
      final updated = existing.copyWith(
        name: draft.name,
        content: draft.content,
      );
      setState(() {
        _texts = _texts
            .map((text) => text.id == existing.id ? updated : text)
            .toList();
        _comparison = compareText(updated.content, updated.transcript);
        _selection = null;
      });
    }
    await _saveTexts();
  }

  Future<void> _deleteText(SavedText text) async {
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
    if (confirmed != true || !mounted) return;
    setState(() {
      _texts = _texts.where((item) => item.id != text.id).toList();
      if (_selectedId == text.id) _selectedId = null;
    });
    await _saveTexts();
  }

  Future<void> _startRecording({TextSelection? selection}) async {
    try {
      await _stopPlayback();
      if (!await _audioRecorder.hasPermission()) {
        setState(() => _error = 'Microphone permission denied');
        return;
      }
      final directory = await getTemporaryDirectory();
      final path =
          '${directory.path}/rec_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 16000,
          numChannels: 1,
          bitRate: 64000,
        ),
        path: path,
      );
      if (!mounted) return;
      setState(() {
        _recording = true;
        _selection = selection;
        _recordingSelection = selection;
        _error = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not start recording: $error');
      }
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      if (!mounted) return;
      final previousPath = _pendingAudioPath;
      setState(() {
        _recording = false;
        if (path != null) _pendingAudioPath = path;
        if (path == null) _error = 'No recording was saved';
      });
      if (path != null && previousPath != null && previousPath != path) {
        final previousFile = File(previousPath);
        if (await previousFile.exists()) await previousFile.delete();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _recording = false;
          _error = 'Could not stop recording: $error';
        });
      }
    }
  }

  Future<void> _togglePlayback() async {
    final path = _pendingAudioPath;
    if (path == null) return;

    try {
      final player = _player ??= AudioPlayer();
      _playerStateSubscription ??= player.onPlayerStateChanged.listen(
        (state) {
          if (mounted) setState(() => _playing = state == PlayerState.playing);
        },
        onError: (Object error) {
          if (mounted) setState(() => _error = 'Playback failed: $error');
        },
      );
      if (_playing) {
        await player.pause();
      } else {
        await player.play(DeviceFileSource(path));
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'Playback failed: $error');
    }
  }

  Future<void> _stopPlayback() async {
    final player = _player;
    if (player == null || player.state == PlayerState.stopped) return;
    await player.stop();
  }

  Future<void> _transcribeRecording() async {
    final path = _pendingAudioPath;
    final text = _selected;
    if (path == null || text == null) return;
    final recordingSelection = _recordingSelection;
    final file = File(path);
    setState(() {
      _transcribing = true;
      _error = null;
    });
    try {
      await _stopPlayback();
      final result = await _transcribe(file);
      if (!mounted) return;
      final updatedTranscript = recordingSelection == null
          ? result
          : replaceTranscriptForSelection(
              text.content,
              text.transcript.isEmpty ? text.content : text.transcript,
              recordingSelection,
              result,
            );
      final updated = text.copyWith(transcript: updatedTranscript);
      setState(() {
        _texts = _texts
            .map((item) => item.id == text.id ? updated : item)
            .toList();
        _comparison = compareText(updated.content, updated.transcript);
        _selection = null;
      });
      await _saveTexts();
    } catch (error) {
      if (mounted) setState(() => _error = 'Transcription failed: $error');
    } finally {
      if (await file.exists()) await file.delete();
      if (mounted) {
        setState(() {
          _pendingAudioPath = null;
          _recordingSelection = null;
          _transcribing = false;
        });
      }
    }
  }

  Future<String> _transcribe(File file) async {
    final response = await http
        .post(
          Uri.parse(endpointUrl),
          headers: {
            'Authorization': 'Bearer $apiToken',
            'Content-Type': 'audio/mp4',
          },
          body: await file.readAsBytes(),
        )
        .timeout(const Duration(seconds: 180));
    final body = utf8.decode(response.bodyBytes);
    if (response.statusCode != 200) {
      throw Exception('Server error ${response.statusCode}: $body');
    }
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final result = decoded['text'];
    if (result is! String) {
      throw const FormatException('Transcription response has no text field');
    }
    return result;
  }

  void _showDifference(TextDifference difference) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Transcript difference'),
        content: Text(
          difference.transcript.isEmpty
              ? 'No matching words were recognized for this section.'
              : difference.transcript,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildTextList() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My texts'),
        actions: [
          PopupMenuButton<_AppMenuAction>(
            tooltip: 'More options',
            onSelected: (action) {
              switch (action) {
                case _AppMenuAction.settings:
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _SettingsPage(
                        darkMode: widget.darkMode,
                        onDarkModeChanged: widget.onDarkModeChanged,
                      ),
                    ),
                  );
                case _AppMenuAction.about:
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const _AboutPage()),
                  );
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _AppMenuAction.settings,
                child: Text('Settings'),
              ),
              PopupMenuItem(value: _AppMenuAction.about, child: Text('About')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _editText,
        icon: const Icon(Icons.add),
        label: const Text('Add text'),
      ),
      body: _texts.isEmpty
          ? const Center(
              child: Text('Add a text to start practicing your reading.'),
            )
          : ListView.builder(
              itemCount: _texts.length,
              itemBuilder: (context, index) {
                final text = _texts[index];
                return ListTile(
                  title: Text(text.name),
                  subtitle: Text(
                    text.transcript.isEmpty
                        ? 'No transcript yet'
                        : 'Transcript saved',
                  ),
                  onTap: () {
                    setState(() {
                      _selectedId = text.id;
                      _selection = null;
                      _comparison = compareText(text.content, text.transcript);
                    });
                  },
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Save ${text.name}',
                        icon: const Icon(Icons.save_outlined),
                        onPressed: () => _exportText(text),
                      ),
                      IconButton(
                        tooltip: 'Delete ${text.name}',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _deleteText(text),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _buildTextView(SavedText text) {
    final spans = _spanBuilder.build(
      original: text.content,
      comparison: _comparison,
      showTranscript: _viewMode == _TextViewMode.both,
      revealColor: Theme.of(context).colorScheme.errorContainer,
      revealUnderlineColor: Theme.of(context).colorScheme.error,
      originalHighlightColor: Colors.green.shade100,
      transcriptHighlightColor: Colors.red.shade100,
      onDifferenceTap: _showDifference,
    );

    final isRecordingSelection = _selection != null && !_selection!.isCollapsed;
    const verticalPadding = 12.0;
    final recordLabel = text.transcript.isEmpty
        ? 'Record'
        : isRecordingSelection
        ? 'Record selected'
        : 'Re-record';
    final defaultTextStyle =
        Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.7) ??
        const TextStyle(height: 1.7);
    final deletedTextStyle = TextStyle(backgroundColor: Colors.green.shade100);
    final addedTextStyle = TextStyle(backgroundColor: Colors.red.shade100);
    final prettyDiff = _viewMode == _TextViewMode.prettyDiff
        ? PrettyDiffText(
            oldText: text.content,
            newText: text.transcript,
            defaultTextStyle: defaultTextStyle,
            deletedTextStyle: deletedTextStyle,
            addedTextStyle: addedTextStyle,
          )
        : null;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back to texts',
          onPressed: () => setState(() => _selectedId = null),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(text.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Edit name or text',
            onPressed: () => _editText(existing: text),
            icon: const Icon(Icons.edit),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              if (text.transcript.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SegmentedButton<_TextViewMode>(
                    segments: const [
                      ButtonSegment(
                        value: _TextViewMode.reveal,
                        label: Text('Reveal'),
                      ),
                      ButtonSegment(
                        value: _TextViewMode.both,
                        label: Text('Both'),
                      ),
                      ButtonSegment(
                        value: _TextViewMode.prettyDiff,
                        label: Text('Diff'),
                      ),
                    ],
                    selected: {_viewMode},
                    onSelectionChanged: (selection) {
                      setState(() => _viewMode = selection.first);
                    },
                  ),
                ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: verticalPadding,
                    ),
                    child: Container(
                      width: double.infinity,
                      height: constraints.maxHeight - verticalPadding * 2,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: prettyDiff != null
                          ? SelectableText.rich(
                              TextSpan(
                                style: defaultTextStyle,
                                children: prettyDiff.textSpans,
                              ),
                              onSelectionChanged: (selection, cause) {
                                setState(() {
                                  _selection = _originalSelectionFromDiff(
                                    selection,
                                    prettyDiff.textSpans,
                                    addedTextStyle: addedTextStyle,
                                  );
                                });
                              },
                            )
                          : SelectableText.rich(
                              TextSpan(
                                style: Theme.of(context).textTheme.bodyLarge
                                    ?.copyWith(height: 1.7),
                                children: spans,
                              ),
                              onSelectionChanged: (selection, cause) {
                                setState(() {
                                  _selection = selection.isCollapsed
                                      ? null
                                      : selection;
                                });
                              },
                            ),
                    ),
                  ),
                ),
              ),
              if (_comparison.differences.isNotEmpty ||
                  _viewMode == _TextViewMode.prettyDiff)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(switch (_viewMode) {
                    _TextViewMode.reveal =>
                      '${_comparison.differences.length} difference(s) '
                          'highlighted. Tap a highlighted section to see the '
                          'transcript.',
                    _TextViewMode.both =>
                      '${_comparison.differences.length} difference(s): '
                          'original text followed by transcript text.',
                    _TextViewMode.prettyDiff =>
                      'Original-only text and transcript-only text are '
                          'highlighted.',
                  }, style: Theme.of(context).textTheme.bodySmall),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (_recording)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: FilledButton.icon(
                    onPressed: _stopRecording,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop recording'),
                  ),
                )
              else if (_pendingAudioPath != null && !_transcribing)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _togglePlayback,
                        icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                        label: Text(_playing ? 'Pause playback' : 'Play'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final selection = _recordingSelection;
                          await _startRecording(selection: selection);
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Re-record'),
                      ),
                      FilledButton.icon(
                        onPressed: _transcribeRecording,
                        icon: const Icon(Icons.send),
                        label: const Text('Go'),
                      ),
                    ],
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _transcribing
                            ? null
                            : () => _startRecording(
                                selection: isRecordingSelection
                                    ? _selection
                                    : null,
                              ),
                        icon: const Icon(Icons.mic),
                        label: Text(recordLabel),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (_transcribing)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 8),
                  Text('Transcribing…'),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final text = _selected;
    if (text != null) return _buildTextView(text);
    return Scaffold(
      body: Column(
        children: [
          if (_error != null)
            MaterialBanner(
              content: Text(_error!),
              actions: [
                TextButton(
                  onPressed: () => setState(() => _error = null),
                  child: const Text('Dismiss'),
                ),
              ],
            ),
          Expanded(child: _buildTextList()),
        ],
      ),
    );
  }
}

String replaceTranscriptForSelection(
  String original,
  String transcript,
  TextSelection selection,
  String replacement,
) {
  final originalWords = _words(original);
  final transcriptWords = _words(transcript);
  final selectedWords = <int>[];
  for (var i = 0; i < originalWords.length; i++) {
    if (originalWords[i].end > selection.start &&
        originalWords[i].start < selection.end) {
      selectedWords.add(i);
    }
  }
  if (selectedWords.isEmpty) {
    throw const FormatException('Select one or more words to re-record');
  }

  final first = selectedWords.first;
  final last = selectedWords.last;
  var transcriptIndex = 0;
  int? startToken;
  int? endToken;
  for (final step in _alignWords(originalWords, transcriptWords)) {
    if (step.originalIndex == first) startToken = transcriptIndex;
    if (step.transcriptIndex != null) transcriptIndex++;
    if (step.originalIndex == last) endToken = transcriptIndex;
  }
  if (startToken == null || endToken == null) {
    throw const FormatException('Could not locate the selected transcript');
  }
  final start = startToken < transcriptWords.length
      ? transcriptWords[startToken].start
      : transcript.length;
  final end = endToken > 0 ? transcriptWords[endToken - 1].end : start;
  return transcript.replaceRange(start, end, replacement);
}

TextSelection? _originalSelectionFromDiff(
  TextSelection selection,
  List<TextSpan> spans, {
  required TextStyle addedTextStyle,
}) {
  if (selection.isCollapsed) return null;

  final selectionStart = selection.start;
  final selectionEnd = selection.end;
  var displayOffset = 0;
  var originalOffset = 0;
  int? originalStart;
  int? originalEnd;

  for (final span in spans) {
    final segment = span.toPlainText();
    final displayEnd = displayOffset + segment.length;
    if (span.style != addedTextStyle) {
      final overlapStart = selectionStart > displayOffset
          ? selectionStart
          : displayOffset;
      final overlapEnd = selectionEnd < displayEnd ? selectionEnd : displayEnd;
      if (overlapStart < overlapEnd) {
        originalStart ??= originalOffset + overlapStart - displayOffset;
        originalEnd = originalOffset + overlapEnd - displayOffset;
      }
      originalOffset += segment.length;
    }
    displayOffset = displayEnd;
  }

  if (originalStart == null || originalEnd == null) return null;
  return TextSelection(baseOffset: originalStart, extentOffset: originalEnd);
}
