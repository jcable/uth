import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pretty_diff_text/pretty_diff_text.dart';
import 'package:record/record.dart';

import 'dictionary_search.dart';
import 'saved_text_page.dart';
import 'saved_texts_page.dart';
import 'text_classes.dart';
import 'text_spans.dart';
import 'transcription_service.dart';

typedef DictionarySearch = Future<List<GaelicDictionaryEntry>> Function(
  String abairt,
);
typedef DictionaryAudioDownloader = Future<File?> Function(
  GaelicDictionaryEntry entry,
);
typedef DictionaryAudioPlayer = Future<void> Function(File file);

enum _TextViewMode { reveal, both, tree, prettyDiff }

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
            TextDraft(_nameController.text.trim(), _contentController.text),
          );
        },
        child: const Text('Save'),
      ),
    ],
  );
}

class TranscribePage extends StatefulWidget {
  const TranscribePage({
    super.key,
    this.documentsDirectoryProvider,
    this.dictionarySearch,
    this.dictionaryAudioDownloader,
    this.dictionaryAudioPlayer,
    required this.darkMode,
    required this.onDarkModeChanged,
  });

  final Future<Directory> Function()? documentsDirectoryProvider;
  final DictionarySearch? dictionarySearch;
  final DictionaryAudioDownloader? dictionaryAudioDownloader;
  final DictionaryAudioPlayer? dictionaryAudioPlayer;
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
  final Map<String, Set<int>> _expandedSentences = {};
  final Map<String, List<GaelicDictionaryEntry>> _dictionaryEntries = {};
  final Set<String> _dictionaryLoading = {};
  final Map<int, Future<File?>> _dictionaryAudioDownloads = {};
  final ValueNotifier<int> _detailPageRevision = ValueNotifier<int>(0);

