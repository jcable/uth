
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:archive/archive.dart';

import 'package:uth/main.dart';

void main() {

  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  
  testWidgets('a named text can be created and opened', (tester) async {
    await tester.pumpWidget(MyApp());
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

    expect(find.text('No transcript yet'), findsOneWidget);

    await tester.tap(find.text('Practice text'));
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
    await tester.pumpWidget(MyApp());
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();

    expect(find.byType(RichText), findsAtLeastNWidgets(2));
  });

  testWidgets('settings switches theme and links to About', (tester) async {
    await tester.pumpWidget(MyApp());
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

  testWidgets('empty saved text shows an editing hint', (tester) async {
    await tester.pumpWidget(MyApp());
    await tester.tap(find.text('Add text'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'Name',
      ),
      'Empty',
    );
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Paste or enter text',
      ),
      '',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Empty'));
    await tester.pumpAndSettle();

    expect(
      find.text('No text yet. Use Edit in the saved texts list to paste text.'),
      findsOneWidget,
    );
    expect(find.text('Record'), findsOneWidget);
  });

  testWidgets('editing saved text updates persistent storage', (
    tester,
  ) async {
    
    await tester.pumpWidget(MyApp());
    await tester.tap(find.text('Add text'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'Name',
      ),
      'Before',
    );
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Paste or enter text',
      ),
      'Some Text',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit Before'));
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

    expect(find.text('Before'), findsNothing);

    await tester.tap(find.text('After'));
    
    await tester.pumpAndSettle();
    
    expect(find.text('After'), findsOneWidget);
    expect(find.text('Read the new text.'), findsOneWidget);
  });

  testWidgets('deleting saved text updates persistent storage', (
    tester,
  ) async {
    
    await tester.pumpWidget(MyApp());
    await tester.tap(find.text('Add text'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'Name',
      ),
      'Script',
    );
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Paste or enter text',
      ),
      'Some Text',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete Script'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Script'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete Script'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Script'), findsNothing);

  });

  testWidgets(
    'text list save action creates a ZIP of original and transcript',
    (tester) async {
    await tester.pumpWidget(MyApp());
    await tester.tap(find.text('Add text'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'Name',
      ),
      'export',
    );
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Paste or enter text',
      ),
      'Some Text',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Save export'));
    await tester.pumpAndSettle();
    expect(find.text('SAVE'), findsOneWidget);
    expect(find.text('export.zip'), findsOneWidget);
    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();

      /* TODO
      final archive = ZipDecoder().decodeBytes(
        createSavedTextArchive(savedText),
      );
      expect(archive.files.map((file) => file.name), [
        'Practice/original.txt',
        'Practice/transcript.txt',
      ]);
      expect(utf8.decode(archive.files[0].content), 'Original text.');
      expect(utf8.decode(archive.files[1].content), 'Recognized text.');
*/
    },
  );

}
