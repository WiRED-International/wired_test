import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wired_test/pages/home_page.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:wired_test/providers/auth_provider.dart';
import 'package:wired_test/providers/user_provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
// import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'l10n/app_localizations.dart';


Future<void> main() async {
  // Enable debug paint
  // debugPaintSizeEnabled = true; // Shows the boundaries of your widgets
  // debugPaintBaselinesEnabled = true; // Shows baselines for text
  // debugPaintLayerBordersEnabled = true; // Shows the borders of layers
  // debugPaintPointersEnabled = true; // Shows the touch points
  // debugRepaintRainbowEnabled = true; // Shows repaint areas with a rainbow effect
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  final authProvider = AuthProvider();
  await authProvider.loadStoredAuthData();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider(create: (_) => UserProvider()), // Add UserProvider
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Locale? _selectedLocale;

  @override
  void initState() {
    super.initState();
    _loadLocale();
  }

  void _loadLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString('locale');
    if (code != null) {
      setState(() {
        _selectedLocale = Locale(code);
      });
    }
  }

  void _changeLocale(Locale locale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('locale', locale.languageCode);
    setState(() {
      _selectedLocale = locale;
    });
  }

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: _selectedLocale,
      supportedLocales: const [
        Locale('en'),
        Locale('zh'),
        Locale('es'),
      ],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      title: 'WiRED International',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.white),
        useMaterial3: true,
      ),
      home: MyHomePage(
        title: 'WiRED International',
        onLocaleChange: _changeLocale,
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}


