import 'package:flutter/foundation.dart';
import '../services/geolocation_service.dart';
import '../services/supabase_service.dart';

class GeolocationHelper {
  /// Get user's city and automatically save to Supabase
  static Future<String?> getUserCityAndSave(String userId) async {
    try {
      debugPrint('📍 Getting user location for userId: $userId');
      
      // Get the city using geolocation
      final city = await GeolocationService.getUserCity();
      
      if (city == null) {
        debugPrint('📍 ✗ Could not get user city - permission denied or location unavailable');
        return null;
      }

      debugPrint('📍 ✓ Detected city: $city');

      // Get country code
      final countryCode = await GeolocationService.getUserCountryCode();
      debugPrint('📍 ✓ Detected country: $countryCode');

      // Save to Supabase
      debugPrint('📍 About to save city and country to Supabase...');
      await GeolocationService.saveUserLocation(
        userId: userId,
        city: city,
        latitude: null,
        longitude: null,
        countryCode: countryCode,
      );

      debugPrint('📍 ✓✓ City and country saved to Supabase: $city, $countryCode');
      return city;
    } catch (e) {
      debugPrint('📍 ✗ Error getting and saving city: $e');
      rethrow;
    }
  }

  /// Get estimated delivery address for order checkout
  static Future<String?> getDeliveryAddressForCheckout() async {
    try {
      debugPrint('📍 Getting delivery address for checkout...');
      
      final currentUser = SupabaseService.instance.client.auth.currentUser;
      if (currentUser == null) {
        debugPrint('📍 User not authenticated');
        return null;
      }

      // Try to get cached city first
      var city = await GeolocationService.getCachedUserCity(
        userId: currentUser.id,
      );

      // If no cached city, get current location
      if (city == null) {
        debugPrint('📍 No cached city, getting current location...');
        city = await GeolocationService.getUserCity();
        
        if (city != null) {
          // Save it for future use
          await GeolocationService.saveUserLocation(
            userId: currentUser.id,
            city: city,
            latitude: null,
            longitude: null,
          );
        }
      }

      if (city != null) {
        final address = 'Delivery to: $city area';
        debugPrint('📍 Address: $address');
        return address;
      }

      return null;
    } catch (e) {
      debugPrint('📍 ✗ Error getting delivery address: $e');
      return null;
    }
  }

  /// Show delivery estimate when user places order
  static Future<String?> getOrderDeliveryEstimate({
    required String sellerCity,
  }) async {
    try {
      debugPrint('📍 Getting delivery estimate from $sellerCity...');
      
      final currentUser = SupabaseService.instance.client.auth.currentUser;
      if (currentUser == null) {
        debugPrint('📍 User not authenticated');
        return null;
      }

      // Get buyer's city
      final buyerCity = await GeolocationService.getCachedUserCity(
        userId: currentUser.id,
      );

      if (buyerCity == null) {
        debugPrint('📍 Could not determine buyer city');
        return null;
      }

      // Get estimate
      final estimate = await GeolocationService.getEstimatedDeliveryDistance(
        sellerCity: sellerCity,
        buyerCity: buyerCity,
      );

      debugPrint('📍 Estimate: $estimate');
      return estimate;
    } catch (e) {
      debugPrint('📍 ✗ Error getting delivery estimate: $e');
      return null;
    }
  }

  /// Setup order with delivery location info
  static Future<void> setupOrderDelivery({
    required String orderId,
    required String sellerCity,
  }) async {
    try {
      debugPrint('📍 Setting up order delivery for: $orderId');
      
      final currentUser = SupabaseService.instance.client.auth.currentUser;
      if (currentUser == null) {
        debugPrint('📍 User not authenticated');
        return;
      }

      // Get buyer's city
      final buyerCity = await GeolocationService.getCachedUserCity(
        userId: currentUser.id,
      );

      if (buyerCity == null) {
        debugPrint('📍 No buyer city found');
        return;
      }

      // Setup order delivery location
      await GeolocationService.setupOrderDeliveryLocation(
        orderId: orderId,
        sellerCity: sellerCity,
        buyerCity: buyerCity,
      );

      debugPrint('📍 ✓ Order delivery setup complete');
    } catch (e) {
      debugPrint('📍 ✗ Error setting up order delivery: $e');
    }
  }
}
