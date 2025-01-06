import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'Web platformu için DefaultFirebaseOptions.web kullanın.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError(
          'iOS platformu için DefaultFirebaseOptions.ios kullanın.',
        );
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'MacOS platformu için DefaultFirebaseOptions.macos kullanın.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'Windows platformu için DefaultFirebaseOptions.windows kullanın.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'Linux platformu için DefaultFirebaseOptions.linux kullanın.',
        );
      default:
        throw UnsupportedError(
          'Desteklenmeyen platform için DefaultFirebaseOptions.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'YOUR-API-KEY',  // google-services.json dosyasından alın
    appId: 'YOUR-APP-ID',    // google-services.json dosyasından alın
    messagingSenderId: 'YOUR-SENDER-ID', // google-services.json dosyasından alın
    projectId: 'YOUR-PROJECT-ID',  // google-services.json dosyasından alın
    storageBucket: 'YOUR-STORAGE-BUCKET', // google-services.json dosyasından alın
  );
} 