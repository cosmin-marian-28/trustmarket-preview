import '../helpers/product_image_helper.dart';

/// Helper to get the best image URL for a product
/// Delegates to ProductImageHelper which handles all field name variations
class ImageHelper {
  /// Get image URL for product cards/lists
  /// Checks hover thumbnail first, then falls back to regular images
  static String getProductCardImage(Map<String, dynamic> product) {
    // Try hover thumbnail first (optimized for cards) - check both camelCase and snake_case
    final hover = product['productImageHover'] ?? 
                  product['product_image_hover'] ??
                  product['hover_thumbnail'] ??
                  product['hoverThumbnail'];
    
    if (hover != null && hover is String && hover.isNotEmpty) {
      return hover;
    }
    
    // Use ProductImageHelper to handle all image field variations
    return ProductImageHelper.getFirstImageUrl(product);
  }
  
  /// Get full resolution images for product detail page
  static List<String> getProductDetailImages(Map<String, dynamic> product) {
    return ProductImageHelper.getAllImageUrls(product);
  }
  
  /// Get image URL for service cards
  /// Checks hover thumbnail first, then falls back to regular images
  static String getServiceCardImage(Map<String, dynamic> service) {
    // Try hover thumbnail first - check both camelCase and snake_case
    final hover = service['hoverThumbnail'] ?? 
                  service['hover_thumbnail'];
    
    if (hover != null && hover is String && hover.isNotEmpty) {
      return hover;
    }
    
    // Use ProductImageHelper to handle all image field variations
    return ProductImageHelper.getFirstImageUrl(service);
  }
}
