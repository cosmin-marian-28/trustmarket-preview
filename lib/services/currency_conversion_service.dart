import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Service for real-time currency conversion using exchange rates API
class CurrencyConversionService {
  // Free API endpoint (no key required for basic usage)
  static const String _apiUrl = 'https://api.exchangerate-api.com/v4/latest/';
  
  // Cache exchange rates locally
  static final Map<String, Map<String, double>> _ratesCache = {};
  static DateTime? _lastFetchTime;
  static const Duration _cacheDuration = Duration(hours: 1);
  
  /// Convert amount from one currency to another
  /// Returns null if conversion fails
  static Future<double?> convert({
    required double amount,
    required String fromCurrency,
    required String toCurrency,
  }) async {
    if (fromCurrency == toCurrency) return amount;
    
    try {
      final rate = await getExchangeRate(fromCurrency, toCurrency);
      if (rate == null) return null;
      
      return amount * rate;
    } catch (e) {
      debugPrint('❌ Currency conversion error: $e');
      return null;
    }
  }
  
  /// Get exchange rate from one currency to another
  static Future<double?> getExchangeRate(String fromCurrency, String toCurrency) async {
    if (fromCurrency == toCurrency) return 1.0;
    
    try {
      // Check cache first
      if (_isCacheValid() && _ratesCache.containsKey(fromCurrency)) {
        final rates = _ratesCache[fromCurrency]!;
        if (rates.containsKey(toCurrency)) {
          debugPrint('✅ Using cached rate: 1 $fromCurrency = ${rates[toCurrency]} $toCurrency');
          return rates[toCurrency];
        }
      }
      
      // Fetch fresh rates
      await _fetchRates(fromCurrency);
      
      if (_ratesCache.containsKey(fromCurrency)) {
        final rates = _ratesCache[fromCurrency]!;
        if (rates.containsKey(toCurrency)) {
          debugPrint('✅ Fetched rate: 1 $fromCurrency = ${rates[toCurrency]} $toCurrency');
          return rates[toCurrency];
        }
      }
      
      return null;
    } catch (e) {
      debugPrint('❌ Error getting exchange rate: $e');
      return null;
    }
  }
  
  /// Fetch exchange rates from API
  static Future<void> _fetchRates(String baseCurrency) async {
    try {
      final url = Uri.parse('$_apiUrl$baseCurrency');
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final rates = data['rates'] as Map<String, dynamic>;
        
        _ratesCache[baseCurrency] = rates.map(
          (key, value) => MapEntry(key, (value as num).toDouble()),
        );
        _lastFetchTime = DateTime.now();
        
        // Save to local storage for offline fallback
        await _saveRatesToLocal(baseCurrency, _ratesCache[baseCurrency]!);
        
        debugPrint('✅ Fetched exchange rates for $baseCurrency');
      } else {
        debugPrint('❌ API error: ${response.statusCode}');
        // Try loading from local storage
        await _loadRatesFromLocal(baseCurrency);
      }
    } catch (e) {
      debugPrint('❌ Error fetching rates: $e');
      // Try loading from local storage
      await _loadRatesFromLocal(baseCurrency);
    }
  }
  
  /// Check if cache is still valid
  static bool _isCacheValid() {
    if (_lastFetchTime == null) return false;
    return DateTime.now().difference(_lastFetchTime!) < _cacheDuration;
  }
  
  /// Save rates to local storage for offline use
  static Future<void> _saveRatesToLocal(String baseCurrency, Map<String, double> rates) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ratesJson = json.encode(rates);
      await prefs.setString('exchange_rates_$baseCurrency', ratesJson);
      await prefs.setString('exchange_rates_timestamp', DateTime.now().toIso8601String());
      debugPrint('✅ Saved exchange rates to local storage');
    } catch (e) {
      debugPrint('❌ Error saving rates to local: $e');
    }
  }
  
  /// Load rates from local storage
  static Future<void> _loadRatesFromLocal(String baseCurrency) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ratesJson = prefs.getString('exchange_rates_$baseCurrency');
      final timestamp = prefs.getString('exchange_rates_timestamp');
      
      if (ratesJson != null && timestamp != null) {
        final rates = json.decode(ratesJson) as Map<String, dynamic>;
        _ratesCache[baseCurrency] = rates.map(
          (key, value) => MapEntry(key, (value as num).toDouble()),
        );
        _lastFetchTime = DateTime.parse(timestamp);
        debugPrint('✅ Loaded exchange rates from local storage');
      }
    } catch (e) {
      debugPrint('❌ Error loading rates from local: $e');
    }
  }
  
  /// Clear cache (useful for testing or forcing refresh)
  static void clearCache() {
    _ratesCache.clear();
    _lastFetchTime = null;
  }
  
  /// Format price with currency symbol
  static String formatPrice(double amount, String currency) {
    final symbols = {
      'USD': '\$',
      'EUR': '€',
      'GBP': '£',
      'RON': 'RON',
      'JPY': '¥',
      'CNY': '¥',
      'INR': '₹',
      'RUB': '₽',
      'BRL': 'R\$',
      'CAD': 'CA\$',
      'AUD': 'A\$',
      'CHF': 'CHF',
      'SEK': 'kr',
      'NOK': 'kr',
      'DKK': 'kr',
      'PLN': 'zł',
      'CZK': 'Kč',
      'HUF': 'Ft',
      'TRY': '₺',
      'MXN': 'MX\$',
      'ZAR': 'R',
      'SGD': 'S\$',
      'HKD': 'HK\$',
      'NZD': 'NZ\$',
      'KRW': '₩',
      'THB': '฿',
    };
    
    final symbol = symbols[currency.toUpperCase()] ?? currency;
    
    // Format with appropriate decimal places
    if (currency.toUpperCase() == 'JPY' || currency.toUpperCase() == 'KRW') {
      // No decimals for yen and won
      return '$symbol${amount.toStringAsFixed(0)}';
    } else {
      return '$symbol${amount.toStringAsFixed(2)}';
    }
  }
}
