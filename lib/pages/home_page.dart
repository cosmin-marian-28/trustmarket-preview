import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:async';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import 'profile_page.dart';
import 'add_product_page.dart';
import 'add_gig_page.dart';
import 'favorites_page.dart';
import 'gig_detail_page.dart';
import 'sort_options_page.dart';
import '../widgets/conversations_modal.dart';
import '../services/product_analysis_service.dart';
import 'product_detail_page.dart';
import 'service_detail_page.dart';
import '../services/product_view_history_service.dart';
import '../services/image_loading_service.dart';
import '../helpers/image_helper.dart';
import '../helpers/city_helper.dart';
import '../constants/translations.dart';
import 'add_service_page.dart';
import '../services/supabase_service.dart';
import '../services/advanced_search_service.dart';
import '../services/fcm_service.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/product_card_widget.dart';
import 'package:flutter_svg/flutter_svg.dart';


const MaterialColor emerald = MaterialColor(
  0xFF000000,
  <int, Color>{
    50: Color(0xFFF5F5F5),
    100: Color(0xFFEEEEEE),
    200: Color(0xFFE0E0E0),
    300: Color(0xFFBDBDBD),
    400: Color(0xFF9E9E9E),
    500: Color(0xFF757575),
    600: Color(0xFF616161),
    700: Color(0xFF424242),
    800: Color(0xFF212121),
    900: Color(0xFF000000),
  },
);

class HomePage extends StatefulWidget {
const HomePage({super.key});

@override
State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin, WidgetsBindingObserver {
// View mode: grid, scroll, or list
String viewMode = 'scroll'; // 'grid', 'scroll', 'list'
// Favorites subscription
StreamSubscription? _favoritesSub;

// Grid mode
Offset gridOffset = Offset.zero;
Offset velocity = Offset.zero;
bool isDraggingGrid = false;

// Classic scroll
final ScrollController scrollController = ScrollController();
  // Card sizing constants - dynamically adjusted based on device type
  // Phone devices (< 500px): 140px cards for 2 columns
  // Tablets/Foldables (500px-800px): 160px cards for 3-4 columns  
  // Large tablets/iPad (800px+): 180px cards for 4-5+ columns
  static const double _cardCellSizePhone = 170.0;
  static const double _cardCellSizeTablet = 170.0;
  static const double _cardCellSizeLarge = 185.0;
  static const double _cardGap = 12.0;

  /// Get the appropriate card cell size based on device width
  double _getCardCellSize(double width) {
    if (width < 500) {
      return _cardCellSizePhone;  // Phones (iPhone, S8, etc)
    } else if (width < 800) {
      return _cardCellSizeTablet;  // Tablets and foldables
    } else {
      return _cardCellSizeLarge;  // Large tablets and iPads
    }
  }

  /// Compute number of columns that fit based on device width
  /// Uses conditional card sizing for optimal layout on each device type
  int _columnsForWidth(double width, {double horizontalPadding = 32.0}) {
    final cardSize = _getCardCellSize(width);
    final available = (width - horizontalPadding).clamp(0.0, double.infinity);
    final cols = ((available + _cardGap) / (cardSize + _cardGap)).floor();
    return cols < 1 ? 1 : cols;
  }

// UI state
bool searchExpanded = false;
String searchQuery = '';
bool categoriesVisible = false;
String selectedCategory = 'all';
bool showFavoritesOnly = false;  // Track if showing only favorited products
bool showGigsOnly = false;  // Track if showing only gigs (help requests)
bool showSearchBar = true;  // Track if search bar should be shown at top (always visible)
bool searchPerformed = false;  // Track if search has been performed (Enter pressed)
bool searchFocused = false; // true when the search TextField has keyboard focus
bool _showBookingsHomepage = false;  // Track if bookings should replace sort button
Set<String> favoritedProductIds = {};  // Track favorited product IDs
Set<String> _recentlyViewedIds = {};  // Track recently viewed product IDs (last 14 days)
List<String> searchHistory = [];  // Store recent search queries
bool showSearchHistory = false; // Track if recent search history should be shown (false by default)
bool showServiceCategoriesBar = false; // Track if service categories bar should be shown
  // Currently selected sort option (persisted)
  // Possible values: 'price_low_high', 'price_high_low', 'most_viewed',
  // 'recent_added', 'oldest'
  String sortOption = 'recent_added';
  
  // Services mode state
  bool showServices = false; // Track if showing services instead of products
  String selectedServiceCategory = 'all'; // Track selected service category
  String _selectedServiceType = 'all'; // 'all', 'remote', 'onsite'
  Set<String> _serviceCategories = {'all'}; // Dynamic categories from database
  
  // Category pills state
  bool showCategoryPills = false; // Track if category pills are expanded
  String selectedCategoryType = 'products'; // 'products', 'services', or 'gigs'
  // Category wheel PageController
  late PageController _categoryWheelController;
  
  // City filter state (for gigs and onsite services)
  String? _userCity; // User's account city (default filter)
  String _selectedCityFilter = 'all'; // Currently selected city, 'all' = no filter
  List<String> _availableCities = []; // Cities from gigs + onsite services
  
  // Controller for the search TextField so the text persists across rebuilds
  late TextEditingController _searchController;
  late FocusNode _searchFocusNode;

final List<Map<String, dynamic>> categories = [
{'id': 'all', 'name': 'All', 'emoji': '🔥'},
{'id': 'fashion', 'name': 'Fashion', 'emoji': '👕'},
{'id': 'tech', 'name': 'Tech', 'emoji': '📱'},
{'id': 'home', 'name': 'Home', 'emoji': '🏠'},
{'id': 'sports', 'name': 'Sports', 'emoji': '⚽'},
];

// Firebase products
late ProductAnalysisService analysisService;
List<Map<String, dynamic>> firebaseProducts = [];
bool isLoadingProducts = true;
// Pagination state for products
int _currentPage = 0;
static const int _pageSize = 20;
bool _hasMoreProducts = true;
// Firebase services
List<Map<String, dynamic>> firebaseServices = [];
bool isLoadingServices = false;
// Firebase gigs
List<Map<String, dynamic>> firebaseGigs = [];
bool isLoadingGigs = false;
// Map of productId -> accepted offer data for current user
final Map<String, Map<String, dynamic>> _acceptedOffersByProduct = {};

// Right-side overlay state (for rendering other pages as a mobile-width panel)
Widget? _rightOverlayInitialPage;
bool _rightOverlayVisible = false;
final GlobalKey<NavigatorState> _overlayNavigatorKey = GlobalKey<NavigatorState>();

@override
void initState() {
  super.initState();
  analysisService = ProductAnalysisService();
  
  // Add observer for app lifecycle changes
  WidgetsBinding.instance.addObserver(this);
  
  // Add scroll listener for pagination
  scrollController.addListener(_onScroll);
  
  // Load saved preferences after initializing defaults
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _loadUserPreferences();
    _loadUserCity();
    _loadSearchHistory();
    _loadRecentlyViewedIds();
    _loadBookingsHomepageSetting();
    _loadSavedCategoryType();
  });
  
  // Defer FCM initialization so notification permission is asked
  // after the user has landed on the home screen, not at startup
  _initializeFCMDeferred();
  
  // Initialize the search controller and keep searchQuery in sync
  _searchController = TextEditingController(text: searchQuery);
  _searchFocusNode = FocusNode();
  _searchFocusNode.addListener(() {
    if (_searchFocusNode.hasFocus && !searchFocused) {
      // Focus gained — update immediately
      setState(() => searchFocused = true);
    } else if (!_searchFocusNode.hasFocus && searchFocused) {
      // Focus lost — delay slightly so button onTap callbacks inside
      // the search bar can fire before the bar collapses.
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted && !_searchFocusNode.hasFocus && !showSearchHistory && searchFocused) {
          setState(() => searchFocused = false);
        }
      });
    }
  });
  _searchController.addListener(() {
    if (_searchController.text != searchQuery) {
      setState(() => searchQuery = _searchController.text);
    }
  });
  // Initialize category wheel controller (starts on page 0 = products)
  _categoryWheelController = PageController(viewportFraction: 0.32, initialPage: 1500);
  
  _loadRandomProducts();
  _updateLastActive();
  // Real-time listener removed - using callback pattern for instant updates
  
  // Start order notifications service
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) {
      // FCM handles notifications now - no need for manual listening
    }
  });
}

@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  super.didChangeAppLifecycleState(state);
  // Reload viewed IDs when app resumes
  if (state == AppLifecycleState.resumed) {
    _loadRecentlyViewedIds();
    _loadBookingsHomepageSetting(); // Reload bookings setting
    FCMService().clearBadge(); // Clear ghost badge on app resume
    _updateLastActive();
  }
}

void _attachFavoritesListener(String uid) {
  // Cancel previous if any
  _favoritesSub?.cancel();
  
  // Subscribe to real-time changes for user favorites
  _favoritesSub = SupabaseService.instance.client
      .from('users')
      .stream(primaryKey: ['id'])
      .eq('id', uid)
      .listen((data) {
    try {
      if (data.isNotEmpty) {
        final userData = data.first;
        final favorites = userData['favorites'] as List<dynamic>? ?? [];
        final newFavorites = favorites.map((id) => id.toString()).toSet();
        if (mounted && newFavorites != favoritedProductIds) {
          setState(() {
            favoritedProductIds = newFavorites;
          });
          debugPrint('✅ Favorites updated in real-time: ${favoritedProductIds.length} items');
        }
      }
    } catch (e) {
      debugPrint('Error in favorites listener: $e');
    }
  });
}

/// Open a given page in the right-side overlay on wide screens.
/// Returns the result passed when that page pops, just like Navigator.push.
Future<dynamic> _openRightOverlay(Widget page) async {
  // Show the overlay container with its own Navigator.
  setState(() {
    _rightOverlayInitialPage = page;
    _rightOverlayVisible = true;
  });

  // Wait a frame for the overlay Navigator to be available.
  await Future.delayed(const Duration(milliseconds: 16));

  if (_overlayNavigatorKey.currentState == null) return null;

  final result = await _overlayNavigatorKey.currentState!.push(MaterialPageRoute(builder: (c) => page));

  // Close the overlay after the inner navigator returns.
  if (mounted) {
    setState(() {
    _rightOverlayVisible = false;
    _rightOverlayInitialPage = null;
  });
  }

  return result;
}

// ignore: unused_element
void _closeRightOverlay() {
  if (_overlayNavigatorKey.currentState != null && _overlayNavigatorKey.currentState!.canPop()) {
    // Pop any inner routes
    while (_overlayNavigatorKey.currentState!.canPop()) {
      _overlayNavigatorKey.currentState!.pop();
    }
  }
  if (mounted) {
    setState(() {
    _rightOverlayVisible = false;
    _rightOverlayInitialPage = null;
  });
  }
}

Future<void> _loadUserPreferences() async {
  try {
    final user = SupabaseService.instance.currentUser;
    if (user == null) {
      debugPrint('⚠️ HOME: No user logged in, cannot load preferences');
      return;
    }
    
    debugPrint('🔵 HOME: Loading preferences for user ${user.id}');
    
    // Load view_mode from users table (primary source of truth)
    final userResponse = await SupabaseService.instance.users
        .select('view_mode')
        .eq('id', user.id)
        .maybeSingle();
    
    String loadedViewMode = 'scroll'; // default
    if (userResponse != null) {
      loadedViewMode = userResponse['view_mode'] as String? ?? 'scroll';
      debugPrint('✅ HOME: View mode loaded from users table: $loadedViewMode');
    } else {
      debugPrint('⚠️ HOME: No user record found, using default: $loadedViewMode');
    }

    setState(() {
      viewMode = loadedViewMode;
      debugPrint('🔵 HOME: viewMode state updated to: $viewMode');
    });
    debugPrint('✅ HOME: User preferences loaded from Supabase (viewMode: $viewMode)');

    // Load favorites
    await _loadUserFavorites();
    
    // Start favorites real-time listener
    _attachFavoritesListener(user.id);
  } catch (e) {
    debugPrint('❌ HOME: Error loading preferences: $e');
  }
}

