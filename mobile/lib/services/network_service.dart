import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';

class NetworkService {
  final NetworkInfo _networkInfo = NetworkInfo();

  Future<String?> getLocalIP() async {
    try {
      return await _networkInfo.getWifiIP();
    } catch (e) {
      debugPrint('Could not get local IP: $e');
      return null;
    }
  }
}
