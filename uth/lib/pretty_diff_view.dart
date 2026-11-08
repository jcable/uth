import 'package:flutter/material.dart';
import 'package:pretty_diff_text/pretty_diff_text.dart';

class PrettyDiffView extends StatelessWidget {
  const PrettyDiffView({
    super.key,
    required this.oldText,
    required this.newText,
    this.onSelectionChanged,
  });

  final String oldText;
  final String newText;
  final ValueChanged<TextSelection?>? onSelectionChanged;

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final originalHighlightColor = isDarkMode
        ? Colors.green.shade900
        : Colors.green.shade100;
    final transcriptHighlightColor = isDarkMode
        ? Colors.red.shade900
        : Colors.red.shade100;
    final defaultTextStyle =
        Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.7) ??
        const TextStyle(height: 1.7);
    final addedTextStyle = TextStyle(backgroundColor: transcriptHighlightColor);
    final diff = PrettyDiffText(
      oldText: oldText,
      newText: newText,
      defaultTextStyle: defaultTextStyle,
      deletedTextStyle: TextStyle(backgroundColor: originalHighlightColor),
      addedTextStyle: addedTextStyle,
    );

    return SelectableText.rich(
      TextSpan(style: defaultTextStyle, children: diff.textSpans),
      onSelectionChanged: (selection, _) {
        onSelectionChanged?.call(
          _originalSelectionFromDiff(
            selection,
            diff.textSpans,
            addedTextStyle: addedTextStyle,
          ),
        );
      },
    );
  }
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
