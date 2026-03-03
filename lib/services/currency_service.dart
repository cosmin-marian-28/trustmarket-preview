import 'package:flutter/foundation.dart';
// CurrencyService is intentionally lightweight: we no longer persist
// currency locally or to Firestore from this service. The app reads the
// user's preferred currency from their Firestore document and applies it
// at sign-in. This avoids having the service auto-write preferences.
// No local persistence needed; SharedPreferences removed
import '../constants/translations.dart';
import 'language_service.dart';
import 'currency_conversion_service.dart';

/// Simple service to persist and expose the user's preferred currency.
class CurrencyService {
  // No local persistence: the app loads the user's preferred currency from
  // Firestore during sign-in and applies it via `setCurrency`.
  static final ValueNotifier<String> currencyNotifier = ValueNotifier(_defaultForLang(LanguageService.current));

  static String get current => currencyNotifier.value;
  
  /// Convert a price from its original currency to the user's preferred currency
  static Future<double?> convertPrice({
    required double amount,
    required String fromCurrency,
    String? toCurrency,
  }) async {
    final targetCurrency = toCurrency ?? current;
    return await CurrencyConversionService.convert(
      amount: amount,
      fromCurrency: fromCurrency,
      toCurrency: targetCurrency,
    );
  }
  
  /// Format a price with conversion to user's preferred currency
  static Future<String> formatPriceWithConversion({
    required double amount,
    required String originalCurrency,
    String? targetCurrency,
    bool showOriginal = false,
  }) async {
    final target = targetCurrency ?? current;
    
    if (originalCurrency == target) {
      return CurrencyConversionService.formatPrice(amount, originalCurrency);
    }
    
    final converted = await convertPrice(
      amount: amount,
      fromCurrency: originalCurrency,
      toCurrency: target,
    );
    
    if (converted == null) {
      // Fallback to original if conversion fails
      return CurrencyConversionService.formatPrice(amount, originalCurrency);
    }
    
    final convertedStr = CurrencyConversionService.formatPrice(converted, target);
    
    if (showOriginal) {
      final originalStr = CurrencyConversionService.formatPrice(amount, originalCurrency);
      return '$convertedStr ($originalStr)';
    }
    
    return convertedStr;
  }

  /// Determine a reasonable default currency for a given language.
  static String _defaultForLang(AppLang lang) {
    switch (lang) {
      case AppLang.ro:
        return 'RON';
      case AppLang.en:
      default:
        return 'USD';
    }
  }

  static String defaultForLang(AppLang lang) => _defaultForLang(lang);

  /// Initialize service state. This does not persist anything; it just
  /// establishes an initial currency based on the language.
  static Future<void> load() async {
    try {
      currencyNotifier.value = _defaultForLang(LanguageService.current);
    } catch (e) {
      debugPrint('CurrencyService.load error: $e');
      currencyNotifier.value = _defaultForLang(LanguageService.current);
    }
  }

  /// Set currency at runtime. The app's AuthGate applies the value from
  /// Firestore so we don't auto-write here.
  static Future<void> setCurrency(String code) async {
    currencyNotifier.value = code;
  }
}
