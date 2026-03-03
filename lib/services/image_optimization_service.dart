import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'supabase_service.dart';

/// Service to optimize images for storage and delivery
class ImageOptimizationService {
  static final _supabase = SupabaseService.instance.client;

  /// Resize image bytes to a smaller resolution for hover preview
  /// Typically used for card thumbnails: 300x300 or 400x400
  /// Runs on client side before upload for better performance
  /// Uses native compression on iOS/Android for better performance
  /// 
  /// Recommended sizes:
  /// - Grid thumbnails: 300x300, quality 80
  /// - List thumbnails: 400x400, quality 85
  /// - Detail page thumbnails: 600x600, quality 90
  static Future<Uint8List> resizeImage({
    required Uint8List imageBytes,
    required int maxWidth,
    required int maxHeight,
    int quality = 80,  // JPEG quality 0-100 (lowered default for faster loading)
  }) async {
    try {
      debugPrint('📐 Resizing image to ${maxWidth}x$maxHeight (quality: $quality)');
      debugPrint('   Original size: ${imageBytes.length} bytes');
      
      // Try native compression first (faster on iOS/Android)
      if (!kIsWeb) {
        try {
          debugPrint('   Using native flutter_image_compress (iOS/Android)...');
          final compressed = await FlutterImageCompress.compressWithList(
            imageBytes,
            minWidth: maxWidth,
            minHeight: maxHeight,
            quality: quality,
            format: CompressFormat.jpeg,
          );
          
          if (compressed.isNotEmpty) {
            final savedBytes = ((1 - compressed.length / imageBytes.length) * 100)
                .toStringAsFixed(1);
            debugPrint('   Resized size: ${compressed.length} bytes');
            debugPrint('   ✓ Space saved: $savedBytes%');
            return Uint8List.fromList(compressed);
          }
        } catch (e) {
          debugPrint('⚠️ Native compression failed, falling back to Dart: $e');
        }
      }
      
      // Fallback to pure Dart implementation (Web or if native fails)
      debugPrint('   Using pure Dart image package (Web or fallback)...');
      final image = img.decodeImage(imageBytes);
      if (image == null) {
        debugPrint('⚠️ Could not decode image - returning original');
        return imageBytes;
      }

      debugPrint('   Original dimensions: ${image.width}x${image.height}');

      // Calculate new dimensions while maintaining aspect ratio
      double scale = 1.0;
      if (image.width > maxWidth || image.height > maxHeight) {
        final scaleWidth = maxWidth / image.width;
        final scaleHeight = maxHeight / image.height;
        scale = scaleWidth < scaleHeight ? scaleWidth : scaleHeight;
      }

      final newWidth = (image.width * scale).toInt();
      final newHeight = (image.height * scale).toInt();

      debugPrint('   New dimensions: ${newWidth}x$newHeight (scale: ${(scale * 100).toStringAsFixed(1)}%)');

      // Resize the image
      final resized = img.copyResize(
        image,
        width: newWidth,
        height: newHeight,
        interpolation: img.Interpolation.linear,
      );

      // Encode as JPEG with quality setting
      final resizedBytes = Uint8List.fromList(
        img.encodeJpg(resized, quality: quality),
      );

      final savedBytes = ((1 - resizedBytes.length / imageBytes.length) * 100)
          .toStringAsFixed(1);
      debugPrint('   Resized size: ${resizedBytes.length} bytes');
      debugPrint('   ✓ Space saved: $savedBytes%');
      
      return resizedBytes;
    } catch (e) {
      debugPrint('⚠️ Image resize failed: $e');
      debugPrint('   Returning original image bytes');
      return imageBytes; // Return original on error - safer fallback
    }
  }

