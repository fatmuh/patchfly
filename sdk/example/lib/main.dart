// Example Flutter app showing how to use the Patchfly SDK.
//
// To try:
//   1. Create a Flutter app
//   2. Add patchfly to pubspec.yaml
//   3. Add the Android platform integration (see android/app/src/main/...)
//   4. Copy the relevant parts of this main.dart
//   5. Run `flutter run` on a real Android device

import 'package:flutter/material.dart';
import 'package:patchfly/patchfly.dart';

const String _serverUrl = 'https://updates.example.com';
const String _sdkKey = 'pfk_...'; // from `patchfly apps create`

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Patchfly.init(
      serverUrl: _serverUrl,
      sdkKey: _sdkKey,
      channel: 'stable',
      verbose: true,
    );

    // Check for an update before showing the UI. You might also do this
    // in the background after the UI loads.
    final update = await Patchfly.instance.checkForUpdate();
    if (update != null) {
      debugPrint('Update available: ${update.releaseVersion}');
      // In production, show a "Update available" dialog before applying.
      // For demo, we apply immediately.
      try {
        final path = await Patchfly.instance.download(update);
        await Patchfly.instance.apply(path);
        // After apply(), the app will be restarted by the platform code
        // with the new Dart code. The call below will not return in that
        // case.
      } on PatchflyException catch (e) {
        debugPrint('Update failed: $e');
      }
    }
  } catch (e) {
    debugPrint('Patchfly init error: $e');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Patchfly Demo',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Patchfly Demo')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Hello, Patchfly!'),
            const SizedBox(height: 16),
            Text('Local patch: ${Patchfly.instance.localPatchPath ?? "(none)"}'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                final update = await Patchfly.instance.checkForUpdate();
                if (update == null) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('No update available')),
                    );
                  }
                  return;
                }
                final path = await Patchfly.instance.download(update);
                await Patchfly.instance.apply(path);
              },
              child: const Text('Check for update'),
            ),
          ],
        ),
      ),
    );
  }
}
