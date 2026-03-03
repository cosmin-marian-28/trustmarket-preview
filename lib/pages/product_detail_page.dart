import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'dart:async';
import 'dart:io';
import '../services/supabase_service.dart';
// dart:math no longer needed in this file
import '../widgets/first_message.dart';
import '../widgets/promote_product_modal.dart';
import '../widgets/liquid_glass_button.dart';
import '../widgets/go_back_button.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../widgets/price_with_conversion_widget.dart';
import '../widgets/product_card_widget.dart';
import 'seller.dart';
import '../helpers/notification_helper.dart';
import '../helpers/product_image_helper.dart';
import '../helpers/country_flag_helper.dart';
import 'profile_page.dart';
import '../constants/translations.dart';
import '../services/language_service.dart';
import '../services/currency_service.dart';
import '../services/product_view_history_service.dart';
import '../services/image_loading_service.dart';
import '../services/image_optimization_service.dart';
import 'order_checkout_page.dart';
import '../constants/payment_constants.dart';
import '../utils/camera.dart';
import '../widgets/shimmer_loading.dart';



class ProductDetailPage extends StatefulWidget {
  final Map<String, dynamic> product;

  const ProductDetailPage({super.key, required this.product});

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

// Internal address carousel extracted to avoid rebuilding the entire
// ProductDetailPage when the user swipes between saved addresses. This
// widget manages its own PageController and internal selected index so
// swiping doesn't trigger a parent setState and won't cause the page to
// jump or refetch unrelated futures.
class _AddressCarousel extends StatefulWidget {
  final List<dynamic> addresses;
  final int initialIndex;
  final ValueChanged<int>? onAddressTap;

  const _AddressCarousel({required this.addresses, this.initialIndex = 0, this.onAddressTap});

  @override
  State<_AddressCarousel> createState() => _AddressCarouselState();

}

class _AddressCarouselState extends State<_AddressCarousel> {
  int _internalSelected = -1;
  late PageController _controller;

