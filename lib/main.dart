import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hug/screens/get_started_screen.dart';
import 'package:hug/services/background_trigger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://fyauekwhdylocfzzknjt.supabase.co',
    publishableKey: 'sb_publishable_zcF8B2eQ0F_tHrW_mkKwaw_Vn9fzenf',
  );

  // Background check (every ~15 minutes) and notifications
  await HugBackground.init();

  runApp(const HugApp());

  // If the student opened Hug by tapping Pat's notification, open the chat
  HugBackground.handleLaunchFromNotification();
}

class HugApp extends StatelessWidget {
  const HugApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: HugBackground.navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Hug',
      home: const GetStartedScreen(),
    );
  }
}
