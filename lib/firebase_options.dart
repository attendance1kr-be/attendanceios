import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.windows:
        return windows;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCN8KWRA89at0s_3sfdkg1Qb2p9ZXesqhA',
    appId: '1:798153616577:web:31a2969fc5c63994167840',
    messagingSenderId: '798153616577',
    projectId: 'staff-tracker-6f67e',
    authDomain: 'staff-tracker-6f67e.firebaseapp.com',
    storageBucket: 'staff-tracker-6f67e.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAAoOzsj180HtC_lAcXPXYcHcQh3W8i7K8',
    appId: '1:798153616577:android:b8a6394e6faa59cc167840',
    messagingSenderId: '798153616577',
    projectId: 'staff-tracker-6f67e',
    storageBucket: 'staff-tracker-6f67e.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAAoOzsj180HtC_lAcXPXYcHcQh3W8i7K8',
    appId: '1:798153616577:ios:31a2969fc5c63994167840',
    messagingSenderId: '798153616577',
    projectId: 'staff-tracker-6f67e',
    storageBucket: 'staff-tracker-6f67e.firebasestorage.app',
    iosBundleId: 'com.raiment.staffTracker',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyAAoOzsj180HtC_lAcXPXYcHcQh3W8i7K8',
    appId: '1:798153616577:web:31a2969fc5c63994167840',
    messagingSenderId: '798153616577',
    projectId: 'staff-tracker-6f67e',
    authDomain: 'staff-tracker-6f67e.firebaseapp.com',
    storageBucket: 'staff-tracker-6f67e.firebasestorage.app',
  );
}
