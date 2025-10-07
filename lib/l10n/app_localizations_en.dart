// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'WiRED International';

  @override
  String get homeTitle => 'CME Module Library';

  @override
  String get newsAndUpdates => 'News and Updates';

  @override
  String get noAlerts => 'No alerts available';

  @override
  String get invalidModuleData => 'Invalid module data provided.';

  @override
  String get noDescription => 'No Description available';

  @override
  String get searchModules => 'Modules';

  @override
  String get searchHint => 'Tap to search for modules';
}
