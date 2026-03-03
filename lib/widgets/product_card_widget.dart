import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../constants/translations.dart';
import '../helpers/image_helper.dart';

/// Reusable product card widget - 100% IDENTICAL to home page design
/// 85/15 split with inverted corners, favorite button, and background circle
class ProductCardWidget extends StatelessWidget {
  final Map<String, dynamic> product;
  final double width;
  final double height;
  final VoidCallback onTap;
  final VoidCallback? onFavoriteTap;
  final bool isFavorited;
  final bool showFavoriteButton;
  final bool showStatusBadge; // Show status badge instead of favorite button
  final Set<String> recentlyViewedIds;
  final bool useAlternatePositioning; // Use lower positioning for seller pages

  const ProductCardWidget({
    super.key,
    required this.product,
    this.width = 160.0,
    this.height = 213.0,
    required this.onTap,
    this.onFavoriteTap,
    this.isFavorited = false,
    this.showFavoriteButton = true,
    this.showStatusBadge = false, // Default to false
    this.recentlyViewedIds = const {},
    this.useAlternatePositioning = false, // Default to false (home page positioning)
  });

  String _getProductPrice() {
    final price = product['price'];
    final currency = product['currency'] ?? 'RON';
    final isNegotiable = product['negotiable'] == true;
    
    if (isNegotiable) return I18n.t('negotiable');
    
    if (price is num) {
      if (price == 0) return I18n.t('negotiable');
      return '${price.toStringAsFixed(0)} $currency';
    } else if (price is String) {
      final priceValue = double.tryParse(price);
      if (priceValue != null) {
        if (priceValue == 0) return I18n.t('negotiable');
        return '${priceValue.toStringAsFixed(0)} $currency';
      } else {
        return price;
      }
    } else {
      return I18n.t('negotiable');
    }
  }

