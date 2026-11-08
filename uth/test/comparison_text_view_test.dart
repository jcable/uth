import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uth/comparison_text_view.dart';
import 'package:uth/text_classes.dart';

void main() {
  testWidgets('renders differences and handles taps and text selection', (
    tester,
  ) async {
    const difference = TextDifference(start: 3, end: 7, transcript: 'love');
    TextDifference? tappedDifference;
    TextSelection? selectedText;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: Scaffold(
          body: ComparisonTextView(
            originalText: 'We like apples.',
            comparison: const TextComparison([difference]),
            onDifferenceTap: (value) => tappedDifference = value,
            onSelectionChanged: (value) => selectedText = value,
          ),
        ),
      ),
    );

    final selectable = tester.widget<SelectableText>(
      find.byType(SelectableText),
    );
    final spans = selectable.textSpan!.children!.whereType<TextSpan>().toList();
    expect(selectable.textSpan!.style?.height, 1.7);
    expect(
      spans.map((span) => span.toPlainText()).join(),
      'We likelove apples.',
    );
    expect(
      spans.singleWhere((span) => span.text == 'like').style?.backgroundColor,
      Colors.green.shade100,
    );
    expect(
      spans.singleWhere((span) => span.text == 'love').style?.backgroundColor,
      Colors.red.shade100,
    );

    (spans.singleWhere((span) => span.text == 'like').recognizer!
            as TapGestureRecognizer)
        .onTap!();
    expect(tappedDifference, same(difference));

    selectable.onSelectionChanged!(
      const TextSelection(baseOffset: 4, extentOffset: 6),
      SelectionChangedCause.longPress,
    );
    expect(selectedText, const TextSelection(baseOffset: 4, extentOffset: 6));

    selectable.onSelectionChanged!(
      const TextSelection.collapsed(offset: 4),
      SelectionChangedCause.longPress,
    );
    expect(selectedText, isNull);
  });

  testWidgets('uses darker difference highlights in dark mode', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: ComparisonTextView(
            originalText: 'old text',
            comparison: const TextComparison([
              TextDifference(start: 0, end: 3, transcript: 'new'),
            ]),
            onDifferenceTap: (_) {},
            onSelectionChanged: (_) {},
          ),
        ),
      ),
    );

    final spans = tester
        .widget<SelectableText>(find.byType(SelectableText))
        .textSpan!
        .children!
        .whereType<TextSpan>();
    expect(
      spans.singleWhere((span) => span.text == 'old').style?.backgroundColor,
      Colors.green.shade900,
    );
    expect(
      spans.singleWhere((span) => span.text == 'new').style?.backgroundColor,
      Colors.red.shade900,
    );
  });

  testWidgets('can hide transcript text and reveal the original difference', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: Scaffold(
          body: ComparisonTextView(
            originalText: 'We like apples.',
            comparison: const TextComparison([
              TextDifference(start: 3, end: 7, transcript: 'love'),
            ]),
            onDifferenceTap: (_) {},
            onSelectionChanged: (_) {},
            showTranscript: false,
          ),
        ),
      ),
    );

    final spans = tester
        .widget<SelectableText>(find.byType(SelectableText))
        .textSpan!
        .children!
        .whereType<TextSpan>()
        .toList();
    expect(spans.map((span) => span.toPlainText()).join(), 'We like apples.');

    final revealedOriginal = spans.singleWhere((span) => span.text == 'like');
    expect(
      revealedOriginal.style?.backgroundColor,
      ThemeData.light().colorScheme.errorContainer,
    );
    expect(revealedOriginal.style?.decoration, TextDecoration.underline);
  });
}
