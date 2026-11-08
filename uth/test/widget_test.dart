import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uth/main.dart';
import 'package:uth/text_classes.dart';
import 'package:uth/text_spans.dart';
import 'package:uth/transcribe_page.dart';
import 'package:uth/saved_texts_page.dart';

const original = """
Am biodhte ann a bhiodh iad sàbhailte?

’S dòcha rachadh iad thall an Ungair. B’ àbhaist dhaibh toilichte ann.

Bha bàta ga dhèanamh deiseil dhaibh.

Dh’fhalbh iad Northumbria ach cha do ràinig am bàta an Roinn Eòrpa. Shèid stoirm am bàta gu tìr ann an Alba.

B’ e fògarraich a bh’ aca. Cha robh Gàidhlig aca. Dè nam biodh iad an glacadh agus an reic mar thràillean?

Cha robh feum aca a bhith dragh orra.

Bha an clann Sasannach a thaobh athar agus bha an teaghlach air a bhith a’ fuireach ann an Sasainn airson còrr is deich bliadhna. Bha Beurla math aca. Bha beurla math aig mòran Gàidheil cuideachd.
""";

const transcript =
    "nam biodh to ann a bhiodh iad sàbhailte s dè s dòcha rachad air thall an ungair b' àbhaist dhaibh toilichte ann bha bàta ga dhìon air deiseil dhaibh dh'fhalbh iad notumbria agus cha robh ràinig am bàta ann an roinn europa thèid stoirm am bàta gu tìr an alba b e fògarraich a bha aga cha robh gàidhlig aca jane and biggie air an glagadh agus an reic mu chroillidhean cha robh feum agaibh a bhith a dragh oirre bha an clann sasannach a thaobh atha agus bha an t-eagalach air a bhith a fuireach ann an sasainn airson còrr is deich";

