import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'text_classes.dart';

List<TextSpan> sentenceTextSpans(
  String original,
  Sentence sentence,
  List<TextDifference> differences,
  Color highlightColor,
) {
  final spans = <TextSpan>[];
  var cursor = sentence.start;
  for (final difference in differences) {
    if (difference.start >= sentence.end) break;
    final start = difference.start > sentence.start
        ? difference.start
        : sentence.start;
    final end = difference.end < sentence.end ? difference.end : sentence.end;
    if (start > cursor) {
      spans.add(TextSpan(text: original.substring(cursor, start)));
    }
    if (end > start) {
      spans.add(
        TextSpan(
          text: original.substring(start, end),
          style: TextStyle(backgroundColor: highlightColor),
        ),
      );
      cursor = end;
    }
  }
  if (cursor < sentence.end) {
    spans.add(TextSpan(text: original.substring(cursor, sentence.end)));
  }
  return spans;
}

class ComparisonTextSpanBuilder {
  final _recognizers = <TapGestureRecognizer>[];

  List<TextSpan> build({
    required String original,
    required TextComparison comparison,
    required bool showTranscript,
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
          style: TextStyle(backgroundColor: originalHighlightColor),
          recognizer: recognizer,
        ),
      );
      if (showTranscript && difference.transcript.isNotEmpty) {
        spans.add(
          TextSpan(
            text: difference.transcript,
            style: TextStyle(backgroundColor: transcriptHighlightColor),
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
