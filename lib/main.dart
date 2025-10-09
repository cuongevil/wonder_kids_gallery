import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'firebase_options.dart';
import 'screens/gallery_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ Khởi tạo Google Mobile Ads SDK và in kết quả ra log
  await MobileAds.instance
      .initialize()
      .then((InitializationStatus status) {
        for (final entry in status.adapterStatuses.entries) {
          debugPrint(
            '📢 Adapter: ${entry.key}, state: ${entry.value.state}, latency: ${entry.value.latency}',
          );
        }
        debugPrint('✅ Google Mobile Ads SDK initialized thành công');
      })
      .catchError((e) {
        debugPrint('❌ Lỗi khởi tạo MobileAds: $e');
      });

  // ✅ Khởi tạo Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // ✅ Bật App Check (Play Integrity ở release)
  await FirebaseAppCheck.instance.activate(
    androidProvider: kDebugMode
        ? AndroidProvider.debug
        : AndroidProvider.playIntegrity,
    appleProvider: kDebugMode ? AppleProvider.debug : AppleProvider.deviceCheck,
  );

  runApp(const WonderKidsGalleryApp());
}

class WonderKidsGalleryApp extends StatelessWidget {
  const WonderKidsGalleryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wonder Kids Gallery',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.purple),
        useMaterial3: true,
      ),
      home: const GalleryScreen(),
    );
  }
}