  @override
  void initState() {
    super.initState();
    final start = (widget.initialIndex >= 0 && widget.initialIndex < widget.addresses.length) ? widget.initialIndex : 0;
    _internalSelected = widget.initialIndex;
    _controller = PageController(initialPage: start, viewportFraction: 1.0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _AddressCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.addresses.length != oldWidget.addresses.length) {
      // Clamp selected index if list shrank
      if (_internalSelected >= widget.addresses.length) {
        _internalSelected = widget.addresses.isNotEmpty ? widget.addresses.length - 1 : -1;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _controller.hasClients && _internalSelected >= 0) _controller.jumpToPage(_internalSelected);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final addresses = widget.addresses;
    if (addresses.isEmpty) return const SizedBox.shrink();

    final screenWidth = MediaQuery.of(context).size.width;
    const outerPadding = 16.0; // Match page padding
    final cardWidth = screenWidth - (outerPadding * 2);

    return SizedBox(
      height: 100,
      child: OverflowBox(
        maxWidth: screenWidth,
        alignment: Alignment.centerLeft,
        child: Transform.translate(
          offset: const Offset(-outerPadding, 0),
          child: SizedBox(
            width: screenWidth,
            child: PageView.builder(
              controller: _controller,
              itemCount: addresses.length,
              physics: const BouncingScrollPhysics(),
              padEnds: false,
              onPageChanged: (page) {
                // Only update internal visuals; don't call parent setState on swipe
                setState(() {
                  _internalSelected = page;
                });
              },
              itemBuilder: (context, idx) {
                final addr = addresses[idx] as Map<String, dynamic>? ?? {};
                final isSelected = _internalSelected == idx;

                return Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: cardWidth,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: () {
                          final newSelected = isSelected ? -1 : idx;
                          setState(() {
                            _internalSelected = newSelected;
                          });
                          if (widget.onAddressTap != null) widget.onAddressTap!(idx);
                        },
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                          decoration: BoxDecoration(
                            color: Colors.grey[900],
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.max,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      addr['name'] ?? I18n.t('address'),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isSelected) const SizedBox(width: 8),
                                  if (isSelected)
                                    Transform.translate(
                                      offset: const Offset(0, -6),
                                      child: const Icon(Icons.check_circle, color: Colors.green),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                [
                                  addr['city'] ?? '',
                                  (addr['zip'] ?? '').toString(),
                                  addr['street'] ?? '',
                                  addr['building'] ?? '',
                                ].where((s) => s != null && s.toString().trim().isNotEmpty).join(', '),
                                style: TextStyle(
                                  color: Colors.grey[300],
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${I18n.t('phone')} ${addr['phone'] ?? ''}',
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductDetailPageState extends State<ProductDetailPage> with WidgetsBindingObserver {
  late Map<String, dynamic> productData;
  List<MapEntry<String, String>> answers = [];
  bool isLoadingQuestions = false;
  bool _showMessageInput = false;
  bool _showAddressForm = false;  // Track if showing add address form
  int _selectedAddressIndex = -1;  // Track selected address
  int _selectedQuantity = 1;  // Track quantity for multi-item purchase
  Map<String, dynamic>? _selectedAddressData; // cache selected address data
  // Track which address index the form is editing.
  // -2 = unset (decide from selection or existing addresses), -1 = new address, >=0 existing index
  int _formAddressIndex = -2;
  int _currentImageIndex = 0;
  late PageController _pageController;
  // Controller dedicated to the addresses PageView was replaced by a
  // dedicated widget `_AddressCarousel` to avoid rebuilding the parent on swipe.
  // Main vertical scroll controller to preserve scroll offset across rebuilds
  late ScrollController _mainScrollController;
  int _selectedOfferPercentage = 0;  // Track selected offer percentage
  bool _isEditingPrice = false;  // Track if price is being edited
  late TextEditingController _priceController;  // Controller for inline price editing
  bool _isFavorited = false;  // Track if product is favorited
  // Offer slider UI state
  bool _showOfferSlider = false;
  double _offerSliderValue = 0.0;
  double _offerSliderMin = 0.0;
  double _offerSliderMax = 0.0;
  // Store original product price while buyer is composing an offer so we
  // can restore it if the buyer cancels the inline offer.
  dynamic _originalPrice;
  // Whether the current user (buyer) already has an accepted offer for this product
  bool _hasAcceptedOfferForThisProduct = false;
  // Offer send rate-limit / countdown state for buyer
  bool _offerBlockedByTimeout = false;
  int _offerHoursRemaining = 0; // hours remaining to show inside the button
  Timer? _offerExpiryTimer;
  
  // Missing info answers tracking (for pending_review products)
  final Map<int, String> _missingInfoAnswers = {}; // Map of question index to selected answer
  
  // Confirmed quantity tracking (for group buy)
  int? _confirmedQuantity; // Max quantity confirmed by seller
  DateTime? _quantityExpiresAt; // When the confirmation expires (3 hours)
  Timer? _quantityExpiryTimer; // Timer to update UI when expired
  int _quantityHoursRemaining = 0; // Hours remaining to show in the button
  
  // Currency conversion controller (shared between price display and button)
  late PriceConversionController _priceConversionController;
  
  // Address form controllers
  late TextEditingController _nameCtrl;
  late TextEditingController _streetCtrl;
  late TextEditingController _cityCtrl;
  late TextEditingController _buildingCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _zipCtrl;
  
  // Cache the user document future so FutureBuilder doesn't refetch on every rebuild
  late Future<Map<String, dynamic>?> _userDocFuture;
  // Seller info futures
  late Future<Map<String, dynamic>?> _sellerDocFuture;
  // Cache seller's other products future so rebuilds don't re-fetch and cause flicker
  late Future<List<Map<String, dynamic>>> _sellerProductsFuture;
  
  // Product statistics
  int _totalViews = 0;
  int _totalFavorites = 0;
  int _totalMessages = 0;
  bool _isLoadingStats = true;
  bool _isRetrying = false;
  
  // Track recently viewed product IDs
  Set<String> _recentlyViewedIds = {};
  
  // Track favorited product IDs for seller's products section
  Set<String> _favoritedProductIds = {};

  @override
  void initState() {
    super.initState();
    
    // Add observer for app lifecycle changes
    WidgetsBinding.instance.addObserver(this);
    
    productData = widget.product;
    // Load recently viewed IDs
    _loadRecentlyViewedIds();
    // Check if buyer recently sent an offer for this product and set up timeout state
    _checkLastOfferForBuyer();
    final currentUser = SupabaseService.instance.currentUser;
    _userDocFuture = _loadUserData(currentUser?.id);
    // Initialize seller futures if product has a userId/seller_id
    final sellerId = productData['userId'] as String? ?? 
                     productData['user_id'] as String? ?? 
                     productData['sellerId'] as String? ?? 
                     productData['seller_id'] as String?;
    if (sellerId != null && sellerId.isNotEmpty) {
      _sellerDocFuture = _loadUserData(sellerId);
      _sellerProductsFuture = SupabaseService.instance.products
          .select()
          .eq('seller_id', sellerId)
          .eq('status', 'active') // Only show active products
          .limit(10);
      // Prefetch seller profile data (photo/name) into productData so the page
      // can display the seller image without waiting for FutureBuilders.
      _sellerDocFuture.then((doc) async {
        if (!mounted) return;
        try {
          if (doc != null && doc.isNotEmpty) {
            final data = doc;
            // Pick profile_image_url
            String? photoCandidate;
            final val = data['profile_image_url']?.toString();
            if (val != null && val.isNotEmpty) {
              photoCandidate = val;
            }

            debugPrint('Seller doc keys: ${data.keys.toList()}');
            debugPrint('Initial photoCandidate: $photoCandidate');

            // If the stored value is a Storage path (not an http URL), try to
            // resolve it to a public URL from Supabase Storage.
            if (photoCandidate != null && photoCandidate.isNotEmpty && !photoCandidate.startsWith('http')) {
              try {
                // Assume it's a path in the avatars bucket
                // Normalize leading slash if present
                final refPath = photoCandidate.startsWith('/') ? photoCandidate.substring(1) : photoCandidate;
                
                // Get public URL from Supabase
                final publicUrl = SupabaseService.instance.getPublicUrl('avatars', refPath);
                photoCandidate = publicUrl;
                debugPrint('Resolved seller photo to Supabase public URL: $publicUrl');
              } catch (e) {
                debugPrint('Could not resolve storage image path for seller: $e');
                // fallback: keep original candidate
              }
            }

            setState(() {
              // Only set productData values if they aren't already provided by the product
              final newPhoto = productData['sellerPhoto'] ?? photoCandidate;
              final newName = productData['sellerName'] ?? (data['display_name'] ?? data['name']);
              // Fallback country/city from seller profile if product doesn't have them
              final newCountry = productData['country'] ?? data['country'];
              final newCity = productData['seller_city'] ?? data['city'];
              // Skip rebuild if nothing actually changed
              if (productData['sellerPhoto'] == newPhoto && 
                  productData['sellerName'] == newName &&
                  productData['country'] == newCountry &&
                  productData['seller_city'] == newCity) {
                return;
              }
              productData['sellerPhoto'] = newPhoto;
              productData['sellerName'] = newName;
              if (newCountry != null) productData['country'] = newCountry;
              if (newCity != null) productData['seller_city'] = newCity;
            });
          }
        } catch (e) {
          debugPrint('Error prefetching seller profile: $e');
        }
      });
    } else {
      // Fallback to empty futures to avoid null checks later
      _sellerDocFuture = Future.value(null);
      _sellerProductsFuture = Future.value(<Map<String, dynamic>>[]);
    }
    _loadAnswers();
    _loadOfferPercentage();
  // Check whether the current user already has an accepted offer for this product
  _checkIfBuyerHasAcceptedOffer();
    _trackProductView();
    // Check for confirmed quantity requests
    _checkConfirmedQuantity();
    _pageController = PageController(initialPage: 0);
  // address carousel uses its own controller now
  _mainScrollController = ScrollController();
    
    // Load favorites status for this product
    _loadFavoriteStatus();
    
    // Initialize form controllers
    _nameCtrl = TextEditingController();
    _streetCtrl = TextEditingController();
    _cityCtrl = TextEditingController();
    _buildingCtrl = TextEditingController();
    _phoneCtrl = TextEditingController();
    _zipCtrl = TextEditingController();
    _priceController = TextEditingController();
    _priceConversionController = PriceConversionController();
    // Listen for language changes so tags can be retranslated dynamically
    LanguageService.languageNotifier.addListener(_onLanguageChanged);
  }

  /// Helper to get inventory count (handles both camelCase and snake_case)
  int _getInventoryCount() {
    return productData['inventoryCount'] as int? ?? 
           productData['inventory_count'] as int? ?? 
           0;
  }

  /// Helper to set inventory count (updates both formats for compatibility)
  void _setInventoryCount(int count) {
    setState(() {
      productData['inventoryCount'] = count;
      productData['inventory_count'] = count;
    });
  }
  
  Future<Map<String, dynamic>?> _loadUserData(String? userId) async {
    if (userId == null || userId.isEmpty) return null;
    try {
      final response = await SupabaseService.instance.users
          .select()
          .eq('id', userId)
          .maybeSingle();
      return response;
    } catch (e) {
      debugPrint('Error loading user data: $e');
      return null;
    }
  }

  bool get _isOwner {
    final currentUserId = SupabaseService.instance.currentUser?.id;
    // Check both camelCase and snake_case field names
    final productUserId = productData['userId'] as String? ?? 
                          productData['user_id'] as String? ??
                          productData['sellerId'] as String? ??
                          productData['seller_id'] as String?;
    return currentUserId != null && currentUserId == productUserId;
  }

  bool get _isBuyer => !_isOwner;

  Future<void> _checkLastOfferForBuyer() async {
    try {
      final buyer = SupabaseService.instance.currentUser;
      final productId = productData['id'] as String?;
      if (buyer == null || productId == null) return;

      // Query offers from Supabase
      final offers = await SupabaseService.instance.offers
          .select()
          .eq('product_id', productId)
          .eq('buyer_id', buyer.id)
          .order('created_at', ascending: false)
          .limit(1);

      if (offers.isEmpty) {
        if (mounted) {
          setState(() {
            _offerBlockedByTimeout = false;
            _offerHoursRemaining = 0;
          });
        }
        return;
      }

      final prev = offers.first;
      final prevStatus = (prev['status'] as String?) ?? 'pending';
      final createdAtRaw = prev['created_at'];
      DateTime? createdAt;
      if (createdAtRaw is String) {
        createdAt = DateTime.parse(createdAtRaw);
      } else if (createdAtRaw is DateTime) {
        createdAt = createdAtRaw;
      }

      // If we can't determine creation time, don't block
      if (createdAt == null) {
        if (mounted) setState(() => _offerBlockedByTimeout = false);
        return;
      }

      // If last offer was rejected, allow new offers immediately
      if (prevStatus == 'rejected') {
        if (mounted) {
          setState(() {
          _offerBlockedByTimeout = false;
          _offerHoursRemaining = 0;
        });
        }
        return;
      }

      // If last offer was accepted, we rely on existing _hasAcceptedOfferForThisProduct logic to hide the Make Offer button.
      if (prevStatus == 'accepted') {
        if (mounted) {
          setState(() {
          _offerBlockedByTimeout = false;
          _offerHoursRemaining = 0;
        });
        }
        return;
      }

      // Compute remaining time from creation to 24 hours
      final now = DateTime.now();
      final elapsed = now.difference(createdAt);
      const totalSeconds = 24 * 3600;
      final secondsLeft = totalSeconds - elapsed.inSeconds;
      if (secondsLeft > 0) {
        final hours = (secondsLeft + 3599) ~/ 3600; // ceil to hours
        if (mounted) {
          setState(() {
          _offerBlockedByTimeout = true;
          _offerHoursRemaining = hours;
        });
        }

        _offerExpiryTimer?.cancel();
        _offerExpiryTimer = Timer(Duration(seconds: secondsLeft), () {
          _checkLastOfferForBuyer();
        });
      } else {
        if (mounted) {
          setState(() {
          _offerBlockedByTimeout = false;
          _offerHoursRemaining = 0;
        });
        }
      }
    } catch (e) {
      debugPrint('Error checking last offer: $e');
    }
  }

  /// Check for confirmed quantity requests from seller
  /// Loads the most recent confirmed quantity and expiration time
  Future<void> _checkConfirmedQuantity() async {
    try {
      final buyer = SupabaseService.instance.currentUser;
      final productId = productData['id'] as String?;
      final sellerId = productData['userId'] as String? ?? 
                       productData['user_id'] as String? ?? 
                       productData['seller_id'] as String?;
      
      if (buyer == null || productId == null || sellerId == null) return;
      if (buyer.id == sellerId) return; // Don't check for own products
      
      // Create conversation ID (same format as offers)
      final ids = [buyer.id, sellerId];
      ids.sort();
      final conversationId = 'conv_${ids[0]}_${ids[1]}';
      
      debugPrint('🔍 Checking for confirmed quantity: conversationId=$conversationId, productId=$productId');
      
      // Query messages from Supabase - look for confirmed quantity requests
      // Don't filter by sender_id since the buyer sends the request but seller confirms it
      final messages = await SupabaseService.instance.messages
          .select()
          .eq('conversation_id', conversationId)
          .eq('type', 'quantity_request')
          .eq('status', 'confirmed')
          .eq('product_id', productId)
          .order('confirmed_at', ascending: false)
          .limit(1);
      
      debugPrint('🔍 Found ${messages.length} confirmed quantity messages');
      
      if (messages.isEmpty) {
        if (mounted) {
          setState(() {
            _confirmedQuantity = null;
            _quantityExpiresAt = null;
            _quantityHoursRemaining = 0;
          });
        }
        return;
      }
      
      final data = messages.first;
      final confirmedQty = data['quantity_requested'] as int?;
      final expiresAtRaw = data['expires_at'];
      
      debugPrint('✅ Found confirmed quantity: qty=$confirmedQty, expiresAt=$expiresAtRaw');
      
      DateTime? expiresAt;
      if (expiresAtRaw is String) {
        expiresAt = DateTime.parse(expiresAtRaw);
      } else if (expiresAtRaw is DateTime) {
        expiresAt = expiresAtRaw;
      }
      
      // Check if expired
      final now = DateTime.now();
      if (expiresAt != null && now.isAfter(expiresAt)) {
        // Expired - clear state
        debugPrint('⏰ Quantity confirmation expired');
        if (mounted) {
          setState(() {
            _confirmedQuantity = null;
            _quantityExpiresAt = null;
            _quantityHoursRemaining = 0;
          });
        }
        return;
      }
      
      // Valid confirmation found
      if (mounted) {
        setState(() {
          _confirmedQuantity = confirmedQty;
          _quantityExpiresAt = expiresAt;
          // Calculate hours remaining
          if (expiresAt != null) {
            final remaining = expiresAt.difference(now);
            _quantityHoursRemaining = (remaining.inSeconds + 3599) ~/ 3600; // ceil to hours
          }
          // SET the selected quantity to the confirmed amount (not just limit it)
          _selectedQuantity = confirmedQty ?? 1;
        });
        
        // Set up timer to refresh when expired
        if (expiresAt != null) {
          final timeUntilExpiry = expiresAt.difference(now);
          if (timeUntilExpiry.inSeconds > 0) {
            _quantityExpiryTimer?.cancel();
            _quantityExpiryTimer = Timer(timeUntilExpiry, () {
              _checkConfirmedQuantity();
            });
          }
        }
      }
      
      debugPrint('✅ Confirmed quantity loaded: $_confirmedQuantity, selected: $_selectedQuantity, hours: $_quantityHoursRemaining');
    } catch (e) {
      debugPrint('❌ Error checking confirmed quantity: $e');
    }
  }

  void _onLanguageChanged() {
    // When the app language changes, update I18n and reload answers (tags)
    setState(() {
      I18n.current = LanguageService.current;
    });
    _loadAnswers();
  }

  @override
  void didUpdateWidget(covariant ProductDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the product or seller changed (for example when navigating to another
    // product without rebuilding the route), refresh cached futures so their
    // FutureBuilders don't refetch unnecessarily on unrelated rebuilds.
    final oldId = oldWidget.product['id'] as String?;
    final newId = widget.product['id'] as String?;
    final oldSeller = oldWidget.product['user_id'] as String? ?? oldWidget.product['userId'] as String?;
    final newSeller = widget.product['user_id'] as String? ?? widget.product['userId'] as String?;

    if (oldId != newId || oldSeller != newSeller) {
      setState(() {
        productData = widget.product;
        final sellerId = productData['user_id'] as String? ?? productData['userId'] as String?;
        if (sellerId != null && sellerId.isNotEmpty) {
          _sellerDocFuture = _loadUserData(sellerId);
          _sellerProductsFuture = SupabaseService.instance.products
              .select()
              .eq('seller_id', sellerId)
              .eq('status', 'active') // Only show active products
              .limit(10);
        } else {
          _sellerDocFuture = Future.value(null);
          _sellerProductsFuture = Future.value(<Map<String, dynamic>>[]);
        }
        _currentImageIndex = 0;
      });
    }
  }

  // Compact inline seller info used to display to the right of the 'Ask the Seller' heading.
  Widget _buildSellerInline() {
    final sellerNameFromProduct = productData['sellerName'] as String?;
    final sellerPhotoFromProduct = productData['sellerPhoto'] as String?;
    return FutureBuilder<Map<String, dynamic>?>(
      future: _sellerDocFuture,
      builder: (context, snapshot) {
        String sellerName = sellerNameFromProduct ?? I18n.t('seller');
        String? sellerPhoto = sellerPhotoFromProduct;

        if (snapshot.hasData && snapshot.data != null) {
          final data = snapshot.data!;
          sellerName = sellerNameFromProduct ?? (data['display_name'] as String? ?? data['name'] as String? ?? sellerName);
          // Check each photo field, skipping empty strings
          String? rawPhoto = sellerPhotoFromProduct;
          if (rawPhoto == null || rawPhoto.isEmpty) {
            final val = data['profile_image_url']?.toString();
            if (val != null && val.isNotEmpty) {
              rawPhoto = val;
            }
          }
          // Resolve storage paths to public URLs
          if (rawPhoto != null && rawPhoto.isNotEmpty && !rawPhoto.startsWith('http')) {
            try {
              final refPath = rawPhoto.startsWith('/') ? rawPhoto.substring(1) : rawPhoto;
              rawPhoto = SupabaseService.instance.getPublicUrl('avatars', refPath);
            } catch (_) {}
          }
          sellerPhoto = rawPhoto;
        }

        // Make the inline seller widget match the approximate height of the
        // "Ask the Seller" heading. Use a fixed container height and smaller
        // avatar so the whole row aligns visually.
        final sellerId = productData['userId'] as String? ?? 
                        productData['user_id'] as String? ?? 
                        productData['sellerId'] as String? ?? 
                        productData['seller_id'] as String? ?? '';
        return GestureDetector(
          onTap: () {
            if (sellerId.isNotEmpty) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SellerPage(
                    sellerId: sellerId,
                    sellerName: sellerName,
                    sellerPhoto: sellerPhoto,
                  ),
                ),
              );
            }
          },
          child: SizedBox(
            height: 24, // match heading text height (~14px font + padding)
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircleAvatar(
                    backgroundImage: sellerPhoto != null && sellerPhoto.isNotEmpty 
                        ? NetworkImage(sellerPhoto) 
                        : const AssetImage('assets/card_logos/noimage.png') as ImageProvider,
                    radius: 12,
                    backgroundColor: Colors.grey[700],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 24,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: 120,
                      child: Text(
                        sellerName,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    // Remove observer
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
  // address carousel disposes its own controller
  _mainScrollController.dispose();
    _nameCtrl.dispose();
    _streetCtrl.dispose();
    _cityCtrl.dispose();
    _buildingCtrl.dispose();
    _phoneCtrl.dispose();
    _zipCtrl.dispose();
    _priceController.dispose();
    _priceConversionController.dispose();
    _offerExpiryTimer?.cancel();
    _quantityExpiryTimer?.cancel();
    // Remove language listener
    LanguageService.languageNotifier.removeListener(_onLanguageChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Reload viewed IDs when app resumes or when returning to this page
    if (state == AppLifecycleState.resumed) {
      _loadRecentlyViewedIds();
      // Refresh quantity confirmation in case it was used/expired
      _checkConfirmedQuantity();
      // Refresh product data to get updated inventory
      _refreshProductData();
    }
  }
  
  /// Refresh product data from database
  Future<void> _refreshProductData() async {
    try {
      final productId = productData['id'] as String?;
      if (productId != null) {
        final response = await SupabaseService.instance.products
            .select()
            .eq('id', productId)
            .maybeSingle();
        
        if (response != null && mounted) {
          setState(() {
            productData = response;
            _setInventoryCount(response['inventory_count'] ?? 0);
          });
          debugPrint('✅ Product data refreshed');
        }
      }
    } catch (e) {
      debugPrint('❌ Error refreshing product: $e');
    }
  }

  // Format DateTime / String into a short readable date
  String _formatProductDate(dynamic ts) {
    if (ts == null) return '';
    DateTime dt;
    try {
      if (ts is DateTime) {
        dt = ts;
      } else if (ts is String) {
        dt = DateTime.parse(ts);
      } else {
        // Unknown type: return its string representation
        return ts.toString();
      }
    } catch (e) {
      return ts.toString();
    }

    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final month = months[(dt.month - 1).clamp(0, 11)];
    return '${dt.day} $month, ${dt.year}';
  }

  // Format a price value with a currency code. Falls back to productData['currency'] or
  // the global CurrencyService.current if no currency is provided.
  String _formatPrice(dynamic price, [String? currency]) {
    final code = currency ?? (productData['currency'] as String?) ?? CurrencyService.current;
    if (price == null) return '0 $code';
    if (price is num) return '${price.toStringAsFixed(0)} $code';
    final parsed = double.tryParse(price.toString());
    if (parsed != null) return '${parsed.toStringAsFixed(0)} $code';
    return '${price.toString()} $code';
  }

  // Track which address index we've loaded into the controllers to avoid
  // mutating controllers repeatedly during rebuilds (which resets focus/selection)
  int _loadedAddressIndex = -1;

  void _loadAddressIntoControllers(Map<String, dynamic> addr, int index) {
    if (_loadedAddressIndex == index) return; // already loaded

    _nameCtrl.text = addr['name'] ?? '';
    _streetCtrl.text = addr['street'] ?? '';
    _buildingCtrl.text = addr['building'] ?? '';
    _cityCtrl.text = addr['city'] ?? '';
    _zipCtrl.text = addr['zip'] ?? '';
    _phoneCtrl.text = addr['phone'] ?? '';

    _loadedAddressIndex = index;
  }

  Future<void> _loadAnswers() async {
    try {
      final currentLang = I18n.current.name.toLowerCase();
      // Use detected_language if available, otherwise fallback to userLanguage
      final productLang = (productData['detected_language'] as String? ?? productData['userLanguage'] as String? ?? 'en').toLowerCase();
      
      debugPrint('[ANSWERS] Loading answers for product ${productData['id']}');
      debugPrint('[ANSWERS] Current language: $currentLang, Product language: $productLang');
      debugPrint('[ANSWERS] Raw answers field: ${productData['answers']}');
      debugPrint('[ANSWERS] Raw answers_english field: ${productData['answers_english']}');
      
      // Load answers based on language matching (same logic as titles)
      Map<String, dynamic> answersMap;
      
      if (currentLang == productLang) {
        // Viewer's language matches product's language, show product's language answers
        answersMap = productData['answers'] as Map<String, dynamic>? ?? {};
        debugPrint('[ANSWERS] Using product language answers: ${answersMap.keys.length} keys');
      } else {
        // Languages don't match, fallback to English answers
        answersMap = productData['answers_english'] as Map<String, dynamic>? ?? productData['answersEnglish'] as Map<String, dynamic>? ?? productData['answers'] as Map<String, dynamic>? ?? {};
        debugPrint('[ANSWERS] Using English answers: ${answersMap.keys.length} keys');
      }
      
      final initial = answersMap.entries
          .map((e) => MapEntry(e.key, (e.value ?? '').toString()))
          .toList();

      if (mounted) {
        setState(() {
          answers = initial;
          isLoadingQuestions = false;
        });
      }

      debugPrint('[ANSWERS] Loaded ${initial.length} answers (product: $productLang, user: $currentLang)');
      if (initial.isNotEmpty) {
        debugPrint('[ANSWERS] First answer: ${initial.first.key} = ${initial.first.value}');
      }
    } catch (e) {
      debugPrint('[ANSWERS] ❌ Error loading answers: $e');
      if (mounted) setState(() => isLoadingQuestions = false);
    }
  }

  Future<void> _loadOfferPercentage() async {
    try {
      final productId = productData['id'] as String?;
      if (productId == null) return;

      final data = await SupabaseService.instance.products
          .select()
          .eq('id', productId)
          .single();

      if (mounted) {
        final offerPercentage = (data['offer_percentage'] is int) 
            ? data['offer_percentage'] as int 
            : (int.tryParse((data['offer_percentage'] ?? '0').toString()) ?? 0);

        // If the product document includes a createdAt timestamp, cache it
        // into local productData so the UI can show the published date.
        final createdCandidate = data['created_at'];
        if (createdCandidate != null && productData['createdAt'] == null) {
          productData['createdAt'] = createdCandidate;
        }

        if (_selectedOfferPercentage != offerPercentage) {
          setState(() {
            _selectedOfferPercentage = offerPercentage;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading offer percentage: $e');
    }
  }

  Future<void> _loadFavoriteStatus() async {
    try {
      final user = SupabaseService.instance.currentUser;
      if (user == null) return;

      final productId = productData['id']?.toString();
      if (productId == null) return;

      final userData = await SupabaseService.instance.users
          .select('favorites')
          .eq('id', user.id)
          .maybeSingle();

      if (mounted && userData != null) {
        final favorites = userData['favorites'] as List<dynamic>? ?? [];
        final isFavorited = favorites.contains(productId);
        final newFavIds = favorites.map((id) => id.toString()).toSet();

        // Skip rebuild if nothing changed
        if (_isFavorited == isFavorited && _favoritedProductIds.length == newFavIds.length) return;
        setState(() {
          _isFavorited = isFavorited;
          _favoritedProductIds = newFavIds;
        });
      }
    } catch (e) {
      debugPrint('Error loading favorite status: $e');
    }
  }

  Future<void> _loadRecentlyViewedIds() async {
    try {
      final viewedIds = await ProductViewHistoryService.getRecentlyViewedIds();
      if (mounted && viewedIds.length != _recentlyViewedIds.length) {
        setState(() {
          _recentlyViewedIds = viewedIds;
        });
      }
      debugPrint('✅ Product detail: Recently viewed IDs loaded: ${_recentlyViewedIds.length} products');
    } catch (e) {
      debugPrint('❌ Error loading recently viewed IDs: $e');
    }
  }

  /// Checks whether the current authenticated user (buyer) has an
  /// accepted offer for the currently-displayed product.
  Future<void> _checkIfBuyerHasAcceptedOffer() async {
    try {
      final buyer = SupabaseService.instance.currentUser;
      final productId = productData['id']?.toString();
      if (buyer == null || productId == null) return;

      final results = await SupabaseService.instance.offers
          .select()
          .eq('product_id', productId)
          .eq('buyer_id', buyer.id)
          .eq('status', 'accepted')
          .limit(1);

      if (!mounted) return;

      if (results.isNotEmpty) {
        final offer = results.first;
        final offerId = offer['id'];
        
        // acceptedAt may be a String (ISO 8601) or DateTime
        DateTime? acceptedAt;
        try {
          final a = offer['accepted_at'];
          if (a is DateTime) {
            acceptedAt = a;
          } else if (a is String) {
            acceptedAt = DateTime.parse(a);
          }
        } catch (e) {
          acceptedAt = null;
        }

        final now = DateTime.now();
        final within24h = (acceptedAt != null) ? now.difference(acceptedAt).inHours < 24 : true;

        if (within24h) {
          final offered = offer['offered_price'] ?? offer['offered'];
          final currency = offer['currency'] as String?;

          setState(() {
            _hasAcceptedOfferForThisProduct = true;
            // Override displayed price for this buyer only
            if (offered != null) {
              productData['price'] = offered;
            }
            if (currency != null && currency.toString().isNotEmpty) {
              productData['currency'] = currency;
            }
            // Store offer ID for token validation during checkout
            productData['_offerId'] = offerId;
          });
          
          debugPrint('✅ Buyer has accepted offer: $offerId with price: $offered');
        } else {
          // Offer expired (older than 24h) — revert to canonical product data from Supabase
          try {
            final productData = await SupabaseService.instance.products
                .select()
                .eq('id', productId)
                .single();
            
            if (!mounted) return;
            setState(() {
              _hasAcceptedOfferForThisProduct = false;
              this.productData['price'] = productData['price'];
              if (productData.containsKey('currency')) {
                this.productData['currency'] = productData['currency'];
              }
              this.productData.remove('_offerId');
            });
          } catch (e) {
            debugPrint('Error reverting product price after offer expiry: $e');
            if (mounted) setState(() => _hasAcceptedOfferForThisProduct = false);
          }
        }
      } else {
        setState(() {
          _hasAcceptedOfferForThisProduct = false;
          productData.remove('_offerId');
        });
      }
    } catch (e) {
      debugPrint('Error checking accepted offer: $e');
    }
  }

  Future<void> _saveFavoriteStatus() async {
    try {
      final user = SupabaseService.instance.currentUser;
      if (user == null) {
        debugPrint('❌ Cannot save favorite: user not logged in');
        return;
      }

      final productId = productData['id']?.toString();
      if (productId == null) {
        debugPrint('❌ Cannot save favorite: productId is null');
        return;
      }

      debugPrint('💚 Saving favorite status for product: $productId, user: ${user.id}, isFavorited: $_isFavorited');

      final userData = await SupabaseService.instance.users
          .select('favorites')
          .eq('id', user.id)
          .maybeSingle();

      final currentFavorites = userData != null ? (userData['favorites'] as List<dynamic>? ?? []) : <dynamic>[];

      debugPrint('📄 Current favorites in DB: $currentFavorites');

      List<String> updatedFavorites;
      if (_isFavorited) {
        // Add to favorites
        if (!currentFavorites.contains(productId)) {
          updatedFavorites = [...currentFavorites.map((e) => e.toString()), productId];
        } else {
          updatedFavorites = currentFavorites.map((id) => id.toString()).toList();
        }
      } else {
        // Remove from favorites
        updatedFavorites = currentFavorites.where((id) => id.toString() != productId).map((id) => id.toString()).toList();
      }

      debugPrint('📝 Updated favorites: $updatedFavorites');

      await SupabaseService.instance.users
          .update({
            'favorites': updatedFavorites,
            'last_updated': DateTime.now().toIso8601String(),
          })
          .eq('id', user.id);

      debugPrint('✅ Favorite status saved for product: $productId');
    } catch (e) {
      debugPrint('❌ Error saving favorite status: $e');
    }
  }

  Future<void> _trackProductView() async {
    try {
      final productId = productData['id'] as String?;
      if (productId == null) {
        debugPrint('⚠️ Cannot track view: productId is null');
        // Still load stats even if we can't track
        _loadProductStats();
        return;
      }

      final userId = SupabaseService.instance.currentUser?.id;
      if (userId == null) {
        debugPrint('⚠️ Cannot track view: user not authenticated');
        // Still load stats even if we can't track
        _loadProductStats();
        return;
      }

      // Don't track views from the product owner, but still load stats
      final productOwnerId = productData['userId'] as String?;
      if (userId == productOwnerId) {
        debugPrint('ℹ️ Skipping view tracking: user is product owner');
        // Load stats so owner can see their product stats
        _loadProductStats();
        return;
      }

      // Increment view count in products table
      await SupabaseService.instance.client.rpc('increment_product_view_count', 
        params: {'product_id_param': productId}
      );

      debugPrint('✅ Product view tracked for $productId by user $userId');
      
      // Reload stats to show updated view count
      _loadProductStats();
    } catch (e) {
      debugPrint('❌ Error tracking product view: $e');
      // Still try to load stats even if tracking failed
      _loadProductStats();
    }
  }

  Future<void> _saveOfferPercentage(int percentage) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final productId = productData['id'] as String?;
      if (productId == null) return;

      await SupabaseService.instance.products
          .update({'offer_percentage': percentage})
          .eq('id', productId);

      if (!mounted) return;
      setState(() {
        _selectedOfferPercentage = percentage;
      });

      messenger.showSnackBar(
        SnackBar(content: Text('${I18n.t('discount_set_to')} $percentage%'))
      );
    } catch (e) {
      debugPrint('Error saving offer percentage: $e');
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(I18n.t('error_saving_discount')))
      );
    }
  }

  void _toggleEditPrice() {
    if (_isEditingPrice) {
      // Exit edit mode without saving
      setState(() => _isEditingPrice = false);
    } else {
      // Enter edit mode
      _priceController.text = (productData['price'] ?? 0).toString();
      setState(() => _isEditingPrice = true);
      Future.delayed(const Duration(milliseconds: 100), () {
        _priceController.selection = TextSelection.fromPosition(
          TextPosition(offset: _priceController.text.length),
        );
      });
    }
  }

  Future<void> _savePriceChange() async {
    final newPriceStr = _priceController.text.trim();
    if (newPriceStr.isEmpty) {
      if (!mounted) return;
      NotificationHelper.showNotification(context, I18n.t('price_cannot_be_empty'));
      return;
    }

    try {
      final newPrice = double.parse(newPriceStr);
      if (newPrice <= 0) {
        if (!mounted) return;
        NotificationHelper.showNotification(context, I18n.t('price_must_be_greater_than_zero'));
        return;
      }

      // Update Supabase
      final productId = productData['id'] as String?;
      if (productId == null) {
        if (!mounted) return;
        NotificationHelper.showNotification(context, I18n.t('error_updating_price'));
        return;
      }

      await SupabaseService.instance.products
          .update({'price': newPrice})
          .eq('id', productId);

      if (!mounted) return;
      // Update local state
      setState(() {
        productData['price'] = newPrice;
        _isEditingPrice = false;
      });

      NotificationHelper.showNotification(context, '${I18n.t('price_updated_to')} ${_formatPrice(newPrice)}');
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showNotification(context, I18n.t('invalid_price_format'));
    }
  }

  Future<void> _submitMissingInfoAnswers() async {
    try {
      final productId = productData['id'] as String?;
      if (productId == null) return;

      // Get existing answers
      final existingAnswers = (productData['answers'] as Map<String, dynamic>?) ?? {};
      
      // Build new answers map from selected answers
      final newAnswersToAdd = <String, dynamic>{};
      
      // Load questions from product document
      final productRecord = await SupabaseService.instance.products
          .select('missing_info_questions')
          .eq('id', productId)
          .single();

      final questionsList = productRecord['missing_info_questions'] as List<dynamic>? ?? [];
      
      for (int i = 0; i < questionsList.length; i++) {
        final qData = questionsList[i] as Map<String, dynamic>;
        final qText = qData['text'];
        final qKey = qText is Map 
            ? (qText['en'] ?? qText.values.first) 
            : qText;
        final answer = _missingInfoAnswers[i];
        if (answer != null) {
          newAnswersToAdd[qKey.toString()] = answer;
        }
      }

      // Merge existing answers with new answers (new answers override existing)
      final mergedAnswers = {...existingAnswers, ...newAnswersToAdd};

      // Update product: add merged answers, set status to 'active'
      await SupabaseService.instance.products
          .update({
            'answers': mergedAnswers,
            'status': 'active', // Mark as approved/active
            'review_status': '', // Clear review status
            'missing_info_questions': null, // Clear questions after answering
          })
          .eq('id', productId);

      // Update local state
      setState(() {
        productData['answers'] = mergedAnswers;
        productData['status'] = 'active';
        productData['reviewStatus'] = '';
        productData['missing_info_questions'] = null;
        _missingInfoAnswers.clear();
        _loadAnswers(); // Reload answers to display as tags
      });

      if (!mounted) return;
      NotificationHelper.showNotification(context, I18n.t('answers_submitted_successfully'));
    } catch (e) {
      debugPrint('Error submitting answers: $e');
      if (!mounted) return;
      NotificationHelper.showNotification(context, '${I18n.t('error_submitting_answers')}: $e');
    }
  }

  Future<void> _navigateToListingFeeCheckout(String productId) async {
    if (productId.isEmpty) return;

    // Navigate directly to checkout with listing fee flag (flat 35 RON fee)
    final imageUrls = (productData['imageUrls'] as List?)?.cast<String>() ?? 
                     (productData['image_urls'] as List?)?.cast<String>() ?? [];
    final firstImage = imageUrls.isNotEmpty ? imageUrls.first : '';
    
    final listingFeeProduct = {
      'id': productId,
      'title': I18n.t('car_listing_fee'),
      'price': 35.0, // Flat fee of 35 RON
      'currency': 'RON', // Always RON for listing fees
      'imageUrls': imageUrls,
      'image_urls': imageUrls,
      'image_url': firstImage, // Add for ProductCardWidget compatibility
      'hover_thumbnail': firstImage, // Add for ProductCardWidget compatibility
      'isListingFee': true,
      'needsDurationSelection': false, // No duration selection needed - flat fee
    };

    if (!mounted) return;
    // Navigate to checkout
    final paymentSuccess = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => OrderCheckoutPage(
          product: listingFeeProduct,
          paymentBreakdown: const {
            'basePrice': 35.0,
            'shippingCost': 0.0,
            'platformFee': 0.0,
            'userTotal': 35.0,
          },
          orderId: 'listing_$productId',
          onPaymentConfirmed: (card) {
            debugPrint('Listing fee payment confirmed');
          },
        ),
      ),
    );

    if (paymentSuccess == true && mounted) {
      NotificationHelper.showNotification(context, I18n.t('payment_success_car_listing'));
      setState(() {
        productData['status'] = 'active';
        productData['reviewStatus'] = 'complete';
        productData['needsPayment'] = false;
      });
    }
  }

  Future<void> _retryAnalysis(String? productId) async {
    if (productId == null || _isRetrying) return;
    if (!mounted) return;
    setState(() => _isRetrying = true);
    try {
      if (!mounted) return;
      NotificationHelper.showNotification(context, I18n.t('analyzing'));
      final callable = FirebaseFunctions.instance.httpsCallable('analyzeProductDescription');
      await callable.call({
        'productId': productId,
        'productTitle': productData['title'] ?? productData['productTitle'] ?? '',
        'description': productData['description'] ?? '',
        'userLanguage': I18n.current.name.toLowerCase(),
      });
      // Refresh product data
      final updated = await SupabaseService.instance.products
          .select()
          .eq('id', productId)
          .maybeSingle();
      if (updated != null && mounted) {
        setState(() {
          productData.addAll(Map<String, dynamic>.from(updated));
        });
      }
    } catch (e) {
      debugPrint('Error retrying analysis: $e');
      if (mounted) {
        NotificationHelper.showNotification(context, '${I18n.t('error_generic')}: $e');
      }
    }
  }

  Future<void> _useCorrectedDescription(String? productId, String correctedDescription) async {
    if (productId == null) return;
    
    try {
      // The corrected description was already analyzed by the backend,
      // so just update the description and publish directly
      await SupabaseService.instance.products.update({
        'description': correctedDescription,
        'status': 'active',
        'review_status': 'approved',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', productId);
      
      if (!mounted) return;
      NotificationHelper.showNotification(context, I18n.t('product_published'));
      
      // Refresh product data
      final updated = await SupabaseService.instance.products
          .select()
          .eq('id', productId)
          .maybeSingle();
      if (updated != null && mounted) {
        setState(() {
          productData.addAll(Map<String, dynamic>.from(updated));
        });
      }
    } catch (e) {
      debugPrint('Error using corrected description: $e');
      if (mounted) {
        NotificationHelper.showNotification(context, '${I18n.t('error_generic')}: $e');
      }
    }
  }


  Widget _buildAIAnalysisSection() {
    final status = productData['status'] ?? '';
    final reviewStatus = productData['review_status'] ?? productData['reviewStatus'] ?? '';
    // Check both camelCase and snake_case field names
    final productUserId = productData['userId'] as String? ?? 
                          productData['user_id'] as String? ??
                          productData['sellerId'] as String? ??
                          productData['seller_id'] as String?;
    final isOwner = SupabaseService.instance.currentUser?.id == productUserId;
    final productId = productData['id'] as String?;

    // Only show for owner
    if (!isOwner) return const SizedBox.shrink();

    // Product is being analyzed
    if (status == 'analyzing') {
      return Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.3), width: 1),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.hourglass_top, color: Colors.blue, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        I18n.t('product_being_analyzed'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        I18n.t('product_analyzing_description'),
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _isRetrying ? null : () => _retryAnalysis(productId),
            child: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: const Color(0xFF242424),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _isRetrying ? I18n.t('analyzing') : I18n.t('stuck_analyzing'),
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  if (!_isRetrying) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      I18n.t('fix'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  ],
                ],
              ),
            ),
          ),
          if (_isRetrying)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                I18n.t('still_stuck_reupload'),
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 11,
                ),
              ),
            ),
        ],
      );
    }
    
    if (status == 'rejected' && reviewStatus == 'violation') {
      // Get the review reason - check both snake_case and camelCase
      String displayReason;
      final reviewReasonData = productData['review_reason'] ?? productData['reviewReason'];
      
      if (reviewReasonData is Map) {
        final currentLang = I18n.current.name.toLowerCase();
        displayReason = (reviewReasonData[currentLang] ?? 
                        reviewReasonData['en'] ?? 
                        reviewReasonData.values.first ?? 
                        I18n.t('policy_violation_default')).toString();
      } else if (reviewReasonData is String && reviewReasonData.isNotEmpty) {
        displayReason = reviewReasonData;
      } else {
        displayReason = I18n.t('policy_violation_default');
      }
      
      // Get corrected description if available
      String? correctedDescription;
      final correctedDescData = productData['corrected_description'] ?? productData['correctedDescription'];
      
      if (correctedDescData is Map) {
        final currentLang = I18n.current.name.toLowerCase();
        correctedDescription = (correctedDescData[currentLang] ?? 
                               correctedDescData['en'] ?? 
                               correctedDescData.values.first)?.toString();
      } else if (correctedDescData is String && correctedDescData.isNotEmpty) {
        correctedDescription = correctedDescData;
      }
      
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.red.withValues(alpha: 0.3), width: 1),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.warning_rounded, color: Colors.red, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        I18n.t('problems_found'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        displayReason,
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Show corrected description if available
          if (correctedDescription != null && correctedDescription.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              I18n.t('corrected_description'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.normal,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF242424),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Text(
                correctedDescription,
                style: TextStyle(
                  color: Colors.grey[300],
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _useCorrectedDescription(productId, correctedDescription!),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Center(
                  child: Text(
                    I18n.t('use_this_description'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
          ],
          
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              I18n.t('violation_trust_warning'),
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 11,
              ),
            ),
          ),
        ],
      );
    }

    // Car Detected - NEEDS PAYMENT
    if (status == 'needs_payment' && reviewStatus == 'payment_required') {
      return Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.red.withValues(alpha: 0.3), width: 1),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.directions_car, color: Colors.red, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        I18n.t('car_listing_fee_required'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        I18n.t('car_detected_fee_warning'),
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // Show "Missing Information" section with questions from subcollection OR main document
    if (status == 'pending_review' && reviewStatus == 'missing_info' && productId != null) {
      // First check if questions exist in the main product document
      final questionsFromDoc = productData['missingInfoQuestions'] as List?;
      
      if (questionsFromDoc != null && questionsFromDoc.isNotEmpty) {
        // Render questions directly from main document (faster, no subcollection query needed)
        return Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                Text(
                  I18n.t('missing_information'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: questionsFromDoc.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final qData = entry.value as Map<String, dynamic>;
                    final qText = qData['text'];
                    final qString = qText is Map 
                        ? (qText[I18n.current.name] ?? qText['en'] ?? qText.values.first) 
                        : qText;
                    final qOptions = qData['options'];
                    final optionsList = qOptions is Map 
                        ? (qOptions[I18n.current.name] ?? qOptions['en'] ?? qOptions.values.first) 
                        : (qOptions as List?);
                    final selectedAnswer = _missingInfoAnswers[idx];

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${idx + 1}. $qString',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (optionsList != null && optionsList.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: (optionsList as List).map((option) {
                                final isSelected = selectedAnswer == option;
                                return GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _missingInfoAnswers[idx] = option.toString();
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected ? Colors.green.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.1),
                                      border: isSelected ? Border.all(
                                        color: Colors.green,
                                        width: 1.5,
                                      ) : null,
                                      borderRadius: BorderRadius.circular(22),
                                    ),
                                    child: Text(
                                      option.toString(),
                                      style: TextStyle(
                                        color: isSelected ? Colors.green : Colors.white70,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ],
        );
      }
      
      // No questions found in main document
      return const SizedBox.shrink();
    }

    return const SizedBox.shrink();
  }  Widget _buildProductStats() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(24),
      ),
      child: _isLoadingStats
          ? const ShimmerLoading(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      GhostBox(width: 28, height: 28, borderRadius: 14),
                      SizedBox(height: 8),
                      GhostBox(width: 32, height: 20),
                      SizedBox(height: 4),
                      GhostBox(width: 48, height: 12),
                    ],
                  ),
                  Column(
                    children: [
                      GhostBox(width: 28, height: 28, borderRadius: 14),
                      SizedBox(height: 8),
                      GhostBox(width: 32, height: 20),
                      SizedBox(height: 4),
                      GhostBox(width: 48, height: 12),
                    ],
                  ),
                  Column(
                    children: [
                      GhostBox(width: 28, height: 28, borderRadius: 14),
                      SizedBox(height: 8),
                      GhostBox(width: 32, height: 20),
                      SizedBox(height: 4),
                      GhostBox(width: 48, height: 12),
                    ],
                  ),
                ],
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                  svgIcon: 'assets/icons/eye.svg',
                  label: I18n.t('views'),
                  value: _totalViews.toString(),
                  color: Colors.blue,
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: Colors.grey[800],
                ),
                _buildStatItem(
                  svgIcon: 'assets/icons/favorite.svg',
                  label: I18n.t('favorites'),
                  value: _totalFavorites.toString(),
                  color: Colors.red,
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: Colors.grey[800],
                ),
                _buildStatItem(
                  svgIcon: 'assets/icons/chat.svg',
                  label: I18n.t('messages'),
                  value: _totalMessages.toString(),
                  color: Colors.green,
                ),
              ],
            ),
    );
  }

