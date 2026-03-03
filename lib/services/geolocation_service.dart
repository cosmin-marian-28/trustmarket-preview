import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter/foundation.dart';
import 'supabase_service.dart';

class GeolocationService {
  static Future<Position?> getCurrentPosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return null;
      }

      return await Geolocator.getCurrentPosition();
    } catch (e) {
      debugPrint('Error getting location: $e');
      return null;
    }
  }

  static Future<double> getDistanceInKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) async {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2) / 1000;
  }

  /// Get user's city from GPS coordinates
  static Future<String?> getUserCity() async {
    try {
      final position = await getCurrentPosition();
      if (position == null) {
        return null;
      }

      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isEmpty) {
        return null;
      }

      final placemark = placemarks.first;
      return placemark.locality ?? placemark.administrativeArea;
    } catch (e) {
      debugPrint('Error getting user city: $e');
      return null;
    }
  }

  /// Get user's country code from GPS coordinates
  static Future<String?> getUserCountryCode() async {
    try {
      final position = await getCurrentPosition();
      if (position == null) {
        return null;
      }

      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isEmpty) {
        return null;
      }

      final placemark = placemarks.first;
      return placemark.isoCountryCode; // Returns 2-letter code like "RO", "US"
    } catch (e) {
      debugPrint('Error getting user country code: $e');
      return null;
    }
  }

  /// Save user location to Supabase
  static Future<void> saveUserLocation({
    required String userId,
    required String city,
    required double? latitude,
    required double? longitude,
    String? countryCode,
  }) async {
    try {
      final data = {
        'city': city,
        'latitude': latitude,
        'longitude': longitude,
        'location_updated_at': DateTime.now().toIso8601String(),
      };
      
      if (countryCode != null) {
        data['country'] = countryCode;
      }
      
      await SupabaseService.instance.client
          .from('users')
          .update(data)
          .eq('id', userId);
    } catch (e) {
      debugPrint('Error saving user location: $e');
      rethrow;
    }
  }

  /// Get cached user city from Supabase
  static Future<String?> getCachedUserCity({
    required String userId,
  }) async {
    try {
      final doc = await SupabaseService.instance.client
          .from('users')
          .select('city')
          .eq('id', userId)
          .single();
      
      return doc['city'] as String?;
    } catch (e) {
      debugPrint('Error getting cached user city: $e');
      return null;
    }
  }

  /// Calculate estimated delivery distance between seller and buyer cities
  static Future<String?> getEstimatedDeliveryDistance({
    required String sellerCity,
    required String buyerCity,
  }) async {
    try {
      if (sellerCity.toLowerCase() == buyerCity.toLowerCase()) {
        return 'Same city delivery (1-2 days)';
      }

      // Get coordinates for both cities
      final sellerLocations = await locationFromAddress(sellerCity);
      final buyerLocations = await locationFromAddress(buyerCity);

      if (sellerLocations.isEmpty || buyerLocations.isEmpty) {
        return 'Delivery estimate unavailable';
      }

      final sellerLoc = sellerLocations.first;
      final buyerLoc = buyerLocations.first;

      final distance = await getDistanceInKm(
        sellerLoc.latitude,
        sellerLoc.longitude,
        buyerLoc.latitude,
        buyerLoc.longitude,
      );

      if (distance < 50) {
        return 'Local delivery (~${distance.toStringAsFixed(0)} km, 1-2 days)';
      } else if (distance < 200) {
        return 'Regional delivery (~${distance.toStringAsFixed(0)} km, 2-3 days)';
      } else {
        return 'National delivery (~${distance.toStringAsFixed(0)} km, 3-5 days)';
      }
    } catch (e) {
      debugPrint('Error calculating delivery distance: $e');
      return 'Delivery estimate unavailable';
    }
  }

  /// Setup order delivery location information
  static Future<void> setupOrderDeliveryLocation({
    required String orderId,
    required String sellerCity,
    required String buyerCity,
  }) async {
    try {
      final estimate = await getEstimatedDeliveryDistance(
        sellerCity: sellerCity,
        buyerCity: buyerCity,
      );

      await SupabaseService.instance.client
          .from('orders')
          .update({
            'delivery_info': {
              'seller_city': sellerCity,
              'buyer_city': buyerCity,
              'estimate': estimate,
              'setup_at': DateTime.now().toIso8601String(),
            },
          })
          .eq('id', orderId);
    } catch (e) {
      debugPrint('Error setting up order delivery location: $e');
      rethrow;
    }
  }
}
