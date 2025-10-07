// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'WiRED Internacional';

  @override
  String get homeTitle => 'Biblioteca de Módulos CME';

  @override
  String get newsAndUpdates => 'Noticias y Actualizaciones';

  @override
  String get noAlerts => 'No hay alertas disponibles';

  @override
  String get invalidModuleData => 'Datos de módulo inválidos.';

  @override
  String get noDescription => 'No hay descripción disponible';

  @override
  String get searchModules => 'Módulos';

  @override
  String get searchHint => 'Toque para buscar módulos';
}
