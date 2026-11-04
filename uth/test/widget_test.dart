import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uth/main.dart';

void main() {
  late Directory documentsDirectory;

  setUp(() async {
    documentsDirectory = await Directory.systemTemp.createTemp('uth-test-');
  });

  test('comparison reports no differences before a transcript exists', () {
    final comparison = compareText('Read this original text.', '');

    expect(comparison.matches, isTrue);
    expect(comparison.differences, isEmpty);
  });

  test('comparison ignores case, whitespace, and supported punctuation', () {
    final comparison = compareText(
      'Hello, world! Are you ready?',
      'hello  world. Are you ready!',
    );

    expect(comparison.matches, isTrue);
  });

  test('comparison returns the recognized text for a discrepancy', () {
    final comparison = compareText(
      'Say hello, then go.',
      'Say goodbye, then go.',
    );

    expect(comparison.differences, hasLength(1));
    expect(comparison.differences.single.transcript, 'goodbye,');
  });

  test('a selected section can be replaced in the saved transcript', () {
    final transcript = replaceTranscriptForSelection(
      'I say hello there.',
      'I say hello there.',
      const TextSelection(baseOffset: 6, extentOffset: 11),
      'goodbye',
    );

    expect(transcript, 'I say goodbye there.');
  });

  testWidgets('a named text can be created and opened', (tester) async {
    await tester.pumpWidget(
      MyApp(documentsDirectoryProvider: () async => documentsDirectory),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();

    await tester.tap(find.text('Add text'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'Name',
      ),
      'Practice text',
    );
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Paste or enter text',
      ),
      'Read this sentence.',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Practice text'), findsOneWidget);
    expect(find.text('Read this sentence.'), findsOneWidget);
    expect(find.text('Record'), findsOneWidget);
    expect(find.text('Record selected section'), findsNothing);

    await tester.tap(find.text('Practice text'));
    await tester.pumpAndSettle();

    expect(
      find.ancestor(
        of: find.byType(SelectableText),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration! as BoxDecoration).border != null,
        ),
      ),
      findsOneWidget,
    );

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('combined view shows original then transcript differences', (
    tester,
  ) async {
    await File('${documentsDirectory.path}/saved_texts.json').writeAsString(
      jsonEncode([
        {
          'id': 'comparison',
          'name': 'Comparison',
          'content': 'We like green apples.',
          'transcript': 'We love green apples.',
        },
      ]),
    );
    await tester.pumpWidget(
      MyApp(documentsDirectoryProvider: () async => documentsDirectory),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    await tester.tap(find.text('Comparison'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Combined'));
    await tester.pumpAndSettle();

    var selectable = tester.widget<SelectableText>(find.byType(SelectableText));
    var spans = selectable.textSpan!.children!.whereType<TextSpan>().toList();
    expect(
      spans.map((span) => span.toPlainText()).join(),
      'We like love green apples.',
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

    await tester.tap(find.text('Original'));
    await tester.pumpAndSettle();
    selectable = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(selectable.textSpan!.toPlainText(), 'We like green apples.');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