  /// Upload a hover thumbnail for any item (product, service, gig)
  /// Ensures output is under 200KB for fast card loading
  static Future<String?> uploadHoverThumbnail({
    required String productId,
    required Uint8List imageBytes,
    required int maxWidth,
    required int maxHeight,
    String bucket = 'products',
  }) async {
    try {
      debugPrint('📸 Creating hover thumbnail for $bucket item: $productId');
      debugPrint('   Input image size: ${(imageBytes.length / 1024).toStringAsFixed(0)}KB');
      debugPrint('   Target dimensions: ${maxWidth}x$maxHeight');
      
      // Resize with aggressive compression to stay under 200KB
      var resizedBytes = await resizeImage(
        imageBytes: imageBytes,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        quality: 70,
      );

      // If still over 200KB, reduce quality further
      if (resizedBytes.length > 200 * 1024) {
        debugPrint('   Still over 200KB (${(resizedBytes.length / 1024).toStringAsFixed(0)}KB), reducing quality to 55...');
        resizedBytes = await resizeImage(
          imageBytes: imageBytes,
          maxWidth: maxWidth,
          maxHeight: maxHeight,
          quality: 55,
        );
      }

      // If STILL over 200KB, shrink dimensions too
      if (resizedBytes.length > 200 * 1024) {
        debugPrint('   Still over 200KB (${(resizedBytes.length / 1024).toStringAsFixed(0)}KB), reducing to 300x300 q40...');
        resizedBytes = await resizeImage(
          imageBytes: imageBytes,
          maxWidth: 300,
          maxHeight: 300,
          quality: 40,
        );
      }

      debugPrint('   Final hover size: ${(resizedBytes.length / 1024).toStringAsFixed(0)}KB');

      // Upload to Supabase Storage
      final hoverPath = 'hover/${productId}_hover.jpg';
      
      debugPrint('   Uploading to bucket "$bucket": $hoverPath');

      await _supabase.storage
          .from(bucket)
          .uploadBinary(hoverPath, resizedBytes);

      final downloadUrl = _supabase.storage
          .from(bucket)
          .getPublicUrl(hoverPath);
          
      debugPrint('   ✓ Hover thumbnail uploaded! ${(resizedBytes.length / 1024).toStringAsFixed(0)}KB');
      debugPrint('   URL: $downloadUrl');
      
      return downloadUrl;
    } catch (e, stackTrace) {
      debugPrint('❌ Error uploading hover thumbnail: $e');
      debugPrint('   Stack trace: $stackTrace');
      return null;
    }
  }

  /// Get hover thumbnail URL for a product
  static Future<String?> getHoverThumbnailUrl(String productId) async {
    try {
      final hoverPath = 'hover/${productId}_hover.jpg';
      final url = _supabase.storage
          .from('products')
          .getPublicUrl(hoverPath);
      return url;
    } catch (e) {
      debugPrint('❌ Error getting hover thumbnail URL: $e');
      return null;
    }
  }

  /// Delete hover thumbnail for a product
  static Future<bool> deleteHoverThumbnail(String productId) async {
    try {
      final hoverPath = 'hover/${productId}_hover.jpg';
      
      await _supabase.storage
          .from('products')
          .remove([hoverPath]);
          
      debugPrint('✓ Deleted hover thumbnail for product: $productId');
      return true;
    } catch (e) {
      debugPrint('❌ Error deleting hover thumbnail: $e');
      return false;
    }
  }

  /// Check if hover thumbnail exists for a product
  static Future<bool> hoverThumbnailExists(String productId) async {
    try {
      
      final files = await _supabase.storage
          .from('products')
          .list(path: 'hover');
      
      return files.any((file) => file.name == '${productId}_hover.jpg');
    } catch (e) {
      return false;
    }
  }

  /// Create multiple thumbnail sizes for optimal loading
  static Future<Map<String, String>> createMultiSizeThumbnails({
    required String productId,
    required Uint8List imageBytes,
  }) async {
    final urls = <String, String>{};

    try {
      // Small thumbnail
      final smallBytes = await resizeImage(
        imageBytes: imageBytes,
        maxWidth: 200,
        maxHeight: 200,
        quality: 75,
      );
      final smallPath = 'thumbnails/${productId}_small.jpg';
      await _supabase.storage.from('products').uploadBinary(smallPath, smallBytes);
      urls['small'] = _supabase.storage.from('products').getPublicUrl(smallPath);

      // Medium thumbnail
      final mediumBytes = await resizeImage(
        imageBytes: imageBytes,
        maxWidth: 400,
        maxHeight: 400,
        quality: 80,
      );
      final mediumPath = 'thumbnails/${productId}_medium.jpg';
      await _supabase.storage.from('products').uploadBinary(mediumPath, mediumBytes);
      urls['medium'] = _supabase.storage.from('products').getPublicUrl(mediumPath);

      // Large thumbnail
      final largeBytes = await resizeImage(
        imageBytes: imageBytes,
        maxWidth: 800,
        maxHeight: 800,
        quality: 85,
      );
      final largePath = 'thumbnails/${productId}_large.jpg';
      await _supabase.storage.from('products').uploadBinary(largePath, largeBytes);
      urls['large'] = _supabase.storage.from('products').getPublicUrl(largePath);

      debugPrint('✓ Created multi-size thumbnails for product: $productId');
      return urls;
    } catch (e) {
      debugPrint('❌ Error creating multi-size thumbnails: $e');
      return urls;
    }
  }

  /// Get thumbnail URL by size
  static Future<String?> getThumbnailUrl(String productId, String size) async {
    try {
      final path = 'thumbnails/${productId}_$size.jpg';
      return _supabase.storage.from('products').getPublicUrl(path);
    } catch (e) {
      return null;
    }
  }
}
