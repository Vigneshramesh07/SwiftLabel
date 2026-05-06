// lib/main.dart

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:swift_label/screens/splash_screen.dart';
import 'package:swift_label/screens/track_parcel.dart';
import 'firebase_options.dart';
import 'providers/auth_provider.dart';
import 'providers/profile_provider.dart';
import 'providers/parcel_provider.dart';
import 'providers/tracking_provider.dart';

// ── Global navigator key ──────────────────────────────────────────
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// ── Local notifications plugin ────────────────────────────────────
final FlutterLocalNotificationsPlugin localNotifications =
FlutterLocalNotificationsPlugin();

Future<void> requestTracking() async {
  final status = await AppTrackingTransparency.requestTrackingAuthorization();
  print('Tracking status: $status');
}

// ── Background handler — must be top-level function ───────────────
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  debugPrint('[FCM] Background: ${message.messageId}');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  Stripe.publishableKey = 'pk_live_51TEACkDQs85qYTWQe3RJjYHH1LjL1RYJtHQWMdRTtwSKgLj6NQMg9oK0Jx5yJIqcFRQkYSKyoaVAtjDUy1y2c7kd00UKojDycL';
  await Stripe.instance.applySettings();
  await requestTracking();

  // ── Firebase ──────────────────────────────────────────────────
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // ── Local notifications ───────────────────────────────────────
  await localNotifications.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      ),
    ),
    onDidReceiveNotificationResponse: (NotificationResponse details) {
      final tn = details.payload ?? '';
      if (tn.isNotEmpty) {
        navigatorKey.currentState?.push(MaterialPageRoute(
          builder: (_) => TrackParcelScreen(initialTrackingNumber: tn),
        ));
      }
    },
  );

  // ── Android notification channel ──────────────────────────────
  final androidPlugin = localNotifications
      .resolvePlatformSpecificImplementation
  <AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.createNotificationChannel(
    const AndroidNotificationChannel(
      'tracking_updates',
      'Tracking Updates',
      description: 'Parcel tracking status change notifications',
      importance: Importance.high,
    ),
  );

  // ── Supabase ──────────────────────────────────────────────────
  await Supabase.initialize(
    url: 'https://tjrjeemaacumepimjltg.supabase.co',
    anonKey:
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRqcmplZW1hYWN1bWVwaW1qbHRnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQxMjE2NjAsImV4cCI6MjA4OTY5NzY2MH0.gtBcFu-J48mPDk_S9ukfVdW-7gUmabGatmJ1g1_5zzo',
  );

  // ── Portrait only ─────────────────────────────────────────────
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // ── Status bar ────────────────────────────────────────────────
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor:                    Colors.transparent,
    statusBarIconBrightness:           Brightness.dark,
    systemNavigationBarColor:          Colors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ProfileProvider()),
        ChangeNotifierProvider(create: (_) => ParcelProvider()),
        ChangeNotifierProvider(create: (_) => TrackingProvider()),
      ],
      child: const SwiftLabelApp(),
    ),
  );
}

class SwiftLabelApp extends StatefulWidget {
  const SwiftLabelApp({super.key});

  @override
  State<SwiftLabelApp> createState() => _SwiftLabelAppState();
}

class _SwiftLabelAppState extends State<SwiftLabelApp> {

  @override
  void initState() {
    super.initState();
    _setupFcm();
  }

  Future<void> _setupFcm() async {
    final messaging = FirebaseMessaging.instance;

    // Request permission
    final settings = await messaging.requestPermission(
      alert:       true,
      badge:       true,
      sound:       true,
      provisional: false,
    );
    debugPrint('[FCM] Permission: ${settings.authorizationStatus}');

    // iOS foreground notifications
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Get and save token
    final token = await messaging.getToken();
    if (token != null) {
      debugPrint('[FCM] Token: $token');
      await _saveFcmToken(token);
    }

    // Token refresh
    messaging.onTokenRefresh.listen(_saveFcmToken);

    // Foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Background → foreground via notification tap
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // App launched from terminated state via notification
    final initial = await messaging.getInitialMessage();
    if (initial != null) _handleNotificationTap(initial);
  }

