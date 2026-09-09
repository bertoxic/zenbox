import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'model.dart';
import 'studio.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final store = StudioStore();
  try {
    await store.load();
    runApp(MyApp(store: store));
  } catch (e) {
    runApp(
      MaterialApp(
        theme: studioTheme(),
        home: Scaffold(
          body: EmptyState(
            Icons.folder_off_outlined,
            'Your study workspace could not be opened',
            'Your files have not been overwritten.\n$e',
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.store});
  final StudioStore store;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<StudioSettings>(
    valueListenable: studioSettingsNotifier,
    builder: (context, settings, _) => MaterialApp(
      title: 'Zenbox — Study & Knowledge Workspace',
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      debugShowCheckedModeBanner: false,
      theme: studioTheme(settings),
      home: Studio(store: store),
    ),
  );
}
