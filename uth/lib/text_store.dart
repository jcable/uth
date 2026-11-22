import 'package:shared_preferences/shared_preferences.dart';
import 'text_classes.dart';

Future<List<SavedText>?> loadTexts() async {
  final prefs = await SharedPreferences.getInstance();
  final List<String>? keys = prefs.getStringList('saved_texts');
  if (keys != null) { 
    return keys.map((key) => SavedText.fromJson(prefs.getString(key)??'')).toList();
  }
  return null;
}

Future<void> saveTexts(List<SavedText> texts) async {
  final prefs = await SharedPreferences.getInstance();
  prefs.setStringList('saved_texts', texts.map((st) => st.name).toList());
  for (final text in texts) {
    prefs.setString(text.name, text.toJson());
  }
}