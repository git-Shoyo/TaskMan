import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'layouts/responsive_layout.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const TaskMan());
}

class TaskMan extends StatelessWidget {
  const TaskMan({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TaskMan',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const ResponsiveLayout(),
    );
  }
}
