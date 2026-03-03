library order_status;

import '../constants/translations.dart';

/// Order Status Management Utility
/// Handles order status display and logic for buyers and sellers

class OrderStatus {
  // Seller statuses
  static const String sellerAwaitingShipment = 'awaiting_shipment';
  static const String sellerShipped = 'shipped';
  static const String sellerDelivered = 'delivered';
  static const String sellerCompleted = 'completed';
  static const String sellerCancelled = 'cancelled';

  // Buyer statuses
  static const String buyerPaid = 'paid';
  static const String buyerInTransit = 'in_transit';
  static const String buyerDelivered = 'delivered';
  static const String buyerCompleted = 'completed';
  static const String buyerCancelled = 'cancelled';

  /// Get status for current user (buyer or seller) based on database fields
  static String getStatusForUser(Map<String, dynamic> order, String userId) {
    final sellerId = order['seller_id'] as String?;
    final isSeller = sellerId == userId;
    
    // Get all status-related fields from database
    final status = order['status'] as String?;
    final paymentStatus = order['payment_status'] as String?;
    final awb = order['awb'] as String?;
    final deliveredAt = order['delivered_at'];
    final shippedAt = order['shipped_at'];
    
    if (isSeller) {
      // Seller view: awaiting_shipment -> shipped -> delivered -> completed
      if (deliveredAt != null) {
        return sellerDelivered;
      }
      if ((awb != null && awb.isNotEmpty) || shippedAt != null) {
        return sellerShipped;
      }
      if (paymentStatus == 'captured' || paymentStatus == 'succeeded' || status == 'paid') {
        return sellerAwaitingShipment;
      }
      return sellerAwaitingShipment;
    } else {
      // Buyer view: paid -> in_transit -> delivered -> completed
      if (deliveredAt != null) {
        return buyerDelivered;
      }
      if ((awb != null && awb.isNotEmpty) || shippedAt != null) {
        return buyerInTransit;
      }
      if (paymentStatus == 'captured' || paymentStatus == 'succeeded' || status == 'paid') {
        return buyerPaid;
      }
      return buyerPaid;
    }
  }

  /// Get human-readable status text
  static String getDisplayText(String status) {
    if (status == sellerAwaitingShipment) return I18n.t('awaiting_shipment');
    if (status == sellerShipped) return I18n.t('shipped');
    if (status == sellerDelivered) return I18n.t('delivered');
    if (status == sellerCompleted) return I18n.t('gig_completed');
    if (status == sellerCancelled) return I18n.t('cancelled');
    
    if (status == buyerPaid) return I18n.t('payment_confirmed');
    if (status == buyerInTransit) return I18n.t('in_transit');
    if (status == buyerDelivered) return I18n.t('delivered');
    if (status == buyerCompleted) return I18n.t('gig_completed');
    if (status == buyerCancelled) return I18n.t('cancelled');
    
    // Legacy statuses
    if (status == 'pending') return I18n.t('pending');
    if (status == 'paid') return I18n.t('paid');
    if (status == 'shipped') return I18n.t('shipped');
    if (status == 'delivered') return I18n.t('delivered');
    if (status == 'completed') return I18n.t('gig_completed');
    if (status == 'cancelled') return I18n.t('cancelled');
    
    return status;
  }

  /// Get status color
  static int getStatusColor(String status) {
    if (status == sellerAwaitingShipment) return 0xFFFFA500; // Orange
    if (status == buyerPaid) return 0xFF4CAF50; // Green
    if (status == sellerShipped || status == buyerInTransit) return 0xFF2196F3; // Blue
    if (status == sellerDelivered || status == buyerDelivered) return 0xFF4CAF50; // Green
    if (status == sellerCompleted || status == buyerCompleted) return 0xFF4CAF50; // Green
    if (status == sellerCancelled || status == buyerCancelled) return 0xFFF44336; // Red
    
    // Legacy
    if (status == 'pending') return 0xFFFFA500;
    if (status == 'paid') return 0xFF4CAF50;
    if (status == 'shipped') return 0xFF2196F3;
    if (status == 'delivered' || status == 'completed') return 0xFF4CAF50;
    if (status == 'cancelled') return 0xFFF44336;
    
    return 0xFF9E9E9E; // Gray default
  }

  /// Check if order is completed (for filtering)
  static bool isCompleted(Map<String, dynamic> order) {
    final status = order['status'] as String?;
    final orderState = order['order_state'] as String?;
    final deliveredAt = order['delivered_at'];
    
    return status == 'completed' || 
           status == 'delivered' ||
           orderState == 'completed' || 
           orderState == 'delivered' ||
           deliveredAt != null;
  }

  /// Check if order can be shipped (seller view)
  static bool canShip(Map<String, dynamic> order) {
    final awb = order['awb'] as String?;
    final shippedAt = order['shipped_at'];
    return (awb == null || awb.isEmpty) && shippedAt == null;
  }

  /// Check if dispute window is open
  static bool isDisputeWindowOpen(Map<String, dynamic> order) {
    final deliveredAt = order['delivered_at'];
    if (deliveredAt == null) return false;
    
    try {
      DateTime deliveryDate;
      if (deliveredAt is String) {
        deliveryDate = DateTime.parse(deliveredAt);
      } else if (deliveredAt is int) {
        deliveryDate = DateTime.fromMillisecondsSinceEpoch(deliveredAt);
      } else {
        return false;
      }
      
      final hoursSinceDelivery = DateTime.now().difference(deliveryDate).inHours;
      return hoursSinceDelivery <= 5; // 5 hour dispute window
    } catch (e) {
      return false;
    }
  }

  /// Get status icon
  static String getStatusIcon(String status) {
    if (status == sellerAwaitingShipment) return '📦';
    if (status == buyerPaid) return '✅';
    if (status == sellerShipped || status == buyerInTransit) return '🚚';
    if (status == sellerDelivered || status == buyerDelivered) return '✅';
    if (status == sellerCompleted || status == buyerCompleted) return '🎉';
    if (status == sellerCancelled || status == buyerCancelled) return '❌';
    return '📋';
  }
}
