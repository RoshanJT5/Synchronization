import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppOpenAdManager {
  AppOpenAdManager._();
  static final AppOpenAdManager instance = AppOpenAdManager._();

  AppOpenAd? _appOpenAd;
  bool _isShowingAd = false;
  DateTime? _appOpenLoadTime;
  bool _showAdOnNextResume = false;

  /// Test ad unit IDs from Google
  final String adUnitId = Platform.isAndroid
      ? 'ca-app-pub-3940256099942544/9257395921'
      : 'ca-app-pub-3940256099942544/5575463023';

  void loadAd() {
    AppOpenAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) async {
          _appOpenLoadTime = DateTime.now();
          _appOpenAd = ad;

          // If this is the very first time the app is ever opened,
          // show the ad immediately if the app is currently in the foreground,
          // otherwise flag it to be shown on the next app resume.
          final prefs = await SharedPreferences.getInstance();
          if (prefs.getString('last_app_open_ad_time') == null) {
            final state = WidgetsBinding.instance.lifecycleState;
            if (state == AppLifecycleState.resumed) {
              showAdIfAvailable();
            } else {
              _showAdOnNextResume = true;
            }
          }
        },
        onAdFailedToLoad: (error) {
          debugPrint('AppOpenAd failed to load: $error');
        },
      ),
    );
  }

  bool get isAdAvailable {
    return _appOpenAd != null;
  }

  Future<void> showAdIfAvailable() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Block App Open ads until onboarding tutorial is dismissed (only on first-time launch)
    final tutorialShown = prefs.getBool('tutorial_shown') ?? false;
    if (!tutorialShown) {
      debugPrint('AppOpenAd: Skipped because onboarding tutorial is not yet completed/shown.');
      return;
    }

    final lastShownStr = prefs.getString('last_app_open_ad_time');
    
    if (lastShownStr != null) {
      final lastShown = DateTime.tryParse(lastShownStr);
      if (lastShown != null) {
        // Enforce 1-hour cooldown
        if (DateTime.now().difference(lastShown).inHours < 1) {
          debugPrint('AppOpenAd: Skipped due to 1-hour cooldown.');
          return;
        }
      }
    }

    if (!isAdAvailable) {
      loadAd();
      return;
    }
    if (_isShowingAd) {
      return;
    }
    
    // Check if ad expired (4 hours limit for app open ads)
    if (DateTime.now().subtract(const Duration(hours: 4)).isAfter(_appOpenLoadTime!)) {
      _appOpenAd!.dispose();
      _appOpenAd = null;
      loadAd();
      return;
    }

    _appOpenAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) async {
        _isShowingAd = true;
        await prefs.setString('last_app_open_ad_time', DateTime.now().toIso8601String());
        _showAdOnNextResume = false;
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        _isShowingAd = false;
        ad.dispose();
        _appOpenAd = null;
        loadAd();
      },
      onAdDismissedFullScreenContent: (ad) {
        _isShowingAd = false;
        ad.dispose();
        _appOpenAd = null;
        loadAd();
      },
    );

    _appOpenAd!.show();
  }

  void handleAppResume() {
    if (_showAdOnNextResume && isAdAvailable) {
      showAdIfAvailable();
    } else {
      showAdIfAvailable();
    }
  }
}
