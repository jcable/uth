import 'package:flutter/material.dart';

import 'text_classes.dart';
import 'text_spans.dart';

class ComparisonTextView extends StatefulWidget {
  const ComparisonTextView({
    super.key,
    required this.originalText,
    required this.comparison,
    required this.onShowDetail,
    required this.onSelectionChanged,
    this.showTranscript = true,
  });

  final String originalText;
  final TextComparison comparison;
  final ValueChanged<TextDifference> onShowDetail;
  final ValueChanged<TextSelection?> onSelectionChanged;
  final bool showTranscript;

  @override
  State<ComparisonTextView> createState() => _ComparisonTextViewState();
}

class _ComparisonTextViewState extends State<ComparisonTextView> {
  final _spanBuilder = ComparisonTextSpanBuilder();
  Color? _transcriptHighlightColor;
  List<TextSpan> _displaySpans = const [];

  @override
  void dispose() {
    _spanBuilder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final originalHighlightColor = isDarkMode
        ? Colors.green.shade900
        : Colors.green.shade100;
    final transcriptHighlightColor = isDarkMode
        ? Colors.red.shade900
        : Colors.red.shade100;
    _transcriptHighlightColor = transcriptHighlightColor;
    final spans = _spanBuilder.build(
      original: widget.originalText,
      comparison: widget.comparison,
      showTranscript: widget.showTranscript,
      originalHighlightColor: originalHighlightColor,
      transcriptHighlightColor: transcriptHighlightColor,
      onShowDetail: widget.onShowDetail,
    );
    _displaySpans = spans;

    return SelectableText.rich(
      TextSpan(
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.7),
        children: spans,
      ),
      onSelectionChanged: (selection, _) {
        widget.onSelectionChanged(_originalSelectionFromDisplay(selection));
      },
    );
  }

  TextSelection? _originalSelectionFromDisplay(TextSelection selection) {
    if (selection.isCollapsed || widget.originalText.isEmpty) return null;

    final baseOffset = _originalOffsetFromDisplay(selection.baseOffset);
    final extentOffset = _originalOffsetFromDisplay(selection.extentOffset);
    if (baseOffset == extentOffset) return null;
    return TextSelection(baseOffset: baseOffset, extentOffset: extentOffset);
  }

  int _originalOffsetFromDisplay(int displayOffset) {
    final transcriptHighlightColor = _transcriptHighlightColor;
    if (transcriptHighlightColor == null) return displayOffset;

    var displayCursor = 0;
    var transcriptLength = 0;
    for (final span in _displaySpans) {
      final segment = span.toPlainText();
      final displayEnd = displayCursor + segment.length;
      final isTranscript =
          span.style?.backgroundColor == transcriptHighlightColor;
      if (displayOffset <= displayEnd) {
        if (isTranscript) {
          transcriptLength += (displayOffset - displayCursor)
              .clamp(0, segment.length)
              .toInt();
        }
        break;
      }
      if (isTranscript) transcriptLength += segment.length;
      displayCursor = displayEnd;
    }

    return displayOffset - transcriptLength;
  }
}