  Widget _buildStatItem({
    String? svgIcon,
    IconData? icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        if (svgIcon != null)
          SvgPicture.asset(svgIcon, width: 28, height: 28, colorFilter: ColorFilter.mode(color, BlendMode.srcIn))
        else
          Icon(icon, color: color, size: 28),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[400],
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Future<void> _loadProductStats() async {
    try {
      final productId = productData['id'] as String?;
      if (productId == null) {
        setState(() => _isLoadingStats = false);
        return;
      }

      // Get total views from product document
      final productRecord = await SupabaseService.instance.products
          .select('view_count')
          .eq('id', productId)
          .single();

      int views = productRecord['view_count'] as int? ?? 0;

      // Count favorites (users who have this product in their favorites list)
      final usersWithFavorite = await SupabaseService.instance.users
          .select('id')
          .contains('favorites', [productId]);

      final favorites = usersWithFavorite.length;

      // Count total messages across all conversations about this product
      final conversationsWithProduct = await SupabaseService.instance.conversations
          .select('id')
          .eq('product_id', productId);

      int totalMessages = 0;
      // For each conversation, count the messages
      for (final conv in conversationsWithProduct) {
        final messages = await SupabaseService.instance.messages
            .select('id')
            .eq('conversation_id', conv['id']);
        totalMessages += messages.length;
      }

      if (mounted) {
        setState(() {
          _totalViews = views;
          _totalFavorites = favorites;
          _totalMessages = totalMessages;
          _isLoadingStats = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading product stats: $e');
      if (mounted) {
        setState(() => _isLoadingStats = false);
      }
    }
  }

  // use file-level getTrustColor



  Widget _buildAddressSection() {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _userDocFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final userData = snapshot.data;
        final addresses = (userData?['addresses'] as List<dynamic>?) ?? [];

        // Auto-select first address if none selected and addresses exist
        if (addresses.isNotEmpty && _selectedAddressIndex == -1 && !_showAddressForm) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _selectedAddressIndex = 0;
                try {
                  _selectedAddressData = (addresses[0] as Map<String, dynamic>?) ?? {};
                } catch (e) {
                  _selectedAddressData = null;
                }
              });
            }
          });
        }