Future<void> _loadUserCity() async {
  try {
    final user = SupabaseService.instance.currentUser;
    if (user == null) return;
    final response = await SupabaseService.instance.users
        .select('city')
        .eq('id', user.id)
        .maybeSingle();
    if (response != null && mounted) {
      final city = response['city'] as String?;
      if (city != null && city.isNotEmpty) {
        setState(() {
          _userCity = normalizeCity(city);
          _selectedCityFilter = _userCity!;
        });
        debugPrint('🏙️ User city loaded: $city');
      }
    }
  } catch (e) {
    debugPrint('❌ Error loading user city: $e');
  }
}

Future<void> _loadUserFavorites() async {
  try {
    final user = SupabaseService.instance.currentUser;
    if (user == null) return;

    final response = await SupabaseService.instance.users
        .select('favorites')
        .eq('id', user.id)
        .maybeSingle();

    if (response != null) {
      final data = response;
      final favorites = data['favorites'] as List<dynamic>? ?? [];
      setState(() {
        favoritedProductIds = favorites.map((id) => id.toString()).toSet();
      });
      debugPrint('✅ User favorites loaded: ${favoritedProductIds.length} items');
    }
  } catch (e) {
    debugPrint('❌ Error loading favorites: $e');
  }
}

Future<void> _loadBookingsHomepageSetting() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getBool('show_bookings_homepage') ?? false;
    if (mounted) {
      setState(() {
        _showBookingsHomepage = value;
      });
      debugPrint('✅ Bookings homepage setting loaded: $value');
    }
  } catch (e) {
    debugPrint('❌ Error loading bookings homepage setting: $e');
  }
}

Future<void> _loadSearchHistory() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('search_history') ?? [];
    setState(() {
      searchHistory = history;
    });
    debugPrint('✅ Search history loaded: ${searchHistory.length} items - $searchHistory');
  } catch (e) {
    debugPrint('❌ Error loading search history: $e');
  }
}

Future<void> _loadRecentlyViewedIds() async {
  try {
    final viewedIds = await ProductViewHistoryService.getRecentlyViewedIds();
    setState(() {
      _recentlyViewedIds = viewedIds;
    });
    debugPrint('✅ Recently viewed IDs loaded: ${_recentlyViewedIds.length} products');
  } catch (e) {
    debugPrint('❌ Error loading recently viewed IDs: $e');
  }
}

Future<void> _saveSearchHistory() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('search_history', searchHistory);
    debugPrint('✅ Search history saved: ${searchHistory.length} items - $searchHistory');
  } catch (e) {
    debugPrint('❌ Error saving search history: $e');
  }
}

Future<void> _addToSearchHistory(String query) async {
  if (query.trim().isEmpty) return;

  debugPrint('💾 Adding to search history: "$query"');

  setState(() {
    // Remove if already exists
    searchHistory.remove(query);
    // Add to beginning
    searchHistory.insert(0, query);
    // Keep only last 10 searches
    if (searchHistory.length > 10) {
      searchHistory = searchHistory.sublist(0, 10);
    }
  });

  await _saveSearchHistory();
}

Future<void> _saveUserPreferences() async {
  try {
    final user = SupabaseService.instance.currentUser;
    if (user == null) return;
    
    // Save view_mode to user_preferences
    await SupabaseService.instance.client
        .from('user_preferences')
        .upsert({
          'user_id': user.id,
          'view_mode': viewMode,
          'updated_at': DateTime.now().toIso8601String(),
        });
    
    // Also save view_mode to users table (for consistency with profile page)
    await SupabaseService.instance.users
        .update({
          'view_mode': viewMode,
          'last_updated': DateTime.now().toIso8601String(),
        })
        .eq('id', user.id);
    
    debugPrint('✅ User preferences saved to Supabase');
  } catch (e) {
    debugPrint('❌ Error saving preferences: $e');
  }
}

/// Update last_active_at so the inactivity scheduler knows the user is alive.
/// Fire-and-forget — errors are silently ignored.
Future<void> _updateLastActive() async {
  try {
    final uid = SupabaseService.instance.currentUserId;
    if (uid == null) return;
    await SupabaseService.instance.client
        .from('users')
        .update({'last_active_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', uid);
  } catch (_) {}
}

Future<void> _loadRandomProducts() async {
  try {
    debugPrint('📥 Loading products from Supabase (page $_currentPage)...');
    
    // Calculate range for pagination
    final startRange = _currentPage * _pageSize;
    final endRange = startRange + _pageSize - 1;
    
    // Build query - fetch products from Supabase
    var query = SupabaseService.instance.products
        .select()
        .eq('status', 'active'); // Only show active products
    
    // Apply category filter if not 'all'
    if (selectedCategory != 'all') {
      debugPrint('📂 Applying category filter: "$selectedCategory"');
      query = query.eq('category', selectedCategory);
    }
    
    // For progressive search, fetch a larger batch to filter client-side
    // since progressive search checks title + answer tags
    List<dynamic> products;
    
    if (searchPerformed && searchQuery.trim().isNotEmpty && _currentPage == 0) {
      final searchTerm = searchQuery.trim();
      debugPrint('🔍 Applying progressive search: "$searchTerm"');
      
      final allResponse = await query
          .order('created_at', ascending: false)
          .limit(500);
      
      final allProducts = (allResponse as List<dynamic>)
          .map((p) => Map<String, dynamic>.from(p))
          .toList();
      
      debugPrint('🔍 Fetched ${allProducts.length} products for progressive search');
      
      products = AdvancedSearchService.progressiveSearch(
        allProducts,
        searchTerm,
      );
      
      debugPrint('🔍 Progressive search returned ${products.length} results');
      _hasMoreProducts = false; // All results returned at once for search
    } else if (searchPerformed && searchQuery.trim().isNotEmpty && _currentPage > 0) {
      // Don't load more pages during search - all results already loaded
      products = [];
      _hasMoreProducts = false;
    } else {
      // Normal browsing - paginated
      final response = await query
          .order('created_at', ascending: false)
          .range(startRange, endRange);
      
      products = response as List<dynamic>;
      _hasMoreProducts = products.length == _pageSize;
    }
    
    // Convert to Map<String, dynamic> and annotate with accepted offers
    final productsList = products.map((p) => Map<String, dynamic>.from(p)).toList();
    await _annotateProductsWithAcceptedOffers(productsList);

    // Add grid positions for CustomPaint rendering
    final productsWithPositions = productsList.asMap().entries.map((entry) {
      final product = entry.value;
      final index = entry.key;
      return {
        ...product,
        'row': index ~/ 3,  // 3 columns
        'col': index % 3,
      };
    }).toList();
    
    if (mounted) {
      setState(() {
        if (_currentPage == 0) {
          // First page - replace products
          firebaseProducts = productsWithPositions;
        } else {
          // Subsequent pages - append products
          firebaseProducts.addAll(productsWithPositions);
        }
        isLoadingProducts = false;
      });
    }
  } catch (e) {
    debugPrint('❌ Error loading products from Supabase: $e');
    if (mounted) {
      setState(() {
        isLoadingProducts = false;
      });
    }
  }
}

/// Load next page of products
Future<void> _loadMoreProducts() async {
  if (!_hasMoreProducts || isLoadingProducts) return;
  
  setState(() {
    _currentPage++;
    isLoadingProducts = true;
  });
  
  await _loadRandomProducts();
}

/// Refresh products (reset to first page)
Future<void> _refreshProducts() async {
  setState(() {
    _currentPage = 0;
    _hasMoreProducts = true;
    isLoadingProducts = true;
  });
  
  await _loadRandomProducts();
}

/// Handle scroll events for pagination
void _onScroll() {
  // Only paginate in list/scroll mode, not in grid mode
  if (viewMode == 'grid') return;
  
  // Check if we're near the bottom of the scroll view
  if (scrollController.position.pixels >= scrollController.position.maxScrollExtent - 200) {
    // Load more products if available
    _loadMoreProducts();
  }
}

  /// For the fetched products, check whether the current authenticated
  /// user has an accepted offer and, if so, override the product's price
  /// and currency for the user's view and set a flag used by the UI.
  Future<void> _annotateProductsWithAcceptedOffers(List<Map<String, dynamic>> products) async {
    try {
      final user = SupabaseService.instance.currentUser;
      if (user == null) return;

      final offersResponse = await SupabaseService.instance.offers
          .select()
          .eq('buyer_id', user.id)
          .eq('status', 'accepted');

      final offers = offersResponse as List<dynamic>;

      _acceptedOffersByProduct.clear();
      for (final offer in offers) {
        final data = offer as Map<String, dynamic>;
        final pid = data['product_id']?.toString();
        if (pid == null) continue;
        // Only keep accepted offers that are within 24 hours
        DateTime? acceptedAt;
        try {
          final a = data['accepted_at'];
          if (a is String) {
            acceptedAt = DateTime.parse(a);
          } else if (a is DateTime) {
            acceptedAt = a;
          }
        } catch (e) {
          acceptedAt = null;
        }
        if (acceptedAt == null) continue;
        if (DateTime.now().difference(acceptedAt).inHours >= 24) continue;
        // Store offer data with document ID
        final offerData = Map<String, dynamic>.from(data);
        offerData['_offerId'] = data['id'];
        _acceptedOffersByProduct[pid] = offerData;
      }

      // Apply overrides for products list
      for (final p in products) {
        final pid = p['id']?.toString();
        if (pid != null && _acceptedOffersByProduct.containsKey(pid)) {
          final offer = _acceptedOffersByProduct[pid]!;
          final offered = offer['offered_price'] ?? offer['offeredPrice'] ?? offer['offered'];
          final currency = offer['currency'] as String?;
          final offerId = offer['_offerId'] as String?;
          if (offered != null) p['price'] = offered;
          if (currency != null && currency.isNotEmpty) p['currency'] = currency;
          if (offerId != null) p['_offerId'] = offerId;
          p['_hasAcceptedOffer'] = true;
        } else {
          p['_hasAcceptedOffer'] = false;
          p.remove('_offerId');
        }
      }
    } catch (e) {
      debugPrint('Error annotating products with accepted offers: $e');
    }
  }

Future<void> _initializeFCMDeferred() async {
  // Wait a few seconds so the user sees the home screen first
  await Future.delayed(const Duration(seconds: 3));
  if (!mounted) return;
  try {
    debugPrint('🔔 [HOME] Initializing FCM (deferred)...');
    await FCMService().initialize();
    debugPrint('🔔 [HOME] FCM initialization completed');
  } catch (e) {
    debugPrint('🔔 [HOME] FCM initialization failed: $e');
  }
}

@override
void dispose() {
  WidgetsBinding.instance.removeObserver(this);
  scrollController.removeListener(_onScroll);
  scrollController.dispose();
  _searchController.dispose();
  _searchFocusNode.dispose();
  _categoryWheelController.dispose();
  _favoritesSub?.cancel();
  // FCM handles notifications - no cleanup needed
  super.dispose();
}

/// Get filtered products or services based on current mode
List<Map<String, dynamic>> _getFilteredProducts() {
  debugPrint('🎯 _getFilteredProducts called');
  debugPrint('🎯 selectedCategoryType: "$selectedCategoryType"');
  debugPrint('🎯 showFavoritesOnly: $showFavoritesOnly');
  
  // If favorites mode is enabled, return ALL favorited items (products, services, gigs)
  if (showFavoritesOnly) {
    List<Map<String, dynamic>> allFavorites = [];
    
    // Add favorited products
    allFavorites.addAll(firebaseProducts.where((product) {
      final productId = product['id']?.toString() ?? '';
      return favoritedProductIds.contains(productId);
    }));
    
    // Add favorited services (if loaded)
    if (firebaseServices.isNotEmpty) {
      allFavorites.addAll(firebaseServices.where((service) {
        final serviceId = service['id']?.toString() ?? '';
        return favoritedProductIds.contains(serviceId);
      }));
    }
    
    // Add favorited gigs (if loaded)
    if (firebaseGigs.isNotEmpty) {
      allFavorites.addAll(firebaseGigs.where((gig) {
        final gigId = gig['id']?.toString() ?? '';
        return favoritedProductIds.contains(gigId);
      }));
    }
    
    debugPrint('🎯 Returning ${allFavorites.length} favorites');
    return allFavorites;
  }
  
  // Return based on selected category type
  if (selectedCategoryType == 'gigs') {
    var gigs = List<Map<String, dynamic>>.from(firebaseGigs);
    // Filter gigs by city
    if (_selectedCityFilter != 'all') {
      gigs = gigs.where((gig) {
        final gigCity = gig['city']?.toString().trim() ?? '';
        return isSameCity(gigCity, _selectedCityFilter);
      }).toList();
    }
    debugPrint('🎯 Returning ${gigs.length} gigs (city: $_selectedCityFilter)');
    return gigs;
  }
  
  if (selectedCategoryType == 'services') {
    debugPrint('🎯 Calling _getFilteredServices()');
    final services = _getFilteredServices();
    debugPrint('🎯 Returning ${services.length} services');
    return services;
  }
  
  // Default to products
  debugPrint('🎯 Returning products (default)');
  // Products are already filtered by search and category in _loadRandomProducts()
  // via Supabase queries, so we just need to apply client-side sorting if needed
  var results = firebaseProducts;

  // Apply user-selected sort option (persisted). Safe-guard against
  // missing fields and handle different data shapes.
  try {
    results.sort((a, b) {
      switch (sortOption) {
        case 'price_low_high':
          final pa = a['price'] is num ? (a['price'] as num).toDouble() : double.infinity;
          final pb = b['price'] is num ? (b['price'] as num).toDouble() : double.infinity;
          return pa.compareTo(pb);
        case 'price_high_low':
          final pa2 = a['price'] is num ? (a['price'] as num).toDouble() : -double.infinity;
          final pb2 = b['price'] is num ? (b['price'] as num).toDouble() : -double.infinity;
          return pb2.compareTo(pa2);
        case 'most_viewed':
          final va = (a['views'] ?? a['viewCount'] ?? a['viewsCount'] ?? 0) as num;
          final vb = (b['views'] ?? b['viewCount'] ?? b['viewsCount'] ?? 0) as num;
          return vb.compareTo(va);
        case 'oldest':
          final da = _parseTimestampToMillis(a['createdAt'] ?? a['created_at'] ?? a['addedAt']);
          final db = _parseTimestampToMillis(b['createdAt'] ?? b['created_at'] ?? b['addedAt']);
          return da.compareTo(db);
        case 'recent_added':
        default:
          final da2 = _parseTimestampToMillis(a['createdAt'] ?? a['created_at'] ?? a['addedAt']);
          final db2 = _parseTimestampToMillis(b['createdAt'] ?? b['created_at'] ?? b['addedAt']);
          return db2.compareTo(da2);
      }
    });
  } catch (e) {
    // If sorting fails for any reason, just return unsorted results.
    debugPrint('Error sorting products: $e');
  }

  return results;
}

/// Compute extra vertical offset for category/city bars below search bar
double _extraBarsHeight(bool isMobile) {
  if (!isMobile) return 0.0;
  double extra = 0.0;
  if (selectedCategoryType == 'services' && showServiceCategoriesBar) {
    extra += 40.0;
  }
  return extra;
}

/// Check if the current list (products/services/gigs) is empty
bool _isCurrentListEmpty() {
  if (selectedCategoryType == 'services') {
    return firebaseServices.isEmpty;
  } else if (selectedCategoryType == 'gigs') {
    return firebaseGigs.isEmpty;
  } else {
    return firebaseProducts.isEmpty;
  }
}

int _parseTimestampToMillis(dynamic v) {
  if (v == null) return 0;
  try {
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is DateTime) return v.millisecondsSinceEpoch;
    if (v is String) {
      final parsed = DateTime.tryParse(v);
      if (parsed != null) return parsed.millisecondsSinceEpoch;
    }
  } catch (_) {}
  return 0;
}