  Future<void> _saveFcmToken(String token) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user?.email == null) return;

      await Supabase.instance.client.from('user_tokens').upsert(
        {
          'user_email': user!.email,
          'fcm_token':  token,
          'updated_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'user_email, fcm_token',
      );
      debugPrint('[FCM] ✓ Token saved to Supabase');
    } catch (e) {
      debugPrint('[FCM] Token save error: $e');
    }
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    debugPrint('[FCM] Foreground: ${message.notification?.title}');
    final notification = message.notification;
    if (notification == null) return;

    await localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'tracking_updates',
          'Tracking Updates',
          channelDescription: 'Parcel tracking status changes',
          importance: Importance.high,
          priority:   Priority.high,
          icon: message.notification?.android?.smallIcon
              ?? '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: message.data['tracking_number'],
    );
  }

  void _handleNotificationTap(RemoteMessage message) {
    final tn = message.data['tracking_number'] ?? '';
    debugPrint('[FCM] Tapped: tn=$tn');
    if (tn.isNotEmpty) {
      navigatorKey.currentState?.push(MaterialPageRoute(
        builder: (_) => TrackParcelScreen(initialTrackingNumber: tn),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title:                    'SwiftLabel',
      debugShowCheckedModeBanner: false,
      navigatorKey:             navigatorKey,
      theme:                    _buildTheme(),
      home:                     const SplashScreen(),
    );
  }

  ThemeData _buildTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness:   Brightness.light,

      scaffoldBackgroundColor: const Color(0xFFFAF9F7),
      colorScheme: const ColorScheme.light(
        primary:   Color(0xFFFF5A00),
        secondary: Color(0xFFFF8C00),
        surface:   Colors.white,
        onPrimary: Colors.white,
        onSurface: Color(0xFF1A1A1A),
        outline:   Color(0xFFE0E0E0),
      ),

      fontFamily: 'DMSans',
      textTheme: const TextTheme(
        displayLarge:   TextStyle(fontFamily: 'Syne', fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A)),
        displayMedium:  TextStyle(fontFamily: 'Syne', fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A)),
        headlineLarge:  TextStyle(fontFamily: 'Syne', fontWeight: FontWeight.w800, fontSize: 24, color: Color(0xFF1A1A1A)),
        headlineMedium: TextStyle(fontFamily: 'Syne', fontWeight: FontWeight.w700, fontSize: 20, color: Color(0xFF1A1A1A)),
        titleLarge:     TextStyle(fontFamily: 'Syne', fontWeight: FontWeight.w700, fontSize: 17, color: Color(0xFF1A1A1A)),
        bodyLarge:      TextStyle(fontFamily: 'DMSans', fontSize: 15, color: Color(0xFF1A1A1A)),
        bodyMedium:     TextStyle(fontFamily: 'DMSans', fontSize: 14, color: Color(0xFF3A3A3A)),
        bodySmall:      TextStyle(fontFamily: 'DMSans', fontSize: 12, color: Color(0xFF6B6B6B)),
        labelLarge:     TextStyle(fontFamily: 'Syne', fontWeight: FontWeight.w700, fontSize: 15, color: Colors.white),
      ),

      appBarTheme: const AppBarTheme(
        backgroundColor:        Colors.white,
        surfaceTintColor:       Colors.white,
        elevation:              0,
        scrolledUnderElevation: 0,
        centerTitle:            false,
        iconTheme:              IconThemeData(color: Color(0xFF1A1A1A)),
        titleTextStyle:         TextStyle(
            fontFamily: 'Syne', fontSize: 20,
            fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A)),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor:          Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor:         const Color(0xFFFF5A00),
          foregroundColor:         Colors.white,
          disabledBackgroundColor: const Color(0xFFFFB899),
          disabledForegroundColor: Colors.white70,
          minimumSize:             const Size(double.infinity, 48),
          elevation:               0,
          shadowColor:             Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(
              fontFamily: 'Syne', fontSize: 15,
              fontWeight: FontWeight.w700, letterSpacing: 0.1),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFFFF5A00),
          textStyle: const TextStyle(
              fontFamily: 'DMSans', fontSize: 14,
              fontWeight: FontWeight.w600),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled:         true,
        fillColor:      Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFFF5A00), width: 1.5)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.red)),
        focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.red, width: 1.5)),
        disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFF0F0F0))),
        labelStyle: const TextStyle(
            fontSize: 13, color: Color(0xFF6B6B6B), fontFamily: 'DMSans'),
        hintStyle: const TextStyle(
            fontSize: 14, color: Color(0xFFB0B0B0), fontFamily: 'DMSans'),
        errorStyle: const TextStyle(
            fontSize: 12, color: Colors.red, fontFamily: 'DMSans'),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor:  Colors.white,
        surfaceTintColor: Colors.white,
        elevation:        0,
        height:           64,
        indicatorColor:   const Color(0xFFFF5A00).withOpacity(0.1),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
                fontFamily: 'DMSans', fontSize: 11,
                fontWeight: FontWeight.w600, color: Color(0xFFFF5A00));
          }
          return const TextStyle(
              fontFamily: 'DMSans', fontSize: 11,
              fontWeight: FontWeight.w500, color: Color(0xFF9B9B9B));
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: Color(0xFFFF5A00), size: 22);
          }
          return const IconThemeData(color: Color(0xFF9B9B9B), size: 22);
        }),
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFEEEEEE)),
        ),
        margin: EdgeInsets.zero,
        color: Colors.white,
      ),

      dividerTheme: const DividerThemeData(
          color: Color(0xFFEEEEEE), thickness: 1, space: 0),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        contentTextStyle: const TextStyle(
            fontFamily: 'DMSans', fontSize: 14, color: Colors.white),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor:  Colors.white,
        surfaceTintColor: Colors.white,
        elevation:        0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titleTextStyle: const TextStyle(
            fontFamily: 'Syne', fontWeight: FontWeight.w800,
            fontSize: 18, color: Color(0xFF1A1A1A)),
        contentTextStyle: const TextStyle(
            fontFamily: 'DMSans', fontSize: 14,
            color: Color(0xFF6B6B6B), height: 1.5),
      ),
    );
  }
}