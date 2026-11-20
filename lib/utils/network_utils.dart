import 'package:connectivity_plus/connectivity_plus.dart';

class NetworkUtils {
  /// Reports network availability, not internet or HealthMAP API reachability.
  static Future<bool> isOnline() async {
    final status = await Connectivity().checkConnectivity();

    return status.isNotEmpty && !status.contains(ConnectivityResult.none);
  }
}
