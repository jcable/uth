# uth

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Tests and coverage

Run the test suite, write an LCOV report, and generate an HTML report with:

```powershell
flutter test --coverage
python tool\coverage_html.py
```

Open `coverage\html\index.html` in a browser. The report includes a project
summary and per-file, line-by-line highlighting. Flutter's `lcov.info` currently
contains line coverage only; function and branch coverage are marked
“Not collected” rather than estimated. The HTML report reads any function or
branch records if they are available in the LCOV input.

Both reports are ignored by Git. Re-run both commands after changing tests or
application code to refresh them.
