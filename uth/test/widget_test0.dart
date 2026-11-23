import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uth/main.dart';
import 'package:uth/text_classes.dart';
import 'package:uth/saved_texts_page.dart';
import 'package:uth/text_store.dart';

void main() {

  testWidgets('dark mode uses darker comparison highlight colors', (
    tester,
  ) async {
    const savedText = SavedText(
      id: 'dark-comparison',
      name: 'Dark comparison',
      content: 'We like apples.',
      transcript: 'We love apples.',
    );
    await saveTexts([savedText]);
    await _pumpApp(tester);

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark mode'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Dark comparison'));
    await tester.pumpAndSettle();
    expect(find.text('Show transcript'), findsOneWidget);

    final spans = tester
        .widget<SelectableText>(find.byType(SelectableText))
        .textSpan!
        .children!
        .whereType<TextSpan>();
    expect(
      spans.singleWhere((span) => span.text == 'like').style?.backgroundColor,
      Colors.green.shade900,
    );
    expect(
      spans.singleWhere((span) => span.text == 'love').style?.backgroundColor,
      Colors.red.shade900,
    );
  });

  testWidgets('comparison views show original and transcript differences', (
    tester,
  ) async {
    const savedText = SavedText(
      id: 'comparison',
      name: 'Comparison',
      content: 'We like green apples.',
      transcript: 'We love green apples.',
    );
    await saveTexts([savedText]);
    await _pumpApp(tester);
    await tester.tap(find.text('Comparison'));
    await tester.pumpAndSettle();

    expect(find.text('Show transcript'), findsOneWidget);
    var selectable = tester.widget<SelectableText>(find.byType(SelectableText));
    final spans = selectable.textSpan!.children!.whereType<TextSpan>().toList();
    expect(
      spans.map((span) => span.toPlainText()).join(),
      'We likelove green apples.',
    );
    expect(spans.first.style?.backgroundColor, isNull);
    expect(
      spans.singleWhere((span) => span.text == 'like').style?.backgroundColor,
      Colors.green.shade100,
    );
    expect(
      spans.singleWhere((span) => span.text == 'love').style?.backgroundColor,
      Colors.red.shade100,
    );
    expect(spans.last.style?.backgroundColor, isNull);

    await tester.tap(find.text('Show transcript'));
    await tester.pump();
    selectable = tester.widget<SelectableText>(find.byType(SelectableText));
    final hiddenSpans = selectable.textSpan!.children!
        .whereType<TextSpan>()
        .toList();
    expect(
      hiddenSpans.map((span) => span.toPlainText()).join(),
      'We like green apples.',
    );
    expect(hiddenSpans.any((span) => span.text == 'love'), isFalse);
    expect(hiddenSpans.singleWhere((span) => span.text == 'like'), isNotNull);
    selectable.onSelectionChanged!(
      const TextSelection(baseOffset: 4, extentOffset: 6),
      SelectionChangedCause.longPress,
    );
    await tester.pump();
    expect(find.text('Record selected'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('sentence splitting separates original text into paragraphs', (
    tester,
  ) async {
    const savedText = SavedText(
      id: 'split-sentences',
      name: 'Sentences',
      content: 'First sentence. Second sentence!',
      transcript: 'First sentence. Second sentence!',
    );
    await saveTexts([savedText]);
    await _pumpApp(tester);
    await tester.tap(find.text('Sentences'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('One sentence per paragraph'));
    await tester.pumpAndSettle();

    final selectable = tester.widget<SelectableText>(
      find.byType(SelectableText),
    );
    expect(
      selectable.textSpan!.toPlainText(),
      'First sentence.\n\nSecond sentence!',
    );
  });

  testWidgets('long pressing a difference opens its detail popup', (
    tester,
  ) async {
    const savedText = SavedText(
      id: 'difference-detail',
      name: 'Difference detail',
      content: 'We like green apples.',
      transcript: 'We love green apples.',
    );
    await saveTexts([savedText]);
    await _pumpApp(tester);
    await tester.tap(find.text('Difference detail'));
    await tester.pumpAndSettle();

    final spans = tester
        .widget<SelectableText>(find.byType(SelectableText))
        .textSpan!
        .children!
        .whereType<TextSpan>();
    (spans.singleWhere((span) => span.text == 'like').recognizer!
            as LongPressGestureRecognizer)
        .onLongPress!();
    await tester.pumpAndSettle();
  });

  testWidgets('load errors can be dismissed', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setStringList('saved_texts', ['a']);
    prefs.setString('a', 'not valid json');
    await _pumpApp(tester);

    expect(find.textContaining('Could not load saved texts:'), findsOneWidget);
    await tester.tap(find.text('Dismiss'));
    await tester.pump();
    expect(find.textContaining('Could not load saved texts:'), findsNothing);
  });
}

Future<void> _pumpApp(WidgetTester tester, {Widget? app}) async {
  await tester.pumpWidget(app ?? MyApp());
  for (
    var attempt = 0;
    attempt < 10 &&
        find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
    attempt++
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
  expect(find.byType(CircularProgressIndicator), findsNothing);
}
