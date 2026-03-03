import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'firebase_options.dart';
import 'pages/home_page.dart';
import 'pages/signup_page.dart';
import 'pages/chat_page.dart';
import 'services/language_service.dart';
import 'services/currency_service.dart';
import 'services/supabase_service.dart';
import 'constants/translations.dart';
import 'services/stripe_service.dart';

// Background message handler for FCM (must be top-level)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('📬 Background notification: ${message.notification?.title}');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Lock to portrait only
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  
  // Load saved language preference from SharedPreferences FIRST
  // This ensures I18n.current is set correctly before any UI is built
  await LanguageService.load();
  
  // Load saved currency preference
  await CurrencyService.load();
  debugPrint('💰 Currency loaded: ${CurrencyService.current}');
  
  // Initialize Supabase FIRST (before any auth/database operations)
  try {
    debugPrint('🔵 Initializing Supabase...');
    await SupabaseService.initialize();
    debugPrint('✅ Supabase initialized successfully');
  } catch (e, stackTrace) {
    debugPrint('❌ Failed to initialize Supabase: $e');
    debugPrint('Stack trace: $stackTrace');
    // Show error to user and exit
    runApp(MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 64),
                const SizedBox(height: 16),
                const Text(
                  'Failed to initialize app',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Error: $e',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    ));
    return;
  }
  
  // Firebase initialization ONLY for FCM (push notifications)
  // Auto-initializes from GoogleService-Info.plist on iOS/Android
  if (!kIsWeb) {
    try {
      await Firebase.initializeApp();
      debugPrint('✅ Firebase initialized for FCM');
    } catch (e) {
      // Firebase already initialized, ignore
      debugPrint('ℹ️ Firebase already initialized');
    }
  } else {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      debugPrint('✅ Firebase initialized for FCM (web)');
    } catch (e) {
      debugPrint('⚠️ Failed to initialize Firebase for FCM: $e');
    }
  }
  
  // Initialize FCM background handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  
  // Clear iOS badge on every app launch (fixes ghost "1" badge)
  if (!kIsWeb) {
    try {
      await FirebaseMessaging.instance.setAutoInitEnabled(true);
      // This is the most reliable way to reset the iOS badge from cold start
      final localNotifications = FlutterLocalNotificationsPlugin();
      await localNotifications.initialize(const InitializationSettings(
        iOS: DarwinInitializationSettings(),
      ));
      await localNotifications.show(
        0, null, null,
        const NotificationDetails(
          iOS: DarwinNotificationDetails(
            presentAlert: false,
            presentSound: false,
            presentBadge: true,
            badgeNumber: 0,
          ),
        ),
      );
      await localNotifications.cancel(0);
      debugPrint('✅ Badge cleared on startup');
    } catch (e) {
      debugPrint('⚠️ Could not clear badge on startup: $e');
    }
  }
  
  // Initialize Stripe for payment processing
  try {
    await StripeService.initializeStripe();
    debugPrint('✅ Stripe initialized');
  } catch (e) {
    debugPrint('⚠️ Failed to initialize Stripe: $e');
  }
  
  // Load user preferences from Supabase if user is already logged in
  final currentUser = SupabaseService.instance.currentUser;
  if (currentUser != null) {
    try {
      final response = await SupabaseService.instance.users
          .select()
          .eq('id', currentUser.id)
          .maybeSingle();
      
      if (response != null) {
        final data = response;
        
        // Load preferred language from Supabase
        final langStr = (data['preferred_language'] as String?) ?? '';
        if (langStr.isNotEmpty) {
          try {
            final lang = AppLang.values.firstWhere(
              (e) => e.name == langStr,
              orElse: () => AppLang.en,
            );
            await LanguageService.setLanguage(lang);
          } catch (e) {
            debugPrint('⚠️ Could not parse preferredLanguage: $e');
          }
        }
        
        // Load preferred currency from Supabase
        final currencyStr = (data['preferred_currency'] as String?) ?? '';
        if (currencyStr.isNotEmpty) {
          try {
            await CurrencyService.setCurrency(currencyStr);
            debugPrint('💰 Startup: Currency loaded from database: $currencyStr');
          } catch (e) {
            debugPrint('⚠️ Could not parse preferredCurrency: $e');
          }
        } else {
          // Fallback to language-based currency
          final langStr = (data['preferred_language'] as String?) ?? '';
          String fallbackCurrency = 'USD';
          if (langStr == 'ro') {
            fallbackCurrency = 'RON';
          } else if (langStr == 'it' || langStr == 'fr' || langStr == 'es' || langStr == 'de') {
            fallbackCurrency = 'EUR';
          }
          await CurrencyService.setCurrency(fallbackCurrency);
          debugPrint('💰 Startup: Using language-based currency: $fallbackCurrency');
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error loading user prefs at startup: $e');
    }
  }
  
  runApp(const TrustMarketApp());
}

class TrustMarketApp extends StatelessWidget {
  const TrustMarketApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) {
        // Don't dismiss keyboard when ChatPage has opted out (e.g. during active typing)
        if (ChatPage.keepKeyboardOpen) return;
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: MaterialApp(
      title: 'TrustMarket',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.purple,
        fontFamily: 'Inter',
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: _NoTransitionBuilder(),
            TargetPlatform.iOS: _NoTransitionBuilder(),
            TargetPlatform.macOS: _NoTransitionBuilder(),
            TargetPlatform.windows: _NoTransitionBuilder(),
            TargetPlatform.linux: _NoTransitionBuilder(),
          },
        ),
      ),
      home: const AuthGate(),
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    // Permissions are now requested contextually when features are used:
    // - Camera: requested when user opens camera screen
    // - Location: requested when user posts a gig or needs delivery info
    // - Notifications: requested after home page loads with a short delay
  }

  /// Fetch the user document and apply stored preferences (language & currency).
  /// Returns true when the user doc exists and prefs have been applied.
  /// Returns true even on errors to avoid signing out users unnecessarily.
  Future<bool> _prepareUser(String uid) async {
    try {
      final response = await SupabaseService.instance.users
          .select()
          .eq('id', uid)
          .maybeSingle();
      
      if (response == null) {
        debugPrint('⚠️ User profile not found yet, using defaults');
        // Don't fail - user might be newly created, profile might be creating
        return true;
      }
      final data = response;

      final langStr = (data['preferred_language'] as String?) ?? '';
      if (langStr.isNotEmpty) {
        try {
          final lang = AppLang.values.firstWhere(
            (e) => e.name == langStr,
            orElse: () => AppLang.en,
          );
          await LanguageService.setLanguage(lang);
        } catch (e) {
          debugPrint('⚠️ Could not parse preferredLanguage from Supabase: $e');
        }
      }

      final prefCurrency = (data['preferred_currency'] as String?) ?? '';
      if (prefCurrency.isNotEmpty) {
        try {
          await CurrencyService.setCurrency(prefCurrency);
          debugPrint('💰 Currency loaded from database: $prefCurrency');
        } catch (e) {
          debugPrint('⚠️ Could not apply preferredCurrency from Supabase: $e');
        }
      } else {
        // No currency set in database — use language-based fallback
        // Location permission will be requested later when actually needed
        debugPrint('💰 No currency in database, using language-based fallback');
        String detectedCurrency = 'USD';
        
        final langForCurrency = (data['preferred_language'] as String?) ?? '';
        if (langForCurrency == 'ro') {
          detectedCurrency = 'RON';
        } else if (langForCurrency == 'it' || langForCurrency == 'fr' || langForCurrency == 'es' || langForCurrency == 'de') {
          detectedCurrency = 'EUR';
        }
        
        await CurrencyService.setCurrency(detectedCurrency);
        debugPrint('💰 Currency set to: $detectedCurrency (language-based)');
      }

      // FCM is now initialized lazily from HomePage after a short delay
      // to avoid spamming permission dialogs at startup

      return true;
    } catch (e) {
      debugPrint('⚠️ Error preparing user prefs: $e');
      // Return true anyway - don't sign out users due to temporary errors
      return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: SupabaseService.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        // Check if still loading
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            resizeToAvoidBottomInset: false,
            backgroundColor: Color(0xFF0A0A0A),
            body: SizedBox.shrink(),
          );
        }

        // Check if user is authenticated
        final authState = snapshot.data;
        final session = authState?.session;
        
        if (session != null) {
          final user = session.user;
          
          // Prepare user prefs (await application) before showing HomePage so
          // widgets read the correct currency/language from services.
          return FutureBuilder<bool>(
            future: _prepareUser(user.id),
            builder: (context, prepSnap) {
              if (prepSnap.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  backgroundColor: Color(0xFF0A0A0A),
                  body: SizedBox.shrink(),
                );
              }

              // Always proceed to home - _prepareUser handles errors gracefully
              return const HomePage();
            },
          );
        } else {
          // User is not logged in, show sign up page
          return const SignUpPage();
        }
      },
    );
  }
}


/// Instant page transition — no animation at all.
class _NoTransitionBuilder extends PageTransitionsBuilder {
  const _NoTransitionBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }
}
