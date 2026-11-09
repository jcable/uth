import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'dictionary_search.dart';
import 'saved_text_page.dart';
import 'saved_texts_page.dart';
import 'text_classes.dart';
import 'transcription_service.dart';
import 'comparison_text_view.dart';
import 'sentence_tree_view.dart';

class TranscribePage extends StatefulWidget {
  const TranscribePage({
    super.key,
    this.documentsDirectoryProvider,
    this.dictionarySearch,
    required this.darkMode,
    required this.onDarkModeChanged,
  });

  final Future<Directory> Function()? documentsDirectoryProvider;
  final DictionarySearch? dictionarySearch;
  final bool darkMode;
  final ValueChanged<bool> onDarkModeChanged;

  @override
  State<TranscribePage> createState() => _TranscribePageState();
}

class _TranscribePageState extends State<TranscribePage> {
  AudioRecorder? _recorder;
  AudioPlayer? _player;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  List<SavedText> _texts = [];
  String? _selectedId;
  String? _pendingAudioPath;
  String? _error;
  String _comparisonText = '';
  // Paragraph formatting inserts newlines, so map displayed selections to source offsets.
  List<int> _comparisonSourceOffsets = const [0];
  TextSelection? _selection;
  TextSelection? _recordingSelection;
  TextComparison _comparison = const TextComparison([]);
  bool _loading = true;
  bool _recording = false;
  bool _playing = false;
  bool _transcribing = false;
  bool _showTranscript = true;
  bool _splitParagraphs = false;
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

  void _updateComparisonText(String content, String transcript) {
    final formattedText = _formatComparisonText(content, _splitParagraphs);
    _comparisonText = formattedText.text;
    _comparisonSourceOffsets = formattedText.sourceOffsets;
    _comparison = compareText(_comparisonText, transcript);
  }

  TextSelection? _sourceSelection(TextSelection? selection) {
    if (selection == null) return null;
    return TextSelection(
      baseOffset: _comparisonSourceOffsets[selection.baseOffset],
      extentOffset: _comparisonSourceOffsets[selection.extentOffset],
    );
  }

  @override
  void initState() {
    super.initState();
    _loadTexts();
  }

  @override
  void dispose() {
    _detailPageRevision.dispose();
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

  Future<void> _addText(SavedText text) async {
    _setState(() {
      _texts = [..._texts, text];
    });
    unawaited(_saveTexts());
  }

  Future<void> _updateText(SavedText updated) async {
    _setState(() {
      _texts = _texts
          .map((text) => text.id == updated.id ? updated : text)
          .toList();
      if (_selectedId == updated.id) {
        _updateComparisonText(updated.content, updated.transcript);
        _selection = null;
      }
    });
    await _saveTexts();
  }

  void _setSelectedText(SavedText? text) {
    if (!mounted) return;
    _setState(() {
      _selectedId = text?.id;
      if (text != null) {
        _selection = null;
        _updateComparisonText(text.content, text.transcript);
      }
    });
  }

  Future<void> _updateTexts(List<SavedText> texts) async {
    _setState(() {
      _texts = texts;
      if (!_texts.any((text) => text.id == _selectedId)) {
        _selectedId = null;
      }
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
        _updateComparisonText(updated.content, updated.transcript);
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

  void _showDetail(TextDifference difference, String original) {
    showDialog<void>(
      context: context,
      builder: (context) => SentenceTreeChildrenDialog(
        text: original.substring(difference.start, difference.end),
        dictionarySearch: widget.dictionarySearch,
        playbackPlayer: _playbackPlayer,
      ),
    );
  }

  Widget _buildTextView(SavedText text) {
    final isRecordingSelection = _selection != null && !_selection!.isCollapsed;
    const verticalPadding = 12.0;
    const buttonPadding = EdgeInsets.fromLTRB(12, 12, 12, 48);
    final recordLabel = text.transcript.isEmpty
        ? 'Record'
        : isRecordingSelection
        ? 'Record selected'
        : 'Re-record';
    return SavedTextPage(
      text: text,
      onBack: () => Navigator.of(context).pop(),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    if (text.transcript.isNotEmpty)
                      Expanded(
                        child: SwitchListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                          ),
                          title: const Text('Show transcript'),
                          value: _showTranscript,
                          onChanged: (showTranscript) {
                            _setState(() => _showTranscript = showTranscript);
                          },
                        ),
                      ),
                    Expanded(
                      child: SwitchListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                        ),
                        title: const Text('One sentence per paragraph'),
                        value: _splitParagraphs,
                        onChanged: (splitParagraphs) {
                          _setState(() {
                            _splitParagraphs = splitParagraphs;
                            _updateComparisonText(
                              text.content,
                              text.transcript,
                            );
                            _selection = null;
                          });
                        },
                      ),
                    ),
                  ],
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
                      child: ComparisonTextView(
                        originalText: _comparisonText,
                        comparison: _comparison,
                        onShowDetail: (difference) =>
                            _showDetail(difference, _comparisonText),
                        onSelectionChanged: (selection) {
                          _setState(
                            () => _selection = _sourceSelection(selection),
                          );
                        },
                        showTranscript: _showTranscript,
                      ),
                    ),
                  ),
                ),
              ),
              if (_comparison.differences.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '${_comparison.differences.length} difference(s): '
                    '${_showTranscript ? 'original text followed by transcript text.' : 'transcript text hidden.'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
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
      onAddText: _addText,
      onUpdateText: _updateText,
      onSelectedTextChanged: _setSelectedText,
      detailPageRevision: _detailPageRevision,
      textPageBuilder: (text) => _buildTextView(_selected ?? text),
      onErrorChanged: (error) => _setState(() => _error = error),
      onTextsChanged: _updateTexts,
    );
  }
}

