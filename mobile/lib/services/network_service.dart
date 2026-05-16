import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';

class NetworkService {
  final NetworkInfo _networkInfo = NetworkInfo();

  Future<String?> getLocalIP() async {
    try {
      final wifiIp = await _networkInfo.getWifiIP();
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      final addresses = <String>{
        if (wifiIp != null && wifiIp.isNotEmpty) wifiIp,
        ...interfaces
            .expand((interface) => interface.addresses)
            .map((address) => address.address)
      }.where(_isPrivateIpv4).toList();

      if (addresses.isEmpty) {
        return wifiIp != null && wifiIp.isNotEmpty ? wifiIp : null;
      }
      addresses.sort((a, b) => _scoreAddress(b).compareTo(_scoreAddress(a)));
      return addresses.first;
    } catch (e) {
      debugPrint('Could not get local IP: $e');
      return null;
    }
  }

  bool _isPrivateIpv4(String address) {
    return address.startsWith('192.168.') ||
        address.startsWith('10.') ||
        RegExp(r'^172\.(1[6-9]|2\d|3[0-1])\.').hasMatch(address);
  }

  int _scoreAddress(String address) {
    if (address.startsWith('192.168.43.') ||
        address.startsWith('192.168.49.') ||
        address.startsWith('192.168.137.') ||
        address.startsWith('172.20.10.')) {
      return 3;
    }
    if (address.startsWith('192.168.')) return 2;
    if (address.startsWith('10.')) return 1;
    return 0;
  }
}
