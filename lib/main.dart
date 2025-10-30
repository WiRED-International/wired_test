import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wired_test/pages/home_page.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:wired_test/providers/auth_provider.dart';
import 'package:wired_test/providers/user_provider.dart';
import 'package:wired_test/providers/quiz_score_provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive_flutter/hive_flutter.dart';
// import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'services/exam_sync_service.dart';
import 'services/retry_queue_service.dart';
import 'state/exam_controller.dart';
import 'models/exam_models.dart';
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

  // Initialize Hive and open exam boxes
  await Hive.initFlutter();

  // 🧹 DEV ONLY: Clear Hive boxes to avoid schema mismatch after model changes
  // ----------------------------------------------------------
  const bool clearBoxesForDev = false; // ✅ set to false for production
  if (clearBoxesForDev) {
    await Hive.deleteBoxFromDisk('exam_attempts');
    await Hive.deleteBoxFromDisk('examBox');
    await Hive.deleteBoxFromDisk('retry_queue');
    debugPrint('🧹 Cleared Hive boxes for development');
  }
  // ----------------------------------------------------------

  // Register Hive adapters
  Hive.registerAdapter(ExamAttemptAdapter());
  Hive.registerAdapter(AnswerRecordAdapter());
  Hive.registerAdapter(PendingSubmissionAdapter());

  final attemptsBox = await Hive.openBox<ExamAttempt>('exam_attempts');
  final retryBox = await Hive.openBox<PendingSubmission>('retry_queue');
  final examBox = await Hive.openBox('examBox');

  // // 🧹 TEMP FIX: clear corrupted quiz_scores from FlutterSecureStorage
  // // ----------------------------------------------------------
  // final secureStorage = const FlutterSecureStorage();
  // await secureStorage.delete(key: "pending_quiz_scores");
  // debugPrint('🧹 Cleared malformed quiz_scores key from secure storage');
  // // ----------------------------------------------------------

  // Initialize AuthProvider before runApp
  final authProvider = AuthProvider();
  await authProvider.loadStoredAuthData();
  runApp(
    MultiProvider(
      providers: [
        // 🔐 Authentication
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),

        // 👤 User identity (profile info)
        ChangeNotifierProvider(create: (_) => UserProvider()),

        // 🧮 Quiz and module progress tracking
        ChangeNotifierProvider(create: (_) => QuizScoreProvider()),

        // 🧩 Exam system
        Provider(create: (_) => RetryQueueService(retryBox)),
        Provider(create: (_) => ExamSyncService(attemptsBox, retryBox)),

        // 🎯 Exam controller (depends on ExamSyncService)
        ChangeNotifierProxyProvider<ExamSyncService, ExamController>(
          create: (context) {
            final syncService = context.read<ExamSyncService>();
            return ExamController(attemptsBox, syncService, examBox);
          },
          update: (context, syncService, controller) {
            return controller ?? ExamController(attemptsBox, syncService, examBox);
          },
        ),
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