  void _setState(VoidCallback callback) {
    setState(callback);
    _detailPageRevision.value++;
  }

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
    _detailPageRevision.dispose();
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
      if (mounted) _setState(() => _loading = false);
    }
  }

  Future<void> _saveTexts() async {
    try {
      final file = await _textsFile();
      await file.writeAsString(
        jsonEncode(_texts.map((text) => text.toJson()).toList()),
      );
    } catch (error) {
      if (mounted) _setState(() => _error = 'Could not save texts: $error');
    }
  }

  Future<void> _exportText(SavedText text) async {
    try {
      final fileName = '${safeExportName(text.name)}.zip';
      final savedFile = await FilePicker.saveFile(
        fileName: fileName,
        bytes: createSavedTextArchive(text),
        mimeType: 'application/zip',
        dialogTitle: 'Save ${text.name}',
      );
      if (savedFile == null || !mounted) return;
      _setState(() => _error = null);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Saved $fileName')));
    } catch (error) {
      if (mounted) {
        _setState(() => _error = 'Could not save "${text.name}": $error');
      }
    }
  }

  Future<void> _editText({SavedText? existing}) async {
    final draft = await showDialog<TextDraft>(
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
      _setState(() {
        _texts = [..._texts, text];
        _selectedId = text.id;
        _selection = null;
        _comparison = compareText(text.content, text.transcript);
      });
      if (mounted) _openText(text);
      await _saveTexts();
      return;
    } else {
      final updated = existing.copyWith(
        name: draft.name,
        content: draft.content,
      );
      _setState(() {
        if (existing.content != updated.content) {
          _expandedSentences.remove(existing.id);
        }
        _texts = _texts
            .map((text) => text.id == existing.id ? updated : text)
            .toList();
        _comparison = compareText(updated.content, updated.transcript);
        _selection = null;
      });
    }
    await _saveTexts();
  }

  void _openText(SavedText text) {
    _setState(() {
      _selectedId = text.id;
      _selection = null;
      _comparison = compareText(text.content, text.transcript);
    });
    unawaited(
      Navigator.of(context)
          .push(
            MaterialPageRoute<void>(
              builder: (_) => ValueListenableBuilder<int>(
                valueListenable: _detailPageRevision,
                builder: (context, _, _) {
                  return _buildTextView(_selected ?? text);
                },
              ),
            ),
          )
          .whenComplete(() {
            if (mounted) _setState(() => _selectedId = null);
          }),
    );
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
    _setState(() {
      _expandedSentences.remove(text.id);
      _texts = _texts.where((item) => item.id != text.id).toList();
      if (_selectedId == text.id) _selectedId = null;
    });
    await _saveTexts();
  }

  Future<void> _startRecording({TextSelection? selection}) async {
    try {
      await _stopPlayback();
      if (!await _audioRecorder.hasPermission()) {
        _setState(() => _error = 'Microphone permission denied');
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
      _setState(() {
        _recording = true;
        _selection = selection;
        _recordingSelection = selection;
        _error = null;
      });
    } catch (error) {
      if (mounted) {
        _setState(() => _error = 'Could not start recording: $error');
      }
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      if (!mounted) return;
      final previousPath = _pendingAudioPath;
      _setState(() {
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
        _setState(() {
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
      final player = _playbackPlayer();
      if (_playing) {
        await player.pause();
      } else {
        await player.play(DeviceFileSource(path));
      }
    } catch (error) {
      if (mounted) _setState(() => _error = 'Playback failed: $error');
    }
  }

  AudioPlayer _playbackPlayer() {
    final player = _player ??= AudioPlayer();
    _playerStateSubscription ??= player.onPlayerStateChanged.listen(
      (state) {
        if (mounted) _setState(() => _playing = state == PlayerState.playing);
      },
      onError: (Object error) {
        if (mounted) _setState(() => _error = 'Playback failed: $error');
      },
    );
    return player;
  }

  Future<void> _searchDictionary(String word) async {
    _setState(() {
      _dictionaryLoading.add(word);
      _dictionaryEntries.remove(word);
      _error = null;
    });

    try {
      final entries =
          await (widget.dictionarySearch?.call(word) ??
              searchGaelicDictionary(abairt: word));
      if (!mounted) return;
      _setState(() => _dictionaryEntries[word] = entries);
      for (final entry in entries.where((entry) => entry.hasAudio)) {
        unawaited(_downloadDictionaryAudio(entry));
      }
    } catch (error) {
      if (mounted) {
        _setState(() => _error = 'Dictionary search failed: $error');
      }
    } finally {
      if (mounted) _setState(() => _dictionaryLoading.remove(word));
    }
  }

  Future<File?> _downloadDictionaryAudio(GaelicDictionaryEntry entry) async {
    final future = _dictionaryAudioDownloads.putIfAbsent(entry.id, () async {
      try {
        return await (widget.dictionaryAudioDownloader?.call(entry) ??
            downloadGaelicDictionaryAudio(entry));
      } catch (error) {
        if (mounted) {
          _setState(
            () => _error = 'Could not download dictionary audio: $error',
          );
        }
        return null;
      }
    });
    final file = await future;
    if (file == null) _dictionaryAudioDownloads.remove(entry.id);
    return file;
  }

  Future<void> _playDictionaryAudio(GaelicDictionaryEntry entry) async {
    try {
      final file = await _downloadDictionaryAudio(entry);
      if (file == null) return;
      final audioPlayer = widget.dictionaryAudioPlayer;
      if (audioPlayer != null) {
        await audioPlayer(file);
      } else {
        await _playbackPlayer().play(DeviceFileSource(file.path));
      }
    } catch (error) {
      if (mounted) _setState(() => _error = 'Playback failed: $error');
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
    _setState(() {
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
      _setState(() {
        _texts = _texts
            .map((item) => item.id == text.id ? updated : item)
            .toList();
        _comparison = compareText(updated.content, updated.transcript);
        _selection = null;
      });
      await _saveTexts();
    } catch (error) {
      if (mounted) _setState(() => _error = 'Transcription failed: $error');
    } finally {
      if (await file.exists()) await file.delete();
      if (mounted) {
        _setState(() {
          _pendingAudioPath = null;
          _recordingSelection = null;
          _transcribing = false;
        });
      }
    }
  }

  Future<String> _transcribe(File file) async {
    return transcribeAudio(file);
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
    const buttonPadding = EdgeInsets.fromLTRB(12, 12, 12, 48);
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
    final sentences = _viewMode == _TextViewMode.tree
        ? sentencesFromText(text.content)
        : const <Sentence>[];
    return SavedTextPage(
      text: text,
      onBack: () => Navigator.of(context).pop(),
      onEdit: () => _editText(existing: text),
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
                        value: _TextViewMode.tree,
                        label: Text('Tree'),
                      ),
                      ButtonSegment(
                        value: _TextViewMode.prettyDiff,
                        label: Text('Diff'),
                      ),
                    ],
                    selected: {_viewMode},
                    onSelectionChanged: (selection) {
                      _setState(() => _viewMode = selection.first);
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
                                _setState(() {
                                  _selection = originalSelectionFromDiff(
                                    selection,
                                    prettyDiff.textSpans,
                                    addedTextStyle: addedTextStyle,
                                  );
                                });
                              },
                            )
                          : _viewMode == _TextViewMode.tree
                          ? DefaultTextStyle(
                              style: defaultTextStyle,
                              child: ListView.builder(
                                key: PageStorageKey<String>(
                                  'sentence-tree-${text.id}',
                                ),
                                itemCount: sentences.length,
                                itemBuilder: (context, index) {
                                  final sentence = sentences[index];
                                  final expandedSentences = _expandedSentences
                                      .putIfAbsent(text.id, () => <int>{});
                                  final words = RegExp(r'\S+')
                                      .allMatches(sentence.text);
                                  return ExpansionTile(
                                    key: PageStorageKey<String>(
                                      'sentence-${text.id}-$index-${sentence.text}',
                                    ),
                                    initiallyExpanded: expandedSentences
                                        .contains(index),
                                    onExpansionChanged: (expanded) {
                                      if (expanded) {
                                        expandedSentences.add(index);
                                      } else {
                                        expandedSentences.remove(index);
                                      }
                                    },
                                    title: Text.rich(
                                      TextSpan(
                                        children: sentenceTextSpans(
                                          text.content,
                                          sentence,
                                          _comparison.differences,
                                        ),
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    children: [
                                      for (final word in words) ...[
                                        ListTile(
                                          dense: true,
                                          contentPadding: const EdgeInsets.only(
                                            left: 32,
                                            right: 16,
                                          ),
                                          onTap: () =>
                                              _searchDictionary(word.group(0)!),
                                          title: Text.rich(
                                            TextSpan(
                                              text: word.group(0),
                                              style:
                                                  _comparison.differences.any(
                                                    (difference) =>
                                                        difference.end >
                                                            sentence.start +
                                                                word.start &&
                                                        difference.start <
                                                            sentence.start +
                                                                word.end,
                                                  )
                                                  ? TextStyle(
                                                      backgroundColor:
                                                          Colors.green.shade100,
                                                    )
                                                  : null,
                                            ),
                                          ),
                                        ),
                                        if (_dictionaryLoading.contains(
                                          word.group(0),
                                        ))
                                          const ListTile(
                                            dense: true,
                                            contentPadding: EdgeInsets.only(
                                              left: 48,
                                            ),
                                            title: LinearProgressIndicator(),
                                          ),
                                        for (final entry
                                            in _dictionaryEntries[word.group(
                                                  0,
                                                )] ??
                                                const <GaelicDictionaryEntry>[])
                                          ExpansionTile(
                                            key: PageStorageKey<String>(
                                              'dictionary-${word.group(0)}-${entry.id}',
                                            ),
                                            dense: true,
                                            tilePadding: const EdgeInsets.only(
                                              left: 48,
                                              right: 16,
                                            ),
                                            title: Row(
                                              children: [
                                                Expanded(
                                                  child: Text(entry.headword),
                                                ),
                                                if (entry.hasAudio)
                                                  IconButton(
                                                    tooltip:
                                                        'Play ${entry.headword}',
                                                    onPressed: () =>
                                                        _playDictionaryAudio(
                                                          entry,
                                                        ),
                                                    icon: const Icon(
                                                      Icons.volume_up,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            children: [
                                              ListTile(
                                                dense: true,
                                                contentPadding:
                                                    const EdgeInsets.only(
                                                      left: 64,
                                                      right: 16,
                                                    ),
                                                title: Text(
                                                  'Grammar: ${entry.grammar}',
                                                ),
                                              ),
                                              ListTile(
                                                dense: true,
                                                contentPadding:
                                                    const EdgeInsets.only(
                                                      left: 64,
                                                      right: 16,
                                                    ),
                                                title: Text(
                                                  'IPA: ${entry.ipa}',
                                                ),
                                              ),
                                            ],
                                          ),
                                      ],
                                    ],
                                  );
                                },
                              ),
                            )
                          : SelectableText.rich(
                              TextSpan(
                                style: Theme.of(context).textTheme.bodyLarge
                                    ?.copyWith(height: 1.7),
                                children: spans,
                              ),
                              onSelectionChanged: (selection, cause) {
                                _setState(() {
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
                    _TextViewMode.tree =>
                      '${_comparison.differences.length} difference(s): '
                          'sentences grouped by word.',
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
                  padding: buttonPadding,
                  child: FilledButton.icon(
                    onPressed: _stopRecording,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop recording'),
                  ),
                )
              else if (_pendingAudioPath != null && !_transcribing)
                Padding(
                  padding: buttonPadding,
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
                  padding: buttonPadding,
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
            Positioned.fill(
              child: ColoredBox(
                color: Theme.of(context).colorScheme.surface,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 8),
                      Text('Transcribing…'),
                    ],
                  ),
                ),
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
    return SavedTextsPage(
      texts: _texts,
      error: _error,
      darkMode: widget.darkMode,
      onDarkModeChanged: widget.onDarkModeChanged,
      onErrorDismissed: () => _setState(() => _error = null),
      onAdd: _editText,
      onOpen: _openText,
      onExport: _exportText,
      onDelete: _deleteText,
    );
  }
}

String replaceTranscriptForSelection(
  String original,
  String transcript,
  TextSelection selection,
  String replacement,
) {
  final originalWords = wordsFromText(original);
  final transcriptWords = wordsFromText(transcript);
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
  for (final step in alignWords(originalWords, transcriptWords)) {
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
