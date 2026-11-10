import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  late final Future<String> _aboutText = rootBundle.loadString(
    'assets/about.md',
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('About')),
    body: FutureBuilder<String>(
      future: _aboutText,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: Text('Loading About content...'));
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Unable to load About content: ${snapshot.error}'),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: Text('About content is unavailable.'));
        }
        return Markdown(
          data: snapshot.data!,
          padding: const EdgeInsets.all(24),
          onTapLink: (String text, String? href, String title) {
            if (href != null) {
              launchUrl(Uri.parse(href));
            }
          },
        );
      },
    ),
  );
}