void main() {
  late Directory documentsDirectory;

  setUp(() async {
    documentsDirectory = await Directory.systemTemp.createTemp('uth-test-');
  });

  test('saved texts round-trip and retain backward compatibility', () {
    const savedText = SavedText(
      id: 'one',
      name: 'Practice',
      content: 'Read this.',
      transcript: 'Read that.',
    );

    expect(SavedText.fromJson(savedText.toJson()).toJson(), savedText.toJson());
    expect(
      SavedText.fromJson({
        'id': 'legacy',
        'name': 'Legacy',
        'content': 'Old format',
      }).transcript,
      isEmpty,
    );
    expect(savedText.copyWith(name: 'Updated').toJson(), {
      'id': 'one',
      'name': 'Updated',
      'content': 'Read this.',
      'transcript': 'Read that.',
    });
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

  test('comparison reports deleted and inserted words', () {
    final deleted = compareText('Say hello, then go.', 'Say then go.');
    expect(deleted.differences, hasLength(1));
    expect(deleted.differences.single.transcript, isEmpty);

    final inserted = compareText('Say hello.', 'Say hello there.');
    expect(inserted.differences, hasLength(1));
    expect(inserted.differences.single.transcript, 'there.');
  });

  test('comparison anchors inserted words at their position in the text', () {
    const text = 'one two three four';
    final comparison = compareText(text, 'one extra two three another four');

    expect(
      comparison.differences
          .map((difference) => text.substring(difference.start, difference.end))
          .toList(),
      ['two', 'four'],
    );
  });

  test('reveal spans preserve the original text for multiple insertions', () {
    final spanBuilder = ComparisonTextSpanBuilder();
    addTearDown(spanBuilder.dispose);
    final spans = spanBuilder.build(
      original: original,
      comparison: compareText(original, transcript),
      showTranscript: false,
      originalHighlightColor: Colors.green,
      transcriptHighlightColor: Colors.red,
    );

    expect(spans.map((span) => span.toPlainText()).join(), original);
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

  test(
    'a selected section is replaced in a transcript with different words',
    () {
      final transcript = replaceTranscriptForSelection(
        'I say hello there.',
        'I say hi there.',
        const TextSelection(baseOffset: 6, extentOffset: 11),
        'goodbye',
      );

      expect(transcript, 'I say goodbye there.');
    },
  );

  test('re-recording rejects a selection that contains no words', () {
    expect(
      () => replaceTranscriptForSelection(
        'Read this text.',
        'Read this text.',
        const TextSelection.collapsed(offset: 5),
        'that',
      ),
      throwsFormatException,
    );
  });

  testWidgets('a named text can be created and opened', (tester) async {
    await _pumpApp(tester, documentsDirectory);

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

  testWidgets('the app menu opens the About page', (tester) async {
    await _pumpApp(tester, documentsDirectory);

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();

    expect(find.byType(RichText), findsAtLeastNWidgets(2));
  });

  testWidgets('settings switches theme and links to About', (tester) async {
    await _pumpApp(tester, documentsDirectory);

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(
      Theme.of(tester.element(find.text('Dark mode'))).brightness,
      Brightness.light,
    );
    expect(find.byType(SwitchListTile), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(
      Theme.of(tester.element(find.text('Dark mode'))).brightness,
      Brightness.dark,
    );

    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();
    expect(find.text('About'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNothing);
  });

  testWidgets('dark mode uses darker comparison highlight colors', (
    tester,
  ) async {
    await _writeSavedTexts(
      tester,
      documentsDirectory,
      jsonEncode([
        {
          'id': 'dark-comparison',
          'name': 'Dark comparison',
          'content': 'We like apples.',
          'transcript': 'We love apples.',
        },
      ]),
    );
    await _pumpApp(tester, documentsDirectory);

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
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
    await _writeSavedTexts(
      tester,
      documentsDirectory,
      jsonEncode([
        {
          'id': 'comparison',
          'name': 'Comparison',
          'content': 'We like green apples.',
          'transcript': 'We love green apples.',
        },
      ]),
    );
    await _pumpApp(tester, documentsDirectory);
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

    await tester.tap(find.byType(Switch));
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

  testWidgets('tapping a difference opens its detail popup', (tester) async {
    await _writeSavedTexts(
      tester,
      documentsDirectory,
      jsonEncode([
        {
          'id': 'difference-detail',
          'name': 'Difference detail',
          'content': 'We like green apples.',
          'transcript': 'We love green apples.',
        },
      ]),
    );
    await _pumpApp(tester, documentsDirectory);
    await tester.tap(find.text('Difference detail'));
    await tester.pumpAndSettle();

    final spans = tester
        .widget<SelectableText>(find.byType(SelectableText))
        .textSpan!
        .children!
        .whereType<TextSpan>();
    (spans.singleWhere((span) => span.text == 'like').recognizer!
            as TapGestureRecognizer)
        .onTap!();
    await tester.pumpAndSettle();

    final popup = find.byType(AlertDialog);
    expect(popup, findsOneWidget);
    expect(
      find.descendant(of: popup, matching: find.text('like')),
      findsWidgets,
    );
    expect(
      find.descendant(of: popup, matching: find.text('Close')),
      findsOneWidget,
    );
  });

  testWidgets('load errors can be dismissed', (tester) async {
    await _writeSavedTexts(tester, documentsDirectory, 'not valid json');
    await _pumpApp(tester, documentsDirectory);

    expect(find.textContaining('Could not load saved texts:'), findsOneWidget);
    await tester.tap(find.text('Dismiss'));
    await tester.pump();
    expect(find.textContaining('Could not load saved texts:'), findsNothing);
  });

  testWidgets(
    'text list save action creates a ZIP of original and transcript',
    (tester) async {
      await _writeSavedTexts(
        tester,
        documentsDirectory,
        jsonEncode([
          {
            'id': 'export',
            'name': 'Practice',
            'content': 'Original text.',
            'transcript': 'Recognized text.',
          },
        ]),
      );
      await _pumpApp(tester, documentsDirectory);

      expect(find.byTooltip('Save Practice'), findsOneWidget);
      expect(find.byTooltip('Delete Practice'), findsOneWidget);
      const savedText = SavedText(
        id: 'export',
        name: 'Practice',
        content: 'Original text.',
        transcript: 'Recognized text.',
      );
      final archive = ZipDecoder().decodeBytes(
        createSavedTextArchive(savedText),
      );
      expect(archive.files.map((file) => file.name), [
        'Practice/original.txt',
        'Practice/transcript.txt',
      ]);
      expect(utf8.decode(archive.files[0].content), 'Original text.');
      expect(utf8.decode(archive.files[1].content), 'Recognized text.');
    },
  );

  testWidgets('editing and deleting saved text updates persistent storage', (
    tester,
  ) async {
    await _writeSavedTexts(
      tester,
      documentsDirectory,
      jsonEncode([
        {
          'id': 'saved',
          'name': 'Before',
          'content': 'Read the old text.',
          'transcript': 'Read the old text.',
        },
      ]),
    );
    await _pumpApp(tester, documentsDirectory);

    await tester.tap(find.text('Before'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit name or text'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'Name',
      ),
      'After',
    );
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Paste or enter text',
      ),
      'Read the new text.',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );

    await tester.tap(find.byTooltip('Back to texts'));
    await tester.pumpAndSettle();
    expect(find.text('After'), findsOneWidget);
    expect(find.text('Transcript saved'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete After'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('After'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete After'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('After'), findsNothing);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    final savedContents = await tester.runAsync(
      () => File('${documentsDirectory.path}/saved_texts.json').readAsString(),
    );
    expect(savedContents, isNotNull);
    expect(jsonDecode(savedContents!), isEmpty);
  });

  testWidgets('empty saved text shows an editing hint', (tester) async {
    await _writeSavedTexts(
      tester,
      documentsDirectory,
      jsonEncode([
        {'id': 'empty', 'name': 'Empty', 'content': '', 'transcript': ''},
      ]),
    );
    await _pumpApp(tester, documentsDirectory);
    await tester.tap(find.text('Empty'));
    await tester.pumpAndSettle();

    expect(find.text('No text yet. Use Edit to paste text.'), findsOneWidget);
    expect(find.text('Record'), findsOneWidget);
  });
}

Future<void> _pumpApp(
  WidgetTester tester,
  Directory documentsDirectory, {
  Widget? app,
}) async {
  await tester.pumpWidget(
    app ?? MyApp(documentsDirectoryProvider: () async => documentsDirectory),
  );
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

Future<void> _writeSavedTexts(
  WidgetTester tester,
  Directory documentsDirectory,
  String contents,
) async {
  await tester.runAsync(() async {
    await File('${documentsDirectory.path}/saved_texts.json')
        .writeAsString(contents);
  });
}
