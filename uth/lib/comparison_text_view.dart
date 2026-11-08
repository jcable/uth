import 'package:flutter/material.dart';

import 'text_classes.dart';
import 'text_spans.dart';

class ComparisonTextView extends StatefulWidget {
  const ComparisonTextView({
    super.key,
    required this.originalText,
    required this.comparison,
    required this.onDifferenceTap,
    required this.onSelectionChanged,
    this.showTranscript = true,
  });

  final String originalText;
  final TextComparison comparison;
  final ValueChanged<TextDifference> onDifferenceTap;
  final ValueChanged<TextSelection?> onSelectionChanged;
  final bool showTranscript;

  @override
  State<ComparisonTextView> createState() => _ComparisonTextViewState();
}

class _ComparisonTextViewState extends State<ComparisonTextView> {
  final _spanBuilder = ComparisonTextSpanBuilder();

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
    final spans = _spanBuilder.build(
      original: widget.originalText,
      comparison: widget.comparison,
      showTranscript: widget.showTranscript,
      revealColor: Theme.of(context).colorScheme.errorContainer,
      revealUnderlineColor: Theme.of(context).colorScheme.error,
      originalHighlightColor: originalHighlightColor,
      transcriptHighlightColor: transcriptHighlightColor,
      onDifferenceTap: widget.onDifferenceTap,
    );

    return SelectableText.rich(
      TextSpan(
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.7),
        children: spans,
      ),
      onSelectionChanged: (selection, _) {
        widget.onSelectionChanged(selection.isCollapsed ? null : selection);
      },
    );
  }
}
