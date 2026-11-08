import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uth/pretty_diff_view.dart';

TextSpan? _spanForText(InlineSpan span, String text) {
  if (span is! TextSpan) return null;
  if (span.text == text) return span;
  for (final child in span.children ?? const <InlineSpan>[]) {
    final match = _spanForText(child, text);
    if (match != null) return match;
  }
  return null;
}

void main() {
  testWidgets('renders diff highlights and maps selections to original text', (
    tester,
  ) async {
    TextSelection? selectedText;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: Scaffold(
          body: PrettyDiffView(
            oldText: 'start old end',
            newText: 'start new end',
            onSelectionChanged: (selection) => selectedText = selection,
          ),
        ),
      ),
    );

    final selectable = tester.widget<SelectableText>(
      find.byType(SelectableText),
    );
    final textSpan = selectable.textSpan!;
    expect(textSpan.style?.height, 1.7);
    expect(
      _spanForText(textSpan, 'old')?.style?.backgroundColor,
      Colors.green.shade100,
    );
    expect(
      _spanForText(textSpan, 'new')?.style?.backgroundColor,
      Colors.red.shade100,
    );

    final displayedText = textSpan.toPlainText();
    final originalStart = 'start old end'.indexOf('old');
    final displayedOriginalStart = displayedText.indexOf('old');
    selectable.onSelectionChanged!(
      TextSelection(
        baseOffset: displayedOriginalStart + 1,
        extentOffset: displayedOriginalStart + 3,
      ),
      SelectionChangedCause.tap,
    );
    expect(
      selectedText,
      TextSelection(
        baseOffset: originalStart + 1,
        extentOffset: originalStart + 3,
      ),
    );

    final addedStart = displayedText.indexOf('new');
    selectable.onSelectionChanged!(
      TextSelection(baseOffset: addedStart, extentOffset: addedStart + 2),
      SelectionChangedCause.tap,
    );
    expect(selectedText, isNull);
  });

  testWidgets('uses dark theme highlight colors', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: const Scaffold(
          body: PrettyDiffView(oldText: 'old', newText: 'new'),
        ),
      ),
    );

    final textSpan = tester
        .widget<SelectableText>(find.byType(SelectableText))
        .textSpan!;
    expect(
      _spanForText(textSpan, 'old')?.style?.backgroundColor,
      Colors.green.shade900,
    );
    expect(
      _spanForText(textSpan, 'new')?.style?.backgroundColor,
      Colors.red.shade900,
    );
  });
}