  Widget _buildStatusBadge() {
    final status = product['status'] as String? ?? 'pending';
    
    Color iconColor;
    String svgPath;
    
    switch (status) {
      case 'active':
      case 'confirmed':
        iconColor = Colors.green;
        svgPath = 'assets/icons/listed-accepted.svg';
        break;
      case 'pending':
      case 'pending_review':
        iconColor = Colors.orange;
        svgPath = 'assets/icons/listed-alert.svg';
        break;
      case 'rejected':
        iconColor = Colors.red;
        svgPath = 'assets/icons/listed-rejected.svg';
        break;
      case 'hidden':
        iconColor = Colors.grey;
        svgPath = 'assets/icons/listed-hidden.svg';
        break;
      case 'analyzing':
        iconColor = Colors.blue;
        svgPath = 'assets/icons/listed-waiting.svg';
        break;
      default:
        iconColor = Colors.grey;
        svgPath = 'assets/icons/listed-incomplete.svg';
    }
    
    return Container(
      width: 32,
      height: 32,
      decoration: const BoxDecoration(
        color: Color(0xFF2A2A2A),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: SvgPicture.asset(
          svgPath,
          width: 18,
          height: 18,
          colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = ImageHelper.getProductCardImage(product);
    final productId = product['id'] as String? ?? '';
    
    // Check if product is promoted
    final isPromoted = product['is_promoted'] == true || product['isPromoted'] == true;
    final promotionEndDate = product['promotion_end_date'] ?? product['promotionEndDate'];
    bool isActivePromotion = false;
    
    if (isPromoted && promotionEndDate != null) {
      try {
        final endDate = promotionEndDate is String
            ? DateTime.parse(promotionEndDate)
            : promotionEndDate is DateTime
                ? promotionEndDate
                : DateTime.now();
        isActivePromotion = endDate.isAfter(DateTime.now());
      } catch (e) {
        debugPrint('⚠️ Error parsing promotion end date: $e');
      }
    }
    
    // Check if product was viewed recently
    final wasViewed = recentlyViewedIds.contains(productId);
    
    // Get title
    final title = product['title']?.toString() ?? I18n.t('untitled');

    final card = Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 12,
              spreadRadius: 1,
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Image section with cutout - 85% of card height
                Expanded(
                  flex: 85,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Image with inverted corners at bottom left and right of button
                      ClipPath(
                        clipper: _ImageBottomInvertedCornerClipper(),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.grey[800],
                          ),
                          child: imageUrl.isNotEmpty
                              ? Image.network(
                                  imageUrl,
                                  fit: BoxFit.cover,
                                  alignment: Alignment.center,
                                  width: double.infinity,
                                  height: double.infinity,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          SvgPicture.asset('assets/icons/image.svg', width: 40, height: 40, colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn)),
                                          const SizedBox(height: 8),
                                          const Text('Image not available', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                        ],
                                      ),
                                    );
                                  },
                                )
                              : Center(
                                  child: SvgPicture.asset('assets/icons/products.svg', width: 48, height: 48, colorFilter: ColorFilter.mode(Colors.grey.shade400, BlendMode.srcIn)),
                                ),
                        ),
                      ),
                      // Fill the clipped area with title section color
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: CustomPaint(
                          size: const Size(double.infinity, 30),
                          painter: _CircleCutoutFillPainter(),
                        ),
                      ),
                      // Glassmorphic price pill at top center
                      Positioned(
                        top: 5,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.2),
                                width: 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: RichText(
                              text: TextSpan(
                                children: [
                                  TextSpan(
                                    text: _getProductPrice(),
                                    style: TextStyle(
                                      color: isActivePromotion 
                                          ? const Color(0xFFFF6B6B)
                                          : Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      height: 1.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Status badge for analyzing/pending_review products - REMOVED
                    ],
                  ),
                ),
                // Bottom section - black background with title - 15% of card height
                Expanded(
                  flex: 15,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFF1A1A1A),
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // Red glow for promoted products, faded green glow for viewed products
                        if (isActivePromotion || wasViewed)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            top: -4,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [
                                    (isActivePromotion ? Colors.red : Colors.green).withValues(alpha: 0.15), // More faded (0.15 instead of 0.3)
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        // Title text - centered, white
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 13.2, // 11 * 1.2 = 13.2 (20% larger)
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            // Background circle for favorite button OR status badge
            if (showFavoriteButton || showStatusBadge)
              Positioned(
                bottom: 0,
                right: 0,
                child: FractionalTranslation(
                  translation: const Offset(0, -0.15),
                  child: Transform.translate(
                    offset: showStatusBadge 
                        ? const Offset(-5, -16) // Status badge: moved up from -12 to -16
                        : useAlternatePositioning
                            ? const Offset(-5, -16) // Alternate positioning (seller page): lower
                            : const Offset(-5, -20), // Default positioning (home page): higher
                    child: Container(
                      width: 38, // 32px * 1.1875 = 38px (about 19% bigger)
                      height: 38,
                      decoration: const BoxDecoration(
                        color: Color(0xFF1A1A1A), // Same as title background
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
            // Favorite button OR status badge overlaid on top
            if (showFavoriteButton || showStatusBadge)
              Positioned(
                bottom: 0, // Position at the bottom of the card
                right: 0,
                child: FractionalTranslation(
                  translation: const Offset(0, -0.15), // Move up by 15% of card height to align with 85/15 split
                  child: Transform.translate(
                    offset: showStatusBadge
                        ? const Offset(-8, -20) // Status badge: moved up from -16 to -20
                        : useAlternatePositioning
                            ? const Offset(-8, -20) // Alternate positioning (seller page): lower
                            : const Offset(-8, -24), // Default positioning (home page): higher
                    child: showStatusBadge
                        ? _buildStatusBadge()
                        : GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              if (onFavoriteTap != null) {
                                onFavoriteTap!();
                              }
                            },
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: const BoxDecoration(
                                color: Color(0xFF2A2A2A),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: SvgPicture.asset(
                                  'assets/icons/favorite.svg',
                                  width: 16,
                                  height: 16,
                                  colorFilter: ColorFilter.mode(
                                    isFavorited ? Colors.green : Colors.white,
                                    BlendMode.srcIn,
                                  ),
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
              ),
          ],
        ),
      );

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.deferToChild,
      child: card,
    );
  }
}

// Painter to fill the circular cutout area with title section color
class _CircleCutoutFillPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1A1A1A) // Same as title background
      ..style = PaintingStyle.fill;
    
    const circleRadius = 19.0;
    final circleCenterX = size.width - 8 - 16;
    const cornerRadius = 8.0;
    
    final leftIntersectX = circleCenterX - circleRadius;
    final rightIntersectX = circleCenterX + circleRadius;
    
    final path = Path();
    
    // Start from left edge
    path.moveTo(0, size.height);
    
    // Line to left intersection
    path.lineTo(leftIntersectX - cornerRadius, size.height);
    
    // Left inverted corner
    path.quadraticBezierTo(
      leftIntersectX, size.height,
      leftIntersectX, size.height - cornerRadius,
    );
    
    // Arc around the circle
    path.arcToPoint(
      Offset(rightIntersectX, size.height - cornerRadius),
      radius: const Radius.circular(circleRadius),
      clockwise: false,
    );
    
    // Right inverted corner
    path.quadraticBezierTo(
      rightIntersectX, size.height,
      rightIntersectX + cornerRadius, size.height,
    );
    
    // Line to right edge
    path.lineTo(size.width, size.height);
    
    path.close();
    
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

// Custom clipper for image bottom with circular cutout for button
class _ImageBottomInvertedCornerClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    
    // Background circle specs: 38px diameter
    const circleRadius = 19.0; // Half of 38px
    final circleCenterX = size.width - 8 - 16; // right edge - padding - half button width
    
    // Small inverted corner radius
    const cornerRadius = 8.0;
    
    // Calculate where circle intersects the bottom edge
    final leftIntersectX = circleCenterX - circleRadius;
    final rightIntersectX = circleCenterX + circleRadius;
    
    // Flatten the arc - only cut 6px deep instead of following full circle
    const arcDepth = 6.0;
    
    // Start from top-left
    path.moveTo(0, 0);
    
    // Top edge
    path.lineTo(size.width, 0);
    
    // Right edge straight down
    path.lineTo(size.width, size.height);
    
    // Bottom edge to right intersection point
    path.lineTo(rightIntersectX + cornerRadius, size.height);
    
    // Right inverted corner
    path.quadraticBezierTo(
      rightIntersectX, size.height,
      rightIntersectX, size.height - cornerRadius,
    );
    
    // Flattened arc - gentle curve instead of full circle
    path.quadraticBezierTo(
      circleCenterX, size.height - arcDepth, // Control point - shallow depth
      leftIntersectX, size.height - cornerRadius,
    );
    
    // Left inverted corner
    path.quadraticBezierTo(
      leftIntersectX, size.height,
      leftIntersectX - cornerRadius, size.height,
    );
    
    // Bottom edge to left
    path.lineTo(0, size.height);
    
    // Left edge back to top
    path.lineTo(0, 0);
    
    path.close();
    
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
