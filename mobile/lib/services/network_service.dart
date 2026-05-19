import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';

class NetworkService {
  final NetworkInfo _networkInfo = NetworkInfo();

  /// Returns the best local IP for serving content to peers.
  ///
  /// Works for:
  ///   - Both devices on common WiFi
  ///   - This device is a hotspot creator (WiFi off, mobile data on)
  ///   - This device is connected to another phone's hotspot
  ///   - USB tethering / Ethernet scenarios
  Future<String?> getLocalIP() async {
    try {
      // 1. Gather all candidate IPs from system network interfaces.
      //    This is the most reliable source — it works even when the phone
      //    is a hotspot creator (where getWifiIP() returns null).
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      final interfaceAddresses = interfaces
          .expand((iface) => iface.addresses)
          .map((addr) => addr.address)
          .toSet();

      // 2. Also try the WiFi-specific lookup (useful when connected as a
      //    client to a regular router).
      String? wifiIp;
      try {
        wifiIp = await _networkInfo.getWifiIP();
      } catch (_) {
        // getWifiIP can throw on some Android versions when WiFi is off.
      }

      final allAddresses = <String>{
        ...interfaceAddresses,
        if (wifiIp != null && wifiIp.isNotEmpty) wifiIp,
      }.where(_isPrivateIpv4).toList();

      if (allAddresses.isEmpty) {
        debugPrint('[NetworkService] No private IPv4 addresses found');
        return null;
      }

      // 3. Sort: hotspot-gateway IPs first, then regular WiFi, then others.
      allAddresses.sort((a, b) => _scoreAddress(b).compareTo(_scoreAddress(a)));

      debugPrint('[NetworkService] Candidates: $allAddresses → ${allAddresses.first}');
      return allAddresses.first;
    } catch (e) {
      debugPrint('[NetworkService] Could not get local IP: $e');
      return null;
    }
  }

  bool _isPrivateIpv4(String address) {
    return address.startsWith('192.168.') ||
        address.startsWith('10.') ||
        RegExp(r'^172\.(1[6-9]|2\d|3[0-1])\.').hasMatch(address);
  }

  /// Score addresses so that hotspot-gateway IPs are chosen first.
  ///
  /// Hotspot creators typically get:
  ///   - Android default: 192.168.43.1 or 192.168.49.1
  ///   - Samsung:         192.168.49.1
  ///   - iOS:             172.20.10.1
  ///   - Windows:         192.168.137.1
  ///
  /// Gateway IPs (ending in .1) get an extra boost because when this device
  /// IS the hotspot, the .1 address is the one peers can reach.
  int _scoreAddress(String address) {
    int score = 0;

    // Hotspot-typical subnets get highest base score
    if (address.startsWith('192.168.43.') ||
        address.startsWith('192.168.49.') ||
        address.startsWith('192.168.137.') ||
        address.startsWith('172.20.10.')) {
      score = 10;
    } else if (address.startsWith('192.168.')) {
      score = 5;
    } else if (address.startsWith('10.')) {
      score = 3;
    } else {
      score = 1;
    }

    // Gateway IP boost: if this device is the hotspot creator, the peers
    // connect to x.x.x.1 — prefer that over client addresses like x.x.x.142.
    if (address.endsWith('.1')) {
      score += 5;
    }

    return score;
  }
}
