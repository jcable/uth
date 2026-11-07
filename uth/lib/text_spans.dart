import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'text_classes.dart';

List<TextSpan> sentenceTextSpans(
  String original,
  Sentence sentence,
  List<TextDifference> differences,
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
          style: TextStyle(backgroundColor: Colors.green.shade100),
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

TextSelection? originalSelectionFromDiff(
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
