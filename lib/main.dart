import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wired_test/pages/home_page.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:wired_test/providers/auth_provider.dart';
import 'package:wired_test/providers/user_provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  // Enable debug paint
  // debugPaintSizeEnabled = true; // Shows the boundaries of your widgets
  // debugPaintBaselinesEnabled = true; // Shows baselines for text
  // debugPaintLayerBordersEnabled = true; // Shows the borders of layers
  // debugPaintPointersEnabled = true; // Shows the touch points
  // debugRepaintRainbowEnabled = true; // Shows repaint areas with a rainbow effect
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()), // Add UserProvider
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      supportedLocales: [
        const Locale('en', ''), // English
        const Locale('zh', ''), // Mandarin (Chinese)
        // Add other locales as needed
      ],
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      title: 'WiRED International',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.white),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'WiRED International'),
      debugShowCheckedModeBanner: false,
      // initialRoute: '/',
      // routes: {
      //   '/': (context) => const MyHomePage(title: 'WiRED International'), // Open to all users
      //   '/restricted': (context) =>  AuthGuard(child: RestrictedPage()), // Restricted page
      //   '/open': (context) => const OpenPage(), // Open to all users
      // },
    );
  }
}


