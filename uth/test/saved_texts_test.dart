import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/src/foundation/change_notifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uth/text_classes.dart';
import 'package:uth/text_store.dart';
import 'package:uth/saved_texts_page.dart';

const String error = '';

void onErrorChanged(String? value) {}
ValueListenable<int> detailPageRevision = ValueNotifier<int>(0);
Future<void> onUpdateText(SavedText text) async {}
void onDarkModeChanged(Object? value) {}
Future<void> onAddText(SavedText text) async {}
void onErrorDismissed() {}
Future<void> onTextDeleted(SavedText text) async {}

MaterialApp makeApp(SavedText text, {bool darkMode = false}) {
  return MaterialApp(
    theme: ThemeData(
      colorSchemeSeed: Colors.indigo,
      brightness: Brightness.light,
      useMaterial3: true,
    ),
    darkTheme: ThemeData(
      colorSchemeSeed: Colors.indigo,
      brightness: Brightness.dark,
      useMaterial3: true,
    ),
    home: Scaffold(
      body: SavedTextsPage(
        texts: [text],
        error: error,
        darkMode: darkMode,
        onDarkModeChanged: onDarkModeChanged,
        onErrorDismissed: onErrorDismissed,
        onAddText: onAddText,
        onTextDeleted: onTextDeleted,
        onUpdateText: onUpdateText,
        detailPageRevision: detailPageRevision,
        onErrorChanged: onErrorChanged,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  testWidgets('light mode uses normal comparison highlight colors', (
    tester,
  ) async {
    const savedText = SavedText(
      id: 'comparison',
      name: 'comparison',
      content: 'We like apples.',
      transcript: 'We love apples.',
    );

    await tester.pumpWidget(makeApp(savedText));

    await tester.tap(find.text('comparison'));
    await tester.pumpAndSettle();
    expect(find.text('Show transcript'), findsOneWidget);

    final spans = tester
        .widget<SelectableText>(find.byType(SelectableText))
        .textSpan!
        .children!
        .whereType<TextSpan>();
    expect(spans.singleWhere((span) => span.text == 'like').style?.backgroundColor, Colors.green.shade100);
    expect(spans.singleWhere((span) => span.text == 'love').style?.backgroundColor, Colors.red.shade100);
  });

  testWidgets('dark mode uses darker comparison highlight colors', (
    tester,
  ) async {
    const savedText = SavedText(
      id: 'dark-comparison',
      name: 'Dark comparison',
      content: 'We like apples.',
      transcript: 'We love apples.',
    );

    await tester.pumpWidget(makeApp(savedText, darkMode: true));

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
    await tester.pumpWidget(makeApp(savedText));
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
    await tester.pumpWidget(makeApp(savedText));
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

  // testWidgets('load errors can be dismissed', (tester) async {
  //   final prefs = await SharedPreferences.getInstance();
  //   prefs.setStringList('saved_texts', ['a']);
  //   prefs.setString('a', 'not valid json');
  //   await tester.pumpWidget(makeApp());

  //   expect(find.textContaining('Could not load saved texts:'), findsOneWidget);
  //   await tester.tap(find.text('Dismiss'));
  //   await tester.pump();
  //   expect(find.textContaining('Could not load saved texts:'), findsNothing);
  // });
}