        // Make the saved addresses scrollable and limit visible height to max 3 items
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (addresses.isNotEmpty && !_showAddressForm)
              _AddressCarousel(
                addresses: addresses,
                initialIndex: _selectedAddressIndex >= 0 ? _selectedAddressIndex : 0,
                onAddressTap: (idx) {
                  setState(() {
                    _selectedAddressIndex = _selectedAddressIndex == idx ? -1 : idx;
                    // Reset form resolution so future form opens behave predictably
                    _formAddressIndex = _selectedAddressIndex;
                    // Cache the selected address data so other widgets (eg. Buy Now) can use it
                    try {
                      _selectedAddressData = (addresses[idx] as Map<String, dynamic>? ) ?? {};
                      } catch (e) {
                        _selectedAddressData = null;
                      }
                    });
                  },
                )
            else if (_showAddressForm || addresses.isEmpty)
              _buildAddressForm(),
          ],
        );
      },
    );
  }

  Widget _buildAddressForm() {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _userDocFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final userData = snapshot.data;
        final addresses = (userData?['addresses'] as List<dynamic>?) ?? [];
        
        // Determine which address to edit.
        // Priority:
        // 1) If _formAddressIndex has been explicitly set (>= -1), use it ( -1 means new )
        // 2) Otherwise fall back to selected index or first address if available
        int addressToEditIndex;
        if (_formAddressIndex != -2) {
          addressToEditIndex = _formAddressIndex;
        } else {
          addressToEditIndex = _selectedAddressIndex >= 0 && _selectedAddressIndex < addresses.length
              ? _selectedAddressIndex
              : (addresses.isNotEmpty ? 0 : -1);
          // record resolution so subsequent rebuilds are stable
          _formAddressIndex = addressToEditIndex;
        }

        // Load address data into controllers if we have addresses and an index to edit.
        // IMPORTANT: do this synchronously and only once per index to avoid
        // changing controller.text during rebuilds (which resets focus/selection).
        if (addresses.isNotEmpty && addressToEditIndex >= 0) {
          final selectedAddr = addresses[addressToEditIndex] as Map<String, dynamic>? ?? {};
          _loadAddressIntoControllers(selectedAddr, addressToEditIndex);
        } else if (addressToEditIndex == -1) {
          // New address - ensure controllers are cleared
          if (_loadedAddressIndex != -1) {
            _loadedAddressIndex = -1;
            _nameCtrl.clear();
            _streetCtrl.clear();
            _cityCtrl.clear();
            _buildingCtrl.clear();
            _phoneCtrl.clear();
            _zipCtrl.clear();
          }
        }
        
        // Removed outer GestureDetector that dismissed the keyboard on ANY tap
        // (including taps inside TextFields). Returning the Column directly so
        // taps on TextFields behave normally and the keyboard stays open while
        // typing. If you want background-tap dismissal, consider one of the
        // patterns in the PR comments (onTapOutside or deferred GestureDetector
        // at page level).
        return Column(
          children: [
            // Full width fields
            _buildAddressTextField(_nameCtrl, I18n.t('name')),
            // Street and Building on same row
            Row(
              children: [
                Expanded(
                  flex: 7,
                  child: _buildAddressTextField(_streetCtrl, I18n.t('street')),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: _buildAddressTextField(_buildingCtrl, I18n.t('building_apt')),
                ),
              ],
            ),
            // City and ZIP on same row
            Row(
              children: [
                Expanded(
                  child: _buildAddressTextField(_cityCtrl, I18n.t('city')),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildAddressTextField(_zipCtrl, I18n.t('zip_code')),
                ),
              ],
            ),
            // Phone number full width
            _buildAddressTextField(_phoneCtrl, I18n.t('phone_number')),
            // Save and Cancel buttons side by side
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _showAddressForm = false;
                        _loadedAddressIndex = -1;
                        _formAddressIndex = -2; // reset to unset
                        // Clear controllers when canceling
                        _nameCtrl.clear();
                        _streetCtrl.clear();
                        _cityCtrl.clear();
                        _buildingCtrl.clear();
                        _phoneCtrl.clear();
                        _zipCtrl.clear();
                      });
                    },
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.grey[900],
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Center(
                        child: Text(
                          I18n.t('cancel'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: _saveAddress,
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Center(
                        child: Text(
                          I18n.t('save'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildAddressTextField(TextEditingController controller, String label) {
    // Single line input with fixed height matching title field in add product page
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SizedBox(
        height: 48,
        child: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          textInputAction: TextInputAction.next,
          scrollPadding: EdgeInsets.zero,
          maxLines: 1,
          keyboardType: label == 'Phone Number' ? TextInputType.phone : TextInputType.text,
          decoration: InputDecoration(
            hintText: label,
            hintStyle: TextStyle(color: Colors.grey[400]),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            filled: true,
            fillColor: Colors.grey[900],
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: const BorderSide(color: Colors.green),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _saveAddress() async {
    if (_nameCtrl.text.isEmpty || _streetCtrl.text.isEmpty || _cityCtrl.text.isEmpty || _zipCtrl.text.isEmpty) {
      if (!mounted) return;
      NotificationHelper.showNotification(context, I18n.t('please_fill_all_required_fields'));
      return;
    }

    try {
      final user = SupabaseService.instance.currentUser;
      if (user == null) return;

      final newAddress = {
        'name': _nameCtrl.text,
        'street': _streetCtrl.text,
        'city': _cityCtrl.text,
        'building': _buildingCtrl.text,
        'phone': _phoneCtrl.text,
        'zip': _zipCtrl.text,
      };

      final userData = await SupabaseService.instance.users
          .select('addresses')
          .eq('id', user.id)
          .maybeSingle();

      final existing = userData ?? {};
      final addresses = List<Map<String, dynamic>>.from((existing['addresses'] as List<dynamic>?)?.map((e) => Map<String, dynamic>.from(e as Map)) ?? []);

      // If form is editing an existing address index, replace that entry
      if (_formAddressIndex >= 0 && _formAddressIndex < addresses.length) {
        addresses[_formAddressIndex] = newAddress;
      } else {
        // Adding a new address: enforce max 3 saved addresses
        if (addresses.length >= 3) {
          if (!mounted) return;
          NotificationHelper.showNotification(context, I18n.t('addresses_limit'));
          return;
        }
        addresses.add(newAddress);
      }

      // Save the full updated addresses list back to Supabase
      await SupabaseService.instance.users
          .update({'addresses': addresses})
          .eq('id', user.id);

      if (!mounted) return;
      // Refresh cached future and close form / clear controllers in one setState
      setState(() {
        _userDocFuture = _loadUserData(user.id);
        _showAddressForm = false;
        _nameCtrl.clear();
        _streetCtrl.clear();
        _cityCtrl.clear();
        _buildingCtrl.clear();
        _phoneCtrl.clear();
        _zipCtrl.clear();
        // Reset loaded indices so next time the form opens it will populate again
        _loadedAddressIndex = -1;
        _formAddressIndex = -2;
      });

      NotificationHelper.showNotification(context, I18n.t('address_saved'));
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showNotification(context, '${I18n.t('error_saving_address')}: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    
    // Get images from product data using helper (handles both camelCase and snake_case)
    final imagesToDisplay = ProductImageHelper.getAllImageUrls(productData);
    
    debugPrint('🖼️ ProductDetailPage - Final imagesToDisplay: ${imagesToDisplay.length} images');
    for (var i = 0; i < imagesToDisplay.length; i++) {
      debugPrint('   Image $i: ${imagesToDisplay[i]}');
    }
    
    // Get title with language matching logic (same as answers)
    final currentLang = I18n.current.name.toLowerCase();
    final detectedLang = (productData['detected_language'] as String? ?? 'en').toLowerCase();
    
    final String title;
    if (currentLang == detectedLang) {
      // Viewer's language matches seller's language, show seller's language title
      title = productData['title'] as String? ?? I18n.t('untitled');
    } else {
      // Languages don't match, fallback to English title
      title = productData['title_english'] as String? ?? productData['title'] as String? ?? I18n.t('untitled');
    }
    
    final price = productData['price'] ?? 'N/A';

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      resizeToAvoidBottomInset: false,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0A0A0A),
              Color(0xFF1A1A1A),
              Color(0xFF0A0A0A),
            ],
          ),
        ),
        child: Stack(
          children: [
            // Product Content - Scrollable, takes full height
            SingleChildScrollView(
              controller: _mainScrollController,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
              physics: const ClampingScrollPhysics(),
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(viewInsets: EdgeInsets.zero),
                child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height,
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 8.0, 16, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    // Product Image Carousel with Swipe and Draggable Height
                    Column(
                      children: [
                        // Main Image Display - Swipeable with aspect ratio
                        Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: Container(
                                width: double.infinity,
                                height: screenHeight * 0.45,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF1A1A1A),
                                ),
                                child: imagesToDisplay.isNotEmpty
                                    ? GestureDetector(
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            PageRouteBuilder(
                                              opaque: false,
                                              pageBuilder: (_, __, ___) => _FullscreenImageViewer(
                                                imageUrls: imagesToDisplay,
                                                initialIndex: _currentImageIndex,
                                              ),
                                            ),
                                          );
                                        },
                                        onHorizontalDragEnd: (details) {
                                          if (details.primaryVelocity! < 0 && _currentImageIndex < imagesToDisplay.length - 1) {
                                            setState(() => _currentImageIndex++);
                                          } else if (details.primaryVelocity! > 0 && _currentImageIndex > 0) {
                                            setState(() => _currentImageIndex--);
                                          }
                                        },
                                        child: ImageLoadingService.cachedImage(
                                          imagesToDisplay[_currentImageIndex],
                                          fit: BoxFit.cover,
                                          width: double.infinity,
                                        ),
                                      )
                                    : SizedBox(
                                        height: 200,
                                        child: Center(
                                          child: SvgPicture.asset('assets/icons/products.svg', width: 80, height: 80, colorFilter: ColorFilter.mode(Colors.grey.shade400, BlendMode.srcIn)),
                                        ),
                                      ),
                              ),
                            ),
                            // Country flag overlay at bottom-right
                            Positioned(
                              bottom: 12,
                              right: 12,
                              child: CountryFlagHelper.getFlagWidget(productData['country'] as String?, size: 20),
                            ),
                            // Indicator Dots - At Bottom of Container
                            if (imagesToDisplay.length > 1)
                              Positioned(
                                bottom: 8,
                                left: 0,
                                right: 0,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: List.generate(
                                    imagesToDisplay.length,
                                    (index) => Container(
                                      margin: const EdgeInsets.symmetric(horizontal: 6),
                                      width: _currentImageIndex == index ? 14 : 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: _currentImageIndex == index
                                            ? Colors.white
                                            : Colors.grey[500],
                                      ),
                                    ),
                                  ),
                              ),
                            ),
                            // SOLD Badge - Centered, bigger, rounded for sold products
                            if (productData['status'] == 'sold')
                              Positioned.fill(
                                child: Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.75),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      I18n.t('sold'),
                                      style: const TextStyle(
                                        color: Colors.green,
                                        fontSize: 28,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 3,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                                // Image info row below image
                                const SizedBox(height: 8),
                        // Place the product date and inventory counters in a row
                        Row(
                          children: [
                            // Inventory counters on the left (Sold: X, Stock: Y)
                            if (productData['status'] == 'sold' || _getInventoryCount() > 0)
                              Padding(
                                padding: const EdgeInsets.only(left: 4.0, right: 8.0),
                                child: Row(
                                  children: [
                                    // Sold counter
                                    if (productData['soldCount'] != null && productData['soldCount'] > 0)
                                      Padding(
                                        padding: const EdgeInsets.only(right: 8.0),
                                        child: Text(
                                          'Sold: ${productData['soldCount']}',
                                          style: TextStyle(
                                            color: Colors.grey[400],
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    // Stock counter (only show if inventory exists and > 0)
                                    if (_getInventoryCount() > 0)
                                      Text(
                                        'Stock: ${_getInventoryCount()}',
                                        style: TextStyle(
                                          color: Colors.grey[400],
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            // Spacer
                            const Spacer(),
                            // Show date on the right if available
                            if ((productData['createdAt'] ?? productData['created_at'] ?? productData['date']) != null)
                              Padding(
                                padding: const EdgeInsets.only(right: 4.0),
                                child: Text(
                                  _formatProductDate(productData['createdAt'] ?? productData['created_at'] ?? productData['date']),
                                  style: TextStyle(color: Colors.grey[400], fontSize: 11),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Title with quantity indicator
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              // Show quantity indicator next to title if buyer selected more than 1
                              if (_isBuyer &&
                                  _selectedQuantity > 1) ...[
                                const SizedBox(width: 8),
                                Text(
                                  'x$_selectedQuantity',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),

                    // Price and Make an Offer Button / Set Discount
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // PRICE - Left side
                        if (_isEditingPrice && _isOwner)
                          // Editing mode
                          Expanded(
                            child: Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 40,
                                    child: TextField(
                                      controller: _priceController,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      onSubmitted: (_) => _savePriceChange(),
                                      decoration: InputDecoration(
                                        hintText: I18n.t('enter_price'),
                                        hintStyle: const TextStyle(color: Colors.grey),
                                        // Currency is shown in the product context; keep the input field clean
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(50),
                                          borderSide: const BorderSide(color: Colors.green, width: 2),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(50),
                                          borderSide: const BorderSide(color: Colors.green, width: 1),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(50),
                                          borderSide: const BorderSide(color: Colors.green, width: 2),
                                        ),
                                      ),
                                      style: const TextStyle(color: Colors.green, fontSize: 18, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: _savePriceChange,
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: const BoxDecoration(
                                      color: Colors.green,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.check, color: Colors.white, size: 20),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: _toggleEditPrice,
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[900],
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(Icons.close, color: Colors.grey[400], size: 20),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          // Display mode with currency conversion (multiply by quantity for buyers)
                          PriceWithConversion(
                            price: ((price is num) ? price.toDouble() : double.tryParse(price.toString()) ?? 0.0) * 
                                   (_isBuyer ? _selectedQuantity : 1),
                            originalCurrency: (productData['currency'] as String?) ?? 'RON',
                            style: const TextStyle(
                              color: Colors.green,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                            showConvertButton: false,
                            autoConvert: false, // Don't auto-convert to avoid API calls on slider changes
                            controller: _priceConversionController, // Shared controller
                          ),
                        // BUTTON - Right side (only show if not editing and not rejected/analyzing)
                        if (!_isEditingPrice && productData['status'] != 'rejected' && productData['status'] != 'analyzing')
                          (() {
                            final isOwner = _isOwner;
                            if (isOwner) {
                              return GestureDetector(
                                onTap: _toggleEditPrice,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[900],
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    I18n.t('edit_price'),
                                    style: TextStyle(
                                      color: Colors.grey[400],
                                      fontSize: 14,
                                      fontWeight: FontWeight.normal,
                                    ),
                                  ),
                                ),
                              );
                            }

                            if (!_hasAcceptedOfferForThisProduct) {
                              // Buyer - Show Make an Offer and Add to Favorite
                              // Build the make-offer button as either interactive or disabled
                              final int sellerAllowedPct = (productData['offerPercentage'] is num)
                                  ? (productData['offerPercentage'] as num).toInt()
                                  : _selectedOfferPercentage;

                              Widget? makeOfferWidget;

                              // Only show offer button if seller allows offers AND no confirmed quantity exists
                              if (sellerAllowedPct > 0 && _confirmedQuantity == null) {
                                if (_offerBlockedByTimeout) {
                                  // Timeout active: render a disabled button showing hours left (circle)
                                  makeOfferWidget = Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: Colors.grey[900],
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Text(
                                        '${_offerHoursRemaining}h',
                                        style: TextStyle(color: Colors.grey[400], fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  );
                                } else {
                                  // Interactive Make Offer button - CIRCLE with icon
                                  makeOfferWidget = GestureDetector(
                                    onTap: () {
                                      // If slider is already visible, hide it (toggle behavior)
                                      if (_showOfferSlider) {
                                        setState(() {
                                          _showOfferSlider = false;
                                          // Restore original product price when cancelling the offer
                                          if (_originalPrice != null && !_hasAcceptedOfferForThisProduct) {
                                            productData['price'] = _originalPrice;
                                            _originalPrice = null;
                                          }
                                        });
                                        return;
                                      }

                                      // initialize slider values and show inline slider
                                      final productPrice = (productData['price'] is num) ? (productData['price'] as num).toDouble() : double.tryParse(productData['price']?.toString() ?? '') ?? 0.0;
                                      final minPrice = productPrice * (1 - sellerAllowedPct / 100.0);
                                      // Save original price so we can restore if buyer cancels
                                      _originalPrice = productData['price'];
                                      setState(() {
                                        // Round to integer values so offers don't include cents
                                        _offerSliderMin = minPrice.roundToDouble();
                                        _offerSliderMax = productPrice.roundToDouble();
                                        // default to max (buyer starts at full price)
                                        _offerSliderValue = _offerSliderMax;
                                        _showOfferSlider = true;
                                        // Update main displayed price to match the selected offer value while composing
                                        productData['price'] = _offerSliderValue;
                                      });
                                    },
                                    child: Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: _showOfferSlider ? Colors.green.withValues(alpha: 0.2) : Colors.grey[900],
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.local_offer,
                                        size: 16,
                                        color: _showOfferSlider ? Colors.green : Colors.grey[400],
                                      ),
                                    ),
                                  );
                                }
                              }

                              return Row(
                                children: [
                                  // Currency conversion button
                                  PriceWithConversion(
                                    price: (price is num) ? price.toDouble() : double.tryParse(price.toString()) ?? 0.0,
                                    originalCurrency: (productData['currency'] as String?) ?? 'RON',
                                    buttonOnly: true,
                                    controller: _priceConversionController,
                                  ),
                                  // Show offer button if seller allows offers
                                  if (makeOfferWidget != null) ...[
                                    const SizedBox(width: 12),
                                    makeOfferWidget,
                                  ],
                                  const SizedBox(width: 12),
                                  // Favorite button - same size as other buttons
                                  GestureDetector(
                                    onTap: () async {
                                      final messenger = ScaffoldMessenger.of(context);
                                      setState(() {
                                        _isFavorited = !_isFavorited;
                                      });
                                      await _saveFavoriteStatus();
                                      if (mounted) {
                                        messenger.showSnackBar(
                                          SnackBar(content: Text(_isFavorited ? I18n.t('added_to_favorites') : I18n.t('removed_from_favorites')))
                                        );
                                      }
                                    },
                                    child: Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: _isFavorited ? Colors.green.withValues(alpha: 0.2) : Colors.grey[900],
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: SvgPicture.asset(
                                          'assets/icons/favorite.svg',
                                          width: 16,
                                          height: 16,
                                          colorFilter: ColorFilter.mode(
                                            _isFavorited ? Colors.green : (Colors.grey[400] ?? Colors.grey),
                                            BlendMode.srcIn,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }

                            // If the buyer already has an accepted offer for this product,
                            // hide the Make an Offer button but keep the favorite button available.
                            return Row(
                              children: [
                                // Currency conversion button
                                PriceWithConversion(
                                  price: (price is num) ? price.toDouble() : double.tryParse(price.toString()) ?? 0.0,
                                  originalCurrency: (productData['currency'] as String?) ?? 'RON',
                                  buttonOnly: true,
                                  controller: _priceConversionController, // Shared controller
                                ),
                                const SizedBox(width: 12),
                                GestureDetector(
                                  onTap: () async {
                                    final messenger = ScaffoldMessenger.of(context);
                                    setState(() {
                                      _isFavorited = !_isFavorited;
                                    });
                                    await _saveFavoriteStatus();
                                    if (mounted) {
                                      messenger.showSnackBar(
                                        SnackBar(content: Text(_isFavorited ? I18n.t('added_to_favorites') : I18n.t('removed_from_favorites')))
                                      );
                                    }
                                  },
                                  child: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: _isFavorited ? Colors.green.withValues(alpha: 0.2) : Colors.grey[900],
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: SvgPicture.asset(
                                        'assets/icons/favorite.svg',
                                        width: 16,
                                        height: 16,
                                        colorFilter: ColorFilter.mode(
                                          _isFavorited ? Colors.green : (Colors.grey[400] ?? Colors.grey),
                                          BlendMode.srcIn,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }()),
                      ],
                    ),

                    // Disclaimer when offer slider is active and currencies differ
                    if (_showOfferSlider && CurrencyService.current != (productData['currency'] ?? 'RON'))
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          I18n.t('offer_conversion_note'),
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),

                    // Small spacing after price (reduced to remove extra gap before offer block)
                    const SizedBox(height: 0),

                    // Inline offer slider shown to buyers when they tapped Make Offer
                    if (_showOfferSlider && _isBuyer && !_hasAcceptedOfferForThisProduct && _confirmedQuantity == null)
                      Builder(builder: (ctx) {
                        // compute seller allowed percent for title
                        final int sellerAllowedPct = (productData['offerPercentage'] is num)
                            ? (productData['offerPercentage'] as num).toInt()
                            : _selectedOfferPercentage;

                        // Use a single-row layout: title | slider | send button to eliminate vertical gaps
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Title above the slider, nudged down to sit closer to the track
                            Transform.translate(
                              offset: const Offset(0, 6),
                              child: Text(
                                '${I18n.t('max_discount_allowed')}: $sellerAllowedPct%',
                                style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
                              ),
                            ),

                            const SizedBox(height: 4),

                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // Start the widget flush with the page padding (20px left from page)
                                const SizedBox(width: 0),

                                // Slider expands
                                Expanded(
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      activeTrackColor: Colors.green,
                                      inactiveTrackColor: Colors.grey[800],
                                      thumbColor: Colors.green,
                                      trackHeight: 10,
                                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
                                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
                                    ),
                                    // Shift the slider track left by the thumb radius so the
                                    // visible track starts aligned with other content (page padding).
                                    // Use Transform.translate instead of negative Padding which
                                    // triggers an assertion in Flutter for non-negative padding.
                                    child: Transform.translate(
                                      offset: const Offset(-12.0, 0),
                                      child: Slider(
                                          min: _offerSliderMin,
                                          max: _offerSliderMax,
                                          // snap to integer steps by setting divisions to the integer range
                                          divisions: ((_offerSliderMax - _offerSliderMin).round() > 0) ? (_offerSliderMax - _offerSliderMin).round() : null,
                                          value: _offerSliderValue.clamp(_offerSliderMin, _offerSliderMax),
                                          onChanged: (v) {
                                            setState(() {
                                              // force integer steps
                                              _offerSliderValue = v.roundToDouble();
                                              // reflect the selected offer in the main price under title
                                              productData['price'] = _offerSliderValue;
                                            });
                                          },
                                        ),
                                    ),
                                  ),
                                ),

                                // gap between end of slider and send button (reduced to give slider more width)
                                const SizedBox(width: 0),

                                // Send button (keeps 20px from right due to page padding)
                                // Slightly shifted left to align better with the slider
                                Transform.translate(
                                  offset: const Offset(-2.0, 0),
                                  child: GestureDetector(
                                      onTap: () async {
                                        
                                        // Prevent sending if a timeout/block is active.
                                        if (_offerBlockedByTimeout) {
                                          if (!mounted) return;
                                          NotificationHelper.showNotification(context, I18n.t('offer_already_pending'));
                                          return;
                                        }

                                        final buyer = SupabaseService.instance.currentUser;
                                      if (buyer == null) {
                                        if (!mounted) return;
                                        NotificationHelper.showNotification(context, I18n.t('must_be_logged_in'));
                                        return;
                                      }

                                      final offered = _offerSliderValue;
                                      if (offered <= 0 || offered < _offerSliderMin) {
                                        if (!mounted) return;
                                        NotificationHelper.showNotification(context, I18n.t('invalid_price'));
                                        return;
                                      }

                                      try {
                                        // Prevent multiple offers: check latest offer by this buyer for this product.
                                        final productIdForCheck = productData['id'] as String?;
                                        if (productIdForCheck != null) {
                                          // Query from Supabase
                                          final prevOffers = await SupabaseService.instance.offers
                                              .select()
                                              .eq('product_id', productIdForCheck)
                                              .eq('buyer_id', buyer.id)
                                              .order('created_at', ascending: false)
                                              .limit(1);

                                          if (prevOffers.isNotEmpty) {
                                            final prev = prevOffers.first;
                                            final prevStatus = (prev['status'] as String?) ?? 'pending';
                                            // If last offer is pending, buyer must wait for seller to respond (reject/accept)
                                            if (prevStatus == 'pending') {
                                              if (!mounted) return;
                                              NotificationHelper.showNotification(context, I18n.t('offer_already_pending'));
                                              return;
                                            }
                                            // If last offer was accepted, do not allow further offers
                                            if (prevStatus == 'accepted') {
                                              if (!mounted) return;
                                              NotificationHelper.showNotification(context, I18n.t('offer_blocked_accepted'));
                                              return;
                                            }
                                            // If last offer was rejected, allow sending another offer immediately per requirement.
                                          }
                                        }

                                        final offerDoc = {
                                          'product_id': productData['id'],
                                          'seller_id': productData['userId'] ?? productData['user_id'] ?? productData['seller_id'],
                                          'buyer_id': buyer.id,
                                          'offered_price': offered,
                                          'currency': productData['currency'] ?? CurrencyService.current,
                                          'status': 'pending',
                                          'created_at': DateTime.now().toIso8601String(),
                                        };

                                        // Save offer and capture its id
                                        final offerResult = await SupabaseService.instance.offers.insert(offerDoc).select();
                                        final offerId = offerResult.first['id'];

                                        // Ensure the product is added to the buyer's favorites when they make an offer.
                                        // This is idempotent because `_saveFavoriteStatus` checks existing favorites
                                        // and will not duplicate entries. We set `_isFavorited` and persist.
                                        try {
                                          if (mounted) {
                                            setState(() {
                                              _isFavorited = true;
                                            });
                                          }
                                          await _saveFavoriteStatus();
                                        } catch (e) {
                                          debugPrint('Error adding product to favorites after offer: $e');
                                        }

                                        // Notify seller via a conversation message so they see the product card and actions
                                        try {
                                          final sellerId = productData['userId'] as String? ?? 
                                                           productData['user_id'] as String? ?? 
                                                           productData['sellerId'] as String? ?? 
                                                           productData['seller_id'] as String? ?? '';
                                          final ids = [buyer.id, sellerId];
                                          ids.sort();
                                          final conversationId = 'conv_${ids[0]}_${ids[1]}';

                                          // Check if conversation exists
                                          final existingConv = await SupabaseService.instance.conversations
                                              .select()
                                              .eq('id', conversationId)
                                              .maybeSingle();

                                          if (existingConv == null) {
                                            await SupabaseService.instance.conversations.insert({
                                              'id': conversationId,
                                              'product_id': productData['id'],
                                              'product_title': productData['title'],
                                              'participants': [buyer.id, sellerId],
                                              'user_id': sellerId,
                                              'last_message': '',
                                              'last_message_time': DateTime.now().toIso8601String(),
                                              'created_at': DateTime.now().toIso8601String(),
                                              'unread_by': [sellerId],
                                            });
                                          }

                                          // Fetch sender display name from DB
                                          String senderName = 'User';
                                          try {
                                            final userData = await SupabaseService.instance.users
                                                .select('display_name, full_name')
                                                .eq('id', buyer.id)
                                                .maybeSingle();
                                            if (userData != null) {
                                              senderName = (userData['display_name'] as String?)?.isNotEmpty == true
                                                  ? userData['display_name'] as String
                                                  : (userData['full_name'] as String?) ?? 'User';
                                            }
                                          } catch (_) {}

                                          await SupabaseService.instance.messages.insert({
                                            'conversation_id': conversationId,
                                            'sender_id': buyer.id,
                                            'sender_name': senderName,
                                            'sender_photo': buyer.userMetadata?['photo_url'],
                                            'content': '',
                                            'created_at': DateTime.now().toIso8601String(),
                                            'product_id': productData['id'],
                                            'is_offer_message': true,
                                            'offer_id': offerId,
                                            'offered_price': offered,
                                            'currency': productData['currency'] ?? CurrencyService.current,
                                            'product_card': {
                                              'title': productData['title'],
                                              'price': offered,
                                              'currency': productData['currency'] ?? CurrencyService.current,
                                              'imageUrl': productData['images'] is List && (productData['images'] as List).isNotEmpty
                                                  ? (productData['images'] as List).first
                                                  : (productData['imageUrl'] ?? ''),
                                            },
                                          });

                                          await SupabaseService.instance.conversations
                                              .update({
                                                'last_message': I18n.t('sent_offer'),
                                                'last_message_time': DateTime.now().toIso8601String(),
                                                'last_message_sender': buyer.id,
                                                'unread_by': [sellerId],
                                              })
                                              .eq('id', conversationId);
                                        } catch (e) {
                                          debugPrint('Error creating conversation message for offer: $e');
                                        }

                                            if (!mounted) return;
                                            setState(() {
                                              _showOfferSlider = false;
                                              // After sending an offer (pending), restore the original price
                                              if (_originalPrice != null && !_hasAcceptedOfferForThisProduct) {
                                                productData['price'] = _originalPrice;
                                                _originalPrice = null;
                                              }
                                            });
                                            
                                            if (mounted) {
                                              NotificationHelper.showNotification(context, I18n.t('offer_sent'));
                                            }
                                            // Refresh last-offer state so the make-offer button shows countdown immediately
                                            await _checkLastOfferForBuyer();
                                      } catch (e) {
                                        debugPrint('Error sending offer: $e');
                                        if (!mounted) return;
                                        NotificationHelper.showNotification(context, I18n.t('error_generic'));
                                      }
                                    },
                                    child: Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: Colors.green,
                                        shape: BoxShape.circle,
                                        boxShadow: [BoxShadow(color: Colors.green.withValues(alpha: 0.2), blurRadius: 6, offset: const Offset(0, 3))],
                                      ),
                                      child: const Icon(Icons.send, color: Colors.white, size: 18),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            // (Removed the small centered price - main price under title now reflects the selected offer while composing)
                          ],
                        );
                      }),
                    
                    // Discount options - visible for product owner ONLY if product is active/published
                    // Hide for needs_payment, rejected, or analyzing status
                    if (_isOwner && 
                        productData['status'] != 'needs_payment' && 
                        productData['status'] != 'rejected' &&
                        productData['status'] != 'analyzing')
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 12),
                          Text(
                            I18n.t('max_discount_allowed'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                          const SizedBox(height: 4),
                          // Discount options as pills in a single row
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [0, 5, 10, 15, 20, 30].map((percentage) {
                                final isSelected = _selectedOfferPercentage == percentage;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: GestureDetector(
                                    onTap: () {
                                      _saveOfferPercentage(percentage);
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: isSelected ? Colors.green.withValues(alpha: 0.2) : Colors.grey[900],
                                        borderRadius: BorderRadius.circular(20),
                                        border: isSelected ? Border.all(color: Colors.green, width: 1.5) : null,
                                      ),
                                      child: Text(
                                        '$percentage%',
                                        style: TextStyle(
                                          color: isSelected ? Colors.green : Colors.grey[400],
                                          fontSize: 14,
                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ),

                    // AI Analysis Section (Missing Info, Car Fee) - only for owners
                    if (_isOwner)
                      ...[
                        _buildAIAnalysisSection(),
                        const SizedBox(height: 4),
                      ],

                    // Spacing before Key Information (only for buyers; owners get spacing from AI analysis/discount sections)
                    if (!_isOwner)
                      const SizedBox(height: 12),

                    // High-value payment notice (for products over €3500) - above Key Info
                    if (_isBuyer && (() {
                      double basePrice = 0.0;
                      final price = productData['price'];
                      if (price is num) {
                        basePrice = price.toDouble();
                      } else if (price is String) {
                        basePrice = double.tryParse(price) ?? 0.0;
                      }
                      final currency = productData['currency'] as String? ?? CurrencyService.current;
                      if (currency == 'EUR') {
                        return basePrice > 3500;
                      } else if (currency == 'RON') {
                        return (basePrice / 5) > 3500;
                      } else if (currency == 'USD') {
                        return (basePrice / 1.1) > 3500;
                      }
                      return false;
                    })())
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.grey[900],
                          borderRadius: BorderRadius.circular(50),
                          border: Border.all(color: Colors.orange.withValues(alpha: 0.3), width: 1),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.info_outline, color: Colors.orange[400], size: 14),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                I18n.t('high_value_payment_notice'),
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 12),

                    // Questions & Answers Section - Show answers directly (AI provides correct context)
                    if (productData['status'] != 'analyzing' && productData['status'] != 'rejected') ...[
                    if (isLoadingQuestions)
                      const Center(
                        child: CircularProgressIndicator(),
                      )
                    else if ((productData['condition'] as String?)?.isNotEmpty == true || (productData['quality'] as String?)?.isNotEmpty == true || (productData['description'] as String?)?.isNotEmpty == true)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    I18n.t('description'),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.normal,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[900],
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                    child: Text(
                                      (productData['description'] as String?) ?? I18n.t('no_description'),
                                      style: TextStyle(
                                        color: Colors.grey[300],
                                        fontSize: 14,
                                        height: 1.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if ((productData['condition'] as String?)?.isNotEmpty == true || 
                                  (productData['quality'] as String?)?.isNotEmpty == true)
                                Positioned(
                                  top: 0,
                                  right: 0,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if ((productData['condition'] as String?)?.isNotEmpty == true)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: Colors.green[800],
                                            borderRadius: BorderRadius.circular(16),
                                          ),
                                          child: Text(
                                            I18n.t(productData['condition'] as String),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      if ((productData['condition'] as String?)?.isNotEmpty == true && 
                                          (productData['quality'] as String?)?.isNotEmpty == true)
                                        const SizedBox(width: 4),
                                      if ((productData['quality'] as String?)?.isNotEmpty == true)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: Colors.green[800],
                                            borderRadius: BorderRadius.circular(16),
                                          ),
                                          child: Text(
                                            I18n.t(productData['quality'] as String),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),

                    // Quantity Selector - Only show for products with stock > 1 and for buyers (below Key Info)
                    if (_isBuyer && _getInventoryCount() > 1)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Text(
                                I18n.t('quantity'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              // Minus button
                              GestureDetector(
                                onTap: _selectedQuantity > 1
                                    ? () {
                                        setState(() {
                                          _selectedQuantity--;
                                        });
                                      }
                                    : null,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.transparent,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: _selectedQuantity > 1 ? Colors.green : Colors.grey,
                                      width: 2,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.remove,
                                    color: _selectedQuantity > 1 ? Colors.green : Colors.grey,
                                    size: 18,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Count display
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.transparent,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.green, width: 2),
                                ),
                                child: Text(
                                  '$_selectedQuantity',
                                  style: const TextStyle(
                                    color: Colors.green,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Plus button - STRICTLY limit to confirmed quantity if available
                              GestureDetector(
                                onTap: () {
                                  // If confirmed quantity exists, use it as the HARD limit
                                  // Otherwise fall back to inventory count
                                  final maxQty = _confirmedQuantity ?? _getInventoryCount();
                                  debugPrint('Plus button: current=$_selectedQuantity, max=$maxQty, confirmed=$_confirmedQuantity');
                                  if (_selectedQuantity < maxQty) {
                                    setState(() {
                                      _selectedQuantity++;
                                    });
                                  }
                                },
                                child: Builder(
                                  builder: (context) {
                                    // If confirmed quantity exists, use it as the HARD limit
                                    final maxQty = _confirmedQuantity ?? _getInventoryCount();
                                    final canIncrease = _selectedQuantity < maxQty;
                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.transparent,
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: canIncrease ? Colors.green : Colors.grey,
                                          width: 2,
                                        ),
                                      ),
                                      child: Icon(
                                        Icons.add,
                                        color: canIncrease ? Colors.green : Colors.grey,
                                        size: 18,
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const Spacer(),
                              // Show countdown timer when confirmed (grey border style)
                              if (_confirmedQuantity != null)
                                Builder(
                                  builder: (context) {
                                    debugPrint('Timer display: confirmed=$_confirmedQuantity, hours=$_quantityHoursRemaining, expires=$_quantityExpiresAt');
                                    // Calculate remaining time from expiry
                                    String timeText = '${_quantityHoursRemaining}h';
                                    if (_quantityExpiresAt != null) {
                                      final now = DateTime.now();
                                      final remaining = _quantityExpiresAt!.difference(now);
                                      final hours = remaining.inHours;
                                      final minutes = remaining.inMinutes % 60;
                                      timeText = '${hours}h ${minutes}m';
                                    }
                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.transparent,
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(color: Colors.grey, width: 2),
                                      ),
                                      child: Text(
                                        timeText,
                                        style: const TextStyle(
                                          color: Colors.grey,
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    );
                                  },
                                )
                              // Request button - only show if no confirmed quantity
                              else if (_selectedQuantity > 1)
                                GestureDetector(
                                  onTap: () async {
                                  // Capture scaffoldMessenger before async operations
                                  final scaffoldMessenger = ScaffoldMessenger.of(context);
                                  
                                  try {
                                    debugPrint('🔵 Quantity request button tapped');
                                    // Send quantity request directly without confirmation
                                    final sellerId = productData['userId'] as String? ?? 
                                                     productData['user_id'] as String? ?? 
                                                     productData['seller_id'] as String? ?? '';
                                    final productId = productData['id'] as String? ?? '';
                                    final productTitle = productData['title'] as String? ?? '';
                                    final productCurrency = productData['currency'] ?? CurrencyService.current;
                                    final productImage = ProductImageHelper.getFirstImageUrl(productData);
                                    final user = SupabaseService.instance.currentUser;
                                    
                                    debugPrint('🔵 sellerId: $sellerId, productId: $productId, user: ${user?.id}');
                                    
                                    if (sellerId.isEmpty || user == null) {
                                      debugPrint('❌ Missing sellerId or user');
                                      if (mounted) {
                                        scaffoldMessenger.showSnackBar(
                                          const SnackBar(content: Text('Cannot send request: seller information missing')),
                                        );
                                      }
                                      return;
                                    }
                                    
                                    // Get price and calculate total
                                    final productPrice = productData['price'];
                                    double basePrice = 0;
                                    if (productPrice is num) {
                                      basePrice = productPrice.toDouble();
                                    } else if (productPrice is String) {
                                      basePrice = double.tryParse(productPrice) ?? 0;
                                    }
                                    final totalPrice = basePrice * _selectedQuantity;
                                    
                                    debugPrint('🔵 Quantity request: base=$basePrice, qty=$_selectedQuantity, total=$totalPrice');
                                    
                                    // Create or get conversation - use same format as offers (sorted IDs, no productId)
                                    final ids = [user.id, sellerId];
                                    ids.sort();
                                    final conversationId = 'conv_${ids[0]}_${ids[1]}';
                                    
                                    debugPrint('🔵 conversationId: $conversationId');
                                    
                                    // Ensure conversation exists
                                    final existingConv = await SupabaseService.instance.conversations
                                        .select()
                                        .eq('id', conversationId)
                                        .maybeSingle();

                                    if (existingConv == null) {
                                      debugPrint('🔵 Creating new conversation');
                                      await SupabaseService.instance.conversations.insert({
                                        'id': conversationId,
                                        'product_id': productId,
                                        'product_title': productTitle,
                                        'participants': [user.id, sellerId],
                                        'user_id': sellerId,
                                        'last_message': '',
                                        'last_message_time': DateTime.now().toIso8601String(),
                                        'created_at': DateTime.now().toIso8601String(),
                                        'unread_by': [sellerId],
                                      });
                                    }
                                    
                                    // Check if a first message checkpoint exists for this product
                                    final existingCheckpoint = await SupabaseService.instance.messages
                                        .select()
                                        .eq('conversation_id', conversationId)
                                        .eq('is_first_message', true)
                                        .eq('product_id', productId)
                                        .limit(1);
                                    
                                    debugPrint('🔵 Sending quantity request message');
                                    // Send quantity request message with product card and checkpoint
                                    await SupabaseService.instance.messages.insert({
                                      'conversation_id': conversationId,
                                      'sender_id': user.id,
                                      'created_at': DateTime.now().toIso8601String(),
                                      'type': 'quantity_request',
                                      'is_quantity_request': true,
                                      'quantity_requested': _selectedQuantity,
                                      'product_id': productId,
                                      'product_title': productTitle,
                                      'status': 'pending',
                                      // Add checkpoint only if this is the first message
                                      if (existingCheckpoint.isEmpty) 'is_first_message': true,
                                      if (existingCheckpoint.isEmpty) 'checkpoint_type': 'product_question',
                                      if (existingCheckpoint.isEmpty) 'checkpoint_title': productTitle,
                                      'product_card': {
                                        'title': productTitle,
                                        'price': totalPrice,
                                        'currency': productCurrency,
                                        'imageUrl': productImage,
                                        'quantity': _selectedQuantity,
                                      },
                                    });
                                    
                                    debugPrint('🔵 Updating conversation');
                                    // Update conversation
                                    await SupabaseService.instance.conversations
                                        .update({
                                          'participants': [user.id, sellerId],
                                          'product_id': productId,
                                          'product_title': productTitle,
                                          'last_message': 'Quantity request: $_selectedQuantity units',
                                          'last_message_time': DateTime.now().toIso8601String(),
                                          'updated_at': DateTime.now().toIso8601String(),
                                          'unread_by': [sellerId],
                                        })
                                        .eq('id', conversationId);
                                    
                                    debugPrint('✅ Quantity request sent successfully');
                                    
                                    if (mounted) {
                                      scaffoldMessenger.showSnackBar(
                                        SnackBar(content: Text(I18n.t('request_sent_to_seller'))),
                                      );
                                      // Refresh to check for confirmation
                                      _checkConfirmedQuantity();
                                    }
                                  } catch (e, stackTrace) {
                                    debugPrint('❌ Error sending quantity request: $e');
                                    debugPrint('Stack trace: $stackTrace');
                                    if (mounted) {
                                      scaffoldMessenger.showSnackBar(
                                        SnackBar(content: Text('Error sending request: $e')),
                                      );
                                    }
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.transparent,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: Colors.green, width: 2),
                                  ),
                                  child: Text(
                                    I18n.t('send'),
                                    style: const TextStyle(
                                      color: Colors.green,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Warning message with dark grey background (same as address cards)
                          SizedBox(
                            width: double.infinity,
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey[900],
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: Text(
                                _confirmedQuantity != null
                                    ? I18n.t('seller_confirmed_quantity').replaceAll('{quantity}', '$_confirmedQuantity')
                                    : I18n.t('seller_will_confirm_quantity'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                    // Inventory Section - Only show for product owner AND sold products
                    if (_isOwner && 
                        productData['status'] == 'sold')
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 20),
                          Text(
                            I18n.t('products_remaining'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              // Minus button
                              GestureDetector(
                                onTap: _getInventoryCount() > 0
                                    ? () async {
                                        final newCount = _getInventoryCount() - 1;
                                        _setInventoryCount(newCount);
                                        // Update Supabase
                                        final productId = productData['id'] as String?;
                                        if (productId != null) {
                                          await SupabaseService.instance.products
                                              .update({'inventory_count': newCount})
                                              .eq('id', productId);
                                        }
                                      }
                                    : null,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.transparent,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: _getInventoryCount() > 0
                                          ? Colors.green
                                          : Colors.grey,
                                      width: 2,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.remove,
                                    color: _getInventoryCount() > 0
                                        ? Colors.green
                                        : Colors.grey,
                                    size: 18,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Count display
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.transparent,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.green, width: 2),
                                ),
                                child: Text(
                                  '${_getInventoryCount()}',
                                  style: const TextStyle(
                                    color: Colors.green,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Plus button
                              GestureDetector(
                                onTap: _getInventoryCount() < 99
                                    ? () async {
                                        final newCount = _getInventoryCount() + 1;
                                        _setInventoryCount(newCount);
                                        // Update Supabase
                                        final productId = productData['id'] as String?;
                                        if (productId != null) {
                                          await SupabaseService.instance.products
                                              .update({'inventory_count': newCount})
                                              .eq('id', productId);
                                        }
                                      }
                                    : null,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.transparent,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: _getInventoryCount() < 99
                                          ? Colors.green
                                          : Colors.grey,
                                      width: 2,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.add,
                                    color: _getInventoryCount() < 99
                                        ? Colors.green
                                        : Colors.grey,
                                    size: 18,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              // Take Proof button
                              GestureDetector(
                                onTap: () async {
                                        if (!mounted) return;
                                        
                                        // Navigate to camera screen for inventory verification
                                        final result = await Navigator.push<List<XFile>>(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => const CameraScreen(
                                              initialImages: [],
                                            ),
                                          ),
                                        );

                                        if (result != null && result.isNotEmpty && mounted) {
                                          // Capture context before async operations
                                          final navigator = Navigator.of(context);
                                          final scaffoldMessenger = ScaffoldMessenger.of(context);
                                          
                                          // Show loading indicator
                                          showDialog(
                                            context: context,
                                            barrierDismissible: false,
                                            builder: (context) => const Center(
                                              child: CircularProgressIndicator(),
                                            ),
                                          );

                                          try {
                                            // Upload image to Supabase Storage
                                            final user = SupabaseService.instance.currentUser;
                                            if (user == null) {
                                              if (mounted) navigator.pop();
                                              return;
                                            }

                                            final productId = productData['id'] as String;
                                            final image = result.first; // Use first image
                                            
                                            // Read image bytes
                                            final imageBytes = await File(image.path).readAsBytes();
                                            
                                            // Upload to Supabase
                                            final path = 'inventory_verification/$productId/${DateTime.now().millisecondsSinceEpoch}.jpg';
                                            final imageUrl = await SupabaseService.instance.uploadFile(
                                              bucket: 'products',
                                              path: path,
                                              fileBytes: imageBytes,
                                              contentType: 'image/jpeg',
                                            );

                                            // Close loading dialog immediately after upload
                                            if (mounted) navigator.pop();

                                            // Show "analyzing" notification
                                            if (mounted) {
                                              scaffoldMessenger.showSnackBar(
                                                SnackBar(content: Text(I18n.t('analyzing_inventory'))),
                                              );
                                            }

                                            // Get current user ID from Supabase
                                            final currentUser = SupabaseService.instance.currentUser;
                                            if (currentUser == null) {
                                              throw Exception('User not authenticated');
                                            }

                                            // Get original product images using helper (handles both camelCase and snake_case)
                                            final originalImages = ProductImageHelper.getAllImageUrls(productData);
                                            
                                            if (originalImages.isEmpty) {
                                              throw Exception('No original product images found');
                                            }

                                            // Call Cloud Function to verify inventory in background (don't await)
                                            final functions = FirebaseFunctions.instance;
                                            functions.httpsCallable('verifyInventory').call({
                                              'productId': productId,
                                              'verificationImageUrl': imageUrl,
                                              'inventoryCount': productData['inventoryCount'] ?? productData['inventory_count'] ?? 1,
                                              'originalImageUrls': originalImages,
                                              'userId': currentUser.id, // Pass Supabase user ID
                                            }).then((verifyResult) async {
                                              final data = verifyResult.data as Map<String, dynamic>;

                                              if (data['success'] == true) {
                                                // Update product status to active
                                                await SupabaseService.instance.products
                                                    .update({
                                                      'status': 'active',
                                                      'last_inventory_verification': DateTime.now().toIso8601String(),
                                                    })
                                                    .eq('id', productId);

                                                if (mounted) {
                                                  setState(() {
                                                    productData['status'] = 'active';
                                                  });
                                                  scaffoldMessenger.showSnackBar(
                                                    SnackBar(content: Text(I18n.t('inventory_verified'))),
                                                  );
                                                }
                                              } else {
                                                final reason = data['reason'] as String? ?? 'unknown';
                                                String errorMessage;
                                                
                                                if (reason == 'image_mismatch') {
                                                  errorMessage = I18n.t('image_does_not_match');
                                                } else if (reason == 'suspicious_image') {
                                                  errorMessage = I18n.t('suspicious_image_detected');
                                                } else {
                                                  errorMessage = '${I18n.t('inventory_verification_failed')}: $reason';
                                                }

                                                if (mounted) {
                                                  scaffoldMessenger.showSnackBar(
                                                    SnackBar(content: Text(errorMessage)),
                                                  );
                                                }
                                              }
                                            }).catchError((e) {
                                              debugPrint('❌ Error verifying inventory: $e');
                                              if (mounted) {
                                                scaffoldMessenger.showSnackBar(
                                                  SnackBar(content: Text('${I18n.t('inventory_verification_failed')}: $e')),
                                                );
                                              }
                                            });

                                          } catch (e) {
                                            debugPrint('❌ Error uploading image: $e');
                                            if (mounted) {
                                              navigator.pop(); // Close loading
                                              scaffoldMessenger.showSnackBar(
                                                SnackBar(content: Text('${I18n.t('inventory_verification_failed')}: $e')),
                                              );
                                            }
                                          }
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: Colors.transparent,
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(color: Colors.green, width: 2),
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            SvgPicture.asset('assets/icons/camera.svg', width: 18, height: 18, colorFilter: const ColorFilter.mode(Colors.green, BlendMode.srcIn)),
                                            const SizedBox(width: 8),
                                            Text(
                                              I18n.t('take_proof'),
                                              style: const TextStyle(
                                                color: Colors.green,
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                            ],
                          ),
                        ],
                      ),

                    // Views Analytics - Only show for product owner (not when analyzing or rejected)
                    if (_isOwner && productData['status'] != 'analyzing' && productData['status'] != 'rejected')
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 8),
                          const Text(
                            'Datele anunțului',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                          const SizedBox(height: 4),
                          _buildProductStats(),
                        ],
                      ),

                    // Add Ask the Seller section with FirstMessageOverlay - only show if not own product
                    if (_isBuyer)
                      ...[
                          const SizedBox(height: 12),
                          // Heading and inline seller info to the right
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Flexible(
                                fit: FlexFit.loose,
                                child: Text(
                                  I18n.t('ask_seller'),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.normal,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Inline compact seller info
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 260),
                                child: _buildSellerInline(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          SizedBox(
                            width: double.infinity,
                            child: FirstMessageOverlay(
                            productId: productData['id'] as String? ?? '',
                            productTitle: productData['title'] as String? ?? I18n.t('product'),
                            otherUserId: productData['user_id'] as String? ?? productData['seller_id'] as String? ?? '',
                            otherUserName: productData['sellerName'] as String? ?? I18n.t('seller'),
                            otherUserPhoto: productData['sellerPhoto'] as String?,
                            productData: productData,
                            onMessageSent: () {
                              // Message sent successfully
                              debugPrint('✅ Message sent from product detail page');
                            },
                          ),
                        ),
                      ],

                    
                    // Delivery Address Section - Header with tabs (only show for buyers)
                    if (_isBuyer)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                I18n.t('delivery_address'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.normal,
                                ),
                              ),
                              // Right side controls: Add New (blue) and Edit/Cancel (green)
                              Row(
                                children: [
                                  // Add New button - always opens form for creating a new address
                                  TextButton(
                                    onPressed: () {
                                      setState(() {
                                        _showAddressForm = true;
                                        _formAddressIndex = -1; // mark as new
                                        _loadedAddressIndex = -1;
                                        // Clear controllers for a fresh form
                                        _nameCtrl.clear();
                                        _streetCtrl.clear();
                                        _cityCtrl.clear();
                                        _buildingCtrl.clear();
                                        _phoneCtrl.clear();
                                        _zipCtrl.clear();
                                      });
                                    },
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.blue,
                                      textStyle: const TextStyle(fontWeight: FontWeight.bold),
                                      padding: EdgeInsets.zero,
                                      minimumSize: const Size(0, 0),
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: Text(I18n.t('add_new')),
                                  ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _showAddressForm = !_showAddressForm;
                                      });
                                    },
                                    child: Text(
                                      I18n.t(_showAddressForm ? 'cancel' : 'edit'),
                                      style: const TextStyle(
                                        color: Colors.green,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          // Address Content - Show form or saved addresses
                          _buildAddressSection(),
                          // Seller's other products - horizontal scroller (below address)
                          FutureBuilder<List<Map<String, dynamic>>>(
                            // Use cached future to avoid refetching on every rebuild
                            future: _sellerProductsFuture,
                            builder: (context, snapshot) {
                              if (snapshot.connectionState == ConnectionState.waiting) {
                                return const SizedBox.shrink();
                              }
                              if (!snapshot.hasData || snapshot.data!.isEmpty) return const SizedBox.shrink();
                              final products = snapshot.data!.where((p) => p['id'] != (productData['id'] as String? ?? '')).toList();
                              if (products.isEmpty) return const SizedBox.shrink();

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 12),
                                  Text(
                                    I18n.t('more_from_seller'),
                                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.normal),
                                  ),
                                  const SizedBox(height: 4),
                                  // Match profile page horizontal scroll
                                  SizedBox(
                                    height: 213,
                                    child: LayoutBuilder(
                                      builder: (context, constraints) {
                                        final screenWidth = MediaQuery.of(context).size.width;
                                        const outerPadding = 20.0; // match page padding
                                        // Match profile page card width
                                        const cardWidth = 160.0;

                                        return OverflowBox(
                                          maxWidth: screenWidth,
                                          alignment: Alignment.centerLeft,
                                          child: Transform.translate(
                                            offset: const Offset(-outerPadding, 0),
                                            child: SizedBox(
                                              width: screenWidth,
                                              child: ListView.separated(
                                                scrollDirection: Axis.horizontal,
                                                itemCount: products.length,
                                                physics: const BouncingScrollPhysics(),
                                                // Ensure the first and last cards line up with page
                                                // content by giving the list left and right padding
                                                // that matches the page's outer padding. Individual
                                                // items only get right spacing so cards keep even gaps.
                                                padding: const EdgeInsets.only(left: outerPadding, right: outerPadding),
                                                separatorBuilder: (_, __) => const SizedBox(width: 12),
                                                itemBuilder: (context, index) {
                                                  final itemMap = products[index];
                                                  final itemId = itemMap['id']?.toString() ?? '';
                                                  final isFavorited = _favoritedProductIds.contains(itemId);
                                                  
                                                  return Padding(
                                                    padding: const EdgeInsets.only(right: 6),
                                                    child: ProductCardWidget(
                                                      product: itemMap,
                                                      width: cardWidth,
                                                      height: 213,
                                                      recentlyViewedIds: _recentlyViewedIds,
                                                      showFavoriteButton: true,
                                                      useAlternatePositioning: true, // Use lower positioning for seller section
                                                      isFavorited: isFavorited,
                                                      onFavoriteTap: () async {
                                                        // Toggle favorite status
                                                        final user = SupabaseService.instance.currentUser;
                                                        if (user == null) return;
                                                        
                                                        try {
                                                          final userData = await SupabaseService.instance.users
                                                              .select('favorites')
                                                              .eq('id', user.id)
                                                              .maybeSingle();
                                                          
                                                          if (userData != null) {
                                                            final currentFavorites = (userData['favorites'] as List<dynamic>? ?? [])
                                                                .map((id) => id.toString())
                                                                .toList();
                                                            
                                                            List<String> updatedFavorites;
                                                            if (isFavorited) {
                                                              // Remove from favorites
                                                              updatedFavorites = currentFavorites.where((id) => id != itemId).toList();
                                                            } else {
                                                              // Add to favorites
                                                              updatedFavorites = [...currentFavorites];
                                                              if (!updatedFavorites.contains(itemId)) {
                                                                updatedFavorites.add(itemId);
                                                              }
                                                            }
                                                            
                                                            // Update in Supabase
                                                            await SupabaseService.instance.users
                                                                .update({'favorites': updatedFavorites})
                                                                .eq('id', user.id);
                                                            
                                                            // Update local state
                                                            if (mounted) {
                                                              setState(() {
                                                                _favoritedProductIds = updatedFavorites.toSet();
                                                              });
                                                              
                                                              NotificationHelper.showNotification(
                                                                context,
                                                                isFavorited ? I18n.t('removed_from_favorites') : I18n.t('added_to_favorites'),
                                                              );
                                                            }
                                                          }
                                                        } catch (e) {
                                                          debugPrint('Error toggling favorite: $e');
                                                        }
                                                      },
                                                      onTap: () {
                                                        final itemWithCurrency = Map<String, dynamic>.from(itemMap);
                                                        itemWithCurrency['currency'] = itemMap['currency'] ?? CurrencyService.current;
                                                        Navigator.push(
                                                          context,
                                                          MaterialPageRoute(
                                                            builder: (_) => ProductDetailPage(product: itemWithCurrency),
                                                          ),
                                                        );
                                                      },
                                                    ),
                                                  );
                                                },
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    
                    // Seller Actions - Hide Ad & Delete Ad buttons (only for owner, not when analyzing)
                    ], // end analyzing hide

                    // Listing Paused banner (for hidden products)
                    if (_isOwner && productData['status'] == 'hidden')
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey[900],
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.orange.withValues(alpha: 0.3), width: 1),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: SvgPicture.asset('assets/icons/hide.svg', width: 20, height: 20, colorFilter: const ColorFilter.mode(Colors.orange, BlendMode.srcIn)),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        I18n.t('gig_paused_title'),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        I18n.t('gig_paused_description'),
                                        style: TextStyle(
                                          color: Colors.grey[400],
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            GestureDetector(
                              onTap: () async {
                                final productId = productData['id'] as String?;
                                if (productId == null) return;
                                await SupabaseService.instance.products
                                    .update({
                                      'status': 'active',
                                      'updated_at': DateTime.now().toIso8601String(),
                                    })
                                    .eq('id', productId);
                                if (mounted) {
                                  NotificationHelper.showNotification(context, I18n.t('listing_reactivated'));
                                  setState(() {
                                    productData['status'] = 'active';
                                  });
                                }
                              },
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Center(
                                  child: Text(
                                    I18n.t('reactivate_listing'),
                                    style: const TextStyle(
                                      color: Colors.orange,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    if (_isOwner && productData['status'] != 'analyzing' && productData['status'] != 'rejected')
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Row(
                            children: [
                                // Delete Ad pill button (LEFT)
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () async {
                                      final productId = productData['id'] as String?;
                                      if (productId == null) return;
                                      
                                      if (!mounted) return;
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          backgroundColor: const Color(0xFF242424),
                                          title: Text(I18n.t('delete_ad_title'), style: const TextStyle(color: Colors.white)),
                                          content: Text(
                                            I18n.t('delete_ad_confirm'),
                                            style: const TextStyle(color: Colors.white70),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(context, false),
                                              child: const Text('Cancel'),
                                            ),
                                            TextButton(
                                              onPressed: () => Navigator.pop(context, true),
                                              child: const Text('Delete', style: TextStyle(color: Colors.red)),
                                            ),
                                          ],
                                        ),
                                      );
                                      
                                      if (confirm == true) {
                                        try {
                                          // Show loading indicator
                                          if (mounted) {
                                            showDialog(
                                              context: context,
                                              barrierDismissible: false,
                                              builder: (context) => const Center(
                                                child: CircularProgressIndicator(),
                                              ),
                                            );
                                          }
                                          
                                          // Delete full-size images from storage (keep hover for order cards/chats)
                                          final imageUrls = productData['imageUrls'] as List<dynamic>? ?? 
                                                           productData['image_urls'] as List<dynamic>? ?? [];
                                          
                                          for (final imageUrl in imageUrls) {
                                            if (imageUrl == null) continue;
                                            final urlStr = imageUrl.toString();
                                            
                                            // Skip hover thumbnails
                                            if (urlStr.contains('/hover/')) continue;
                                            
                                            final uri = Uri.parse(urlStr);
                                            final pathSegments = uri.pathSegments;
                                            
                                            final productsIndex = pathSegments.indexOf('products');
                                            if (productsIndex != -1 && productsIndex < pathSegments.length - 1) {
                                              final storagePath = pathSegments.sublist(productsIndex + 1).join('/');
                                              
                                              try {
                                                await SupabaseService.instance.deleteFile('products', storagePath);
                                                debugPrint('✅ Deleted image: $storagePath');
                                              } catch (e) {
                                                debugPrint('⚠️ Error deleting image $storagePath: $e');
                                              }
                                            }
                                          }
                                          
                                          // Delete inventory verification images
                                          try {
                                            final verificationFiles = await SupabaseService.instance.client.storage
                                                .from('products')
                                                .list(path: 'inventory_verification/$productId');
                                            if (verificationFiles.isNotEmpty) {
                                              final paths = verificationFiles
                                                  .map((f) => 'inventory_verification/$productId/${f.name}')
                                                  .toList();
                                              await SupabaseService.instance.client.storage
                                                  .from('products')
                                                  .remove(paths);
                                              debugPrint('✅ Deleted ${paths.length} inventory verification images');
                                            }
                                          } catch (e) {
                                            debugPrint('⚠️ Error deleting inventory verification images: $e');
                                          }
                                          
                                          // Soft-delete: set status to 'deleted', clear full image URLs but keep hover
                                          await SupabaseService.instance.products
                                              .update({
                                                'status': 'deleted',
                                                'image_urls': <String>[],
                                              })
                                              .eq('id', productId);
                                          
                                          debugPrint('✅ Product soft-deleted: $productId (hover preserved)');
                                          
                                          // Close loading dialog
                                          if (mounted) {
                                            Navigator.pop(context);
                                          }
                                          
                                          // Show success notification and navigate back
                                          if (mounted) {
                                            NotificationHelper.showNotification(
                                              context,
                                              I18n.t('product_deleted'),
                                            );
                                            Navigator.pop(context);
                                          }
                                        } catch (e) {
                                          debugPrint('❌ Error deleting product: $e');
                                          
                                          // Close loading dialog
                                          if (mounted) {
                                            Navigator.pop(context);
                                          }
                                          
                                          // Show error notification
                                          if (mounted) {
                                            NotificationHelper.showNotification(
                                              context,
                                              '${I18n.t('error_deleting_product')}: $e',
                                            );
                                          }
                                        }
                                      }
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      decoration: BoxDecoration(
                                        color: Colors.red.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(24),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          SvgPicture.asset('assets/icons/delete.svg', width: 20, height: 20, colorFilter: const ColorFilter.mode(Colors.red, BlendMode.srcIn)),
                                          const SizedBox(width: 8),
                                          const Text(
                                            'Delete',
                                            style: TextStyle(
                                              color: Colors.red,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 15,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // Hide Ad pill button (RIGHT) - hide when analyzing
                                if (productData['status'] != 'analyzing')
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () async {
                                      final productId = productData['id'] as String?;
                                      if (productId == null) return;
                                      
                                      final currentStatus = productData['status'] ?? 'active';
                                      final newStatus = currentStatus == 'hidden' ? 'active' : 'hidden';
                                      
                                      await SupabaseService.instance.products
                                          .update({'status': newStatus})
                                          .eq('id', productId);
                                      
                                      if (mounted) {
                                        NotificationHelper.showNotification(
                                          context, 
                                          newStatus == 'hidden' ? 'Ad hidden from search' : 'Ad visible in search'
                                        );
                                        setState(() {
                                          productData['status'] = newStatus;
                                        });
                                      }
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF242424),
                                        borderRadius: BorderRadius.circular(24),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          SvgPicture.asset(
                                            (productData['status'] ?? 'active') == 'hidden' 
                                                ? 'assets/icons/eye.svg' 
                                                : 'assets/icons/hide.svg',
                                            width: 20,
                                            height: 20,
                                            colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            (productData['status'] ?? 'active') == 'hidden' 
                                                ? I18n.t('show') 
                                                : I18n.t('hide'),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 15,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                    
                    // Add padding at bottom to prevent content from being hidden behind buttons AND to show draggable handle
                    const SizedBox(height: 70),
                    ],
                  ),
                ),
              ),
              ), // MediaQuery
              ),

              // Fixed Action Buttons at Bottom (Delete LEFT, Back MIDDLE, Buy Now RIGHT)
              Positioned(
                bottom: 25,
                left: 20,
                right: 20,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final screenWidth = constraints.maxWidth;
                    // Reduce padding on smaller screens
                    final horizontalPadding = screenWidth < 350 ? 16.0 : 24.0;
                    final isOwner = _isOwner;
                    final isBuyer = !isOwner;
                    
                    // Check if price exceeds €3500 (convert to EUR if needed)
                    final basePrice = (productData['price'] is num) ? (productData['price'] as num).toDouble() : double.tryParse(productData['price']?.toString() ?? '') ?? 0.0;
                    final currency = productData['currency'] as String? ?? CurrencyService.current;
                    bool isHighValueProduct = false;
                    
                    if (currency == 'EUR') {
                      isHighValueProduct = basePrice > 3500;
                    } else if (currency == 'RON') {
                      // Approximate conversion: 1 EUR ≈ 5 RON
                      isHighValueProduct = (basePrice / 5) > 3500;
                    } else if (currency == 'USD') {
                      // Approximate conversion: 1 EUR ≈ 1.1 USD
                      isHighValueProduct = (basePrice / 1.1) > 3500;
                    }
                    
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        // Side buttons row for equal spacing
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Empty space on left for symmetry
                            const SizedBox.shrink(),
                            
                            // Buy Now Pill - Right side (only show for buyers and non-high-value products)
                            if (isBuyer && !isHighValueProduct)
                              LiquidGlassButton(
                                borderRadius: 24,
                                child: Container(
                                height: 48,
                                constraints: BoxConstraints(minWidth: screenWidth < 350 ? 100 : 120),
                                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                                decoration: BoxDecoration(
                                  color: Colors.transparent,
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () async {
                                      if (_selectedAddressIndex < 0) {
                                        // Require address selection before proceeding
                                        if (!mounted) return;
                                        NotificationHelper.showNotification(context, I18n.t('no_address_selected'));
                                        return;
                                      }
                                      
                                      // Navigate to checkout page with card carousel
                                      final basePrice = (productData['price'] is num) ? (productData['price'] as num).toDouble() : double.tryParse(productData['price']?.toString() ?? '') ?? 0.0;
                                      var quantity = _selectedQuantity > 0 ? _selectedQuantity : 1;
                                      
                                      // Enforce confirmed quantity limit if exists
                                      if (_confirmedQuantity != null && quantity > _confirmedQuantity!) {
                                        quantity = _confirmedQuantity!;
                                        setState(() {
                                          _selectedQuantity = _confirmedQuantity!;
                                        });
                                      }
                                      
                                      final totalPrice = basePrice * quantity;
                                      final paymentBreakdown = PaymentConstants.calculatePaymentBreakdown(totalPrice);
                                      
                                      // Create product data with quantity information
                                      final productWithQuantity = Map<String, dynamic>.from(productData);
                                      productWithQuantity['quantity'] = quantity;
                                      productWithQuantity['unitPrice'] = basePrice;
                                      productWithQuantity['totalPrice'] = totalPrice;
                                      
                                      // Store quantity for instant update
                                      final purchasedQuantity = quantity;
                                      
                                      if (!mounted) return;
                                      final result = await Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => OrderCheckoutPage(
                                            product: productWithQuantity,
                                            address: _selectedAddressIndex >= 0 ? _selectedAddressData : null,
                                            paymentBreakdown: paymentBreakdown,
                                            orderId: '', // Will be generated during payment
                                            onPaymentConfirmed: (card) {
                                              // INSTANT UPDATE: Optimistically update UI before backend confirms
                                              if (mounted) {
                                                setState(() {
                                                  // Clear quantity confirmation
                                                  _confirmedQuantity = null;
                                                  _quantityExpiresAt = null;
                                                  _quantityHoursRemaining = 0;
                                                  
                                                  // Cancel the timer
                                                  _quantityExpiryTimer?.cancel();
                                                  _quantityExpiryTimer = null;
                                                  
                                                  // Update inventory count
                                                  final currentInventory = _getInventoryCount();
                                                  final newInventory = currentInventory - purchasedQuantity;
                                                  _setInventoryCount(newInventory);
                                                  productData['inventory_count'] = newInventory;
                                                  
                                                  // Reset selected quantity
                                                  _selectedQuantity = 1;
                                                });
                                                debugPrint('✅ Instant UI update: inventory decreased by $purchasedQuantity, quantity confirmation cleared, timer cancelled');
                                              }
                                              
                                              // Small delay to let user see the update
                                              Future.delayed(const Duration(milliseconds: 100), () {
                                                if (mounted) {
                                                  // Payment completed, navigate to profile
                                                  Navigator.of(context).pop();
                                                  Navigator.of(context).push(
                                                    MaterialPageRoute(
                                                      builder: (_) => const ProfilePage(),
                                                    ),
                                                  );
                                                }
                                              });
                                            },
                                          ),
                                        ),
                                      );
                                      
                                      // Refresh product data after returning from checkout
                                      if (result == true || result == null) {
                                        debugPrint('🔄 Refreshing product data after checkout');
                                        
                                        // Reload product to get updated inventory
                                        final currentProductId = productData['id'] as String?;
                                        if (currentProductId != null) {
                                          try {
                                            final response = await SupabaseService.instance.products
                                                .select()
                                                .eq('id', currentProductId)
                                                .maybeSingle();
                                            
                                            if (response != null) {
                                              setState(() {
                                                productData = response;
                                                _setInventoryCount(response['inventory_count'] ?? 0);
                                              });
                                              debugPrint('✅ Product data refreshed, inventory: ${response['inventory_count']}');
                                            }
                                          } catch (e) {
                                            debugPrint('❌ Error refreshing product: $e');
                                          }
                                        }
                                        
                                        // Clear confirmed quantity state
                                        setState(() {
                                          _confirmedQuantity = null;
                                        });
                                        debugPrint('✅ Quantity confirmation cleared');
                                      }
                                    },
                                    borderRadius: BorderRadius.circular(24),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          I18n.t('buy_now'),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              )
                            else if (isOwner)
                              // If product is sold, show nothing (inventory managed above)
                              (productData['status'] == 'sold')
                                ? const SizedBox.shrink()
                                // If product has problems (rejected or pending_review), show nothing
                                : (productData['status'] == 'rejected' || productData['status'] == 'pending_review' || productData['status'] == 'analyzing')
                                ? const SizedBox.shrink()
                                // If product needs payment (car listing fee), show Pay Fee button
                                : (productData['status'] == 'needs_payment')
                                ? LiquidGlassButton(
                                    borderRadius: 24,
                                    glassColor: Colors.red,
                                    child: Container(
                                    height: 48,
                                    constraints: BoxConstraints(minWidth: screenWidth < 350 ? 100 : 120),
                                    padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                                    decoration: BoxDecoration(
                                      color: Colors.transparent,
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () async {
                                          final productId = productData['id'] as String? ?? '';
                                          await _navigateToListingFeeCheckout(productId);
                                        },
                                        borderRadius: BorderRadius.circular(24),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              I18n.t('pay_fee'),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  )
                                : LiquidGlassButton(
                                    borderRadius: 24,
                                    child: Container(
                                height: 48,
                                constraints: BoxConstraints(minWidth: screenWidth < 350 ? 100 : 120),
                                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                                decoration: BoxDecoration(
                                  color: Colors.transparent,
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () async {
                                      // Get product details
                                      final productId = productData['id'] as String? ?? '';
                                      final productTitle = productData['title'] as String? ?? '';
                                      // Check both camelCase and snake_case for image URLs
                                      final imageUrls = (productData['imageUrls'] as List?)?.cast<String>() ?? 
                                                       (productData['image_urls'] as List?)?.cast<String>() ?? [];
                                      final productImageUrl = imageUrls.isNotEmpty ? imageUrls.first : '';
                                      final productPrice = (productData['price'] is num) ? (productData['price'] as num).toDouble() : double.tryParse(productData['price']?.toString() ?? '') ?? 0.0;
                                      final currency = productData['currency'] as String? ?? CurrencyService.current;
                                      
                                      if (!mounted) return;
                                      // Navigate to promotion modal
                                      final result = await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => PromoteProductModal(
                                            productId: productId,
                                            productTitle: productTitle,
                                            productImageUrl: productImageUrl,
                                            productPrice: productPrice,
                                            currency: currency,
                                            itemType: 'product',
                                          ),
                                        ),
                                      );
                                      
                                      if (result != null && result is Map && result['paymentSuccess'] == true) {
                                        debugPrint('✨ Product promoted successfully: $productId');
                                      }
                                    },
                                    borderRadius: BorderRadius.circular(24),
                                    child: const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'Promote',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              )
                            else
                              const SizedBox.shrink(),
                          ],
                        ),
                        // Back Button placeholder
                        const SizedBox(width: 48, height: 48),
                        if ((productData['status'] == 'analyzing' || productData['status'] == 'rejected') && isOwner)
                          Positioned(
                            left: 0,
                            child: Container(
                              height: 48,
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () async {
                                    final productId = productData['id'] as String?;
                                    if (productId == null) return;
                                    if (!mounted) return;
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        backgroundColor: const Color(0xFF242424),
                                        title: Text(I18n.t('delete_ad_title'), style: const TextStyle(color: Colors.white)),
                                        content: Text(
                                          I18n.t('action_cannot_be_undone'),
                                          style: const TextStyle(color: Colors.white70),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(context, false),
                                            child: const Text('Cancel'),
                                          ),
                                          TextButton(
                                            onPressed: () => Navigator.pop(context, true),
                                            child: const Text('Delete', style: TextStyle(color: Colors.red)),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true && mounted) {
                                      try {
                                        // Show loading
                                        showDialog(
                                          context: context,
                                          barrierDismissible: false,
                                          builder: (context) => const Center(child: CircularProgressIndicator()),
                                        );
                                        
                                        // Hard nuke: delete ALL images (full + hover) from storage
                                        final imageUrls = productData['imageUrls'] as List<dynamic>? ?? 
                                                         productData['image_urls'] as List<dynamic>? ?? [];
                                        
                                        for (final imageUrl in imageUrls) {
                                          if (imageUrl == null) continue;
                                          final urlStr = imageUrl.toString();
                                          final uri = Uri.parse(urlStr);
                                          final pathSegments = uri.pathSegments;
                                          final productsIndex = pathSegments.indexOf('products');
                                          if (productsIndex != -1 && productsIndex < pathSegments.length - 1) {
                                            final storagePath = pathSegments.sublist(productsIndex + 1).join('/');
                                            try {
                                              await SupabaseService.instance.deleteFile('products', storagePath);
                                            } catch (_) {}
                                          }
                                        }
                                        
                                        // Delete hover thumbnail
                                        try {
                                          await ImageOptimizationService.deleteHoverThumbnail(productId);
                                        } catch (_) {}
                                        
                                        // Delete inventory verification images
                                        try {
                                          final verificationFiles = await SupabaseService.instance.client.storage
                                              .from('products')
                                              .list(path: 'inventory_verification/$productId');
                                          if (verificationFiles.isNotEmpty) {
                                            final paths = verificationFiles
                                                .map((f) => 'inventory_verification/$productId/${f.name}')
                                                .toList();
                                            await SupabaseService.instance.client.storage
                                                .from('products')
                                                .remove(paths);
                                          }
                                        } catch (_) {}
                                        
                                        // Hard delete product row
                                        await SupabaseService.instance.products.delete().eq('id', productId);
                                        
                                        if (mounted) Navigator.pop(context); // close loading
                                        if (mounted) {
                                          NotificationHelper.showNotification(context, I18n.t('product_deleted'));
                                          Navigator.pop(context);
                                        }
                                      } catch (e) {
                                        if (mounted) Navigator.pop(context); // close loading
                                        if (mounted) {
                                          NotificationHelper.showNotification(context, '${I18n.t('error_deleting_product')}: $e');
                                        }
                                      }
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(24),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SvgPicture.asset('assets/icons/delete.svg', width: 18, height: 18, colorFilter: const ColorFilter.mode(Colors.red, BlendMode.srcIn)),
                                      const SizedBox(width: 6),
                                      const Text(
                                        'Delete',
                                        style: TextStyle(
                                          color: Colors.red,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        
                        // Submit Answers Button - Positioned to the right of back button (like promote)
                        if (productData['status'] == 'pending_review' && isOwner)
                          Positioned(
                            right: 0,
                            child: Builder(
                              builder: (context) {
                                final totalQuestions = (productData['missingInfoQuestions'] as List?)?.length ?? 0;
                                final answeredCount = _missingInfoAnswers.length;
                                final allAnswered = answeredCount >= totalQuestions && totalQuestions > 0;
                                
                                return LiquidGlassButton(
                                  borderRadius: 24,
                                  child: Container(
                                  height: 48,
                                  constraints: BoxConstraints(minWidth: screenWidth < 350 ? 100 : 120),
                                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                                  decoration: BoxDecoration(
                                    color: Colors.transparent,
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: allAnswered ? () => _submitMissingInfoAnswers() : null,
                                      borderRadius: BorderRadius.circular(24),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            allAnswered ? I18n.t('send') : '$answeredCount/$totalQuestions',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
              // First Message Overlay - Only show when message button is tapped and not own product
              if (_showMessageInput && _isBuyer)
                FirstMessageOverlay(
                  productId: productData['id'] as String? ?? '',
                  productTitle: productData['title'] as String? ?? I18n.t('product'),
                  otherUserId: productData['user_id'] as String? ?? productData['seller_id'] as String? ?? '',
                  otherUserName: productData['sellerName'] as String? ?? I18n.t('seller'),
                  otherUserPhoto: productData['sellerPhoto'] as String?,
                  productData: productData,
                  onMessageSent: () {
                    // After message sent, hide the overlay
                    setState(() {
                      _showMessageInput = false;
                    });
                  },
                ),
              // Back Button
              const GoBackButton(),
            ],
          ),
        ),
      );
  }
}

// Custom painter for Apple-style border (light top-left, dark bottom-right)



class _FullscreenImageViewer extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;

  const _FullscreenImageViewer({
    required this.imageUrls,
    required this.initialIndex,
  });

  @override
  State<_FullscreenImageViewer> createState() => _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<_FullscreenImageViewer> {
  late int _currentIndex;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.black.withValues(alpha: 0.5),
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.imageUrls.length,
            onPageChanged: (index) => setState(() => _currentIndex = index),
            itemBuilder: (context, index) {
              return InteractiveViewer(
                minScale: 1.0,
                maxScale: 5.0,
                clipBehavior: Clip.none,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Image.network(
                        widget.imageUrls[index],
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.broken_image,
                          color: Colors.grey,
                          size: 40,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          if (widget.imageUrls.length > 1)
            Positioned(
              bottom: 100,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(widget.imageUrls.length, (i) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _currentIndex == i ? 10 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _currentIndex == i ? Colors.white : Colors.grey[600],
                  ),
                )),
              ),
            ),
          Positioned(
            bottom: 25,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    color: Color(0xFF242424),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(Icons.close, color: Colors.white, size: 24),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