class _FormattedComparisonText {
  const _FormattedComparisonText(this.text, this.sourceOffsets);

  final String text;
  final List<int> sourceOffsets;
}

_FormattedComparisonText _formatComparisonText(
  String text,
  bool splitParagraphs,
) {
  if (!splitParagraphs) {
    return _FormattedComparisonText(
      text,
      List<int>.generate(text.length + 1, (index) => index),
    );
  }

  final sentences = sentencesFromText(text);
  if (sentences.length < 2) {
    return _FormattedComparisonText(
      text,
      List<int>.generate(text.length + 1, (index) => index),
    );
  }

  final formatted = StringBuffer();
  final sourceOffsets = <int>[];

  void appendSourceRange(int start, int end) {
    if (sourceOffsets.isEmpty) {
      sourceOffsets.add(start);
    } else {
      sourceOffsets.last = start;
    }
    formatted.write(text.substring(start, end));
    for (var index = start; index < end; index++) {
      sourceOffsets.add(index + 1);
    }
  }

  appendSourceRange(0, sentences.first.start);
  for (var index = 0; index < sentences.length; index++) {
    final sentence = sentences[index];
    appendSourceRange(sentence.start, sentence.end);
    if (index < sentences.length - 1) {
      final nextStart = sentences[index + 1].start;
      sourceOffsets.last = sentence.end;
      formatted.write('\n\n');
      sourceOffsets
        ..add(sentence.end)
        ..add(nextStart);
    }
  }
  appendSourceRange(sentences.last.end, text.length);

  return _FormattedComparisonText(formatted.toString(), sourceOffsets);
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
  if (endToken == startToken) {
    var insertion = replacement;
    if (startToken < transcriptWords.length) {
      final previousEnd = startToken == 0
          ? 0
          : transcriptWords[startToken - 1].end;
      final whitespace = transcript.substring(previousEnd, start);
      insertion += whitespace.isEmpty ? ' ' : whitespace;
    } else if (start > 0 && !RegExp(r'\s').hasMatch(transcript[start - 1])) {
      insertion = ' $insertion';
    }
    return transcript.replaceRange(start, start, insertion);
  }
  final end = endToken > startToken ? transcriptWords[endToken - 1].end : start;
  return transcript.replaceRange(start, end, replacement);
}
