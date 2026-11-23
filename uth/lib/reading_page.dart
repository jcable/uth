import 'dart:async';

import 'package:flutter/material.dart';

import 'text_classes.dart';
import 'comparison_text_view.dart';
import 'transcribe_widget.dart';

class SavedTextPage extends StatefulWidget {
  const SavedTextPage({super.key, required this.darkMode, required this.text});

  final bool darkMode;
  final SavedText text;

  @override
  State<SavedTextPage> createState() => _SavedTextPageState();
}

class _SavedTextPageState extends State<SavedTextPage> {
  String _comparisonText = '';
  // Paragraph formatting inserts newlines, so map displayed selections to source offsets.
  List<int> _comparisonSourceOffsets = const [0];
  TextSelection? _selection;
  TextComparison _comparison = const TextComparison([]);
  bool _showTranscript = true;
  bool _splitParagraphs = false;
  final ValueNotifier<int> _detailPageRevision = ValueNotifier<int>(0);
  final verticalPadding = 12.0;
  final buttonPadding = EdgeInsets.fromLTRB(12, 12, 12, 48);
  late SavedText _text;
  bool _transcribing = false;

  @override
  void initState() {
    super.initState();
    _text = widget.text;
    _updateComparisonText(widget.text.content, widget.text.transcript);
  }

  @override
  void dispose() {
    _detailPageRevision.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        tooltip: 'Back to texts',
        onPressed: () {
          Navigator.pop(context, _text);
        },
        icon: const Icon(Icons.arrow_back),
      ),
      title: Text(
        widget.text.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
    body: Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  if (_text.transcript.isNotEmpty)
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
                            _text.content,
                            _text.transcript,
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
                  padding: EdgeInsets.symmetric(
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
            TranscribeWidget(
              recordLabel: recordLabel(_text, _selection),
              onTranscriptionRequested: _handleTranscribing, 
              onTranscriptReturned: _handleTranscript,
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

  void _setState(VoidCallback callback) {
    setState(callback);
    _detailPageRevision.value++;
  }

  String recordLabel(SavedText text, TextSelection? selection) {
    return text.transcript.isEmpty
        ? 'Record'
        : (selection == null || selection.isCollapsed)
        ? 'Re-record'
        : 'Record selected';
  }

  Future<void> _handleTranscribing() async {
    _setState(() {
      _transcribing = true;
    });
  }

  Future<void> _handleTranscript(String transcript) async {
    if (!mounted) return;
    final updatedTranscript = _selection == null
        ? transcript
        : replaceTranscriptForSelection(
            _text.content,
            _text.transcript.isEmpty ? _text.content : _text.transcript,
            _selection!,
            transcript,
          );
    _setState(() {
      _text = _text.copyWith(transcript: updatedTranscript);
      _updateComparisonText(_text.content, _text.transcript);
      _selection = null;
      _transcribing = false;
    });
  }

  void _updateComparisonText(String content, String transcript) {
    final formattedText = formatComparisonText(content, _splitParagraphs);
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
