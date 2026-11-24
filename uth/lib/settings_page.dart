import 'package:flutter/material.dart';

import 'about_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.onDarkModeChanged,
  });

  final ValueChanged<bool> onDarkModeChanged;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: ListView(
      children: [
        SwitchListTile(
          title: const Text('Dark mode'),
          value: Theme.of(context).brightness == Brightness.dark,
          onChanged: (value) {
            widget.onDarkModeChanged(value);
          },
        ),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('About'),
          onTap: () {
            Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const AboutPage()));
          },
        ),
      ],
    ),
  );
}