@override
Widget build(BuildContext context) {
  final screenSize = MediaQuery.of(context).size;
  // Preserve the original desktop detection based on the full screen size.
  // When we later constrain the left column with MediaQuery.copyWith(size: Size(leftWidth,...))
  // that would make `size.shortestSide` smaller and incorrectly flip the UI into
  // mobile behavior. Compute this once from the real screenSize and reuse it.
  // Treat the layout as "desktop" only when the available width is wide
  // enough. This ensures that when a desktop window is resized to a
  // narrow width (matching phones) the UI falls back to mobile rules.
  final bool globalIsDesktop = screenSize.width >= 600.0;
  // Build the main homepage stack (without the right overlay). We'll
  // reuse this for single-column mobile and the left column in desktop mode.
  Widget mainHomepageStack(Size size) {
    // Horizontal swipe tracking for category switching.
    // Uses a Listener so it doesn't compete with child GestureDetectors.
    double? swipeStartX;
    double? swipeStartY;
    bool swipeCancelled = false;

    return Listener(
      onPointerDown: (e) {
        swipeStartX = e.position.dx;
        swipeStartY = e.position.dy;
        swipeCancelled = false;
      },
      onPointerMove: (e) {
        if (swipeCancelled || swipeStartX == null || swipeStartY == null) return;
        final dy = (e.position.dy - swipeStartY!).abs();
        // If vertical movement exceeds threshold, this is a scroll — cancel swipe
        if (dy > 30) {
          swipeCancelled = true;
        }
      },
      onPointerUp: (e) {
        if (swipeCancelled || swipeStartX == null || swipeStartY == null) return;
        // Don't switch categories while interacting with search or dragging grid
        if (searchFocused || searchQuery.isNotEmpty || isDraggingGrid) return;
        final dx = e.position.dx - swipeStartX!;
        final dy = (e.position.dy - swipeStartY!).abs();
        final screenWidth = size.width;
        // Require: horizontal distance > 35% of screen width AND mostly horizontal
        if (dx.abs() > screenWidth * 0.35 && dx.abs() > dy * 2.0) {
          const types = ['products', 'services', 'gigs'];
          final currentIndex = types.indexOf(selectedCategoryType);
          if (currentIndex == -1) return;
          final newIndex = dx < 0
              ? (currentIndex + 1) % types.length
              : (currentIndex - 1 + types.length) % types.length;
          if (newIndex != currentIndex) {
            _selectCategoryByType(types[newIndex]);
            // Animate the carousel wheel one page in the swipe direction
            final wheelPage = _categoryWheelController.page?.round() ?? 1500;
            final step = dx < 0 ? 1 : -1; // left swipe = next, right swipe = prev
            _categoryWheelController.animateToPage(
              wheelPage + step,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          }
        }
        swipeStartX = null;
        swipeStartY = null;
      },
      child: Stack(
      children: [
        // Main content area
        Builder(
          builder: (context) {
            debugPrint('🎨 Current viewMode: $viewMode');
            return viewMode == 'grid' 
                ? _buildGridMode(size) 
                : viewMode == 'list'
                    ? _buildListMode()
                    : _buildClassicMode();
          },
        ),

  // Dark fade above search bar — transparent at bottom, solid background at top
  if (!showFavoritesOnly && showSearchBar)
    Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: MediaQuery.of(context).padding.top + 66,
      child: IgnorePointer(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                Color(0x000A0A0A),
                Color(0x330A0A0A),
                Color(0x990A0A0A),
                Color(0xDD0A0A0A),
                Color(0xFF0A0A0A),
              ],
              stops: [0.0, 0.2, 0.5, 0.75, 1.0],
            ),
          ),
        ),
      ),
    ),

  // Favorites header
  if (showFavoritesOnly)
    Positioned(
      top: MediaQuery.of(context).padding.top + 6,
      left: 20,
      child: Text(
        I18n.t('favorites'),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

  // Category wheel (below search bar in z-order so search covers it)
  // Disable touch on wheel when search is expanded so it doesn't steal taps
  if (!showFavoritesOnly && !(searchFocused || searchQuery.isNotEmpty))
    _buildCategoryWheel(size, isDesktopOverride: globalIsDesktop),

  // Search bar overlay (on top) - covers categories when expanded
  // Tap-to-dismiss layer: tapping outside the search bar closes it
  if (!showFavoritesOnly && (searchFocused || searchQuery.isNotEmpty))
    Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          setState(() {
            searchFocused = false;
            showSearchHistory = false;
          });
          _searchFocusNode.unfocus();
        },
      ),
    ),
  // Recent searches modal (after tap-to-dismiss, before search bar for layered effect)
  if (!showFavoritesOnly && showSearchBar && searchHistory.isNotEmpty && showSearchHistory)
    _buildRecentSearchesModal(size, isDesktopOverride: globalIsDesktop),

  if (!showFavoritesOnly && showSearchBar) _buildSearchBarOverlay(size, isDesktopOverride: globalIsDesktop),
  
  // Service categories bar (below search bar when in services mode) - only on mobile, desktop shows inline
  if (!showFavoritesOnly && selectedCategoryType == 'services' && _serviceCategories.length > 1 && showServiceCategoriesBar && !globalIsDesktop) _buildServiceCategoriesBar(size, isDesktopOverride: globalIsDesktop),
  // Hide history button - positioned at bottom center, only show when typing
  if (!showFavoritesOnly && showSearchBar && searchQuery.isNotEmpty && searchHistory.isNotEmpty && !searchPerformed && showSearchHistory)
    Positioned(
      top: 250,
      left: 0,
      right: 0,
      child: Center(
        child: GestureDetector(
          onTap: () {
            setState(() {
              showSearchHistory = false;
              _searchFocusNode.unfocus(); // Close keyboard
            });
          },
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF242424),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: const Icon(
              Icons.expand_less,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
      ),
    ),

        // Fixed bottom button row
        Positioned(
          left: 0,
          right: 0,
          bottom: 34,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () => _performOrbAction('home'),
                  child: _buildHomeOrb(),
                ),
                const SizedBox(width: 18),
                GestureDetector(
                  onTap: () => _performOrbAction('profile'),
                  child: _buildProfileOrb(),
                ),
                const SizedBox(width: 18),
                GestureDetector(
                  onTap: () => _performOrbAction('add'),
                  child: _buildAddOrb(),
                ),
                const SizedBox(width: 18),
                GestureDetector(
                  onTap: () => _performOrbAction('chat'),
                  child: _buildChatOrb(),
                ),
                const SizedBox(width: 18),
                GestureDetector(
                  onTap: () => _performOrbAction('favorites'),
                  child: _buildFavoritesOrb(),
                ),
              ],
            ),
          ),
        ),

        // Categories overlay
        if (categoriesVisible) _buildCategoriesOverlay(),
      ],
    ),
    );
  }

  final bool isDesktop = screenSize.width >= 600.0;
  final double overlayWidth = math.min(420.0, screenSize.width * 0.45);

  // If desktop and overlay is visible, render two-pane: left is the
  // homepage constrained to the remaining width, right is the overlay.
  if (isDesktop && _rightOverlayVisible) {
    final leftWidth = screenSize.width - overlayWidth;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Row(
        children: [
          SizedBox(
            width: leftWidth,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(size: Size(leftWidth, screenSize.height)),
              child: mainHomepageStack(Size(leftWidth, screenSize.height)),
            ),
          ),
          // Right overlay navigator
          Container(
            width: overlayWidth,
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                bottomLeft: Radius.circular(24),
              ),
              border: Border(
                // Use a soft green accent for the overlay divider on desktop
                left: BorderSide(color: const Color.fromARGB(255, 49, 49, 49).withValues(alpha: 0.65), width: 2.0),
              ),
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                bottomLeft: Radius.circular(24),
              ),
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(size: Size(overlayWidth, screenSize.height)),
                child: Navigator(
                  key: _overlayNavigatorKey,
                  onGenerateRoute: (settings) {
                    return MaterialPageRoute(builder: (c) => _rightOverlayInitialPage ?? const SizedBox.shrink());
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Fallback: original single-stack layout (keeps mobile unchanged)
  return Scaffold(
    resizeToAvoidBottomInset: false,
    body: mainHomepageStack(screenSize),
  );
}

Widget _buildGridMode(Size screenSize) {
// Normal mode: grid is draggable
return GestureDetector(
onPanStart: (details) {
  setState(() => isDraggingGrid = true);
},
onPanUpdate: (details) {
  if (isDraggingGrid) {
    final displayProducts = _getFilteredProducts();
    
    // No dragging for single product
    if (displayProducts.length <= 1) {
      setState(() => isDraggingGrid = false);
      return;
    }
    
    final cellSize = _getCardCellSize(MediaQuery.of(context).size.width);
    const gap = _cardGap;
    
    // Calculate grid dimensions
    int gridSize = (math.sqrt(displayProducts.length.toDouble()).ceil()).toInt();
    if (gridSize < 1) gridSize = 1;
    
    final totalGridWidth = gridSize * cellSize + (gridSize - 1) * gap;
    final totalGridHeight = gridSize * cellSize + (gridSize - 1) * gap;
    
    // Allow dragging with ~1 cell height/width of empty space around products
    final paddingZone = cellSize;
    final maxDragX = (totalGridWidth + paddingZone * 2) / 2;
    final maxDragY = (totalGridHeight + paddingZone * 2) / 2;
    
    setState(() {
      gridOffset += details.delta;
      velocity = details.delta;
      
      // Clamp offset to boundaries
      gridOffset = Offset(
        gridOffset.dx.clamp(-maxDragX, maxDragX),
        gridOffset.dy.clamp(-maxDragY, maxDragY),
      );
    });
  }
},
onPanEnd: (details) {
  if (isDraggingGrid) {
    setState(() => isDraggingGrid = false);
    _applyMomentum();
  }
},
child: Stack(
  children: [
    // Background
    Container(
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
    ),
    // Grid of product cards
    CustomPaint(
      painter: GridProductsPainter(firebaseProducts, gridOffset, screenSize),
      size: Size.infinite,
    ),
    // Product cards with actual images
    ..._buildGridProductCards(screenSize),
  ],
),
);
}

List<Widget> _buildGridProductCards(Size screenSize) {
  // Square grid only: cols = rows = sqrt(productCount)
  final displayProducts = _getFilteredProducts();
  final cellSize = _getCardCellSize(screenSize.width);
  const gap = _cardGap;
  
  // ProductCardWidget uses 160x213 aspect ratio (0.75)
  const cardWidth = 160.0;
  const cardHeight = 213.0;
  final cardActualHeight = cellSize * (cardHeight / cardWidth);

  // Calculate square grid size
  int gridSize = (math.sqrt(displayProducts.length.toDouble()).ceil()).toInt();
  if (gridSize < 1) gridSize = 1;
  
  final cols = gridSize;

  final totalGridWidth = cols * cellSize + (cols - 1) * gap;
  final originX = (screenSize.width - totalGridWidth) / 2.0 + gridOffset.dx;

  // Calculate consistent top spacing based on search bar position
  // Search bar uses safe area top + 8px on mobile, 12px on desktop
  // Search bar height: 50px
  final isMobile = screenSize.shortestSide < 600.0;
  final safeTop = MediaQuery.of(context).padding.top;
  final searchBarTop = isMobile ? safeTop + 2.0 : 12.0;
  const searchBarHeight = 42.0;
  final categoriesExtra = _extraBarsHeight(isMobile);
  const spacingBelowSearchBar = 8.0;
  final safeAreaAdjust = (!kIsWeb && isMobile) ? 40.0 : 0.0;
  final originY = searchBarTop + searchBarHeight + categoriesExtra + spacingBelowSearchBar - safeAreaAdjust + gridOffset.dy;

  return displayProducts.asMap().entries.map((entry) {
    final i = entry.key;
    final product = entry.value;
    final col = i % cols;
    final row = i ~/ cols;

    final x = originX + col * (cellSize + gap);
    final y = originY + row * (cardActualHeight + gap); // Use actual card height for row spacing

    // Skip if off-screen (use actual card height for bounds check)
    if (x < -cellSize || x > screenSize.width + cellSize ||
        y < -cardActualHeight || y > screenSize.height + cardActualHeight) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: x,
      top: y,
      width: cellSize,
      height: cardActualHeight,
      child: _buildGridProductCard(product, cellSize, cardActualHeight),
    );
  }).toList();
}

Widget _buildGridProductCard(Map<String, dynamic> product, double cardWidth, double cardHeight) {
  final productId = product['id'] as String? ?? '';
  final isFavorited = favoritedProductIds.contains(productId);

  return ProductCardWidget(
    product: product,
    width: cardWidth,
    height: cardHeight,
    recentlyViewedIds: _recentlyViewedIds,
    showFavoriteButton: true,
    isFavorited: isFavorited,
    onFavoriteTap: () async {
      if (productId.isNotEmpty) {
        final user = SupabaseService.instance.currentUser;
        if (user != null) {
          setState(() {
            if (isFavorited) {
              favoritedProductIds.remove(productId);
            } else {
              favoritedProductIds.add(productId);
            }
          });
          await SupabaseService.instance.users
              .update({
            'favorites': favoritedProductIds.toList(),
          })
              .eq('id', user.id);
        }
      }
    },
    onTap: () async {
      // Mark as viewed when tapped
      if (productId.isNotEmpty) {
        debugPrint('🟢 [Grid] Marking product $productId as viewed. Current count: ${_recentlyViewedIds.length}');
        await ProductViewHistoryService.markAsViewed(productId);
        
        // Reload the viewed IDs to ensure we have the latest
        final updatedIds = await ProductViewHistoryService.getRecentlyViewedIds();
        setState(() {
          _recentlyViewedIds = updatedIds;
        });
        debugPrint('🟢 [Grid] After marking: ${_recentlyViewedIds.length} viewed products, contains $productId: ${_recentlyViewedIds.contains(productId)}');
      }
      
      final productWithCurrency = {...product, 'currency': product['currency'] ?? 'RON'}; // Keep original currency
      
      // Check if this is a gig, service, or product
      final isGig = product['type'] == 'gig' || selectedCategoryType == 'gigs';
      final isService = selectedCategoryType == 'services' && !isGig;
      
      final Widget page;
      if (isGig) {
        page = GigDetailPage(gig: productWithCurrency);
      } else if (isService) {
        page = ServiceDetailPage(service: productWithCurrency);
      } else {
        page = ProductDetailPage(product: productWithCurrency);
      }
      
      if (!mounted) return;
      final isWide = MediaQuery.of(context).size.width >= 600.0;
      
      final result = isWide 
          ? await _openRightOverlay(page)
          : (mounted ? await Navigator.of(context).push(MaterialPageRoute(builder: (c) => page)) : null);
      
      // Reload viewed IDs after returning from detail page
      if (mounted) {
        final updatedIds = await ProductViewHistoryService.getRecentlyViewedIds();
        setState(() {
          _recentlyViewedIds = updatedIds;
        });
        debugPrint('🟢 [Grid] Reloaded after detail page: ${_recentlyViewedIds.length} viewed products');
        
        // If item was deleted, refresh the list
        if (result == true) {
          debugPrint('🔄 Item was deleted, refreshing list...');
          if (isGig) {
            _loadGigs();
          } else if (isService) {
            _loadServices();
          } else {
            _refreshProducts();
          }
        }
      }
    },
  );
}

void _applyMomentum() {
  if (velocity.distance < 1) return;

  Future.delayed(const Duration(milliseconds: 16), () {
    if (!isDraggingGrid && mounted) {
      final displayProducts = _getFilteredProducts();
      
      // No momentum for single product
      if (displayProducts.length <= 1) return;
      
      final cellSize = _getCardCellSize(MediaQuery.of(context).size.width);
      const gap = _cardGap;
      
      // Calculate grid dimensions
      int gridSize = (math.sqrt(displayProducts.length.toDouble()).ceil()).toInt();
      if (gridSize < 1) gridSize = 1;
      
      final totalGridWidth = gridSize * cellSize + (gridSize - 1) * gap;
      final totalGridHeight = gridSize * cellSize + (gridSize - 1) * gap;
      
      // Allow dragging with ~1 cell height/width of empty space around products
      final paddingZone = cellSize;
      final maxDragX = (totalGridWidth + paddingZone * 2) / 2;
      final maxDragY = (totalGridHeight + paddingZone * 2) / 2;
      
      setState(() {
        gridOffset += velocity;
        velocity *= 0.95;
        
        // Clamp offset to boundaries
        gridOffset = Offset(
          gridOffset.dx.clamp(-maxDragX, maxDragX),
          gridOffset.dy.clamp(-maxDragY, maxDragY),
        );
      });
      _applyMomentum();
    }
  });
}

Widget _buildListMode() {
  final products = _getFilteredProducts();
  
  // Calculate top padding based on whether categories are expanded (same as scroll mode)
  final isMobile = MediaQuery.of(context).size.shortestSide < 600.0;
  final safeTop = MediaQuery.of(context).padding.top;
  final searchBarTop = isMobile ? safeTop + 2.0 : 12.0;
  const searchBarHeight = 42.0;
  final categoriesExtra = _extraBarsHeight(isMobile);
  const spacingBelowSearchBar = 8.0;
  final topPadding = searchBarTop + searchBarHeight + categoriesExtra + spacingBelowSearchBar;
  
  final isLoading = isLoadingProducts || (selectedCategoryType == 'services' && isLoadingServices) || (selectedCategoryType == 'gigs' && isLoadingGigs);
  
  return Container(
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
    child: isLoading
      ? ShimmerScope(
          child: ShimmerLoading(
            child: ListView(
              padding: EdgeInsets.only(top: topPadding, bottom: 100, left: 16, right: 16),
              children: List.generate(8, (_) => const GhostListCard()),
            ),
          ),
        )
      : RefreshIndicator(
      onRefresh: _refreshProducts,
      color: Colors.green,
      backgroundColor: Colors.grey[900],
      child: ListView.builder(
        padding: EdgeInsets.only(top: topPadding, bottom: 100, left: 16, right: 16),
        itemCount: products.length,
        itemBuilder: (context, index) {
          final product = products[index];
          final productId = product['id'] as String? ?? '';
          final isViewed = _recentlyViewedIds.contains(productId);
          
          return _buildListCard(product, isViewed);
        },
      ),
    ),
  );
}

Widget _buildListCard(Map<String, dynamic> product, bool isViewed) {
  final title = product['title'] as String? ?? 'Untitled';
  final priceValue = product['price'];
  final isNegotiable = product['price_negotiable'] == true || 
                       product['priceNegotiable'] == true || 
                       product['negotiable'] == true ||
                       priceValue == 'negotiable' ||
                       priceValue == null ||
                       (priceValue is num && priceValue == 0);
  final price = (priceValue is num) ? priceValue : 0;
  final currency = product['currency'] as String? ?? 'RON';
  final imageUrl = ImageHelper.getProductCardImage(product);
  final productId = product['id'] as String? ?? '';
  final isGig = product['type'] == 'gig' || selectedCategoryType == 'gigs';
  final isService = selectedCategoryType == 'services' && !isGig;
  
  return GestureDetector(
    onTap: () async {
      if (productId.isNotEmpty) {
        await ProductViewHistoryService.markAsViewed(productId);
        final updatedIds = await ProductViewHistoryService.getRecentlyViewedIds();
        setState(() {
          _recentlyViewedIds = updatedIds;
        });
      }
      
      final productWithCurrency = {...product, 'currency': product['currency'] ?? 'RON'};
      
      final Widget page;
      if (isGig) {
        page = GigDetailPage(gig: productWithCurrency);
      } else if (isService) {
        page = ServiceDetailPage(service: productWithCurrency);
      } else {
        page = ProductDetailPage(product: productWithCurrency);
      }
      
      if (!mounted) return;
      final isWide = MediaQuery.of(context).size.width >= 600.0;
      
      if (!mounted) return;
      final result = isWide 
          ? await _openRightOverlay(page)
          : (mounted ? await Navigator.of(context).push(MaterialPageRoute(builder: (c) => page)) : null);
      
      if (mounted) {
        final updatedIds = await ProductViewHistoryService.getRecentlyViewedIds();
        setState(() {
          _recentlyViewedIds = updatedIds;
        });
        
        if (result == true) {
          if (isGig) {
            _loadGigs();
          } else if (isService) {
            _loadServices();
          } else {
            _refreshProducts();
          }
        }
      }
    },
    child: Stack(
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          height: 80,
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(24),
          ),
      child: Row(
        children: [
          // Image
          ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              bottomLeft: Radius.circular(24),
            ),
            child: Container(
              width: 80,
              height: 80,
              color: Colors.grey[800],
              child: imageUrl.isNotEmpty
                  ? ImageLoadingService.cachedImage(imageUrl, fit: BoxFit.cover)
                  : const Icon(Icons.image, size: 32, color: Colors.grey),
            ),
          ),
          // Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isNegotiable ? I18n.t('negotiable') : '${price.toStringAsFixed(0)} $currency',
                    style: const TextStyle(
                      color: Colors.green,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
        ),
        // Bottom fade glow inside the card
        if (isViewed)
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Container(
              height: 30,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    Colors.green.withValues(alpha: 0.12),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
        // Favorite button centered right
        Positioned(
          right: 8,
          top: 0,
          bottom: 12,
          child: Center(
            child: GestureDetector(
              onTap: () async {
                final user = SupabaseService.instance.currentUser;
                if (user == null) return;
                
                final isFavorited = favoritedProductIds.contains(productId);
                setState(() {
                  if (isFavorited) {
                    favoritedProductIds.remove(productId);
                  } else {
                    favoritedProductIds.add(productId);
                  }
                });
                await SupabaseService.instance.users
                    .update({
                  'favorites': favoritedProductIds.toList(),
                })
                    .eq('id', user.id);
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
                      favoritedProductIds.contains(productId)
                          ? Colors.green
                          : Colors.white,
                      BlendMode.srcIn,
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
}

Widget _buildClassicMode() {
return Container(
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
child: isLoadingProducts || (selectedCategoryType == 'services' && isLoadingServices) || (selectedCategoryType == 'gigs' && isLoadingGigs)
    ? Builder(
        builder: (context) {
          final isMobile = MediaQuery.of(context).size.shortestSide < 600.0;
          final safeTop = MediaQuery.of(context).padding.top;
          final searchBarTop = isMobile ? safeTop + 2.0 : 12.0;
          const searchBarHeight = 42.0;
          final categoriesExtra = _extraBarsHeight(isMobile);
          const spacingBelowSearchBar = 8.0;
          final topPadding = searchBarTop + searchBarHeight + categoriesExtra + spacingBelowSearchBar;
          final cols = _columnsForWidth(MediaQuery.of(context).size.width, horizontalPadding: 32.0);

          return ShimmerScope(
            child: ShimmerLoading(
              child: ListView(
                padding: EdgeInsets.only(
                  top: topPadding,
                  left: 16,
                  right: 16,
                  bottom: 100,
                ),
                children: [
                  GridView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      childAspectRatio: 0.75,
                      crossAxisSpacing: _cardGap,
                      mainAxisSpacing: _cardGap,
                    ),
                    itemCount: cols * 3,
                    itemBuilder: (context, index) => const GhostProductCard(),
                  ),
                ],
              ),
            ),
          );
        },
      )
    : _isCurrentListEmpty()
        ? RefreshIndicator(
            onRefresh: _refreshProducts,
            color: Colors.green,
            backgroundColor: Colors.grey[900],
            child: LayoutBuilder(
              builder: (context, constraints) => ListView(
              children: [
                SizedBox(
                  height: constraints.maxHeight,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SvgPicture.asset(
                          selectedCategoryType == 'services' ? 'assets/icons/servicies.svg' : 
                          selectedCategoryType == 'gigs' ? 'assets/icons/work.svg' :
                          'assets/icons/products.svg', 
                          width: 64, 
                          height: 64,
                          colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          selectedCategoryType == 'services' 
                            ? (_selectedCityFilter != 'all' 
                                ? '${I18n.t('no_services_yet')} ${I18n.t('in_city')} $_selectedCityFilter'
                                : I18n.t('no_services_yet')) :
                          selectedCategoryType == 'gigs' 
                            ? (_selectedCityFilter != 'all'
                                ? '${I18n.t('no_work_posts_yet')} ${I18n.t('in_city')} $_selectedCityFilter'
                                : I18n.t('no_work_posts_yet')) :
                          I18n.t('no_products_yet'), 
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 16, color: Colors.grey)
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          )
        : Builder(
            builder: (context) {
              final displayProducts = _getFilteredProducts();
              
              debugPrint('🚨 [CRITICAL] About to render GridView');
              debugPrint('   displayProducts.length: ${displayProducts.length}');
              debugPrint('   selectedCategoryType: $selectedCategoryType');
              debugPrint('   firebaseProducts.length: ${firebaseProducts.length}');
              debugPrint('   firebaseServices.length: ${firebaseServices.length}');
              debugPrint('   firebaseGigs.length: ${firebaseGigs.length}');
              debugPrint('   isLoadingProducts: $isLoadingProducts');
              debugPrint('   isLoadingServices: $isLoadingServices');
              debugPrint('   isLoadingGigs: $isLoadingGigs');
              
              if (displayProducts.isEmpty && (searchQuery.isNotEmpty || selectedCategory != 'all')) {
                debugPrint('🚨 [CRITICAL] Showing EMPTY STATE (no results)');
                return RefreshIndicator(
                  onRefresh: _refreshProducts,
                  color: Colors.green,
                  backgroundColor: Colors.grey[900],
                  child: LayoutBuilder(
                    builder: (context, constraints) => ListView(
                    children: [
                      SizedBox(
                        height: constraints.maxHeight,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              SvgPicture.asset('assets/icons/products.svg', width: 64, height: 64, colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn)),
                              const SizedBox(height: 16),
                              Text(I18n.t('no_products_found'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: Colors.grey)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  ),
                );
              }

              debugPrint('🚨 [CRITICAL] Rendering GridView with ${displayProducts.length} items');

              final isMobile = MediaQuery.of(context).size.shortestSide < 600.0;
              
              // Calculate consistent top spacing based on search bar position
              // Match list mode: searchBarTop + searchBarHeight + categories + spacing
              final safeTop = MediaQuery.of(context).padding.top;
              final searchBarTop = isMobile ? safeTop + 2.0 : 12.0;
              const searchBarHeight = 42.0;
              final categoriesExtra = _extraBarsHeight(isMobile);
              const spacingBelowSearchBar = 8.0;
              final topPadding = searchBarTop + searchBarHeight + categoriesExtra + spacingBelowSearchBar;

              return RefreshIndicator(
                onRefresh: _refreshProducts,
                color: Colors.green,
                backgroundColor: Colors.grey[900],
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.only(
                    top: topPadding,
                    left: 16,
                    right: 16,
                    bottom: 100,
                  ),
                  children: [
                    Builder(builder: (context) {
                      final cols = _columnsForWidth(MediaQuery.of(context).size.width, horizontalPadding: 32.0);
                      debugPrint('🎯 GridView rendering: ${displayProducts.length} items | categoryType: $selectedCategoryType');
                      return GridView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          childAspectRatio: 0.75,
                          crossAxisSpacing: _cardGap,
                          mainAxisSpacing: _cardGap,
                        ),
                        itemCount: displayProducts.length,
                        itemBuilder: (context, index) {
                          final product = displayProducts[index];
                          return _buildProductCard(product);
                        },
                      );
                    }),
                  ],
                ),
              );
            },
          ),
);
}

Widget _buildProductCard(Map<String, dynamic> product) {
  // Debug: Log what type of item we're rendering
  final isGig = product['type'] == 'gig' || selectedCategoryType == 'gigs';
  final isService = selectedCategoryType == 'services' && !isGig;
  debugPrint('🎴 Building card: ${product['title']} | isService: $isService | isGig: $isGig | categoryType: $selectedCategoryType');
  
  // Get title with language matching logic (same as product detail)
  final currentLang = I18n.current.name.toLowerCase();
  
  // Handle both product fields (detected_language) and service fields (detectedLanguage)
  final detectedLang = (product['detectedLanguage'] as String? ?? 
                        product['detected_language'] as String? ?? 
                        'en').toLowerCase();
  
  final String title;
  if (currentLang == detectedLang) {
    // Viewer's language matches product's language, show original title
    title = product['title'] as String? ?? 'Untitled';
  } else {
    // Languages don't match, fallback to English title
    // Handle both product fields (title_english) and service fields (titleEnglish)
    title = product['titleEnglish'] as String? ?? 
            product['title_english'] as String? ?? 
            product['title'] as String? ?? 
            'Untitled';
  }
  
  // Check for both 'imageUrl' (first image) and 'imageUrls' (array of images)
  // Prefer hover thumbnail for faster loading
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
  
  // Check if product was viewed recently (synchronously from cache)
  final wasViewed = _recentlyViewedIds.contains(productId);
  
  if (wasViewed) {
    debugPrint('🟢 Product $productId was viewed recently - showing green glow');
  }

  return GestureDetector(
    onTap: () async {
      // Mark as viewed when tapped
      if (productId.isNotEmpty) {
        debugPrint('🟢 Marking product $productId as viewed. Current count: ${_recentlyViewedIds.length}');
        await ProductViewHistoryService.markAsViewed(productId);
        
        // Reload the viewed IDs to ensure we have the latest
        final updatedIds = await ProductViewHistoryService.getRecentlyViewedIds();
        setState(() {
          _recentlyViewedIds = updatedIds;
        });
        debugPrint('🟢 After marking: ${_recentlyViewedIds.length} viewed products, contains $productId: ${_recentlyViewedIds.contains(productId)}');
      }
      
      final productWithCurrency = {...product, 'currency': product['currency'] ?? 'RON'}; // Keep original currency
      
      // Check if this is a gig, service, or product
      final isGig = product['type'] == 'gig' || selectedCategoryType == 'gigs';
      final isService = selectedCategoryType == 'services' && !isGig;
      
      final Widget page;
      if (isGig) {
        page = GigDetailPage(gig: productWithCurrency);
      } else if (isService) {
        page = ServiceDetailPage(service: productWithCurrency);
      } else {
        page = ProductDetailPage(product: productWithCurrency);
      }
      
      if (!mounted) return;
      final isWide = MediaQuery.of(context).size.width >= 600.0;
      
      final result = isWide 
          ? await _openRightOverlay(page)
          : (mounted ? await Navigator.of(context).push(MaterialPageRoute(builder: (c) => page)) : null);
      
      // Reload viewed IDs after returning from detail page
      if (mounted) {
        final updatedIds = await ProductViewHistoryService.getRecentlyViewedIds();
        setState(() {
          _recentlyViewedIds = updatedIds;
        });
        debugPrint('🟢 Reloaded after detail page: ${_recentlyViewedIds.length} viewed products');
        
        // If item was deleted, refresh the list
        if (result == true) {
          debugPrint('🔄 Item was deleted, refreshing list...');
          if (isGig) {
            _loadGigs();
          } else if (isService) {
            _loadServices();
          } else {
            _refreshProducts();
          }
        }
      }
    },
    child: Container(
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
                                        Text(I18n.t('image_not_available'), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                      ],
                                    ),
                                  );
                                },
                              )
                            : Center(
                                child: SvgPicture.asset(
                                  'assets/icons/products.svg',
                                  width: 48,
                                  height: 48,
                                  colorFilter: ColorFilter.mode(Colors.grey.shade400, BlendMode.srcIn),
                                ),
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
                                  text: _getProductPrice(product),
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
                    // Status badge for analyzing/pending_review products
                    if (product['status'] == 'analyzing' || product['status'] == 'pending_review')
                      Positioned(
                        top: 40,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: product['status'] == 'analyzing' 
                                  ? Colors.orange.withValues(alpha: 0.9)
                                  : Colors.blue.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.3),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              product['status'] == 'analyzing' ? '🔄 Analyzing...' : '📝 Pending Info',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      ),
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
          // Background circle for favorite button (20% bigger, same color as title background)
          Positioned(
            bottom: 0,
            right: 0,
            child: FractionalTranslation(
              translation: const Offset(0, -0.15),
              child: Transform.translate(
                offset: const Offset(-5, -20), // Move circle up (changed from -18 to -20)
                child: Container(
                  width: 38, // 32px * 1.1875 = 38px (about 19% bigger, reduced from 25%)
                  height: 38,
                  decoration: const BoxDecoration(
                    color: Color(0xFF1A1A1A), // Same as title background
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
          // Favorite button overlaid on top - positioned at the boundary between image and title
          Positioned(
            bottom: 0, // Position at the bottom of the card
            right: 0,
            child: FractionalTranslation(
              translation: const Offset(0, -0.15), // Move up by 15% of card height to align with 85/15 split
              child: Transform.translate(
                offset: const Offset(-8, -24), // 8px from right edge, 24px up
                child: GestureDetector(
                  onTap: () async {
                    final productId = product['id']?.toString() ?? '';
                    if (productId.isNotEmpty) {
                      final user = SupabaseService.instance.currentUser;
                      if (user != null) {
                        final isFavorited = favoritedProductIds.contains(productId);
                        setState(() {
                          if (isFavorited) {
                            favoritedProductIds.remove(productId);
                          } else {
                            favoritedProductIds.add(productId);
                          }
                        });
                        await SupabaseService.instance.users
                            .update({
                          'favorites': favoritedProductIds.toList(),
                        })
                            .eq('id', user.id);
                      }
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
                          favoritedProductIds.contains(product['id']?.toString() ?? '')
                              ? Colors.green
                              : Colors.white,
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
    ),
  );
}

  // Helper to get price display for products/services (handles tiered pricing)
  String _getProductPrice(Map<String, dynamic> product) {
    // Check if price is negotiable (on-site services)
    final priceNegotiable = product['priceNegotiable'] as bool? ?? product['price_negotiable'] as bool? ?? product['negotiable'] as bool? ?? false;
    if (priceNegotiable) {
      return I18n.t('negotiable');
    }
    
    final pricingType = product['pricingType'] as String? ?? product['pricing_type'] as String?;
    final currency = product['currency'] ?? 'RON'; // Keep original currency, don't override
    
    if (pricingType == 'tiered') {
      final tiers = (product['tiers'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (tiers.isNotEmpty) {
        final prices = tiers.map((t) {
          final price = t['price'];
          if (price is num) return price.toDouble();
          if (price is String) return double.tryParse(price) ?? 0.0;
          return 0.0;
        }).toList();
        final minPrice = prices.reduce((a, b) => a < b ? a : b);
        final maxPrice = prices.reduce((a, b) => a > b ? a : b);
        if (minPrice == maxPrice) {
          return '${minPrice.toStringAsFixed(0)} $currency';
        }
        return '${minPrice.toStringAsFixed(0)}-${maxPrice.toStringAsFixed(0)} $currency';
      }
    }
    
    // Single pricing or fallback
    if (product['price'] is num) {
      if ((product['price'] as num) == 0) return I18n.t('negotiable');
      return '${(product['price'] as num).toStringAsFixed(0)} $currency';
    } else if (product['price'] is String) {
      final priceValue = double.tryParse(product['price'] as String);
      if (priceValue != null) {
        if (priceValue == 0) return I18n.t('negotiable');
        return '${priceValue.toStringAsFixed(0)} $currency';
      }
    }
    return product['price']?.toString() ?? I18n.t('negotiable');
  }

  // Helper to perform the same action as tapping a draggable orb. This is
  // used by the desktop fixed row so we don't duplicate logic.
  void _performOrbAction(String element) {
    if (element == 'home') {
      // Open sort/filter options — city row only for gigs
      final isWide = MediaQuery.of(context).size.width >= 600.0;
      final bool showCityFilter = selectedCategoryType == 'gigs';
      
      if (isWide) {
        _openRightOverlay(SortOptionsPage(
          initial: sortOption,
          onSelected: (value) {
            setState(() => sortOption = value);
            _saveUserPreferences();
            Navigator.of(context).pop();
          },
          selectedCity: showCityFilter ? _selectedCityFilter : null,
          availableCities: showCityFilter ? _availableCities : const [],
          userCity: showCityFilter ? _userCity : null,
          onCitySelected: showCityFilter
              ? (city) { setState(() => _selectedCityFilter = city); }
              : null,
        ));
      } else {
        var localCity = _selectedCityFilter;
        showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          builder: (context) => StatefulBuilder(
            builder: (context, setSheetState) => SortOptionsPage(
              initial: sortOption,
              onSelected: (value) {
                setState(() => sortOption = value);
                _saveUserPreferences();
                Navigator.of(context).pop();
              },
              selectedCity: showCityFilter ? localCity : null,
              availableCities: showCityFilter ? _availableCities : const [],
              userCity: showCityFilter ? _userCity : null,
              onCitySelected: showCityFilter
                  ? (city) {
                      localCity = city;
                      setState(() => _selectedCityFilter = city);
                      setSheetState(() {});
                    }
                  : null,
            ),
          ),
        );
      }
    } else if (element == 'profile') {
      final page = ProfilePage(
        showServices: selectedCategoryType == 'services',
        onViewModeChanged: (newMode) {
          // Update home page immediately when profile changes view mode
          debugPrint('🔵 HOME: Received view mode change from Profile: $newMode');
          if (mounted) {
            setState(() {
              viewMode = newMode;
            });
            // Save in background
            _saveUserPreferences();
          }
        },
        onBookingsHomepageChanged: (value) {
          // Update home page immediately when bookings homepage setting changes
          debugPrint('🔵 HOME: Received bookings homepage change from Profile: $value');
          if (mounted) {
            setState(() {
              _showBookingsHomepage = value;
            });
          }
        },
      );
      final isWide = MediaQuery.of(context).size.width >= 600.0;
      if (isWide) {
        _openRightOverlay(page);
      } else {
        Navigator.push(context, MaterialPageRoute(builder: (c) => page));
      }
    } else if (element == 'add') {
      final isWide = MediaQuery.of(context).size.width >= 600.0;
      
      // Show modal with all 3 options
      showModalBottomSheet(
        context: context,
        backgroundColor: const Color(0xFF1A1A1A),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (context) => Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  const page = AddProductModal();
                  if (isWide) {
                    _openRightOverlay(page);
                  } else {
                    Navigator.push(context, MaterialPageRoute(builder: (c) => page));
                  }
                },
                child: _buildAddOption(
                  I18n.t('sell_a_product'),
                  I18n.t('list_item_for_sale'),
                  SvgPicture.asset('assets/icons/products.svg', width: 20, height: 20, colorFilter: const ColorFilter.mode(Colors.green, BlendMode.srcIn)),
                ),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  const page = AddServicePage();
                  if (isWide) {
                    _openRightOverlay(page);
                  } else {
                    Navigator.push(context, MaterialPageRoute(builder: (c) => page));
                  }
                },
                child: _buildAddOption(
                  I18n.t('provide_a_service'),
                  I18n.t('offer_skills_expertise'),
                  SvgPicture.asset('assets/icons/servicies.svg', width: 20, height: 20, colorFilter: const ColorFilter.mode(Colors.green, BlendMode.srcIn)),
                ),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  const page = AddGigPage();
                  if (isWide) {
                    _openRightOverlay(page);
                  } else {
                    Navigator.push(context, MaterialPageRoute(builder: (c) => page));
                  }
                },
                child: _buildAddOption(
                  I18n.t('request_help'),
                  I18n.t('get_help_with_tasks'),
                  SvgPicture.asset('assets/icons/work.svg', width: 20, height: 20, colorFilter: const ColorFilter.mode(Colors.green, BlendMode.srcIn)),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      );
    } else if (element == 'chat') {
      final isWide = MediaQuery.of(context).size.width >= 600.0;
      if (isWide) {
        final page = Scaffold(
          backgroundColor: Colors.grey[900],
          body: const ConversationsModal(),
        );
        _openRightOverlay(page);
      } else {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const ConversationsModal(),
          ),
        );
      }
    } else if (element == 'favorites') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const FavoritesPage()),
      );
    }
  }

  Widget _buildAddOption(String title, String subtitle, Widget iconWidget) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(child: iconWidget),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.arrow_forward_ios, color: Colors.grey[600], size: 14),
        ],
      ),
    );
  }

Future<void> _loadServices() async {
  try {
    setState(() => isLoadingServices = true);
    debugPrint('📥 Loading services from Supabase...');
    
    // First, check all services to see what's in the database
    final allServicesResponse = await SupabaseService.instance.services
        .select('id, title, status, review_status');
    
    final allServices = allServicesResponse as List<dynamic>;
    debugPrint('📊 Total services in database: ${allServices.length}');
    
    // Count by status
    final statusCounts = <String, int>{};
    for (final service in allServices) {
      final status = service['status']?.toString() ?? 'unknown';
      statusCounts[status] = (statusCounts[status] ?? 0) + 1;
    }
    debugPrint('📊 Services by status: $statusCounts');
    
    // Load services - include 'analyzing' status for testing
    final servicesResponse = await SupabaseService.instance.services
        .select()
        .eq('status', 'active') // Only show active services (fee paid for offline services)
        .limit(20);
    
    final services = (servicesResponse as List<dynamic>).map((service) {
      return Map<String, dynamic>.from(service);
    }).toList();
    
    debugPrint('✅ Services loaded (active + analyzing): ${services.length}');
    if (services.isNotEmpty) {
      debugPrint('📝 First service: ${services[0]['title']} (${services[0]['id']}) - status: ${services[0]['status']}');
      debugPrint('📝 First service image_url: ${services[0]['image_url']}');
      debugPrint('📝 First service image_urls: ${services[0]['image_urls']}');
    }
    
    // Extract unique categories from services
    final categories = <String>{'all'};
    for (final service in services) {
      final category = service['category']?.toString().trim();
      if (category != null && category.isNotEmpty) {
        categories.add(category.toLowerCase());
      }
    }
    
    if (mounted) {
      // Extract raw cities from onsite services + gigs, then deduplicate.
      // Seed with user's account city so its spelling (with diacritics) wins.
      final rawCities = <String>[];
      if (_userCity != null && _userCity!.isNotEmpty) {
        rawCities.add(_userCity!);
      }
      for (final service in services) {
        if (service['is_remote'] == false) {
          final city = service['service_city']?.toString().trim();
          if (city != null && city.isNotEmpty) {
            rawCities.add(city);
          }
        }
      }
      for (final gig in firebaseGigs) {
        final city = gig['city']?.toString().trim();
        if (city != null && city.isNotEmpty) {
          rawCities.add(city);
        }
      }

      setState(() {
        firebaseServices = services;
        _serviceCategories = categories;
        _availableCities = deduplicateCities(rawCities);
        isLoadingServices = false;
      });
      debugPrint('✅ Loaded ${services.length} services with ${categories.length} categories');
      debugPrint('📂 Categories: $categories');
      debugPrint('🏙️ Available cities: $_availableCities');
    }
  } catch (e) {
    debugPrint('❌ Error loading services: $e');
    debugPrint('❌ Stack trace: ${StackTrace.current}');
    if (mounted) {
      setState(() {
        isLoadingServices = false;
      });
    }
  }
}

Future<void> _loadGigs() async {
  try {
    setState(() => isLoadingGigs = true);
    debugPrint('📥 Loading gigs from Supabase...');
    
    // Load all gigs without filters (like products)
    final gigsResponse = await SupabaseService.instance.gigs
        .select()
        .limit(20);
    
    // Filter active gigs on client side
    final gigs = (gigsResponse as List<dynamic>)
        .map((gig) {
          return Map<String, dynamic>.from(gig);
        })
        .where((gig) => gig['status'] == 'active')
        .toList();
    
    if (mounted) {
      // Extract raw cities from gigs + onsite services, then deduplicate.
      // Seed with user's account city so its spelling (with diacritics) wins.
      final rawCities = <String>[];
      if (_userCity != null && _userCity!.isNotEmpty) {
        rawCities.add(_userCity!);
      }
      for (final gig in gigs) {
        final city = gig['city']?.toString().trim();
        if (city != null && city.isNotEmpty) {
          rawCities.add(city);
        }
      }
      for (final service in firebaseServices) {
        if (service['is_remote'] == false) {
          final city = service['service_city']?.toString().trim();
          if (city != null && city.isNotEmpty) {
            rawCities.add(city);
          }
        }
      }

      setState(() {
        firebaseGigs = gigs;
        _availableCities = deduplicateCities(rawCities);
        isLoadingGigs = false;
      });
      debugPrint('✅ Loaded ${gigs.length} active gigs');
      debugPrint('🏙️ Available cities: $_availableCities');
    }
  } catch (e) {
    debugPrint('❌ Error loading gigs: $e');
    if (mounted) {
      setState(() {
        isLoadingGigs = false;
      });
    }
  }
}

List<Map<String, dynamic>> _getFilteredServices() {
  debugPrint('🔍 _getFilteredServices called');
  debugPrint('🔍 firebaseServices.length: ${firebaseServices.length}');
  debugPrint('🔍 searchQuery: "$searchQuery"');
  debugPrint('🔍 selectedServiceCategory: "$selectedServiceCategory"');
  
  var services = firebaseServices;

  // Filter by search query
  if (searchQuery.isNotEmpty) {
    final query = searchQuery.toLowerCase();
    services = services.where((service) {
      final title = service['title']?.toString().toLowerCase() ?? '';
      final description = service['description']?.toString().toLowerCase() ?? '';
      final city = service['serviceCity']?.toString().toLowerCase() ?? '';
      final category = service['category']?.toString().toLowerCase() ?? '';
      return title.contains(query) || 
             description.contains(query) || 
             city.contains(query) ||
             category.contains(query);
    }).toList();
    debugPrint('🔍 After search filter: ${services.length} services');
  }

  // Filter by selected category
  if (selectedServiceCategory != 'all') {
    services = services.where((service) {
      final category = service['category']?.toString().toLowerCase() ?? '';
      return category == selectedServiceCategory;
    }).toList();
    debugPrint('🔍 After category filter: ${services.length} services');
  }

  // Filter by service type (remote / onsite)
  if (_selectedServiceType == 'remote') {
    services = services.where((s) => s['is_remote'] == true).toList();
  } else if (_selectedServiceType == 'onsite') {
    services = services.where((s) => s['is_remote'] != true).toList();
  }

  // Filter onsite services by city (remote services always pass through)
  if (_selectedCityFilter != 'all') {
    services = services.where((service) {
      final isRemote = service['is_remote'] == true;
      if (isRemote) return true; // Remote services are not city-restricted
      final serviceCity = service['service_city']?.toString().trim() ?? '';
      return isSameCity(serviceCity, _selectedCityFilter);
    }).toList();
    debugPrint('🔍 After city filter ($_selectedCityFilter): ${services.length} services');
  }

  debugPrint('🔍 Returning ${services.length} filtered services');
  return services;
}

  // ...search orb removed; search bar is always visible and centered instead.

Widget _buildSearchBarOverlay(Size screenSize, {required bool isDesktopOverride}) {
  final isDesktop = isDesktopOverride;
  final double safeTop = MediaQuery.of(context).padding.top;
  final double barTop = isDesktop ? 12.0 : safeTop + 2.0;

  const double searchBarSize = 42.0;
  const double rightPadding = 16.0;

  final bool isExpanded = searchFocused || searchQuery.isNotEmpty;

  final double expandedWidth;
  if (!isDesktop) {
    expandedWidth = screenSize.width - 32.0;
  } else {
    expandedWidth = math.min(480.0, screenSize.width * 0.6);
  }

  final double barWidth = isExpanded ? expandedWidth : searchBarSize;

  return Positioned(
    top: barTop,
    right: rightPadding,
    height: searchBarSize,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (!_searchFocusNode.hasFocus) {
          _searchFocusNode.requestFocus();
          setState(() => searchFocused = true);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOutCubic,
        width: barWidth,
        height: searchBarSize,
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: const Color(0xFF242424),
          borderRadius: BorderRadius.circular(searchBarSize / 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            // Centered icon for collapsed state
            if (!isExpanded)
              const Center(
                child: Icon(
                  Icons.search,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            // Expanded content
            if (isExpanded)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: expandedWidth,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 32,
                      height: 32,
                      child: Center(
                        child: Icon(
                          Icons.search,
                          color: Colors.green,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: isExpanded
                        ? TextField(
                            controller: _searchController,
                            focusNode: _searchFocusNode,
                            autofocus: false,
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: _getSearchHint(),
                              hintStyle: TextStyle(color: Colors.grey[600]),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            onChanged: (value) => setState(() => searchQuery = value),
                            onTap: () {
                              setState(() => searchFocused = true);
                            },
                            onSubmitted: (value) async {
                              if (value.trim().isNotEmpty) {
                                await _addToSearchHistory(value.trim());
                                setState(() => searchPerformed = true);
                                await _refreshProducts();
                              }
                            },
                          )
                        : const SizedBox.shrink(),
                    ),
                    if (isExpanded && selectedCategoryType == 'services' && _serviceCategories.length > 1)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          setState(() => searchFocused = true);
                          _showServiceCategoriesModal();
                        },
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: (selectedServiceCategory != 'all' || _selectedServiceType != 'all')
                                ? Colors.green.withValues(alpha: 0.3)
                                : Colors.grey[850],
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: SvgPicture.asset(
                              'assets/icons/category.svg',
                              width: 16,
                              height: 16,
                              colorFilter: ColorFilter.mode(
                                (selectedServiceCategory != 'all' || _selectedServiceType != 'all')
                                    ? Colors.green
                                    : Colors.white,
                                BlendMode.srcIn,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (isExpanded && searchQuery.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.only(
                          left: (selectedCategoryType == 'services' && _serviceCategories.length > 1) ? 6.0 : 0.0,
                        ),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () async {
                            _searchController.clear();
                            setState(() {
                              searchQuery = '';
                              searchPerformed = false;
                              showSearchHistory = false;
                              searchFocused = false;
                            });
                            _searchFocusNode.unfocus();
                            await _refreshProducts();
                          },
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Colors.grey[850],
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close, color: Colors.white, size: 16),
                          ),
                        ),
                      )
                    else if (isExpanded && selectedCategoryType != 'services' && searchHistory.isNotEmpty)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          setState(() {
                            showSearchHistory = !showSearchHistory;
                            searchFocused = true;
                          });
                        },
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: showSearchHistory ? Colors.green.withValues(alpha: 0.3) : Colors.grey[850],
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: SvgPicture.asset(
                              'assets/icons/recent.svg',
                              width: 16,
                              height: 16,
                              colorFilter: ColorFilter.mode(
                                showSearchHistory ? Colors.green : Colors.white,
                                BlendMode.srcIn,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

String _getSearchHint() {
  switch (selectedCategoryType) {
    case 'products':
      return I18n.t('search_products_hint');
    case 'services':
      return I18n.t('search_services_hint');
    case 'gigs':
      return I18n.t('search_gigs_hint');
    default:
      return I18n.t('search_products_hint');
  }
}

Widget _buildCategoryWheel(Size screenSize, {required bool isDesktopOverride}) {
  final double safeTop = MediaQuery.of(context).padding.top;
  final double barTop = isDesktopOverride ? 12.0 : safeTop + 2.0;

  final categories = [
    {'label': I18n.t('products'), 'icon': 'assets/icons/products.svg', 'type': 'products'},
    {'label': I18n.t('services'), 'icon': 'assets/icons/servicies.svg', 'type': 'services'},
    {'label': I18n.t('gigs'), 'icon': 'assets/icons/work.svg', 'type': 'gigs'},
  ];
  final int catCount = categories.length;

  // Available width = screen minus search circle minus right padding and gap
  const double searchSize = 42.0;
  const double rightPad = 16.0;
  const double gap = 12.0;
  final double availableWidth = screenSize.width - searchSize - rightPad - gap;

  // Large item count for infinite loop illusion
  const int loopMultiplier = 1000;
  const int totalItems = loopMultiplier * 3; // 3 categories
  final int initialItem = loopMultiplier ~/ 2 * catCount; // start in the middle

  return Positioned(
    top: barTop + 2,
    left: 0,
    width: availableWidth,
    height: 38,
    child: ShaderMask(
      shaderCallback: (Rect bounds) {
        return const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.transparent,
          ],
          stops: [0.0, 0.08, 0.92, 1.0],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: PageView.builder(
      controller: _categoryWheelController,
      itemCount: totalItems,
      onPageChanged: (index) {
        _selectCategoryByType(categories[index % catCount]['type']!);
      },
      physics: const BouncingScrollPhysics(),
      itemBuilder: (context, index) {
        final cat = categories[index % catCount];

        return AnimatedBuilder(
          animation: _categoryWheelController,
          builder: (context, child) {
            double page = 0;
            try {
              page = _categoryWheelController.page ?? initialItem.toDouble();
            } catch (_) {
              page = initialItem.toDouble();
            }

            final diff = (page - index).abs().clamp(0.0, 1.5);
            final isCenter = diff < 0.5;
            final scale = isCenter ? 1.0 : 0.85;

            return GestureDetector(
              onTap: () {
                // Tapping a side pill animates the wheel to that page
                if (!isCenter) {
                  _categoryWheelController.animateToPage(
                    index,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                }
              },
              child: Center(
              child: Transform.scale(
                  scale: scale,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF242424),
                      borderRadius: BorderRadius.circular(20),
                      border: isCenter ? Border.all(
                        color: Colors.green,
                        width: 1.5,
                      ) : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SvgPicture.asset(
                          cat['icon']!,
                          width: 16,
                          height: 16,
                          colorFilter: ColorFilter.mode(
                            isCenter ? Colors.green : Colors.white70,
                            BlendMode.srcIn,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          cat['label']!,
                          style: TextStyle(
                            color: isCenter ? Colors.green : Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    ),
  )
);
}

// Handle category selection from the wheel
void _selectCategoryByType(String type) {
  setState(() {
    selectedCategoryType = type;
    showCategoryPills = false;

    if (type == 'products') {
      showServices = false;
      showGigsOnly = false;
      _selectedCityFilter = 'all';
    } else if (type == 'services') {
      showServices = true;
      showGigsOnly = false;
      _selectedCityFilter = _userCity ?? 'all';
      _loadServices();
    } else if (type == 'gigs') {
      showServices = true;
      showGigsOnly = true;
      _selectedCityFilter = _userCity ?? 'all';
      _loadGigs();
    }
  });
  // Persist to local storage
  SharedPreferences.getInstance().then((prefs) {
    prefs.setString('selected_category_type', type);
  });
}

Future<void> _loadSavedCategoryType() async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString('selected_category_type');
  if (saved != null && saved != selectedCategoryType && ['products', 'services', 'gigs'].contains(saved)) {
    _selectCategoryByType(saved);
    // Sync the wheel to the saved category
    const types = ['products', 'services', 'gigs'];
    final newIndex = types.indexOf(saved);
    final wheelPage = _categoryWheelController.page?.round() ?? 1500;
    final wheelOffset = wheelPage % types.length;
    final delta = newIndex - wheelOffset;
    _categoryWheelController.jumpToPage(wheelPage + delta);
  }
}

// Recent searches modal shown behind the search bar (fills to bottom).
Widget _buildRecentSearchesModal(Size screenSize, {required bool isDesktopOverride}) {
  // Keep recent searches aligned and the same width as the search bar so
  // it moves together with the homepage area when the left column resizes.
  // On desktop we want the recent list to align closer to the top like the
  // search bar. Use the same desktop offset so they move together.
  final safeTop = MediaQuery.of(context).padding.top;
  final barTop = isDesktopOverride ? 12.0 : safeTop + 8.0;
  final double barWidth;
  final double barLeft;
  if (!isDesktopOverride) {
    const sidePadding = 16.0;
    barWidth = screenSize.width - (sidePadding * 2);
    barLeft = sidePadding;
  } else {
    barWidth = math.min(480.0, screenSize.width * 0.6);
    barLeft = (screenSize.width - barWidth) / 2.0;
  }
  // Align the modal top with the search bar top so the internal padding
  // pushes content to appear below the bar consistently across sizes.
  final modalWidth = barWidth;
  final left = barLeft;
  final top = barTop; // align with search bar top; internal padding moves content down

  return Positioned(
    top: top,
    left: left,
    width: modalWidth,
    child: Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Container(
            height: 180,
            // Add extra top padding so the list items start below the search bar
            padding: const EdgeInsets.only(top: 38),
            decoration: BoxDecoration(
              color: const Color(0xFF1a1a1a),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(28),
                bottomRight: Radius.circular(28),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: searchHistory.length,
              itemBuilder: (context, index) {
                final query = searchHistory[index];
                // Filter to show only matching searches
                if (!query.toLowerCase().contains(searchQuery.toLowerCase())) {
                  return const SizedBox.shrink();
            }
            return GestureDetector(
              onTap: () async {
                _searchController.text = query;
                _searchController.selection = TextSelection.fromPosition(
                  TextPosition(offset: query.length),
                );
                setState(() {
                  searchQuery = query;
                  searchPerformed = true;
                  showSearchHistory = false;
                  searchFocused = false;
                  _searchFocusNode.unfocus();
                });
                await _addToSearchHistory(query);
                await _refreshProducts();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                child: Row(
                  children: [
                    SvgPicture.asset('assets/icons/recent.svg', width: 16, height: 16, colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        query,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        setState(() => searchHistory.removeAt(index));
                        _saveSearchHistory();
                      },
                      child: const Icon(Icons.close, color: Colors.grey, size: 16),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
          ),
        ],
      ),
    ),
  );
}


/// Sort key for a category name. If it starts with a digit, use the second
/// word so "3d modeling" sorts under "m" not "3".
String _categorySortKey(String cat) {
  final words = cat.trim().toLowerCase().split(RegExp(r'[\s_]+'));
  if (words.isNotEmpty && words[0].isNotEmpty && RegExp(r'^\d').hasMatch(words[0])) {
    if (words.length > 1) return words[1];
  }
  return words.isNotEmpty ? words[0] : cat.toLowerCase();
}

void _showServiceCategoriesModal() {
  final rawCategories = _serviceCategories.where((c) => c != 'all').toList();
  rawCategories.sort((a, b) => _categorySortKey(a).compareTo(_categorySortKey(b)));

  // Group categories by their sort letter
  final Map<String, List<String>> grouped = {};
  for (final cat in rawCategories) {
    final letter = _categorySortKey(cat)[0].toUpperCase();
    grouped.putIfAbsent(letter, () => []).add(cat);
  }
  final letters = grouped.keys.toList()..sort();

  var localType = _selectedServiceType;
  var localCategory = selectedServiceCategory;
  String? selectedLetter; // null = show all

  showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) {
        // Categories to show based on selected letter
        final visibleCategories = selectedLetter == null
            ? rawCategories
            : (grouped[selectedLetter] ?? []);

        return Dialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 60),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.65,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                // Row 1: Remote / On-site / All
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      _buildServiceTypeChip(I18n.t('all'), 'all', localType, (v) {
                        setDialogState(() => localType = v);
                        setState(() => _selectedServiceType = v);
                      }),
                      const SizedBox(width: 8),
                      _buildServiceTypeChip('Remote', 'remote', localType, (v) {
                        setDialogState(() => localType = v);
                        setState(() => _selectedServiceType = v);
                      }),
                      const SizedBox(width: 8),
                      _buildServiceTypeChip('On-site', 'onsite', localType, (v) {
                        setDialogState(() => localType = v);
                        setState(() => _selectedServiceType = v);
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Row 2: Letter bar
                SizedBox(
                  height: 32,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: letters.length + 1, // +1 for "All" at start
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        // "All" letter button
                        final isActive = selectedLetter == null;
                        return GestureDetector(
                          onTap: () => setDialogState(() => selectedLetter = null),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: isActive ? Colors.green.withValues(alpha: 0.15) : const Color(0xFF2A2A2A),
                              shape: BoxShape.circle,
                              border: Border.all(color: isActive ? Colors.green : Colors.transparent, width: 1.5),
                            ),
                            child: Center(
                              child: Text('#', style: TextStyle(color: isActive ? Colors.green : Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                            ),
                          ),
                        );
                      }
                      final letter = letters[index - 1];
                      final isActive = selectedLetter == letter;
                      return GestureDetector(
                        onTap: () => setDialogState(() => selectedLetter = letter),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: isActive ? Colors.green.withValues(alpha: 0.15) : const Color(0xFF2A2A2A),
                            shape: BoxShape.circle,
                            border: Border.all(color: isActive ? Colors.green : Colors.transparent, width: 1.5),
                          ),
                          child: Center(
                            child: Text(letter, style: TextStyle(color: isActive ? Colors.green : Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                // Row 3: Category pills
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        // "All categories" pill — only when no letter is selected
                        if (selectedLetter == null)
                          _buildCategoryPillChip(I18n.t('all'), 'all', localCategory, (v) {
                            setDialogState(() => localCategory = v);
                            setState(() => selectedServiceCategory = v);
                            Navigator.pop(context);
                          }),
                        ...visibleCategories.map((cat) {
                          final label = (cat[0].toUpperCase() + cat.substring(1)).replaceAll('_', ' ');
                          return _buildCategoryPillChip(label, cat, localCategory, (v) {
                            setDialogState(() => localCategory = v);
                            setState(() => selectedServiceCategory = v);
                            Navigator.pop(context);
                          });
                        }),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    ),
  );
}

Widget _buildServiceTypeChip(String label, String value, String current, void Function(String) onTap) {
  final isSelected = current == value;
  return GestureDetector(
    onTap: () => onTap(value),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isSelected ? Colors.green.withValues(alpha: 0.15) : const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isSelected ? Colors.green : Colors.transparent, width: 1.5),
      ),
      child: Text(label, style: TextStyle(color: isSelected ? Colors.green : Colors.white, fontSize: 13, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400)),
    ),
  );
}

Widget _buildCategoryPillChip(String label, String value, String current, void Function(String) onTap) {
  final isSelected = current == value;
  return GestureDetector(
    onTap: () => onTap(value),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isSelected ? Colors.green.withValues(alpha: 0.15) : const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isSelected ? Colors.green : Colors.transparent, width: 1.5),
      ),
      child: Text(label, style: TextStyle(color: isSelected ? Colors.green : Colors.white, fontSize: 13, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400)),
    ),
  );
}

Widget _buildServiceCategoriesBar(Size screenSize, {required bool isDesktopOverride}) {
  final isDesktop = isDesktopOverride;
  // Position below the search bar
  final double safeTop = MediaQuery.of(context).padding.top;
  final double barTop = isDesktop ? 72.0 : safeTop + 8.0 + 50.0 + 10.0;

  // Sort categories: 'all' first, then alphabetically
  final sortedCategories = _serviceCategories.toList()..sort((a, b) {
    if (a == 'all') return -1;
    if (b == 'all') return 1;
    return a.compareTo(b);
  });

  return Positioned(
    top: barTop,
    left: 0,
    right: 0,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 8,
        children: sortedCategories.map((category) {
          final isSelected = selectedServiceCategory == category;
          // Capitalize first letter and replace underscores with spaces for display
          final displayName = category == 'all' 
              ? 'Toate' 
              : (category[0].toUpperCase() + category.substring(1)).replaceAll('_', ' ');
          
          return GestureDetector(
            onTap: () {
              setState(() {
                selectedServiceCategory = category;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF242424),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? Colors.green : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Center(
                child: Text(
                  displayName,
                  style: TextStyle(
                    color: isSelected ? Colors.green : Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    ),
  );
}

Widget _buildProfileOrb() {
  return Container(
    width: 56,
    height: 56,
    decoration: BoxDecoration(
      color: const Color(0xFF242424),
      shape: BoxShape.circle,
      // border removed per request
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.4),
          blurRadius: 20,
          spreadRadius: 2,
        ),
      ],
    ),
    child: Center(
      child: SvgPicture.asset('assets/icons/profile.svg', width: 24, height: 24, colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
    ),
  );
}

Widget _buildChatOrb() {
  final currentUser = SupabaseService.instance.currentUser;
  
  return Stack(
    children: [
      Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: const Color(0xFF242424),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Center(child: SvgPicture.asset('assets/icons/chat.svg', width: 24, height: 24, colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn))),
      ),
      // Unread message count badge
      if (currentUser != null)
        Positioned(
          top: 0,
          right: 0,
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: SupabaseService.instance.client
                .from('conversations')
                .stream(primaryKey: ['id']),
            builder: (context, snapshot) {
              int totalUnread = 0;

              if (snapshot.hasData) {
                final conversations = snapshot.data ?? [];
                for (var convData in conversations) {
                  // Robust unread detection: check several common fields
                  bool convIsUnread(Map<String, dynamic> data, String uid) {
                    try {
                      // Check if participants array contains the user
                      final participants = data['participants'] as List?;
                      if (participants == null || !participants.contains(uid)) return false;
                      
                      if (data['unread_by'] is List && (data['unread_by'] as List).contains(uid)) return true;
                      if (data['unreadBy'] is List && (data['unreadBy'] as List).contains(uid)) return true;
                      if (data['unread'] is bool && data['unread'] == true) return true;
                      if (data['seen'] is bool && data['seen'] == false) return true;
                      if (data['read_by'] is List && !(data['read_by'] as List).contains(uid)) return true;
                      if (data['readBy'] is List && !(data['readBy'] as List).contains(uid)) return true;
                      if (data['seen_by'] is List && !(data['seen_by'] as List).contains(uid)) return true;
                      if (data['seenBy'] is List && !(data['seenBy'] as List).contains(uid)) return true;
                      if (data['last_message_seen_by'] is List && !(data['last_message_seen_by'] as List).contains(uid)) return true;
                      if (data['lastMessageSeenBy'] is List && !(data['lastMessageSeenBy'] as List).contains(uid)) return true;
                    } catch (e) {
                      // ignore and treat as not unread
                    }
                    return false;
                  }

                  if (convIsUnread(convData, currentUser.id)) totalUnread++;
                }
              }

              // Only show a small red dot if there are unread conversations
              if (totalUnread == 0) return const SizedBox.shrink();

              return Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
              );
            },
          ),
        ),
    ],
  );
}

Widget _buildHomeOrb() {
  return Container(
    width: 56,
    height: 56,
    decoration: BoxDecoration(
      color: const Color(0xFF242424),
      shape: BoxShape.circle,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.4),
          blurRadius: 20,
          spreadRadius: 2,
        ),
      ],
    ),
    child: Center(
      child: _showBookingsHomepage 
        ? SvgPicture.asset('assets/icons/bookings.svg', width: 22, height: 22, colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn))
        : SvgPicture.asset('assets/icons/sort.svg', width: 22, height: 22, colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
    ),
  );
}

Widget _buildAddOrb() {
  return Container(
    width: 56,
    height: 56,
    decoration: BoxDecoration(
      color: const Color(0xFF242424),
      shape: BoxShape.circle,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.4),
          blurRadius: 20,
          spreadRadius: 2,
        ),
      ],
    ),
    child: Center(child: SvgPicture.asset('assets/icons/add.svg', width: 24, height: 24, colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn))),
  );
}

Widget _buildFavoritesOrb() {
  return Container(
    width: 56,
    height: 56,
    decoration: BoxDecoration(
      color: const Color(0xFF242424),
      shape: BoxShape.circle,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.4),
          blurRadius: 20,
          spreadRadius: 2,
        ),
      ],
    ),
    child: Center(child: SvgPicture.asset('assets/icons/favorite.svg', width: 24, height: 24, colorFilter: ColorFilter.mode(showFavoritesOnly ? Colors.green : Colors.white, BlendMode.srcIn))),
  );
}

Widget _buildCategoriesOverlay() {
  return Positioned.fill(
    child: GestureDetector(
      onTap: () {
        debugPrint('🔍 Overlay tapped - closing');
        setState(() => categoriesVisible = false);
      },
      child: Container(
        color: Colors.transparent,
        child: Center(
          child: GestureDetector(
            onTap: () {
              // Prevent closing when tapping inside the modal
              debugPrint('🔍 Modal tapped - not closing');
            },
            child: Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Categories',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: categories.map((cat) {
                      final isSelected = selectedCategory == cat['id'];
                      return GestureDetector(
                        onTap: () async {
                          debugPrint('🔍 Category tapped: ${cat['id']}');
                          setState(() {
                            selectedCategory = cat['id'];
                            categoriesVisible = false;
                          });
                          // Refresh products with category filter
                          await _refreshProducts();
                        },
                        child: Container(
                          height: 36,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            gradient: isSelected
                                ? LinearGradient(
                                    colors: [Colors.black, Colors.grey.shade800],
                                  )
                                : null,
                            color: isSelected ? null : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(cat['emoji'], style: const TextStyle(fontSize: 16)),
                              const SizedBox(width: 8),
                              Text(
                                cat['name'],
                                style: TextStyle(
                                  color: isSelected ? Colors.white : Colors.black87,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
}

class GridProductsPainter extends CustomPainter {
final List<Map<String, dynamic>> products;
final Offset offset;
final Size screenSize;

GridProductsPainter(this.products, this.offset, this.screenSize);

@override
void paint(Canvas canvas, Size size) {
// Just draw the background - actual cards are rendered with Flutter widgets
const gradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [
    Color(0xFF0A0A0A),
    Color(0xFF1A1A1A),
    Color(0xFF0A0A0A),
  ],
);

final paint = Paint()
  ..shader = gradient.createShader(Rect.fromLTWH(0, 0, size.width, size.height));
canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
}

@override
bool shouldRepaint(GridProductsPainter oldDelegate) {
return oldDelegate.offset != offset || oldDelegate.products != products;
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