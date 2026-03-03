import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:ui';
import 'dart:io';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import '../helpers/notification_helper.dart';
import 'product_detail_page.dart';
import 'service_detail_page.dart';
import 'gig_detail_page.dart';
import 'service_delivery_page.dart';
import 'order_detail_page.dart';
import 'dispute_response_page.dart';
import '../services/currency_service.dart';
import '../constants/translations.dart';
import '../helpers/image_helper.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/chat_checkpoints.dart';
import 'chat_settings_page.dart';

// Module-level cache for product images — shared across chat page instances
final Map<String, String?> _productImageCacheStatic = {};
final Map<String, Future<String?>> _productImageFuturesStatic = {};

/// Detects inappropriate chat behavior and assigns penalties
class ChatBehaviorDetector {
  // Personal information patterns
  static final _personalInfoPatterns = RegExp(
    r'(?:phone|number|whatsapp|telegram|instagram|facebook|email|address|zipcode|postal|apartment|street|city|country|id\s+number|passport|credit\s+card|bank|account|ssn)',
    caseSensitive: false,
  );

  // Money in advance patterns (require context to avoid false positives)
  static final _advancePaymentPatterns = RegExp(
    r'(?:pay\s+(?:first|now|upfront|advance|before|in\s+advance)|send\s+money|wire\s+(?:money|transfer)|payment\s+first|prepay|advance\s+payment|down\s+payment)',
    caseSensitive: false,
  );

  // Bad language patterns - English profanity (word boundaries to avoid false positives like "hello")
  static final _englishBadLanguage = RegExp(
    r'\b(?:shit|damn|crap|hell|piss|bastard|asshole|bitch|dick|cock|pussy|fuck|fucker|fucking|ass\s*hole|motherfuck(?:er|ing)?|dipshit|shitty|fuckhead|asswipe|cunthead)\b',
    caseSensitive: false,
  );

  // Bad language patterns - Romanian CORE offensive words (most common)
  static final _romanianBadLanguage = RegExp(
    r'(?:\bpula\b|\bpulă\b|\bpizda\b|\bpizde\b|\bsclav\b|\bsclavule\b|\bmortii\b|\bmortii\s+mati\b|\bmata\b|\bmati\b|\bcur\b|\bcuru\b|\bblana\b|\bfut\b|\bfute\b|\bmuie\b)',
    caseSensitive: false,
  );

  // Obfuscation patterns - numbers replacing letters (simple common ones)
  static final _numberObfuscationPatterns = [
    RegExp(r'\b(?:5h1t|5h!t|5h17|\$h1t|5h!7)\b', caseSensitive: false), // shit
    RegExp(r'\b(?:f\*ck|f\*\*k|f_ck|f@ck|fcuk|phuck|f4ck|f0ck)\b', caseSensitive: false), // fuck
    RegExp(r'\b(?:d4mn|d@mn|d\*mn|d-mn)\b', caseSensitive: false), // damn
    RegExp(r'\b(?:b1tch|b!tch|b\*tch|b@tch|b-tch|b1+ch)\b', caseSensitive: false), // bitch
    RegExp(r'\b(?:4ss|@ss|\*ss|a55|a\$\$)\b', caseSensitive: false), // ass
  ];

  // Romanian obfuscation - most common bad words with number/symbol tricks
  static final _romanianObfuscationPatterns = [
    RegExp(r'(?:\bp\d{1,2}l\d{1,2}\b|\bp\*l\d{1,2}\b|\bp\@l\d{1,2}\b|\bp-l-\b)', caseSensitive: false), // pula
    RegExp(r'(?:\bp\d{1,2}zd\d{1,2}\b|\bp\*zd\d{1,2}\b|\bp\@zd\d{1,2}\b)', caseSensitive: false), // pizda
    RegExp(r'(?:\bsc14v\b|\bsc1@v\b|\bsc\*1av\b|\bscl@v\b)', caseSensitive: false), // sclav
    RegExp(r'(?:\bm0rt\d{1,2}\b|\bm\*rt\d{1,2}\b|\bm@rt\d{1,2}\b)', caseSensitive: false), // mortii
    RegExp(r'(?:\bm@t\d{1,2}\b|\bm\*t\d{1,2}\b|\bm0t\d{1,2}\b)', caseSensitive: false), // mata/mati
    RegExp(r'(?:\bc\d{1,2}r\b|\bc\@r\b|\bc\*r\b)', caseSensitive: false), // cur
    RegExp(r'(?:\bm\d{1,2}\d{1,2}ie\b|\bm\@ie\b|\bmu\*e\b)', caseSensitive: false), // muie
  ];

  /// Check message for inappropriate behavior
  static BehaviorViolation? detectViolation(String message) {
    if (message.isEmpty) return null;

    final lowerMessage = message.toLowerCase();

    // Check for personal info request
    final hasPersonalInfoQuestion = _personalInfoPatterns.hasMatch(lowerMessage) && 
        (lowerMessage.contains('?') || lowerMessage.contains('what') || 
         lowerMessage.contains('can') || lowerMessage.contains('give'));
    
    if (hasPersonalInfoQuestion) {
      return BehaviorViolation(
        type: ViolationType.personalInfoRequest,
        message: 'Attempting to request personal information',
        trustPenalty: -5,
      );
    }

    // Check for money in advance request
    if (_advancePaymentPatterns.hasMatch(lowerMessage)) {
      return BehaviorViolation(
        type: ViolationType.advancePaymentRequest,
        message: 'Attempting to request advance payment',
        trustPenalty: -20,
      );
    }

    // Check for English bad language
    if (_englishBadLanguage.hasMatch(lowerMessage)) {
      return BehaviorViolation(
        type: ViolationType.badLanguage,
        message: 'Keep it respectful',
        trustPenalty: -5,
      );
    }

    // Check for Romanian bad language (core words)
    if (_romanianBadLanguage.hasMatch(lowerMessage)) {
      return BehaviorViolation(
        type: ViolationType.badLanguage,
        message: 'Keep it respectful',
        trustPenalty: -5,
      );
    }

    // Check for obfuscated English bad language
    for (final pattern in _numberObfuscationPatterns) {
      if (pattern.hasMatch(lowerMessage)) {
        return BehaviorViolation(
          type: ViolationType.badLanguage,
          message: 'Keep it respectful',
          trustPenalty: -5,
        );
      }
    }

    // Check for obfuscated Romanian bad language
    for (final pattern in _romanianObfuscationPatterns) {
      if (pattern.hasMatch(lowerMessage)) {
        return BehaviorViolation(
          type: ViolationType.badLanguage,
          message: 'Keep it respectful',
          trustPenalty: -5,
        );
      }
    }

    return null;
  }
}

enum ViolationType {
  personalInfoRequest,
  advancePaymentRequest,
  badLanguage,
}

class BehaviorViolation {
  final ViolationType type;
  final String message;
  final int trustPenalty;

  BehaviorViolation({
    required this.type,
    required this.message,
    required this.trustPenalty,
  });
}

class ChatPage extends StatefulWidget {
  /// When true, the global keyboard-dismiss listener in main.dart is bypassed.
  static bool keepKeyboardOpen = false;

  final String conversationId;
  final String productId;
  final String productTitle;
  final String otherUserId;
  final String? otherUserName;
  final String? otherUserPhoto;
  final Map<String, dynamic>? productData;

  const ChatPage({
    super.key,
    required this.conversationId,
    required this.productId,
    required this.productTitle,
    required this.otherUserId,
    this.otherUserName,
    this.otherUserPhoto,
    this.productData,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  late TextEditingController messageController;
  late ScrollController scrollController;
  late FocusNode _messageFocusNode;

  // Track collapsed checkpoint sections (by message docId)
  final Set<String> _collapsedCheckpoints = {};

  // Cache for product images is at module level (_productImageCacheStatic)

  // Pre-computed sorted message list — rebuilt only when _messages or _pendingServiceOrders change,
  // NOT on every build() call.
  List<Map<String, dynamic>> _preparedMessages = [];
  
  // Cache checkpoint titles to prevent rebuilding on every toggle
  final Map<String, String> _checkpointTitleCache = {};
  
  // Cache product card data to prevent refetching
  final Map<String, Map<String, dynamic>> _productCardCache = {};
  
  // Current user's display name (fetched from DB for accurate notifications)
  String _currentUserDisplayName = 'User';
  
  // Other user's display name (loaded from DB if not passed via widget)
  String? _otherUserDisplayName;
  
  // Optimistic UI state for offers and quantity requests
  final Map<String, String> _offerStatusCache = {}; // offerId -> status
  final Map<String, String> _quantityRequestStatusCache = {}; // messageId -> status

  // Sent-bubble gradient colors (IG-style: flows across all sent messages based on scroll position)
  final ValueNotifier<List<Color>> _bubbleGradientNotifier = ValueNotifier(
    const [Color(0xFF4CAF50), Color(0xFF2E7D32), Color(0xFF1B5E20)],
  );

  // Supabase real-time subscription
  RealtimeChannel? _messagesSubscription;
  
  // Polling timer as fallback for real-time
  Timer? _pollTimer;
  
  // Messages list for Supabase
  List<Map<String, dynamic>> _messages = [];
  bool _isLoadingMessages = true;
  
  // Pending service orders (loaded separately and injected into messages)
  List<Map<String, dynamic>> _pendingServiceOrders = [];

  @override
  bool get wantKeepAlive => true;

  // Helper to get short title (first word + 2-3 letters of second word)
  String _getShortTitle(String? fullTitle) {
    if (fullTitle == null || fullTitle.isEmpty) return 'Item';
    
    final words = fullTitle.trim().split(RegExp(r'\s+'));
    
    if (words.isEmpty) return 'Item';
    
    // Get first word
    String result = words[0];
    
    // If first word is too long, truncate it
    if (result.length > 20) {
      return '${result.substring(0, 20)}...';
    }
    
    // Add 2-3 letters from second word if it exists
    if (words.length > 1 && words[1].isNotEmpty) {
      final secondWord = words[1];
      final lettersToTake = secondWord.length >= 3 ? 3 : secondWord.length;
      result += ' ${secondWord.substring(0, lettersToTake)}...';
    }
    
    return result;
  }

  String _formatChatPrice(Map<String, dynamic> card) {
    final price = card['price'];
    final currency = card['currency'] ?? CurrencyService.current;
    if (price == null || price == 'negotiable' || price == 'Negotiable') {
      return I18n.t('negotiable');
    }
    if (price is num) {
      if (price == 0) return I18n.t('negotiable');
      return '${price.toStringAsFixed(0)} $currency';
    }
    if (price is String) {
      final parsed = double.tryParse(price);
      if (parsed != null && parsed == 0) return I18n.t('negotiable');
      if (parsed != null) return '${parsed.toStringAsFixed(0)} $currency';
      return price;
    }
    return I18n.t('negotiable');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    messageController = TextEditingController();
    scrollController = ScrollController();
    _messageFocusNode = FocusNode();
    _messageFocusNode.addListener(() {
      ChatPage.keepKeyboardOpen = _messageFocusNode.hasFocus;
    });
    _ensureConversationExists();
    _markConversationAsRead();
    _setupRealtimeSubscription();
    _loadInitialMessages();
    _startMessagePolling();
    _loadCurrentUserName();
    _loadOtherUserName();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ChatPage.keepKeyboardOpen = false;
    _bubbleGradientNotifier.dispose();
    messageController.dispose();
    scrollController.dispose();
    _messageFocusNode.dispose();
    _messagesSubscription?.unsubscribe();
    _pollTimer?.cancel();
    super.dispose();
  }


  /// Load current user's display name from DB for accurate notification sender names
  Future<void> _loadCurrentUserName() async {
    try {
      final userId = SupabaseService.instance.currentUserId;
      if (userId == null) return;
      final data = await SupabaseService.instance.users
          .select('display_name, full_name')
          .eq('id', userId)
          .maybeSingle();
      if (data != null && mounted) {
        final name = (data['display_name'] as String?)?.isNotEmpty == true
            ? data['display_name'] as String
            : (data['full_name'] as String?) ?? 'User';
        setState(() => _currentUserDisplayName = name);
      }
    } catch (e) {
      debugPrint('⚠️ Could not load current user name: $e');
    }
  }

  /// Load other user's display name from DB when not passed via widget params
  Future<void> _loadOtherUserName() async {
    if (widget.otherUserName != null && widget.otherUserName!.isNotEmpty) return;
    try {
      final data = await SupabaseService.instance.users
          .select('display_name, full_name')
          .eq('id', widget.otherUserId)
          .maybeSingle();
      if (data != null && mounted) {
        final name = (data['display_name'] as String?)?.isNotEmpty == true
            ? data['display_name'] as String
            : (data['full_name'] as String?) ?? '';
        setState(() => _otherUserDisplayName = name);
      }
    } catch (e) {
      debugPrint('⚠️ Could not load other user name: $e');
    }
  }

  /// Rebuild the pre-computed sorted message list.
  /// Call this whenever _messages or _pendingServiceOrders change — NOT in build().
  void _rebuildPreparedMessages() {
    final formattedMessages = _messages.map((data) {
      String? normalizedTimestamp;
      final rawTimestamp = data['created_at'];
      if (rawTimestamp != null) {
        try {
          final dt = rawTimestamp is DateTime
              ? rawTimestamp
              : DateTime.parse(rawTimestamp.toString());
          normalizedTimestamp = dt.toIso8601String();
        } catch (_) {
          normalizedTimestamp = rawTimestamp.toString();
        }
      }

      return <String, dynamic>{
        'docId': data['id'] as String? ?? '',
        'userId': data['sender_id'] as String? ?? '',
        'name': '',
        'message': data['content'] as String? ?? '',
        'photoUrl': data['profile_image_url'] as String? ?? '',
        'senderPhoto': data['sender_photo'] as String? ?? '',
        'timestamp': normalizedTimestamp,
        'isFirstMessage': data['is_first_message'] as bool? ?? false,
        'isOfferMessage': data['is_offer_message'] as bool? ?? false,
        'isQuantityRequest': data['is_quantity_request'] as bool? ?? false,
        'isServiceBookingRequest': data['is_service_booking_request'] as bool? ?? false,
        'isServiceOrderConfirmation': data['is_service_order_confirmation'] as bool? ?? false,
        'isDisputeMessage': data['is_dispute_message'] as bool? ?? false,
        'isOrderCancelled': data['is_order_cancelled'] as bool? ?? false,
        'offerId': data['offer_id'] as String?,
        'offeredPrice': data['offered_price'],
        'currency': data['currency'] as String? ?? CurrencyService.current,
        'productId': data['product_id'] as String? ?? widget.productId,
        'productCard': data['product_card'] as Map<String, dynamic>? ?? {},
        'quantityRequested': data['quantity_requested'] as int?,
        'status': data['status'] as String?,
        'serviceDelivery': data['service_delivery'] as Map<String, dynamic>?,
        'disputeData': data['dispute_data'] as Map<String, dynamic>?,
        'orderCancelledData': data['order_cancelled_data'] as Map<String, dynamic>?,
        'type': data['type'] as String?,
        'checkpointTitle': data['checkpoint_title'] as String?,
        'title': data['title'] as String?,
        'imageUrl': data['image_url'] as String?,
        'imageReportStatus': data['image_report_status'] as String?,
        'imageReportAnalysis': data['image_report_analysis'] as Map<String, dynamic>?,
        'imageReporterId': data['image_reporter_id'] as String?,
        'orderId': data['order_id'] as String?,
        'serviceTitle': data['service_title'] as String?,
        'servicePrice': data['service_price'],
        'isBooking': data['is_booking'] as bool? ?? false,
        'bookingDate': data['booking_date'] as String?,
        'contactCard': data['contact_card'] as Map<String, dynamic>?,
        'isContactCard': data['is_contact_card'] as bool? ?? false,
      };
    }).toList();

    // Inject pending service orders
    final allMessages = [...formattedMessages];
    for (final order in _pendingServiceOrders) {
      final createdAt = order['created_at'] as String?;
      if (createdAt == null) continue;

      DateTime orderTime;
      try {
        orderTime = DateTime.parse(createdAt);
      } catch (_) {
        continue;
      }

      final normalizedTimestamp = orderTime.toIso8601String();
      final serviceImageUrl = order['service_image_url'] as String?;
      final buyerName = order['buyer_name'] as String?;
      final buyerAddress = order['buyer_address'] as String?;

      allMessages.add(<String, dynamic>{
        'docId': order['id'] as String,
        'userId': '',
        'name': '',
        'message': '',
        'photoUrl': '',
        'senderPhoto': '',
        'timestamp': normalizedTimestamp,
        'isFirstMessage': false,
        'isOfferMessage': false,
        'isQuantityRequest': false,
        'isServiceBookingRequest': false,
        'isServiceOrderConfirmation': true,
        'isDisputeMessage': false,
        'offerId': null,
        'offeredPrice': null,
        'currency': order['currency'] as String? ?? 'RON',
        'productId': order['service_id'] as String?,
        'productCard': <String, dynamic>{
          'title': order['service_title'],
          'price': order['service_price'],
          'currency': order['currency'] ?? 'RON',
          'type': order['is_booking'] == true ? 'booking' : 'service',
        },
        'quantityRequested': null,
        'status': order['status'] as String?,
        'serviceDelivery': null,
        'disputeData': null,
        'type': 'service_order_confirmation',
        'checkpointTitle': null,
        'title': null,
        'imageUrl': null,
        'imageReportStatus': null,
        'imageReportAnalysis': null,
        'imageReporterId': null,
        'orderId': order['order_id'] as String?,
        'serviceTitle': order['service_title'] as String?,
        'servicePrice': order['service_price'],
        'isBooking': order['is_booking'] as bool? ?? false,
        'bookingDate': order['booking_date'] as String?,
        'created_at': normalizedTimestamp,
        'serviceImageUrl': serviceImageUrl,
        'buyerName': buyerName,
        'buyerAddress': buyerAddress,
      });
    }

    // Sort by timestamp (chronological).
    // Use index as tiebreaker so messages with identical timestamps
    // keep their insertion order (stable sort).
    for (int i = 0; i < allMessages.length; i++) {
      allMessages[i]['_sortIndex'] = i;
    }
    allMessages.sort((a, b) {
      final aTime = a['timestamp']?.toString() ?? '';
      final bTime = b['timestamp']?.toString() ?? '';
      final cmp = aTime.compareTo(bTime);
      if (cmp != 0) return cmp;
      return (a['_sortIndex'] as int).compareTo(b['_sortIndex'] as int);
    });

    _preparedMessages = allMessages;
  }

  /// Load initial messages from Supabase
  Future<void> _loadInitialMessages() async {
    try {
      final response = await SupabaseService.instance.messages
          .select()
          .eq('conversation_id', widget.conversationId)
          .order('created_at', ascending: true);
      
      debugPrint('📨 Loaded ${response.length} messages for conversation ${widget.conversationId}');
      
      if (mounted) {
        // Merge any real-time messages that arrived while we were loading
        final loadedMessages = List<Map<String, dynamic>>.from(response);
        // Keep real-time messages that aren't in the loaded batch
        final extraRealtime = _messages.where((m) => !loadedMessages.any((l) => l['id'] == m['id'])).toList();
        _messages = [...loadedMessages, ...extraRealtime];
        _isLoadingMessages = false;
        _rebuildPreparedMessages();
        setState(() {});
        
        // Scroll to bottom after initial load
        if (_messages.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && scrollController.hasClients) {
              scrollController.jumpTo(0);
            }
          });
        }
      }
      
      // Load service orders in background — don't block message rendering
      _loadPendingServiceOrders().then((_) {
        if (mounted) {
          _rebuildPreparedMessages();
          setState(() {});
        }
      });
    } catch (e) {
      debugPrint('Error loading initial messages: $e');
      if (mounted) {
        setState(() {
          _isLoadingMessages = false;
        });
      }
    }
  }

  /// Poll for new messages every 2 seconds.
  /// This is the primary mechanism for receiving messages since Supabase
  /// real-time is unreliable. Only fetches messages newer than the latest
  /// we already have, so it's lightweight.
  void _startMessagePolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollNewMessages());
  }

  Future<void> _pollNewMessages() async {
    if (!mounted || _isLoadingMessages) return;
    try {
      // Find the latest created_at we have (from real messages, not temp)
      String? latestTimestamp;
      for (final m in _messages) {
        final id = m['id']?.toString() ?? '';
        if (id.startsWith('temp_')) continue;
        final ts = m['created_at']?.toString();
        if (ts != null && (latestTimestamp == null || ts.compareTo(latestTimestamp) > 0)) {
          latestTimestamp = ts;
        }
      }

      List<dynamic> newMessages;
      if (latestTimestamp != null) {
        newMessages = await SupabaseService.instance.messages
            .select()
            .eq('conversation_id', widget.conversationId)
            .gt('created_at', latestTimestamp)
            .order('created_at', ascending: true);
      } else {
        // No messages yet — fetch all
        newMessages = await SupabaseService.instance.messages
            .select()
            .eq('conversation_id', widget.conversationId)
            .order('created_at', ascending: true);
      }

      if (!mounted || newMessages.isEmpty) return;

      bool changed = false;
      for (final raw in newMessages) {
        final msg = Map<String, dynamic>.from(raw);
        final msgId = msg['id']?.toString() ?? '';

        // Skip if already in list by real ID
        if (_messages.any((m) => m['id'] == msgId)) continue;

        // Check if it matches an optimistic temp message
        final sender = msg['sender_id']?.toString() ?? '';
        final content = msg['content']?.toString() ?? '';
        DateTime? msgTime;
        try { msgTime = DateTime.parse(msg['created_at'].toString()); } catch (_) {}

        final tempIdx = _messages.indexWhere((m) {
          if (!m['id'].toString().startsWith('temp_')) return false;
          if (m['sender_id']?.toString() != sender) return false;
          if (m['content']?.toString() != content) return false;
          if (msgTime != null) {
            try {
              final t = DateTime.parse(m['created_at'].toString());
              if (msgTime.difference(t).inSeconds.abs() > 10) return false;
            } catch (_) {}
          }
          return true;
        });

        if (tempIdx != -1) {
          final originalCreatedAt = _messages[tempIdx]['created_at'];
          msg['created_at'] = originalCreatedAt;
          _messages[tempIdx] = msg;
        } else {
          _messages.add(msg);
        }
        changed = true;
      }

      if (changed && mounted) {
        _rebuildPreparedMessages();
        setState(() {});
        // Scroll to bottom for new messages
        Future.delayed(const Duration(milliseconds: 50), () {
          if (mounted && scrollController.hasClients) {
            scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });
        // Mark as read
        _markConversationAsRead();
      }
    } catch (e) {
      debugPrint('⚠️ Poll error: $e');
    }
  }

  /// Query service orders and bookings for this conversation
  Future<void> _loadPendingServiceOrders() async {
    try {
      final currentUser = SupabaseService.instance.currentUser;
      if (currentUser == null) {
        debugPrint('❌ No current user');
        _pendingServiceOrders = [];
        return;
      }
      
      debugPrint('🔍 Current user ID: ${currentUser.id}');
      debugPrint('🔍 Conversation ID: ${widget.conversationId}');
      
      // Determine if current user is seller from conversation ID
      // Format: conv_sortedId1_sortedId2 (IDs are sorted alphabetically, not by role)
      final parts = widget.conversationId.split('_');
      debugPrint('🔍 Conversation parts: $parts');
      
      if (parts.length < 3 || parts[0] != 'conv') {
        debugPrint('❌ Invalid conversation ID format (expected: conv_id1_id2)');
        _pendingServiceOrders = [];
        return;
      }
      
      final userId1 = parts[1];
      final userId2 = parts[2];
      final otherUserId = userId1 == currentUser.id ? userId2 : userId1;
      
      debugPrint('🔍 User 1: $userId1');
      debugPrint('🔍 User 2: $userId2');
      debugPrint('🔍 Other user: $otherUserId');
      debugPrint('🔍 Current user: ${currentUser.id}');
      
      List<Map<String, dynamic>> pendingOrders = [];
      
      // Query service_orders between these two users (either as seller or buyer)
      debugPrint('🔍 Querying service_orders for this conversation...');
      final serviceOrders = await SupabaseService.instance.serviceOrders
          .select('*, services!inner(*)')
          .or('and(seller_id.eq.${currentUser.id},buyer_id.eq.$otherUserId),and(seller_id.eq.$otherUserId,buyer_id.eq.${currentUser.id})');
      
      debugPrint('🔍 Found ${serviceOrders.length} service orders');
      
      final now = DateTime.now();
      
      for (final order in serviceOrders) {
        final service = order['services'] as Map<String, dynamic>?;
        if (service == null) continue;
        
        String status = order['status'] as String? ?? '';
        final createdAt = DateTime.tryParse(order['created_at'] as String? ?? '');
        
        // Auto-decline pending orders older than 12h
        if (_isPendingStatus(status) && createdAt != null && now.difference(createdAt).inHours >= 12) {
          status = 'declined';
          try {
            await SupabaseService.instance.serviceOrders
                .update({'status': 'declined'})
                .eq('id', order['id']);
            debugPrint('⏰ Auto-declined service order ${order['id']} (12h expired)');
          } catch (e) {
            debugPrint('⚠️ Failed to auto-decline service order: $e');
          }
        }
        
        pendingOrders.add({
          'id': 'service_order_${order['id']}',
          'type': 'service_order_confirmation',
          'order_id': order['id'],
          'service_id': order['service_id'],
          'service_title': service['title'],
          'service_image_url': service['image_url'],
          'service_price': order['price'],
          'currency': order['currency'] ?? 'RON',
          'status': status,
          'is_booking': false,
          'buyer_id': order['buyer_id'],
          'created_at': order['created_at'],
          'is_service_order_confirmation': true,
        });
      }
      
      // Query bookings between these two users
      debugPrint('🔍 Querying bookings for this conversation...');
      final bookings = await SupabaseService.instance.bookings
          .select('*, services!inner(*)')
          .or('and(seller_id.eq.${currentUser.id},buyer_id.eq.$otherUserId),and(seller_id.eq.$otherUserId,buyer_id.eq.${currentUser.id})');
      
      debugPrint('🔍 Found ${bookings.length} bookings');
      
      for (final booking in bookings) {
        final service = booking['services'] as Map<String, dynamic>?;
        if (service == null) continue;
        
        String status = booking['status'] as String? ?? '';
        if (status == 'paid') status = 'pending_confirmation';
        final createdAt = DateTime.tryParse(booking['created_at'] as String? ?? '');
        
        // Auto-decline pending bookings older than 12h
        if (_isPendingStatus(status) && createdAt != null && now.difference(createdAt).inHours >= 12) {
          status = 'declined';
          try {
            await SupabaseService.instance.bookings
                .update({'status': 'declined'})
                .eq('id', booking['id']);
            debugPrint('⏰ Auto-declined booking ${booking['id']} (12h expired)');
          } catch (e) {
            debugPrint('⚠️ Failed to auto-decline booking: $e');
          }
        }
        
        pendingOrders.add({
          'id': 'booking_${booking['id']}',
          'type': 'service_order_confirmation',
          'order_id': booking['id'],
          'service_id': booking['service_id'],
          'service_title': service['title'],
          'service_image_url': service['image_url'],
          'service_price': booking['price'],
          'currency': booking['currency'] ?? 'RON',
          'status': status,
          'is_booking': true,
          'booking_date': booking['booking_date'],
          'buyer_id': booking['buyer_id'],
          'created_at': booking['created_at'],
          'is_service_order_confirmation': true,
          'buyer_address_full': booking['buyer_address_full'],
          'buyer_address_name': booking['buyer_address_name'],
          'buyer_address_street': booking['buyer_address_street'],
          'buyer_address_building': booking['buyer_address_building'],
          'buyer_address_city': booking['buyer_address_city'],
          'buyer_address_zip': booking['buyer_address_zip'],
          'buyer_address_phone': booking['buyer_address_phone'],
        });
      }
      
      // Sort by created_at
      pendingOrders.sort((a, b) => 
        (a['created_at'] as String).compareTo(b['created_at'] as String)
      );
      
      // Fetch buyer names for all orders
      final buyerIds = pendingOrders.map((o) => o['buyer_id'] as String?).where((id) => id != null).toSet();
      final Map<String, String> buyerNames = {};
      final Map<String, String> buyerAddresses = {};
      
      if (buyerIds.isNotEmpty) {
        try {
          final usersData = await SupabaseService.instance.users
              .select('id, display_name, full_name, addresses')
              .inFilter('id', buyerIds.toList());
          
          for (final user in usersData) {
            final displayName = user['display_name'] as String?;
            final fullName = user['full_name'] as String?;
            buyerNames[user['id'] as String] = (displayName != null && displayName.isNotEmpty) ? displayName : (fullName ?? 'Unknown');
            
            final addresses = user['addresses'];
            if (addresses is List && addresses.isNotEmpty) {
              final firstAddr = addresses.first;
              if (firstAddr is Map) {
                final parts = [firstAddr['street'], firstAddr['city'], firstAddr['zip']].where((p) => p != null && p.toString().isNotEmpty);
                buyerAddresses[user['id'] as String] = parts.isNotEmpty ? parts.join(', ') : 'No address provided';
              } else {
                buyerAddresses[user['id'] as String] = 'No address provided';
              }
            } else {
              buyerAddresses[user['id'] as String] = 'No address provided';
            }
          }
        } catch (e) {
          debugPrint('❌ Error fetching buyer names: $e');
        }
      }
      
      // Add buyer names and addresses to orders
      for (final order in pendingOrders) {
        final buyerId = order['buyer_id'] as String?;
        if (buyerId != null) {
          order['buyer_name'] = buyerNames[buyerId] ?? 'Unknown';
          
          // For bookings, use the buyer_address_full from the booking itself
          // For service orders, fall back to user's address
          if (order['buyer_address_full'] != null && (order['buyer_address_full'] as String).isNotEmpty) {
            order['buyer_address'] = order['buyer_address_full'];
          } else {
            order['buyer_address'] = buyerAddresses[buyerId] ?? 'No address provided';
          }
        }
      }
      
      debugPrint('✅ Total pending service orders/bookings: ${pendingOrders.length}');
      if (pendingOrders.isNotEmpty) {
        debugPrint('✅ Pending orders list: $pendingOrders');
      }
      
      _pendingServiceOrders = pendingOrders;
    } catch (e, stackTrace) {
      debugPrint('❌ Error querying service orders: $e');
      debugPrint('❌ Stack trace: $stackTrace');
      _pendingServiceOrders = [];
    }
  }

  /// Check if a booking/order status is still pending (actionable)
  bool _isPendingStatus(String status) {
    return ['pending_confirmation', 'to_do', 'paid', 'booked'].contains(status);
  }

  /// Persist an optimistic message to Supabase in the background.
  /// This runs fire-and-forget so the UI stays instant.
  Future<void> _persistMessage(String optimisticId, String text, String senderId, String createdAt) async {
    try {
      // Run message insert AND conversation metadata update in parallel
      // so the conversations list updates as fast as possible.
      final insertFuture = SupabaseService.instance.messages.insert({
        'conversation_id': widget.conversationId,
        'sender_id': senderId,
        'sender_name': _currentUserDisplayName,
        'content': text,
        'product_id': widget.productId,
        'created_at': createdAt,
      }).select().single();

      // Update conversation metadata immediately (don't wait for message insert)
      // This makes the conversations list show the new message ASAP.
      final convUpdateFuture = _updateConversationMetadata(text, senderId, createdAt);

      final results = await Future.wait([insertFuture, convUpdateFuture]);

      // Swap optimistic placeholder with real row (if realtime hasn't already)
      if (mounted) {
        final inserted = results[0] as Map<String, dynamic>;
        final idx = _messages.indexWhere((m) => m['id'] == optimisticId);
        if (idx != -1) {
          // Keep the original optimistic timestamp so sort order stays stable
          inserted['created_at'] = createdAt;
          _messages[idx] = inserted;
          _rebuildPreparedMessages();
          setState(() {});
        }
        // If not found, realtime already swapped it — that's fine
      }

      debugPrint('✅ Message persisted to Supabase');
    } catch (e) {
      debugPrint('❌ Error persisting message: $e');
      if (mounted) {
        _messages = _messages.where((m) => m['id'] != optimisticId).toList();
        _rebuildPreparedMessages();
        setState(() {});
        NotificationHelper.showNotification(context, I18n.t('error_sending_message'));
      }
    }
  }

  /// Update conversation last_message / unread_by in one shot.
  Future<void> _updateConversationMetadata(String text, String senderId, String createdAt) async {
    try {
      final convData = await SupabaseService.instance.conversations
          .select('unread_by')
          .eq('id', widget.conversationId)
          .maybeSingle();

      final unreadBy = convData != null
          ? List<String>.from(convData['unread_by'] ?? [])
          : <String>[];
      if (!unreadBy.contains(widget.otherUserId)) {
        unreadBy.add(widget.otherUserId);
      }
      unreadBy.remove(senderId);

      await SupabaseService.instance.conversations.update({
        'last_message': text,
        'last_message_time': createdAt,
        'last_message_sender': senderId,
        'unread_by': unreadBy,
      }).eq('id', widget.conversationId);
    } catch (e) {
      debugPrint('❌ Error updating conversation metadata: $e');
    }
  }

  /// Set up Supabase real-time subscription for new messages
  void _setupRealtimeSubscription() {
    // Subscribe to new messages
    _messagesSubscription = SupabaseService.instance.client
        .channel('messages:${widget.conversationId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: widget.conversationId,
          ),
          callback: (payload) {
            debugPrint('New message received via real-time: ${payload.newRecord}');
            if (mounted) {
              final newMessage = Map<String, dynamic>.from(payload.newRecord);
              final messageId = newMessage['id'];
              
              // Check if message already exists by real ID
              final existsByRealId = _messages.any((m) => m['id'] == messageId);
              
              if (existsByRealId) {
                debugPrint('Message $messageId already exists, skipping');
                return;
              }
              
              // Check if this is a realtime echo of our optimistic message.
              // Match by sender + content + close timestamp (within 10s) to avoid
              // swapping the wrong temp when the same text is sent twice.
              final newSender = newMessage['sender_id']?.toString() ?? '';
              final newContent = newMessage['content']?.toString() ?? '';
              DateTime? newTime;
              try {
                newTime = DateTime.parse(newMessage['created_at'].toString());
              } catch (_) {}
              
              final tempIdx = _messages.indexWhere((m) {
                if (!m['id'].toString().startsWith('temp_')) return false;
                if (m['sender_id']?.toString() != newSender) return false;
                if (m['content']?.toString() != newContent) return false;
                // Also check timestamp proximity to avoid wrong match
                if (newTime != null) {
                  try {
                    final tempTime = DateTime.parse(m['created_at'].toString());
                    if (newTime.difference(tempTime).inSeconds.abs() > 10) return false;
                  } catch (_) {}
                }
                return true;
              });
              
              if (tempIdx != -1) {
                // Swap optimistic placeholder with real message,
                // but keep the original optimistic timestamp for stable ordering
                final originalCreatedAt = _messages[tempIdx]['created_at'];
                newMessage['created_at'] = originalCreatedAt;
                _messages[tempIdx] = newMessage;
                _rebuildPreparedMessages();
                setState(() {});
              } else {
                // Genuinely new message (from the other user)
                _messages = [..._messages, newMessage];
                _rebuildPreparedMessages();
                setState(() {});
                
                // Scroll to bottom when new message arrives
                Future.delayed(const Duration(milliseconds: 100), () {
                  if (mounted && scrollController.hasClients) {
                    scrollController.animateTo(
                      0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  }
                });
              }
            }
          },
        )
        .subscribe();
    
    // Subscribe to booking status changes for real-time updates
    final currentUser = SupabaseService.instance.currentUser;
    if (currentUser != null) {
      // Subscribe to bookings table changes
      SupabaseService.instance.client
          .channel('bookings:${widget.conversationId}')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'bookings',
            callback: (payload) {
              debugPrint('📅 Booking status updated via real-time: ${payload.newRecord}');
              if (mounted) {
                _loadPendingServiceOrders().then((_) {
                  if (mounted) {
                    _rebuildPreparedMessages();
                    setState(() {});
                  }
                });
              }
            },
          )
          .subscribe();
      
      // Subscribe to service_orders table changes
      SupabaseService.instance.client
          .channel('service_orders:${widget.conversationId}')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'service_orders',
            callback: (payload) {
              debugPrint('🛠️ Service order status updated via real-time: ${payload.newRecord}');
              if (mounted) {
                _loadPendingServiceOrders().then((_) {
                  if (mounted) {
                    _rebuildPreparedMessages();
                    setState(() {});
                  }
                });
              }
            },
          )
          .subscribe();
    }
    
    debugPrint('✅ Subscribed to messages and booking updates for conversation: ${widget.conversationId}');
  }

  /// Helper function to record trust history changes
  Future<void> _recordTrustHistory({
    required String userId,
    required int points,
    required String reason,
    required String type,
  }) async {
    try {
      await SupabaseService.instance.trustHistory.insert({
        'user_id': userId,
        'type': type,
        'reason': reason,
        'points': points,
        'timestamp': DateTime.now().toIso8601String(),
      });
      debugPrint('✅ Trust history recorded: $reason ($points points)');
    } catch (e) {
      debugPrint('❌ Error recording trust history: $e');
    }
  }

  Future<void> _markConversationAsRead() async {
    try {
      final currentUser = SupabaseService.instance.currentUser;
      if (currentUser == null) return;

      // Get current conversation data
      final convData = await SupabaseService.instance.conversations
          .select('unread_by, seen_by, read_by, last_message_seen_by')
          .eq('id', widget.conversationId)
          .maybeSingle();

      if (convData == null) return;

      // Update arrays by removing/adding user ID
      final unreadBy = List<String>.from(convData['unread_by'] ?? []);
      final seenBy = List<String>.from(convData['seen_by'] ?? []);
      final readBy = List<String>.from(convData['read_by'] ?? []);
      final lastMessageSeenBy = List<String>.from(convData['last_message_seen_by'] ?? []);

      unreadBy.remove(currentUser.id);
      if (!seenBy.contains(currentUser.id)) seenBy.add(currentUser.id);
      if (!readBy.contains(currentUser.id)) readBy.add(currentUser.id);
      if (!lastMessageSeenBy.contains(currentUser.id)) lastMessageSeenBy.add(currentUser.id);

      await SupabaseService.instance.conversations.update({
        'unread_by': unreadBy,
        'seen_by': seenBy,
        'read_by': readBy,
        'last_message_seen_by': lastMessageSeenBy,
      }).eq('id', widget.conversationId);
    } catch (e) {
      debugPrint('Error marking conversation as read/seen: $e');
    }
  }

  Future<void> _ensureConversationExists() async {
    try {
      final currentUser = SupabaseService.instance.currentUser;
      if (currentUser == null) return;

      final convData = await SupabaseService.instance.conversations
          .select()
          .eq('id', widget.conversationId)
          .maybeSingle();

      if (convData == null) {
        final insertData = <String, dynamic>{
          'id': widget.conversationId,
          'product_id': widget.productId,
          'product_title': widget.productTitle,
          'participants': [currentUser.id, widget.otherUserId],
          'user_id': widget.otherUserId,
          'last_message': '',
          'last_message_time': DateTime.now().toIso8601String(),
          'created_at': DateTime.now().toIso8601String(),
          'unread_by': [widget.otherUserId],
        };
        // Gig conversations use format: id1_id2_gigId (no conv_ prefix)
        if (!widget.conversationId.startsWith('conv_')) {
          insertData['gig_id'] = widget.productId;
        }
        await SupabaseService.instance.conversations.insert(insertData);
        debugPrint('✅ Conversation created: ${widget.conversationId}');
      }
    } catch (e) {
      debugPrint('Error ensuring conversation exists: $e');
    }
  }

  /// Apply trust penalty for behavior violation
  Future<void> _applyTrustPenalty(String userId, BehaviorViolation violation) async {
    try {
      // Get current user data
      final userData = await SupabaseService.instance.users
          .select('trust_score')
          .eq('id', userId)
          .maybeSingle();

      if (userData != null) {
        final currentScore = (userData['trust_score'] as num?)?.toInt() ?? 0;
        final newScore = currentScore + violation.trustPenalty;

        // Update trust_score (same column the backend TrustScoreManager uses)
        await SupabaseService.instance.users.update({
          'trust_score': newScore,
          'last_violation': DateTime.now().toIso8601String(),
          'last_violation_type': violation.type.toString(),
        }).eq('id', userId);
      }

      // Save to trust history
      await _recordTrustHistory(
        userId: userId,
        points: violation.trustPenalty,
        reason: violation.message,
        type: 'violation',
      );

      debugPrint('⚠️ Trust penalty applied to $userId: ${violation.trustPenalty} (${violation.message})');
    } catch (e) {
      debugPrint('Error applying trust penalty: $e');
    }
  }

  /// Check if current user can send images based on checkpoint and role
  Future<bool> _canSendImages() async {
    try {
      final currentUser = SupabaseService.instance.currentUser;
      if (currentUser == null) {
        debugPrint('[IMAGE] No current user');
        return false;
      }

      // Determine if current user is seller (conversationId format: buyerId_sellerId_productId)
      final conversationParts = widget.conversationId.split('_');
      if (conversationParts.length < 2) {
        debugPrint('[IMAGE] Invalid conversation ID format');
        return false;
      }
      
      final buyerId = conversationParts[0];
      final sellerId = conversationParts[1];
      
      final isSeller = currentUser.id == sellerId;
      final isBuyer = currentUser.id == buyerId;
      
      debugPrint('[IMAGE] User role - isSeller: $isSeller, isBuyer: $isBuyer');
      
      // Sellers can always send images
      if (isSeller) {
        debugPrint('[IMAGE] Seller can send images');
        return true;
      }
      
      // Buyers can send images if there's a service checkpoint
      if (isBuyer) {
        final checkpoint = await ChatCheckpoints.getCurrentCheckpoint(widget.conversationId);
        debugPrint('[IMAGE] Current checkpoint: $checkpoint');
        
        if (checkpoint == ChatCheckpoints.serviceDetails || 
            checkpoint == ChatCheckpoints.serviceDelivery) {
          debugPrint('[IMAGE] Buyer can send images (service checkpoint)');
          return true;
        }
        
        debugPrint('[IMAGE] Buyer cannot send images (not service checkpoint)');
        return false;
      }
      
      debugPrint('[IMAGE] User is neither buyer nor seller');
      return false;
    } catch (e) {
      debugPrint('[IMAGE] Error checking image permission: $e');
      return false;
    }
  }

  /// Build image report note widget
  Widget _buildImageReportNote(
    Map<String, dynamic> analysis,
    String? reporterId,
    bool isCurrentUser,
    String? currentUserId,
  ) {
    final violation = analysis['violation'] as bool? ?? false;
    
    // If violation found, show to both users
    // If no violation, only show to reporter
    final isReporter = currentUserId == reporterId;
    
    if (!violation && !isReporter) {
      return const SizedBox.shrink(); // Don't show to non-reporter if no violation
    }
    
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 8, right: 8),
      child: Center(
        child: Text(
          violation 
              ? 'Image sent violates platform policy. -15 trust score deducted for user.'
              : 'No violation of platform policy found.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: violation ? Colors.red[300] : Colors.grey[400],
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  /// Report an image for AI analysis
  Future<void> _reportImage(String messageId, String imageUrl, String senderId) async {
    try {
      final currentUser = SupabaseService.instance.currentUser;
      if (currentUser == null) return;

      // Show confirmation dialog
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: Text(I18n.t('report_image'), style: const TextStyle(color: Colors.white)),
          content: Text(
            I18n.t('report_image_confirm'),
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(I18n.t('cancel'), style: const TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(I18n.t('report'), style: const TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      if (mounted) {
        NotificationHelper.showNotification(context, I18n.t('analyzing_image_report'));
      }

      // Create report document in Supabase
      await SupabaseService.instance.imageReports.insert({
        'message_id': messageId,
        'image_url': imageUrl,
        'sender_id': senderId,
        'reporter_id': currentUser.id,
        'conversation_id': widget.conversationId,
        'status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        NotificationHelper.showNotification(context, I18n.t('image_reported_analyzing'));
      }
    } catch (e) {
      debugPrint('Error reporting image: $e');
      if (mounted) {
        NotificationHelper.showNotification(context, I18n.t('error_reporting_image'));
      }
    }
  }

  /// Pick and send image
  Future<void> _pickAndSendImage() async {
    try {
      final currentUser = SupabaseService.instance.currentUser;
      if (currentUser == null) return;

      // Check if user can send images
      final canSend = await _canSendImages();
      if (!canSend) {
        if (mounted) {
          NotificationHelper.showNotification(context, I18n.t('images_not_allowed_phase'));
        }
        return;
      }

      // Pick image using file_picker
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      
      if (result == null || result.files.isEmpty) return;
      
      final file = result.files.first;
      if (file.bytes == null && file.path == null) return;

      // Show loading
      if (mounted) {
        NotificationHelper.showNotification(context, I18n.t('uploading_image'));
      }

      // Upload to Supabase Storage
      String? imageUrl;
      Uint8List? imageBytes;
      
      if (kIsWeb && file.bytes != null) {
        imageBytes = file.bytes!;
      } else if (file.path != null) {
        imageBytes = await File(file.path!).readAsBytes();
      }
      
      if (imageBytes != null) {
        final path = 'chat_images/${widget.conversationId}/${DateTime.now().millisecondsSinceEpoch}.jpg';
        imageUrl = await SupabaseService.instance.uploadFile(
          bucket: 'chat_images',
          path: path,
          fileBytes: imageBytes,
          contentType: 'image/jpeg',
        );
      }

      if (imageUrl == null) {
        if (mounted) {
          NotificationHelper.showNotification(context, I18n.t('failed_upload_image'));
        }
        return;
      }

      // Send message with image to Supabase
      await SupabaseService.instance.messages.insert({
        'conversation_id': widget.conversationId,
        'sender_id': currentUser.id,
        'sender_name': _currentUserDisplayName,
        'sender_photo': currentUser.userMetadata?['photo_url'],
        'image_url': imageUrl,
        'type': 'image',
        'created_at': DateTime.now().toIso8601String(),
        'product_id': widget.productId,
      });

      // Update conversation metadata
      final convData = await SupabaseService.instance.conversations
          .select('unread_by')
          .eq('id', widget.conversationId)
          .maybeSingle();

      if (convData != null) {
        final unreadBy = List<String>.from(convData['unread_by'] ?? []);
        if (!unreadBy.contains(widget.otherUserId)) {
          unreadBy.add(widget.otherUserId);
        }
        unreadBy.remove(currentUser.id);

        await SupabaseService.instance.conversations.update({
          'last_message': '📷 Image',
          'last_message_time': DateTime.now().toIso8601String(),
          'last_message_sender': currentUser.id,
          'unread_by': unreadBy,
        }).eq('id', widget.conversationId);
      }

      debugPrint('✅ Image sent successfully');

      if (mounted) {
        NotificationHelper.showNotification(context, I18n.t('image_sent'));
        // Scroll to bottom
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted && scrollController.hasClients) {
            scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } catch (e) {
      debugPrint('❌ Error sending image: $e');
      if (mounted) {
        NotificationHelper.showNotification(context, I18n.t('error_sending_image'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final currentUser = SupabaseService.instance.currentUser;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFF0A0A0A),
      body: Stack(
        children: [
          GestureDetector(
            onTap: () {
              FocusScope.of(context).unfocus();
            },
            child: Column(
              children: [
                Expanded(
                  child: Builder(
                    builder: (context) {
                      if (_isLoadingMessages && _messages.isEmpty) {
                        return const Center(
                          child: CircularProgressIndicator(
                            color: Colors.green,
                            strokeWidth: 2,
                          ),
                        );
                      }

                      if (_messages.isEmpty && _pendingServiceOrders.isEmpty) {
                        return const SizedBox.shrink();
                      }

                      final allMessages = _preparedMessages;

                      final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

                      return ListView.builder(
                        controller: scrollController,
                        reverse: true,
                        padding: EdgeInsets.fromLTRB(4, 70, 4, keyboardOpen ? 52 : 72),
                        itemCount: allMessages.length,
                        cacheExtent: 500,
                        addAutomaticKeepAlives: false,
                        addRepaintBoundaries: false,
                        itemBuilder: (ctx, idx) {
                          // reverse: true flips the list — index 0 is at the bottom
                          final reversedIdx = allMessages.length - 1 - idx;
                          final msg = allMessages[reversedIdx];
                          final docId = msg['docId'] as String? ?? reversedIdx.toString();

                          final isCurrentUser = msg['userId'] == currentUser?.id;
                          final userId = msg['userId'] as String?;
                          final messageText = msg['message'] as String? ?? '';
                          final productCard = msg['productCard'] as Map<String, dynamic>? ?? {};
                          final serviceDelivery = msg['serviceDelivery'] as Map<String, dynamic>?;
                          final disputeData = msg['disputeData'] as Map<String, dynamic>?;
                          final messageType = msg['type'] as String?;
                          final imageUrl = msg['imageUrl'] as String?;
                          final imageReportStatus = msg['imageReportStatus'] as String?;
                          final imageReportAnalysis = msg['imageReportAnalysis'] as Map<String, dynamic>?;
                          final imageReporterId = msg['imageReporterId'] as String?;
                          final checkpointTitle = msg['checkpointTitle'] as String?;
                          final messageProductId = msg['productId'] as String? ?? widget.productId;
                          final isFirstMessage = msg['isFirstMessage'] as bool? ?? false;
                          final isOfferMessage = msg['isOfferMessage'] as bool? ?? false;
                          final isQuantityRequest = msg['isQuantityRequest'] as bool? ?? false;
                          final isServiceBookingRequest = msg['isServiceBookingRequest'] as bool? ?? msg['is_service_booking_request'] as bool? ?? false;
                          final isServiceOrderConfirmation = msg['isServiceOrderConfirmation'] as bool? ?? false;
                          final isDisputeMessage = msg['isDisputeMessage'] as bool? ?? false;
                          final isOrderCancelled = msg['isOrderCancelled'] as bool? ?? false;
                          final orderCancelledData = msg['orderCancelledData'] as Map<String, dynamic>?;
                          final isContactCard = msg['isContactCard'] as bool? ?? false;
                          final contactCard = msg['contactCard'] as Map<String, dynamic>?;
                          final offerId = msg['offerId'] as String?;
                          final quantityRequested = msg['quantityRequested'] as int?;
                          final requestStatus = msg['status'] as String?;
                          
                          // Determine checkpoint ID for this message
                          // For offers and quantity requests about the same product, use the first message's checkpoint
                          String? checkpointId;
                          if (isFirstMessage) {
                            // First message creates its own checkpoint
                            checkpointId = docId;
                          } else if (isOfferMessage || isQuantityRequest || isServiceBookingRequest || isServiceOrderConfirmation) {
                            // Offers, quantity requests, and service booking requests should use the first message checkpoint for the same product
                            // Find the first message checkpoint for this product
                            for (int i = idx - 1; i >= 0; i--) {
                              final prevMsg = allMessages[i];
                              final prevProductId = prevMsg['productId'] as String?;
                              if (prevMsg['isFirstMessage'] == true && prevProductId == messageProductId) {
                                checkpointId = prevMsg['docId'] as String?;
                                break;
                              }
                            }
                            // If no first message found for this product, create own checkpoint
                            checkpointId ??= docId;
                          } else if (serviceDelivery != null || isDisputeMessage || isOrderCancelled) {
                            // Service deliveries, disputes, and order cancellations create their own checkpoints
                            checkpointId = docId;
                          } else {
                            // Regular messages: find the most recent checkpoint before this message
                            for (int i = idx - 1; i >= 0; i--) {
                              final prevMsg = allMessages[i];
                              if (prevMsg['isFirstMessage'] == true || 
                                  prevMsg['isOfferMessage'] == true || 
                                  prevMsg['isQuantityRequest'] == true ||
                                  prevMsg['isServiceBookingRequest'] == true ||
                                  prevMsg['isServiceOrderConfirmation'] == true ||
                                  prevMsg['is_service_booking_request'] == true ||
                                  prevMsg['serviceDelivery'] != null ||
                                  prevMsg['isDisputeMessage'] == true ||
                                  prevMsg['isOrderCancelled'] == true) {
                                checkpointId = prevMsg['docId'] as String?;
                                break;
                              }
                            }
                          }
                          
                          // Handle checkpoint messages (render as divider only)
                          if (messageType == 'checkpoint') {
                            final title = checkpointTitle ?? msg['title'] as String? ?? 'Checkpoint';
                            
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      height: 1,
                                      color: Colors.grey[800],
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    child: Text(
                                      title,
                                      style: TextStyle(
                                        color: Colors.grey[400],
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Container(
                                      height: 1,
                                      color: Colors.grey[800],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }

                          final prevUserId = reversedIdx > 0 ? allMessages[reversedIdx - 1]['userId'] as String? : null;
                          final isContinuation = prevUserId == userId;
                          final nextUserId = reversedIdx < allMessages.length - 1 ? allMessages[reversedIdx + 1]['userId'] as String? : null;
                          final isLastInGroup = nextUserId != userId;

                          final isShortMessage = messageText.length < 30;
                          // Grouped bubble shape: rounded on outer corners, tight on inner corners
                          final bool isFirst = !isContinuation; // first in group
                          final bool isLast = isLastInGroup;    // last in group
                          final double outerR = isShortMessage ? 24 : 16;
                          const double innerR = 4;
                          final borderRadius = isCurrentUser
                              ? BorderRadius.only(
                                  topLeft: Radius.circular(outerR),
                                  topRight: Radius.circular(isFirst ? outerR : innerR),
                                  bottomLeft: Radius.circular(outerR),
                                  bottomRight: Radius.circular(isLast ? outerR : innerR),
                                )
                              : BorderRadius.only(
                                  topLeft: Radius.circular(isFirst ? outerR : innerR),
                                  topRight: Radius.circular(outerR),
                                  bottomLeft: Radius.circular(isLast ? outerR : innerR),
                                  bottomRight: Radius.circular(outerR),
                                );

              // Check if this message's checkpoint is collapsed - hide non-checkpoint messages
              // Use the actual checkpointId (which may be inherited from first message for offers/quantity requests/service bookings/service orders)
              if (checkpointId != null && _collapsedCheckpoints.contains(checkpointId) && 
                  !isFirstMessage && !isOfferMessage && !isQuantityRequest && !isServiceBookingRequest && !isServiceOrderConfirmation && serviceDelivery == null && !isDisputeMessage) {
                return const SizedBox.shrink();
              }

              return KeyedSubtree(
                key: ValueKey(docId),
                child: RepaintBoundary(
              child: Column(
                              crossAxisAlignment: isCurrentUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                              children: [
                                // Show checkpoint divider ONLY for messages that START a new phase
                                // For the same product: first message, service delivery, and disputes get dividers
                                // Offers and quantity requests about the same product do NOT get separate dividers
                                if (isFirstMessage && productCard.isNotEmpty)
                                  _CheckpointDivider(
                                    key: ValueKey('checkpoint_$docId'),
                                    docId: docId,
                                    title: _checkpointTitleCache[docId] ?? checkpointTitle ?? _getShortTitle(productCard['title'] as String?),
                                    isCollapsed: _collapsedCheckpoints.contains(checkpointId ?? docId),
                                    onTap: () {
                                      setState(() {
                                        final id = checkpointId ?? docId;
                                        if (_collapsedCheckpoints.contains(id)) {
                                          _collapsedCheckpoints.remove(id);
                                        } else {
                                          _collapsedCheckpoints.add(id);
                                        }
                                      });
                                    },
                                    onTitleComputed: (title) {
                                      if (!_checkpointTitleCache.containsKey(docId)) {
                                        _checkpointTitleCache[docId] = title;
                                      }
                                    },
                                    messageProductId: messageProductId,
                                    productCard: productCard,
                                  )
                                else if (serviceDelivery != null)
                                  _CheckpointDivider(
                                    key: ValueKey('checkpoint_service_$docId'),
                                    docId: docId,
                                    title: checkpointTitle ?? 'Service: ${_getShortTitle(serviceDelivery['serviceTitle'] as String?)}',
                                    isCollapsed: _collapsedCheckpoints.contains(docId),
                                    onTap: () {
                                      setState(() {
                                        if (_collapsedCheckpoints.contains(docId)) {
                                          _collapsedCheckpoints.remove(docId);
                                        } else {
                                          _collapsedCheckpoints.add(docId);
                                        }
                                      });
                                    },
                                  )
                                else if (isDisputeMessage && disputeData != null)
                                  _CheckpointDivider(
                                    key: ValueKey('checkpoint_dispute_$docId'),
                                    docId: docId,
                                    title: checkpointTitle ?? I18n.t('dispute'),
                                    isCollapsed: _collapsedCheckpoints.contains(docId),
                                    onTap: () {
                                      setState(() {
                                        if (_collapsedCheckpoints.contains(docId)) {
                                          _collapsedCheckpoints.remove(docId);
                                        } else {
                                          _collapsedCheckpoints.add(docId);
                                        }
                                      });
                                    },
                                  ),
                                if (isOfferMessage && productCard.isNotEmpty)
                                  _collapsedCheckpoints.contains(checkpointId ?? docId)
                                      ? const SizedBox.shrink()
                                      : Padding(
                                      padding: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
                                      child: Container(
                                        margin: const EdgeInsets.symmetric(horizontal: 8),
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF242424),
                                          borderRadius: BorderRadius.circular(24),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(alpha: 0.25),
                                              blurRadius: 8,
                                              spreadRadius: 0.5,
                                            )
                                          ],
                                        ),
                                        child: FutureBuilder<Map<String, dynamic>?>(
                                          future: (offerId != null)
                                              ? SupabaseService.instance.offers
                                                  .select()
                                                  .eq('id', offerId)
                                                  .maybeSingle()
                                              : Future.value(null),
                                          builder: (context, snap) {
                                            final offerData = snap.data ?? {};
                                            // Use cached status for instant UI update, fallback to Supabase data
                                            var status = _offerStatusCache[offerId] ?? (offerData['status'] as String?) ?? 'pending';
                                            
                                            // Check if offer has expired
                                            if (status == 'pending' || status == 'accepted') {
                                              final expiresAt = offerData['expires_at'] as dynamic;
                                              if (expiresAt != null) {
                                                final expireTime = DateTime.tryParse(expiresAt.toString());
                                                if (expireTime != null && DateTime.now().isAfter(expireTime)) {
                                                  status = 'expired';
                                                }
                                              }
                                            }
                                            
                                            final buyerId = offerData['buyer_id'] as String? ?? '';
                                            final sellerId = offerData['seller_id'] as String? ?? '';
                                            final isViewerSeller = currentUser?.id == sellerId;
                                            final isViewerBuyer = currentUser?.id == buyerId;
                                            final offeredPrice = offerData['offered_price'] ?? offerData['offered'];
                                            
                                            return FutureBuilder<String?>(
                                              future: _getProductImage(messageProductId),
                                              builder: (context, imageSnapshot) {
                                                final imageUrl = imageSnapshot.data;
                                                
                                                return Stack(
                                                  children: [
                                                    Row(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        // Product image
                                                        ClipRRect(
                                                          borderRadius: BorderRadius.circular(10),
                                                          child: SizedBox(
                                                            width: 70,
                                                            height: 70,
                                                            child: imageUrl != null && imageUrl.isNotEmpty
                                                                ? Image.network(
                                                                    imageUrl,
                                                                    fit: BoxFit.cover,
                                                                    errorBuilder: (context, error, stackTrace) {
                                                                      return Image.asset(
                                                                        'assets/card_logos/noimage.png',
                                                                        fit: BoxFit.cover,
                                                                      );
                                                                    },
                                                                  )
                                                                : Image.asset(
                                                                    'assets/card_logos/noimage.png',
                                                                    fit: BoxFit.cover,
                                                                  ),
                                                          ),
                                                        ),
                                                        const SizedBox(width: 12),
                                                        // Product details
                                                        Expanded(
                                                          child: Column(
                                                            crossAxisAlignment: CrossAxisAlignment.start,
                                                            mainAxisSize: MainAxisSize.min,
                                                            children: [
                                                              Text(
                                                                productCard['title']?.toString() ?? 'Product',
                                                                style: const TextStyle(
                                                                  color: Colors.white,
                                                                  fontWeight: FontWeight.bold,
                                                                  fontSize: 13,
                                                                ),
                                                                maxLines: 2,
                                                                overflow: TextOverflow.ellipsis,
                                                              ),
                                                              const SizedBox(height: 4),
                                                              Text(
                                                                offeredPrice is num
                                                                    ? '${(offeredPrice).toStringAsFixed(0)} ${offerData['currency'] ?? productCard['currency'] ?? CurrencyService.current}'
                                                                    : (offeredPrice?.toString() ?? ''),
                                                                style: const TextStyle(
                                                                  color: Colors.white,
                                                                  fontWeight: FontWeight.bold,
                                                                  fontSize: 13,
                                                                ),
                                                              ),
                                                              const SizedBox(height: 4), // Minimal space
                                                            ],
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    // Buttons at bottom right - only show to seller for pending offers
                                                    if (status == 'pending' && isViewerSeller)
                                                      Positioned(
                                                        right: 0,
                                                        bottom: 0,
                                                        child: Row(
                                                          children: [
                                                            GestureDetector(
                                                              onTap: () async {
                                                                if (offerId == null) return;
                                                                // Optimistic UI update
                                                                setState(() {
                                                                  _offerStatusCache[offerId] = 'denied';
                                                                });
                                                                try {
                                                                  await SupabaseService.instance.offers.update({
                                                                    'status': 'denied',
                                                                    'denied_at': DateTime.now().toIso8601String(),
                                                                    'denied_by': currentUser?.id,
                                                                  }).eq('id', offerId);
                                                                } catch (e) {
                                                                  debugPrint('Error denying offer: $e');
                                                                  // Revert on error
                                                                  setState(() {
                                                                    _offerStatusCache.remove(offerId);
                                                                  });
                                                                }
                                                              },
                                                              child: Container(
                                                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                                                decoration: BoxDecoration(
                                                                  border: Border.all(color: Colors.red, width: 2),
                                                                  borderRadius: BorderRadius.circular(30),
                                                                ),
                                                                child: const Text(
                                                                  'Decline',
                                                                  style: TextStyle(fontSize: 12, color: Colors.red),
                                                                ),
                                                              ),
                                                            ),
                                                            const SizedBox(width: 8),
                                                            GestureDetector(
                                                              onTap: () async {
                                                                if (offerId == null) return;
                                                                // Optimistic UI update
                                                                setState(() {
                                                                  _offerStatusCache[offerId] = 'accepted';
                                                                });
                                                                try {
                                                                  await SupabaseService.instance.offers.update({
                                                                    'status': 'accepted',
                                                                    'accepted_at': DateTime.now().toIso8601String(),
                                                                    'accepted_by': currentUser?.id,
                                                                  }).eq('id', offerId);
                                                                  
                                                                  // Auto-add product to buyer's favorites
                                                                  try {
                                                                    final productId = offerData['product_id'] ?? productCard['id'] ?? widget.productId;
                                                                    if (productId != null && productId.toString().isNotEmpty) {
                                                                      // Get current favorites
                                                                      final userData = await SupabaseService.instance.users
                                                                          .select('favorites')
                                                                          .eq('id', buyerId)
                                                                          .maybeSingle();
                                                                      
                                                                      if (userData != null) {
                                                                        final favorites = List<String>.from(userData['favorites'] ?? []);
                                                                        if (!favorites.contains(productId)) {
                                                                          favorites.add(productId);
                                                                          await SupabaseService.instance.users.update({
                                                                            'favorites': favorites,
                                                                          }).eq('id', buyerId);
                                                                        }
                                                                      }
                                                                    }
                                                                  } catch (e) {
                                                                    debugPrint('Error auto-adding product to buyer favorites: $e');
                                                                  }
                                                                } catch (e) {
                                                                  debugPrint('Error accepting offer: $e');
                                                                  // Revert on error
                                                                  setState(() {
                                                                    _offerStatusCache.remove(offerId);
                                                                  });
                                                                }
                                                              },
                                                              child: Container(
                                                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                                                decoration: BoxDecoration(
                                                                  border: Border.all(color: Colors.green, width: 2),
                                                                  borderRadius: BorderRadius.circular(30),
                                                                ),
                                                                child: const Text(
                                                                  'Accept',
                                                                  style: TextStyle(fontSize: 12, color: Colors.green),
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      )
                                                    else if (status == 'accepted')
                                                      Positioned(
                                                        right: 0,
                                                        bottom: 0,
                                                        child: Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                                          decoration: BoxDecoration(
                                                            border: Border.all(color: Colors.green, width: 2),
                                                            borderRadius: BorderRadius.circular(30),
                                                          ),
                                                          child: Text(
                                                            isViewerBuyer ? 'Buy Now' : 'Accepted',
                                                            style: const TextStyle(fontSize: 12, color: Colors.green),
                                                          ),
                                                        ),
                                                      )
                                                    else if (status == 'denied')
                                                      Positioned(
                                                        right: 0,
                                                        bottom: 0,
                                                        child: Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                                          decoration: BoxDecoration(
                                                            border: Border.all(color: Colors.red, width: 2),
                                                            borderRadius: BorderRadius.circular(30),
                                                          ),
                                                          child: const Text(
                                                            'Declined',
                                                            style: TextStyle(fontSize: 12, color: Colors.red),
                                                          ),
                                                        ),
                                                      )
                                                    else if (status == 'expired')
                                                      Positioned(
                                                        right: 0,
                                                        bottom: 0,
                                                        child: Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                                          decoration: BoxDecoration(
                                                            border: Border.all(color: Colors.grey, width: 2),
                                                            borderRadius: BorderRadius.circular(30),
                                                          ),
                                                          child: const Text(
                                                            'Expired',
                                                            style: TextStyle(fontSize: 12, color: Colors.grey),
                                                          ),
                                                        ),
                                                      ),
                                                  ],
                                                );
                                              },
                                            );
                                          },
                                        ),
                                      ),
                                    )
                                else if (isQuantityRequest)
                                  _collapsedCheckpoints.contains(docId)
                                      ? const SizedBox.shrink()
                                      : Padding(
                                      padding: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
                                      child: GestureDetector(
                                        onTap: () async {
                                          // Navigate to product detail page when card is tapped
                                          if (messageProductId.isNotEmpty) {
                                            try {
                                              // Fetch full product data from Supabase
                                              final productData = await SupabaseService.instance.products
                                                  .select()
                                                  .eq('id', messageProductId)
                                                  .maybeSingle();
                                              
                                              if (productData != null && mounted) {
                                                final fullProductData = Map<String, dynamic>.from(productData);
                                                fullProductData['id'] = messageProductId;
                                                
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (context) => ProductDetailPage(
                                                      product: fullProductData,
                                                    ),
                                                  ),
                                                );
                                              }
                                            } catch (e) {
                                              debugPrint('Error opening product: $e');
                                            }
                                          }
                                        },
                                        child: Container(
                                          margin: const EdgeInsets.symmetric(horizontal: 8),
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF242424),
                                            borderRadius: BorderRadius.circular(24),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withValues(alpha: 0.25),
                                                blurRadius: 8,
                                                spreadRadius: 0.5,
                                              )
                                            ],
                                          ),
                                          child: FutureBuilder<String?>(
                                            future: _getProductImage(messageProductId),
                                            builder: (context, imageSnapshot) {
                                              final imageUrl = imageSnapshot.data;
                                              
                                              return Stack(
                                                children: [
                                                  Row(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      // Product image
                                                      ClipRRect(
                                                        borderRadius: BorderRadius.circular(10),
                                                        child: SizedBox(
                                                          width: 70,
                                                          height: 70,
                                                          child: imageUrl != null && imageUrl.isNotEmpty
                                                              ? Image.network(
                                                                  imageUrl,
                                                                  fit: BoxFit.cover,
                                                                  errorBuilder: (context, error, stackTrace) {
                                                                    return Image.asset(
                                                                      'assets/card_logos/noimage.png',
                                                                      fit: BoxFit.cover,
                                                                    );
                                                                  },
                                                                )
                                                              : Image.asset(
                                                                  'assets/card_logos/noimage.png',
                                                                  fit: BoxFit.cover,
                                                                ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 12),
                                                      // Product details
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            Text(
                                                              productCard['title']?.toString() ?? 'Product',
                                                              style: const TextStyle(
                                                                color: Colors.white,
                                                                fontWeight: FontWeight.bold,
                                                                fontSize: 13,
                                                              ),
                                                              maxLines: 2,
                                                              overflow: TextOverflow.ellipsis,
                                                            ),
                                                            const SizedBox(height: 4),
                                                            // Show quantity requested
                                                            if (quantityRequested != null && quantityRequested > 1)
                                                              Padding(
                                                                padding: const EdgeInsets.only(bottom: 4),
                                                                child: Text(
                                                                  '${I18n.t('quantity')}: $quantityRequested ${I18n.t('quantity_units')}',
                                                                  style: TextStyle(
                                                                    color: Colors.grey[400],
                                                                    fontSize: 11,
                                                                  ),
                                                                ),
                                                              ),
                                                            Text(
                                                              _formatChatPrice(productCard),
                                                              style: const TextStyle(
                                                                color: Colors.white,
                                                                fontWeight: FontWeight.bold,
                                                                fontSize: 13,
                                                              ),
                                                            ),
                                                            const SizedBox(height: 4), // Minimal space
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  // Buttons at bottom right - seller can accept/decline, buyer sees "Waiting"
                                                  if (requestStatus == 'pending')
                                                    Builder(
                                                      builder: (context) {
                                                        // Check for cached status for instant UI update
                                                        final cachedStatus = _quantityRequestStatusCache[docId];
                                                        final displayStatus = cachedStatus ?? requestStatus;
                                                        
                                                        // If status changed via cache, show the new status
                                                        if (displayStatus == 'confirmed') {
                                                          return Positioned(
                                                            right: 0,
                                                            bottom: 0,
                                                            child: Container(
                                                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                                              decoration: BoxDecoration(
                                                                border: Border.all(color: Colors.green, width: 2),
                                                                borderRadius: BorderRadius.circular(30),
                                                              ),
                                                              child: const Text(
                                                                'Confirmed',
                                                                style: TextStyle(fontSize: 12, color: Colors.green),
                                                              ),
                                                            ),
                                                          );
                                                        }
                                                        
                                                        if (displayStatus == 'declined') {
                                                          return Positioned(
                                                            right: 0,
                                                            bottom: 0,
                                                            child: Container(
                                                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                                              decoration: BoxDecoration(
                                                                border: Border.all(color: Colors.red, width: 2),
                                                                borderRadius: BorderRadius.circular(30),
                                                              ),
                                                              child: const Text(
                                                                'Declined',
                                                                style: TextStyle(fontSize: 12, color: Colors.red),
                                                              ),
                                                            ),
                                                          );
                                                        }
                                                        
                                                        // Determine if current user is seller
                                                        // conversationId format: conv_sortedId1_sortedId2
                                                        final conversationParts = widget.conversationId.split('_');
                                                        if (conversationParts.length < 3) return const SizedBox.shrink();
                                                        
                                                        // Get seller from message sender (quantity request is sent by buyer)
                                                        final buyerId = msg['userId'] as String?;
                                                        final isBuyer = currentUser?.id == buyerId;
                                                        
                                                        // Buyer sees "Waiting" pill
                                                        if (isBuyer) {
                                                          return Positioned(
                                                            right: 0,
                                                            bottom: 0,
                                                            child: Container(
                                                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                                              decoration: BoxDecoration(
                                                                border: Border.all(color: Colors.orange, width: 2),
                                                                borderRadius: BorderRadius.circular(30),
                                                              ),
                                                              child: Text(
                                                                I18n.t('waiting'),
                                                                style: const TextStyle(fontSize: 12, color: Colors.orange),
                                                              ),
                                                            ),
                                                          );
                                                        }
                                                        
                                                        // Seller sees Accept/Decline buttons
                                                        return Positioned(
                                                          right: 0,
                                                          bottom: 0,
                                                          child: Row(
                                                            children: [
                                                              GestureDetector(
                                                                onTap: () async {
                                                                  // Optimistic UI update
                                                                  setState(() {
                                                                    _quantityRequestStatusCache[docId] = 'declined';
                                                                  });
                                                                  try {
                                                                    debugPrint('🔴 Declining quantity request: $docId');
                                                                    
                                                                    final result = await SupabaseService.instance.messages.update({
                                                                      'status': 'declined',
                                                                      'declined_at': DateTime.now().toIso8601String(),
                                                                    }).eq('id', docId).select();
                                                                    
                                                                    debugPrint('✅ Update result: $result');
                                                                    
                                                                    // Reload messages to get the updated status
                                                                    final response = await SupabaseService.instance.messages
                                                                        .select()
                                                                        .eq('conversation_id', widget.conversationId)
                                                                        .order('created_at', ascending: true);
                                                                    
                                                                    debugPrint('✅ Reloaded ${response.length} messages');
                                                                    
                                                                    if (mounted) {
                                                                      setState(() {
                                                                        _messages = List<Map<String, dynamic>>.from(response);
                                                                      });
                                                                    }
                                                                  } catch (e, stackTrace) {
                                                                    debugPrint('❌ Error declining: $e');
                                                                    debugPrint('Stack trace: $stackTrace');
                                                                    // Revert on error
                                                                    setState(() {
                                                                      _quantityRequestStatusCache.remove(docId);
                                                                    });
                                                                  }
                                                                },
                                                                child: Container(
                                                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                                                  decoration: BoxDecoration(
                                                                    border: Border.all(color: Colors.red, width: 2),
                                                                    borderRadius: BorderRadius.circular(30),
                                                                  ),
                                                                  child: const Text(
                                                                    'Decline',
                                                                    style: TextStyle(fontSize: 12, color: Colors.red),
                                                                  ),
                                                                ),
                                                              ),
                                                              const SizedBox(width: 8),
                                                              GestureDetector(
                                                                onTap: () async {
                                                                  // Optimistic UI update
                                                                  setState(() {
                                                                    _quantityRequestStatusCache[docId] = 'confirmed';
                                                                  });
                                                                  try {
                                                                    debugPrint('🟢 Confirming quantity request: $docId');
                                                                    
                                                                    final result = await SupabaseService.instance.messages.update({
                                                                      'status': 'confirmed',
                                                                      'confirmed_at': DateTime.now().toIso8601String(),
                                                                      'expires_at': DateTime.now().add(const Duration(hours: 3)).toIso8601String(), // 3-hour expiry
                                                                    }).eq('id', docId).select();
                                                                    
                                                                    debugPrint('✅ Update result: $result');
                                                                    
                                                                    // Reload messages to get the updated status
                                                                    final response = await SupabaseService.instance.messages
                                                                        .select()
                                                                        .eq('conversation_id', widget.conversationId)
                                                                        .order('created_at', ascending: true);
                                                                    
                                                                    debugPrint('✅ Reloaded ${response.length} messages');
                                                                    
                                                                    if (mounted) {
                                                                      setState(() {
                                                                        _messages = List<Map<String, dynamic>>.from(response);
                                                                      });
                                                                    }
                                                                  } catch (e, stackTrace) {
                                                                    debugPrint('❌ Error confirming: $e');
                                                                    debugPrint('Stack trace: $stackTrace');
                                                                    // Revert on error
                                                                    setState(() {
                                                                      _quantityRequestStatusCache.remove(docId);
                                                                    });
                                                                  }
                                                                },
                                                                child: Container(
                                                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                                                  decoration: BoxDecoration(
                                                                    border: Border.all(color: Colors.green, width: 2),
                                                                    borderRadius: BorderRadius.circular(30),
                                                                  ),
                                                                  child: const Text(
                                                                    'Confirm',
                                                                    style: TextStyle(fontSize: 12, color: Colors.green),
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        );
                                                      },
                                                    )
                                                  else if (requestStatus == 'confirmed')
                                                    Positioned(
                                                      right: 0,
                                                      bottom: 0,
                                                      child: Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                                        decoration: BoxDecoration(
                                                          border: Border.all(color: Colors.green, width: 2),
                                                          borderRadius: BorderRadius.circular(30),
                                                        ),
                                                        child: const Text(
                                                          'Confirmed',
                                                          style: TextStyle(fontSize: 12, color: Colors.green),
                                                        ),
                                                      ),
                                                    )
                                                  else if (requestStatus == 'declined')
                                                    Positioned(
                                                      right: 0,
                                                      bottom: 0,
                                                      child: Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                                        decoration: BoxDecoration(
                                                          border: Border.all(color: Colors.red, width: 2),
                                                          borderRadius: BorderRadius.circular(30),
                                                        ),
                                                        child: const Text(
                                                          'Declined',
                                                          style: TextStyle(fontSize: 12, color: Colors.red),
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                    )
                                else if (isServiceBookingRequest)
                                  Builder(
                                    builder: (context) {
                                      debugPrint('🎯 SERVICE BOOKING REQUEST DETECTED:');
                                      debugPrint('   docId: $docId');
                                      debugPrint('   status: $requestStatus');
                                      debugPrint('   isServiceBookingRequest: $isServiceBookingRequest');
                                      debugPrint('   collapsed: ${_collapsedCheckpoints.contains(docId)}');
                                      
                                      return _collapsedCheckpoints.contains(docId)
                                          ? const SizedBox.shrink()
                                          : Padding(
                                              padding: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
                                              child: _buildServiceBookingConfirmationCard(msg, docId, currentUser),
                                            );
                                    },
                                  )
                                else if (msg['isServiceOrderConfirmation'] == true)
                                  _collapsedCheckpoints.contains(checkpointId ?? docId)
                                      ? const SizedBox.shrink()
                                      : Padding(
                                        padding: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
                                        child: _buildServiceOrderConfirmationCard(
                                          msg, 
                                          currentUser,
                                          onUpdate: () async {
                                            await _loadPendingServiceOrders();
                                            if (mounted) {
                                              _rebuildPreparedMessages();
                                              setState(() {});
                                            }
                                          },
                                        ),
                                      )
                                else if (isFirstMessage && productCard.isNotEmpty && !isContactCard)
                                  _collapsedCheckpoints.contains(docId)
                                      ? const SizedBox.shrink()
                                      : Padding(
                                      padding: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
                                      child: _buildChatProductCard(productCard, messageProductId),
                                    )
                                else if (serviceDelivery != null)
                                  _collapsedCheckpoints.contains(docId)
                                      ? const SizedBox.shrink()
                                      : Padding(
                                      padding: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
                                      child: _buildServiceDeliveryCard(serviceDelivery, context),
                                    )
                                else if (isDisputeMessage && disputeData != null)
                                  _collapsedCheckpoints.contains(docId)
                                      ? const SizedBox.shrink()
                                      : Padding(
                                      padding: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
                                      child: _buildDisputeCard(disputeData, context),
                                    )
                                else if (isOrderCancelled && orderCancelledData != null)
                                  _collapsedCheckpoints.contains(docId)
                                      ? const SizedBox.shrink()
                                      : Padding(
                                      padding: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
                                      child: _buildOrderCancelledCard(orderCancelledData),
                                    ),
                                // Contact card
                                if (isContactCard && contactCard != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
                                    child: _buildContactCard(contactCard),
                                  ),
                                // Hide regular messages when checkpoint is collapsed OR if this is a service delivery message OR dispute message OR quantity request OR service booking request OR service order confirmation
                                if (!isOfferMessage && !isQuantityRequest && !isServiceBookingRequest && !isServiceOrderConfirmation && serviceDelivery == null && !isDisputeMessage && !isOrderCancelled && !isContactCard && !(checkpointId != null && _collapsedCheckpoints.contains(checkpointId)))
                                  Container(
                                      margin: EdgeInsets.only(
                                        bottom: isContinuation && !isLastInGroup ? 2 : isLastInGroup ? 8 : 2,
                                        left: 0,
                                      ),
                                  child: Row(
                                    mainAxisAlignment: isCurrentUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Flexible(
                                        child: Column(
                                          crossAxisAlignment: isCurrentUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                          mainAxisAlignment: MainAxisAlignment.start,
                                          children: [
                                            // Image message
                                            if (messageType == 'image' && imageUrl != null)
                                              Column(
                                                crossAxisAlignment: isCurrentUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                                children: [
                                                  Padding(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                                    child: Stack(
                                                      children: [
                                                        ClipRRect(
                                                          borderRadius: BorderRadius.circular(16),
                                                          child: Container(
                                                            constraints: const BoxConstraints(
                                                              maxWidth: 250,
                                                              maxHeight: 300,
                                                            ),
                                                            child: Image.network(
                                                              imageUrl,
                                                              fit: BoxFit.cover,
                                                              loadingBuilder: (context, child, loadingProgress) {
                                                                if (loadingProgress == null) return child;
                                                                return Container(
                                                                  width: 250,
                                                                  height: 200,
                                                                  color: Colors.grey[800],
                                                                  child: Center(
                                                                    child: CircularProgressIndicator(
                                                                      value: loadingProgress.expectedTotalBytes != null
                                                                          ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                                                          : null,
                                                                    ),
                                                                  ),
                                                                );
                                                              },
                                                              errorBuilder: (context, error, stackTrace) {
                                                                return Container(
                                                                  width: 250,
                                                                  height: 200,
                                                                  color: Colors.grey[800],
                                                                  child: const Center(
                                                                    child: Icon(Icons.error, color: Colors.red),
                                                                  ),
                                                                );
                                                              },
                                                            ),
                                                          ),
                                                        ),
                                                        // Report button (only show if not current user's image)
                                                        if (!isCurrentUser)
                                                          Positioned(
                                                            top: 8,
                                                            right: 8,
                                                            child: GestureDetector(
                                                              onTap: () => _reportImage(docId, imageUrl, userId ?? ''),
                                                              child: Container(
                                                                padding: const EdgeInsets.all(6),
                                                                decoration: BoxDecoration(
                                                                  color: Colors.black.withValues(alpha: 0.6),
                                                                  shape: BoxShape.circle,
                                                                ),
                                                                child: const Icon(
                                                                  Icons.flag,
                                                                  color: Colors.white,
                                                                  size: 16,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                  // AI Analysis Note
                                                  if (imageReportStatus == 'analyzed' && imageReportAnalysis != null)
                                                    _buildImageReportNote(
                                                      imageReportAnalysis,
                                                      imageReporterId,
                                                      isCurrentUser,
                                                      currentUser?.id,
                                                    ),
                                                ],
                                              )
                                            // Text message
                                            else
                                              ConstrainedBox(
                                              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                                              child: isCurrentUser
                                                ? _ScreenGradientBubble(
                                                    gradientNotifier: _bubbleGradientNotifier,
                                                    scrollController: scrollController,
                                                    builder: (gradColors) {
                                                      final bubbleColor = gradColors.isNotEmpty ? gradColors.first : const Color(0xFF1B5E20);
                                                      return ClipRRect(
                                                        borderRadius: borderRadius,
                                                        child: Padding(
                                                          padding: const EdgeInsets.symmetric(horizontal: 8),
                                                          child: Container(
                                                            constraints: (isShortMessage && kIsWeb)
                                                                ? const BoxConstraints(minHeight: 40, maxHeight: 40)
                                                                : isShortMessage
                                                                    ? const BoxConstraints(minHeight: 40)
                                                                    : const BoxConstraints(),
                                                            padding: isShortMessage
                                                                ? const EdgeInsets.symmetric(horizontal: 14, vertical: 10)
                                                                : const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                                            decoration: BoxDecoration(
                                                              color: bubbleColor,
                                                              borderRadius: borderRadius,
                                                            ),
                                                            child: Row(
                                                              mainAxisSize: MainAxisSize.min,
                                                              crossAxisAlignment: CrossAxisAlignment.center,
                                                              children: [
                                                                Flexible(
                                                                  child: Text(
                                                                    messageText,
                                                                    maxLines: null,
                                                                    softWrap: true,
                                                                    style: const TextStyle(
                                                                      fontSize: 13,
                                                                      color: Colors.white,
                                                                      fontWeight: FontWeight.w600,
                                                                      letterSpacing: 0.3,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ),
                                                      );
                                                    },
                                                  )
                                                : ClipRRect(
                                              borderRadius: borderRadius,
                                              child: Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                                child: Container(
                                                constraints: (isShortMessage && kIsWeb)
                                                    ? const BoxConstraints(minHeight: 40, maxHeight: 40)
                                                    : isShortMessage
                                                        ? const BoxConstraints(minHeight: 40)
                                                        : const BoxConstraints(),
                                                padding: isShortMessage
                                                    ? const EdgeInsets.symmetric(horizontal: 14, vertical: 10)
                                                    : const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                                decoration: BoxDecoration(
                                                  color: Colors.white.withValues(alpha: 0.1),
                                                  borderRadius: borderRadius,
                                                ),
                                                child: Text(
                                                  messageText,
                                                  maxLines: null,
                                                  softWrap: true,
                                                  style: const TextStyle(
                                                    fontSize: 13,
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w600,
                                                    letterSpacing: 0.3,
                                                  ),
                                                ),
                                                ),
                                              ),
                                            ),
                                        )],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  }),
                ),
              ],
            ),
          ),
          // Input container fixed at bottom
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom > 0 ? 6 : 24,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 48),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 12,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.only(left: 16, top: 0, bottom: 0, right: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: messageController,
                            focusNode: _messageFocusNode,
                            keyboardAppearance: Brightness.dark,
                            decoration: InputDecoration(
                              hintText: I18n.t('type_message'),
                              hintStyle: const TextStyle(color: Colors.grey),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(vertical: 12),
                              filled: false,
                            ),
                            style: const TextStyle(color: Colors.white),
                            minLines: 1,
                            maxLines: 3,
                            textInputAction: TextInputAction.newline,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Image button (grey circle, left of send button)
                        GestureDetector(
                          onTap: () => _pickAndSendImage(),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.grey[850],
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: SvgPicture.asset('assets/icons/image.svg', width: 18, height: 18, colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextFieldTapRegion(
                        child: GestureDetector(
                            onTap: () {
                              final message = messageController.text.trim();
                              if (message.isEmpty) return;
                              final user = SupabaseService.instance.currentUser;
                              if (user == null) return;

                              // Behavior check
                              final violation = ChatBehaviorDetector.detectViolation(message);
                              if (violation != null) {
                                _applyTrustPenalty(user.id, violation);
                                if (mounted) {
                                  NotificationHelper.showNotification(
                                    context,
                                    '⚠️ ${violation.message} - Trust penalty: ${violation.trustPenalty}',
                                  );
                                }
                                messageController.clear();
                                return;
                              }

                              final text = message;
                              messageController.clear();

                              final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
                              final ts = DateTime.now().toIso8601String();

                              // Add optimistic message and rebuild
                              _messages = [
                                ..._messages,
                                <String, dynamic>{
                                  'id': tempId,
                                  'conversation_id': widget.conversationId,
                                  'sender_id': user.id,
                                  'content': text,
                                  'product_id': widget.productId,
                                  'created_at': ts,
                                  'profile_image_url': null,
                                  'sender_photo': null,
                                  'is_first_message': false,
                                  'is_offer_message': false,
                                  'is_quantity_request': false,
                                  'is_service_booking_request': false,
                                  'is_service_order_confirmation': false,
                                  'is_dispute_message': false,
                                  'offer_id': null,
                                  'offered_price': null,
                                  'currency': CurrencyService.current,
                                  'product_card': <String, dynamic>{},
                                  'quantity_requested': null,
                                  'status': null,
                                  'service_delivery': null,
                                  'dispute_data': null,
                                  'type': null,
                                  'checkpoint_title': null,
                                  'title': null,
                                  'image_url': null,
                                  'image_report_status': null,
                                  'image_report_analysis': null,
                                  'image_reporter_id': null,
                                  'order_id': null,
                                  'service_title': null,
                                  'service_price': null,
                                  'is_booking': false,
                                  'booking_date': null,
                                },
                              ];
                              _rebuildPreparedMessages();
                              setState(() {});

                              // Scroll to bottom after layout
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted && scrollController.hasClients) {
                                  scrollController.animateTo(
                                    0,
                                    duration: const Duration(milliseconds: 150),
                                    curve: Curves.easeOut,
                                  );
                                }
                              });

                              // Persist in background
                              _persistMessage(tempId, text, user.id, ts);
                            },
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: const BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                            ),
                            child: const Center(
                              child: Icon(Icons.send, color: Colors.white, size: 16),
                            ),
                          ),
                        ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Header bar fixed at top — transparent, floating over messages
          // Subtle fade so messages dissolve behind the status bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Container(
                height: MediaQuery.of(context).padding.top + 56,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFF0A0A0A),
                      Color(0xB30A0A0A),
                      Color(0x000A0A0A),
                    ],
                    stops: [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),
          ),
          // Header buttons on top of the gradient
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Padding(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 4,
                left: 16,
                right: 16,
              ),
              child: Row(
                children: [
                  // Back button — liquid glass + tilt
                  Transform(
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.001)
                      ..rotateY(-0.05)
                      ..rotateX(0.03),
                    alignment: Alignment.center,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: _LiquidGlass(
                        borderRadius: 50,
                        child: Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          child: SvgPicture.asset('assets/icons/back.svg', width: 22, height: 22, colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Username pill — liquid glass + tilt
                  Transform(
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.001)
                      ..rotateX(0.04),
                    alignment: Alignment.center,
                    child: _LiquidGlass(
                      borderRadius: 50,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        child: Text(
                          widget.otherUserName ?? _otherUserDisplayName ?? '',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Settings button — liquid glass + tilt
                  Transform(
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.001)
                      ..rotateY(0.05)
                      ..rotateX(0.03),
                    alignment: Alignment.center,
                    child: GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatSettingsPage(
                              otherUserId: widget.otherUserId,
                              otherUserName: widget.otherUserName ?? _otherUserDisplayName,
                              otherUserPhoto: widget.otherUserPhoto,
                              conversationId: widget.conversationId,
                            ),
                          ),
                        );
                      },
                      child: _LiquidGlass(
                        borderRadius: 50,
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: ClipOval(
                              child: widget.otherUserPhoto != null && widget.otherUserPhoto!.isNotEmpty
                                  ? Image.network(
                                      widget.otherUserPhoto!,
                                      width: 40,
                                      height: 40,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Image.asset('assets/card_logos/noimage.png', width: 40, height: 40, fit: BoxFit.cover),
                                    )
                                  : Image.asset('assets/card_logos/noimage.png', width: 40, height: 40, fit: BoxFit.cover),
                            ),
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
    );
  }

  Widget _buildChatProductCard(Map<String, dynamic> productCard, String productId, [bool allowTap = true]) {
    try {
      final title = productCard['title'] as String? ?? 'Untitled';
      
      // Check cache first
      if (_productCardCache.containsKey(productId)) {
        final cachedData = _productCardCache[productId]!;
        final collection = cachedData['_collection'] as String? ?? 'products';
        String? imageUrl;
        
        if (collection == 'services' || collection == 'gigs') {
          imageUrl = ImageHelper.getServiceCardImage(cachedData);
        } else {
          imageUrl = ImageHelper.getProductCardImage(cachedData);
        }
        
        dynamic displayPrice = productCard['price'];
        if (cachedData['priceNegotiable'] == true || cachedData['price_negotiable'] == true) {
          displayPrice = I18n.t('negotiable');
        } else if (cachedData['price'] != null) {
          displayPrice = cachedData['price'];
          if (displayPrice is num && displayPrice == 0) displayPrice = I18n.t('negotiable');
        }
        
        final updatedProductCard = {
          ...productCard,
          'price': displayPrice,
        };
        
        return _buildChatCardUI(title, updatedProductCard, productId, imageUrl, allowTap, collection);
      }
      
      // Try fetching from all collections to find where this item exists
      return FutureBuilder<Map<String, dynamic>?>(
        future: _fetchItemFromAnyCollection(productId),
        builder: (context, snapshot) {
          String? imageUrl;
          String collection = 'products'; // default
          Map<String, dynamic>? itemData;
          dynamic displayPrice = productCard['price']; // default to stored price
          
          if (snapshot.hasData && snapshot.data != null) {
            itemData = snapshot.data!;
            collection = itemData['_collection'] as String? ?? 'products';
            
            // Cache the result
            _productCardCache[productId] = itemData;
            
            // Use ImageHelper to get the best image based on collection type
            if (collection == 'services' || collection == 'gigs') {
              imageUrl = ImageHelper.getServiceCardImage(itemData);
            } else {
              imageUrl = ImageHelper.getProductCardImage(itemData);
            }
            
            // Handle price - check if negotiable
            if (itemData['priceNegotiable'] == true || itemData['price_negotiable'] == true) {
              displayPrice = I18n.t('negotiable');
            } else if (itemData['price'] != null) {
              displayPrice = itemData['price'];
              if (displayPrice is num && displayPrice == 0) displayPrice = I18n.t('negotiable');
            }
            
            debugPrint('Chat card using image: $imageUrl for $collection $productId, price: $displayPrice');
          }
          
          // Create updated productCard with correct price
          final updatedProductCard = {
            ...productCard,
            'price': displayPrice,
          };
          
          return _buildChatCardUI(title, updatedProductCard, productId, imageUrl, allowTap, collection);
        },
      );
    } catch (e) {
      debugPrint('Error building product card: $e');
      const double cardWidth = 170.0;
      const double cardHeight = 170.0;
      
      return Container(
        width: cardWidth,
        height: cardHeight,
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          border: Border(
            bottom: BorderSide(
              color: Colors.white.withValues(alpha: 0.1),
              width: 1,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 12,
              spreadRadius: 1,
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 30,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24), bottom: Radius.circular(24)),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                  ),
                  child: Center(
                    child: SvgPicture.asset('assets/icons/products.svg', width: 48, height: 48, colorFilter: ColorFilter.mode(Colors.grey.shade400, BlendMode.srcIn)),
                  ),
                ),
              ),
            ),
            const Expanded(
              flex: 4,
              child: Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'Product',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildChatCardUI(String title, Map<String, dynamic> productCard, String productId, String? imageUrl, bool allowTap, [String collection = 'products']) {
    const double cardWidth = 170.0;
    const double cardHeight = 170.0;
    
    return GestureDetector(
      onTap: allowTap
          ? () async {
              try {
                final itemData = await SupabaseService.instance.client
                    .from(collection)
                    .select()
                    .eq('id', productId)
                    .maybeSingle();
                
                if (itemData != null && mounted) {
                  final fullItemData = Map<String, dynamic>.from(itemData);
                  final itemWithId = {...fullItemData, 'id': productId, 'currency': fullItemData['currency'] ?? 'RON'};
                  
                  // Navigate to appropriate detail page based on collection
                  if (collection == 'services') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ServiceDetailPage(service: itemWithId),
                      ),
                    );
                  } else if (collection == 'gigs') {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => GigDetailPage(gig: itemWithId),
                      ),
                    );
                    // Note: Chat page doesn't need to refresh on deletion
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ProductDetailPage(product: itemWithId),
                      ),
                    );
                  }
                }
              } catch (e) {
                debugPrint('Error fetching full item data: $e');
                if (mounted) {
                  final itemWithCurrency = {...productCard, 'currency': productCard['currency'] ?? CurrencyService.current};
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ProductDetailPage(product: itemWithCurrency),
                    ),
                  );
                }
              }
            }
          : null,
        child: Container(
          width: cardWidth,
          height: cardHeight,
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(24),
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withValues(alpha: 0.1),
                width: 1,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 12,
                spreadRadius: 1,
              )
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 30,
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(24), bottom: Radius.circular(24)),
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.grey[800],
                        ),
                        child: (imageUrl != null && imageUrl.isNotEmpty)
                            ? Image.network(
                                imageUrl,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                                alignment: Alignment.center,
                                frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                                  if (wasSynchronouslyLoaded || frame != null) {
                                    return child;
                                  }
                                  // Show placeholder while loading
                                  return Container(
                                    color: Colors.grey[800],
                                    child: Center(
                                      child: SvgPicture.asset('assets/icons/products.svg', width: 48, height: 48, colorFilter: ColorFilter.mode(Colors.grey.shade400, BlendMode.srcIn)),
                                    ),
                                  );
                                },
                                errorBuilder: (context, error, stackTrace) {
                                  return Center(
                                    child: SvgPicture.asset('assets/icons/products.svg', width: 48, height: 48, colorFilter: ColorFilter.mode(Colors.grey.shade400, BlendMode.srcIn)),
                                  );
                                },
                                gaplessPlayback: false,
                              )
                            : Center(
                                child: SvgPicture.asset('assets/icons/products.svg', width: 48, height: 48, colorFilter: ColorFilter.mode(Colors.grey.shade400, BlendMode.srcIn)),
                              ),
                      ),
                    ),
                    // Price pill at top center
                    Positioned(
                      top: 5,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
                          child: Text(
                            _formatChatPrice(productCard),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 4,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildServiceDeliveryCard(Map<String, dynamic> serviceDelivery, BuildContext context) {
    final orderId = serviceDelivery['orderId'] as String?;
    final serviceTitle = serviceDelivery['serviceTitle'] as String? ?? 'Service';
    final isExternalLink = serviceDelivery['isExternalLink'] as bool? ?? false;
    final fileCount = serviceDelivery['fileCount'] as int? ?? 0;

    return FutureBuilder<String?>(
      future: _getServiceImage(orderId),
      builder: (context, snapshot) {
        final imageUrl = snapshot.data;
        
        return GestureDetector(
          onTap: () {
            if (orderId != null) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ServiceDeliveryPage(
                    orderId: orderId,
                    serviceTitle: serviceTitle,
                  ),
                ),
              );
            }
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            decoration: BoxDecoration(
              color: const Color(0xFF242424),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 8,
                  spreadRadius: 0.5,
                ),
              ],
            ),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status indicator
                    Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green.shade600, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          'Service Delivered',
                          style: TextStyle(color: Colors.grey[400], fontSize: 11),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 70,
                            height: 70,
                            child: imageUrl != null && imageUrl.isNotEmpty
                                ? Image.network(
                                    imageUrl,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    height: double.infinity,
                                    frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                                      if (wasSynchronouslyLoaded || frame != null) {
                                        return child;
                                      }
                                      return Container(
                                        color: Colors.grey[800],
                                        child: const Icon(
                                          Icons.home_repair_service,
                                          color: Colors.white54,
                                          size: 30,
                                        ),
                                      );
                                    },
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        color: Colors.grey[800],
                                        child: const Icon(
                                          Icons.home_repair_service,
                                          color: Colors.white54,
                                          size: 30,
                                        ),
                                      );
                                    },
                                    gaplessPlayback: false,
                                  )
                                : Container(
                                    color: Colors.grey[800],
                                    child: const Icon(
                                      Icons.home_repair_service,
                                      color: Colors.white54,
                                      size: 30,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                serviceTitle,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    isExternalLink ? Icons.link : Icons.folder,
                                    color: Colors.grey[400],
                                    size: 12,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isExternalLink ? 'External link' : '$fileCount file${fileCount != 1 ? 's' : ''}',
                                    style: TextStyle(
                                      color: Colors.grey[400],
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                // View Files button positioned at bottom right
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.green.shade600, width: 2),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: const Text(
                      'View Files',
                      style: TextStyle(fontSize: 12, color: Colors.green),
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

  /// Build contact info card sent by gig owner
  Widget _buildContactCard(Map<String, dynamic> contactCard) {
    final name = contactCard['name'] as String? ?? 'User';
    final phone = contactCard['phone'] as String? ?? '';
    final email = contactCard['email'] as String? ?? '';
    final imageUrl = contactCard['image_url'] as String?;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF242424),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 8,
            spreadRadius: 0.5,
          ),
        ],
      ),
      child: Row(
        children: [
          // Gig image
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 56,
              height: 56,
              child: imageUrl != null && imageUrl.isNotEmpty
                  ? Image.network(imageUrl, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.grey[800],
                        child: const Icon(Icons.image, color: Colors.grey, size: 24),
                      ),
                    )
                  : Container(
                      color: Colors.grey[800],
                      child: const Icon(Icons.image, color: Colors.grey, size: 24),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          // Name, phone, email
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.phone_outlined, color: Colors.grey[500], size: 13),
                    const SizedBox(width: 4),
                    Text(
                      phone.isNotEmpty ? phone : 'No phone',
                      style: TextStyle(
                        color: phone.isNotEmpty ? Colors.grey[300] : Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.email_outlined, color: Colors.grey[500], size: 13),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        email.isNotEmpty ? email : 'No email',
                        style: TextStyle(
                          color: email.isNotEmpty ? Colors.grey[300] : Colors.grey[600],
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Call button
          if (phone.isNotEmpty)
            GestureDetector(
              onTap: () => _launchPhone(phone),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.call, color: Colors.green, size: 22),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _launchPhone(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      await launchUrl(uri);
    } catch (e) {
      debugPrint('Could not launch phone: $e');
    }
  }

  /// Build dispute card (styled like service delivery card)
  Widget _buildDisputeCard(Map<String, dynamic> disputeData, BuildContext context) {
    final orderId = disputeData['orderId'] ?? disputeData['order_id'] as String?;
    final inlineTitle = disputeData['product_title'] ?? disputeData['productTitle'] ?? '';
    final inlineImage = disputeData['product_image'] ?? disputeData['productImage'];

    return FutureBuilder<Map<String, dynamic>?>(
      future: orderId != null
          ? SupabaseService.instance.disputes
              .select()
              .eq('order_id', orderId)
              .limit(1)
              .maybeSingle()
          : Future.value(null),
      builder: (context, snapshot) {
        final dispute = snapshot.data;
        final productTitle = (dispute?['product_title'] ?? inlineTitle).toString();
        final productImage = (dispute?['product_image'] ?? inlineImage)?.toString() ?? '';
        
        // Compute time remaining
        String timeText = '';
        final createdAtStr = dispute?['created_at'] as String?;
        final disputeStatus = dispute?['status'] as String?;
        if (createdAtStr != null && (disputeStatus == 'pending_seller_response' || disputeStatus == 'under_review' || disputeStatus == 'ai_analyzing')) {
          final createdAt = DateTime.tryParse(createdAtStr);
          if (createdAt != null) {
            final deadline = createdAt.add(const Duration(hours: 48));
            final timeRemaining = deadline.difference(DateTime.now());
            if (timeRemaining.isNegative) {
              timeText = I18n.t('expired');
            } else if (timeRemaining.inHours > 0) {
              timeText = '${timeRemaining.inHours}h ${timeRemaining.inMinutes % 60}m';
            } else {
              timeText = '${timeRemaining.inMinutes}m';
            }
          }
        }

    return GestureDetector(
      onTap: () async {
        if (orderId == null) return;
        
        final currentUser = SupabaseService.instance.currentUser;
        if (currentUser == null) return;
        
        try {
          final disputeDoc = dispute ?? await SupabaseService.instance.disputes
              .select()
              .eq('order_id', orderId)
              .limit(1)
              .maybeSingle();

          if (disputeDoc == null) return;

          final fullDisputeData = Map<String, dynamic>.from(disputeDoc);
          final disputeId = disputeDoc['id'] as String;

          final orderData = await SupabaseService.instance.orders
              .select()
              .eq('id', orderId)
              .maybeSingle();

          if (orderData == null) return;

          final buyerId = fullDisputeData['buyer_id'] as String?;
          final isBuyer = currentUser.id == buyerId;
          
          if (isBuyer) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => OrderDetailPage(
                  orderId: orderId,
                  orderData: orderData,
                ),
              ),
            );
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DisputeResponsePage(
                  disputeId: disputeId,
                  disputeData: fullDisputeData,
                  orderData: orderData,
                ),
              ),
            );
          }
        } catch (e) {
          debugPrint('Error opening dispute: $e');
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        decoration: BoxDecoration(
          color: const Color(0xFF242424),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 8,
              spreadRadius: 0.5,
            ),
          ],
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Product image
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 70,
                        height: 70,
                        child: productImage.isNotEmpty
                            ? Image.network(
                                productImage,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                                frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                                  if (wasSynchronouslyLoaded || frame != null) return child;
                                  return Container(
                                    color: Colors.grey[800],
                                    child: const Icon(Icons.image, color: Colors.white54, size: 30),
                                  );
                                },
                                errorBuilder: (_, __, ___) => Container(
                                  color: Colors.grey[800],
                                  child: const Icon(Icons.image, color: Colors.white54, size: 30),
                                ),
                              )
                            : Container(
                                color: Colors.grey[800],
                                child: const Icon(Icons.image, color: Colors.white54, size: 30),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            I18n.t('problem_found'),
                            style: TextStyle(
                              color: Colors.red[300],
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (productTitle.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              productTitle,
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          if (timeText.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              timeText,
                              style: TextStyle(color: Colors.grey[500], fontSize: 11),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            // View button at bottom right
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.red.shade400, width: 2),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text(
                  I18n.t('view'),
                  style: TextStyle(fontSize: 12, color: Colors.red[300]),
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

  /// Build order cancelled card for chat
  Widget _buildOrderCancelledCard(Map<String, dynamic> cancelledData) {
    final productTitle = cancelledData['product_title'] ?? I18n.t('untitled');
    final orderId = cancelledData['order_id'] as String?;
    final currentUser = SupabaseService.instance.currentUser;
    // Buyer is whoever is NOT the seller; seller_id comes from the cancelled data or we check the order
    final sellerId = cancelledData['seller_id'] as String?;
    final isBuyer = currentUser != null && sellerId != null && currentUser.id != sellerId;

    return _OrderCancelledCard(
      productTitle: productTitle,
      orderId: orderId,
      isBuyer: isBuyer,
    );
  }

  /// Get product image (hover thumbnail preferred) — cached to avoid DB hits on every build
  Future<String?> _getProductImage(String? productId) async {
    if (productId == null) return null;
    
    // Return from cache if available
    if (_productImageCacheStatic.containsKey(productId)) {
      return _productImageCacheStatic[productId];
    }
    
    // Deduplicate in-flight requests
    if (_productImageFuturesStatic.containsKey(productId)) {
      return _productImageFuturesStatic[productId]!;
    }
    
    final future = () async {
      try {
        final productData = await SupabaseService.instance.products
            .select()
            .eq('id', productId)
            .maybeSingle();
        
        if (productData == null) {
          _productImageCacheStatic[productId] = null;
          return null;
        }
        
        final url = ImageHelper.getProductCardImage(productData);
        _productImageCacheStatic[productId] = url;
        return url;
      } catch (e) {
        debugPrint('Error fetching product image: $e');
        _productImageCacheStatic[productId] = null;
        return null;
      } finally {
        _productImageFuturesStatic.remove(productId);
      }
    }();
    
    _productImageFuturesStatic[productId] = future;
    return future;
  }

  /// Fetch item from products, services, or gigs collection
  Future<Map<String, dynamic>?> _fetchItemFromAnyCollection(String itemId) async {
    try {
      // Try products first (most common)
      var data = await SupabaseService.instance.products
          .select()
          .eq('id', itemId)
          .maybeSingle();
      
      if (data != null) {
        return {...data, '_collection': 'products'};
      }
      
      // Try services
      data = await SupabaseService.instance.services
          .select()
          .eq('id', itemId)
          .maybeSingle();
      
      if (data != null) {
        return {...data, '_collection': 'services'};
      }
      
      // Try gigs
      data = await SupabaseService.instance.gigs
          .select()
          .eq('id', itemId)
          .maybeSingle();
      
      if (data != null) {
        return {...data, '_collection': 'gigs'};
      }
      
      return null;
    } catch (e) {
      debugPrint('Error fetching item from collections: $e');
      return null;
    }
  }

  /// Build service booking confirmation card (for both services and bookings)
  Widget _buildServiceBookingConfirmationCard(Map<String, dynamic> msg, String docId, User? currentUser) {
    final productCard = msg['product_card'] as Map<String, dynamic>? ?? {};
    final serviceTitle = productCard['title'] ?? 'Service';
    final servicePrice = msg['service_price'] ?? productCard['price'];
    final currency = msg['currency'] ?? productCard['currency'] ?? 'RON';
    final status = msg['status'] as String? ?? 'pending';
    final serviceOrderId = msg['service_order_id'] as String?;
    final bookingId = msg['booking_id'] as String?;
    final orderId = serviceOrderId ?? bookingId;
    
    // Determine type from product_card or message fields
    final cardType = productCard['type'] as String?;
    final isBooking = cardType == 'booking' || bookingId != null;
    final bookingDate = msg['booking_date'] as String?;
    
    // Get conversation ID to determine seller
    final conversationId = msg['conversation_id'] as String?;
    
    // Determine if current user is the seller
    // The sender is the buyer, so seller is the other participant
    bool isViewerSeller = false;
    if (conversationId != null && currentUser != null) {
      final parts = conversationId.split('_');
      if (parts.length >= 2) {
        final sellerId = parts[1];
        isViewerSeller = currentUser.id == sellerId;
      }
    }
    
    // Determine display text based on type
    final typeLabel = isBooking ? 'Booking' : 'Service';
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF242424),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 8,
            spreadRadius: 0.5,
          )
        ],
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Type badge (Booking or Service)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isBooking ? Colors.blue.withValues(alpha: 0.2) : Colors.green.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isBooking ? Colors.blue : Colors.green,
                    width: 1,
                  ),
                ),
                child: Text(
                  typeLabel,
                  style: TextStyle(
                    color: isBooking ? Colors.blue : Colors.green,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                serviceTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                (servicePrice is num && servicePrice == 0) || servicePrice == null || servicePrice == 'negotiable'
                    ? I18n.t('negotiable')
                    : '${servicePrice is num ? servicePrice.toStringAsFixed(0) : servicePrice} $currency',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              // Show booking date if it's a booking
              if (isBooking && bookingDate != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Date: ${_formatBookingDate(bookingDate)}',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 11,
                  ),
                ),
              ],
              const SizedBox(height: 4),
            ],
          ),
          // Buttons at bottom right - only show to seller for pending requests
          if (status == 'pending' && isViewerSeller)
            Positioned(
              right: 0,
              bottom: 0,
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () async {
                      if (orderId == null) return;
                      
                      try {
                        // Call refund function
                        final callable = FirebaseFunctions.instance.httpsCallable('refundServiceBooking');
                        await callable.call({
                          'orderId': orderId,
                          'isBooking': isBooking,
                        });
                        
                        // Update message status
                        await SupabaseService.instance.messages
                            .update({'status': 'declined'})
                            .eq('id', docId);
                        
                        // Real-time subscription will automatically reload pending orders
                      } catch (e) {
                        debugPrint('Error declining booking: $e');
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.red, width: 2),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: const Text(
                        'Decline',
                        style: TextStyle(fontSize: 12, color: Colors.red),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () async {
                      if (orderId == null) return;
                      
                      try {
                        // Update order status to confirmed
                        final collectionName = isBooking ? 'bookings' : 'service_orders';
                        await SupabaseService.instance.client
                            .from(collectionName)
                            .update({'status': isBooking ? 'booked' : 'confirmed'})
                            .eq('id', orderId);
                        
                        // Update message status
                        await SupabaseService.instance.messages
                            .update({'status': isBooking ? 'booked' : 'confirmed'})
                            .eq('id', docId);
                        
                        // Real-time subscription will automatically reload pending orders
                      } catch (e) {
                        debugPrint('Error confirming booking: $e');
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.green, width: 2),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: const Text(
                        'Accept',
                        style: TextStyle(fontSize: 12, color: Colors.green),
                      ),
                    ),
                  ),
                ],
              ),
            )
          // Show status badge to both buyer and seller for confirmed/declined
          else if (status == 'confirmed' || status == 'booked' || status == 'to_do')
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.green, width: 2),
                  borderRadius: BorderRadius.circular(30),
                  color: Colors.green.withValues(alpha: 0.1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      isViewerSeller ? 'Accepted' : 'Confirmed',
                      style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            )
          else if (status == 'declined')
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.red, width: 2),
                  borderRadius: BorderRadius.circular(30),
                  color: Colors.red.withValues(alpha: 0.1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cancel, color: Colors.red, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      isViewerSeller ? 'Declined' : 'Rejected',
                      style: const TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            )
          // Show "Pending" status to buyer while waiting for seller response
          else if (status == 'pending' && !isViewerSeller)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.orange, width: 2),
                  borderRadius: BorderRadius.circular(30),
                  color: Colors.orange.withValues(alpha: 0.1),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                      ),
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Pending',
                      style: TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Build service order confirmation card from direct query (simpler version)
  Widget _buildServiceOrderConfirmationCard(
    Map<String, dynamic> order, 
    User? currentUser,
    {required Future<void> Function() onUpdate}
  ) {
    // Extract buyer name and address from order data - try both formats
    final buyerName = order['buyer_name'] ?? order['buyerName'] as String?;
    final buyerAddress = order['buyer_address'] ?? order['buyerAddress'] as String?;
    
    debugPrint('🎴 Building confirmation card - buyerName: $buyerName, buyerAddress: $buyerAddress');
    
    return _ServiceOrderConfirmationCard(
      order: order,
      currentUser: currentUser,
      onUpdate: onUpdate,
      buyerName: buyerName,
      buyerAddress: buyerAddress,
    );
  }

  /// Get service image URL
  Future<String?> _getServiceImage(String? serviceId) async {
    if (serviceId == null || serviceId.isEmpty) return null;
    
    try {
      final service = await SupabaseService.instance.services
          .select('image_url')
          .eq('id', serviceId)
          .maybeSingle();
      
      return service?['image_url'] as String?;
    } catch (e) {
      debugPrint('Error fetching service image: $e');
      return null;
    }
  }

  /// Format booking date for display
  String _formatBookingDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${months[date.month - 1]} ${date.day}, ${date.year}';
    } catch (e) {
      return dateStr;
    }
  }


/// Separate stateful widget for service order confirmation card
class _ServiceOrderConfirmationCard extends StatefulWidget {
  final Map<String, dynamic> order;
  final User? currentUser;
  final Future<void> Function() onUpdate;
  final String? buyerName;
  final String? buyerAddress;

  const _ServiceOrderConfirmationCard({
    required this.order,
    required this.currentUser,
    required this.onUpdate,
    this.buyerName,
    this.buyerAddress,
  });

  @override
  State<_ServiceOrderConfirmationCard> createState() => _ServiceOrderConfirmationCardState();
}

class _ServiceOrderConfirmationCardState extends State<_ServiceOrderConfirmationCard> {
  late TextEditingController _notesController;
  int? _selectedStartHour;
  int? _selectedEndHour;

  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  /// Show hour range picker modal
  Future<void> _selectHourRange(BuildContext context) async {
    int? tempStartHour = _selectedStartHour;
    int? tempEndHour = _selectedEndHour;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            contentPadding: const EdgeInsets.all(16),
            actionsPadding: const EdgeInsets.only(right: 8, bottom: 8),
            content: SizedBox(
              width: 300,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Instructions
                  Text(
                    'Tap to select start hour, tap again for end hour',
                    style: TextStyle(color: Colors.grey[400], fontSize: 11),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  // Hour grid (5 AM to midnight)
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      childAspectRatio: 1.8,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: 20, // 5 AM to midnight (00:00) = 20 hours
                    itemBuilder: (context, index) {
                      final hour = (index + 5) % 24; // Start from 5 AM, wrap to 0 for midnight
                      bool isInRange = false;
                      
                      if (tempStartHour != null && tempEndHour != null) {
                        isInRange = hour >= tempStartHour! && hour <= tempEndHour!;
                      } else if (tempStartHour != null && tempEndHour == null) {
                        isInRange = hour == tempStartHour;
                      }

                      return GestureDetector(
                        onTap: () {
                          setDialogState(() {
                            if (tempStartHour == null) {
                              // First tap - set start hour
                              tempStartHour = hour;
                              tempEndHour = null;
                            } else if (tempEndHour == null) {
                              // Second tap - set end hour
                              if (hour > tempStartHour!) {
                                tempEndHour = hour;
                              } else if (hour == tempStartHour) {
                                // Same hour clicked - 1 hour booking
                                tempEndHour = hour;
                              } else {
                                // Clicked before start - reset and make this the new start
                                tempStartHour = hour;
                                tempEndHour = null;
                              }
                            } else {
                              // Both set - reset and start over
                              tempStartHour = hour;
                              tempEndHour = null;
                            }
                          });
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: isInRange 
                                ? Colors.green.withValues(alpha: 0.3)
                                : const Color(0xFF2A2A2A),
                            borderRadius: BorderRadius.circular(25),
                            border: Border.all(
                              color: isInRange ? Colors.green : Colors.grey[700]!,
                              width: 1,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              '${hour.toString().padLeft(2, '0')}:00',
                              style: TextStyle(
                                color: isInRange ? Colors.green : Colors.white,
                                fontSize: 12,
                                fontWeight: isInRange ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
              ),
              TextButton(
                onPressed: tempStartHour != null && tempEndHour != null
                    ? () {
                        setState(() {
                          _selectedStartHour = tempStartHour;
                          _selectedEndHour = tempEndHour;
                        });
                        Navigator.pop(context);
                      }
                    : null,
                child: Text(
                  'Confirm',
                  style: TextStyle(
                    color: tempStartHour != null && tempEndHour != null
                        ? Colors.blue
                        : Colors.grey,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final serviceTitle = widget.order['serviceTitle'] ?? widget.order['service_title'] ?? 'Service';
    final status = widget.order['status'] as String? ?? 'pending_confirmation';
    final orderId = widget.order['orderId'] ?? widget.order['order_id'] as String?;
    final isBooking = widget.order['isBooking'] ?? widget.order['is_booking'] as bool? ?? false;
    final bookingDate = widget.order['bookingDate'] ?? widget.order['booking_date'] as String?;
    final createdAt = widget.order['created_at'] as String?;
    final serviceImageUrl = widget.order['serviceImageUrl'] as String?; // Pre-fetched image URL
    
    debugPrint('🎨 Building service order confirmation card:');
    debugPrint('   Service Title: $serviceTitle');
    debugPrint('   Order ID: $orderId');
    debugPrint('   Status: $status');
    debugPrint('   Created At: $createdAt');
    debugPrint('   Image URL: $serviceImageUrl');
    
    // For accepted/declined status, use compact card like quantity request
    if (status == 'booked' || status == 'to_do' || status == 'declined') {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF242424),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 8,
              spreadRadius: 0.5,
            )
          ],
        ),
        child: Stack(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Service image
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 70,
                    height: 70,
                    child: serviceImageUrl != null && serviceImageUrl.isNotEmpty
                        ? Image.network(
                            serviceImageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Image.asset(
                                'assets/card_logos/noimage.png',
                                fit: BoxFit.cover,
                              );
                            },
                          )
                        : Image.asset(
                            'assets/card_logos/noimage.png',
                            fit: BoxFit.cover,
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                // Service details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        serviceTitle,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      if (isBooking && bookingDate != null)
                        Text(
                          _formatBookingDate(bookingDate),
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 11,
                          ),
                        ),
                      const SizedBox(height: 4), // Minimal space
                    ],
                  ),
                ),
              ],
            ),
            // Status badge at bottom right
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: (status == 'booked' || status == 'to_do') ? Colors.green : Colors.red,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text(
                  (status == 'booked' || status == 'to_do') ? 'Accepted' : 'Declined',
                  style: TextStyle(
                    fontSize: 12,
                    color: (status == 'booked' || status == 'to_do') ? Colors.green : Colors.red,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    
    // For pending confirmation, show full card with actions
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF242424),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 6,
            spreadRadius: 0.5,
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Service image on left
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 70,
                  height: 70,
                  child: serviceImageUrl != null && serviceImageUrl.isNotEmpty
                      ? Image.network(
                          serviceImageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Image.asset(
                              'assets/card_logos/noimage.png',
                              fit: BoxFit.cover,
                            );
                          },
                        )
                      : Image.asset(
                          'assets/card_logos/noimage.png',
                          fit: BoxFit.cover,
                        ),
                ),
              ),
              const SizedBox(width: 12),
              // Service details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Row 1: "Confirm Booking" label and Service title on same line
                    Row(
                      children: [
                        Text(
                          'Confirm Booking: ',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            serviceTitle,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    // Row 2: Date and Buyer name combined
                    Text(
                      isBooking && bookingDate != null
                          ? '${_formatBookingDate(bookingDate)} • ${widget.buyerName ?? 'Unknown'}'
                          : 'Buyer: ${widget.buyerName ?? 'Unknown'}',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 9,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    // Row 3: Buyer address
                    const SizedBox(height: 2),
                    Text(
                      widget.buyerAddress ?? 'No address provided',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 9,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4), // Minimal space before buttons
                  ],
                ),
              ),
            ],
          ),
              
              // Hour availability selector and notes (only for bookings and pending status)
              if (isBooking) ...[
                const SizedBox(height: 8),
                const Divider(color: Color(0xFF3A3A3A), height: 1),
                const SizedBox(height: 8),
                
                // Hour selector with dropdowns
                // Description/Notes field
                SizedBox(
                  height: 35, // Match button height (padding 8 + text ~19)
                  child: TextField(
                    controller: _notesController,
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                    maxLines: 1,
                    textAlignVertical: TextAlignVertical.center,
                    decoration: InputDecoration(
                      hintText: 'Note about the service (for yourself)',
                      hintStyle: TextStyle(color: Colors.grey[600], fontSize: 10),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(color: Colors.grey[700]!),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(color: Colors.grey[700]!),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(color: Colors.blue),
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 8),
                
                // Time button and action buttons row
                Row(
                  children: [
                    // Time selection button (smaller, not expanded)
                    GestureDetector(
                      onTap: () => _selectHourRange(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: _selectedStartHour != null && _selectedEndHour != null
                              ? Colors.green.withValues(alpha: 0.2)
                              : const Color(0xFF1E1E1E),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _selectedStartHour != null && _selectedEndHour != null
                                ? Colors.green
                                : Colors.grey[700]!,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 13,
                              color: _selectedStartHour != null && _selectedEndHour != null
                                  ? Colors.green
                                  : Colors.grey[600],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _selectedStartHour != null && _selectedEndHour != null
                                  ? _selectedStartHour == _selectedEndHour
                                      ? '${_selectedStartHour.toString().padLeft(2, '0')}:00-${(_selectedEndHour! + 1).toString().padLeft(2, '0')}:00'
                                      : '${_selectedStartHour.toString().padLeft(2, '0')}:00-${(_selectedEndHour! + 1).toString().padLeft(2, '0')}:00'
                                  : 'Select Time',
                              style: TextStyle(
                                color: _selectedStartHour != null && _selectedEndHour != null
                                    ? Colors.green
                                    : Colors.grey[600],
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    // Decline button
                    GestureDetector(
                      onTap: () async {
                        if (orderId == null) return;
                        
                        debugPrint('🔴 Declining service order: $orderId');
                        
                        try {
                          final callable = FirebaseFunctions.instance.httpsCallable('refundServiceBooking');
                          await callable.call({
                            'orderId': orderId,
                            'isBooking': isBooking,
                          });
                          
                          debugPrint('✅ Service order declined and refunded');
                          await widget.onUpdate();
                        } catch (e) {
                          debugPrint('❌ Error declining booking: $e');
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.red, width: 1.5),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Decline',
                          style: TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Accept button
                    GestureDetector(
                      onTap: () async {
                        if (orderId == null) return;
                        
                        // Validate hour selection for bookings
                        if (isBooking) {
                          if (_selectedStartHour == null || _selectedEndHour == null) {
                            debugPrint('⚠️ Hours not selected');
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please select available hours')),
                            );
                            return;
                          }
                        }
                        
                        debugPrint('🟢 Accepting service order: $orderId');
                        
                        try {
                          final collectionName = isBooking ? 'bookings' : 'service_orders';
                          final updateData = <String, dynamic>{
                            'status': isBooking ? 'booked' : 'to_do',
                          };
                          
                          if (isBooking) {
                            updateData['availability_start_hour'] = _selectedStartHour;
                            updateData['availability_end_hour'] = _selectedEndHour == _selectedStartHour 
                                ? _selectedEndHour! + 1 
                                : _selectedEndHour! + 1;
                            updateData['seller_notes'] = _notesController.text.trim();
                          }
                          
                          await SupabaseService.instance.client
                              .from(collectionName)
                              .update(updateData)
                              .eq('id', orderId);
                          
                          debugPrint('✅ ${isBooking ? 'Booking' : 'Service order'} confirmed - status changed to ${isBooking ? 'booked' : 'to_do'}');
                          await widget.onUpdate();
                        } catch (e) {
                          debugPrint('❌ Error confirming booking: $e');
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.green, width: 1.5),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Accept',
                          style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
              ],
        ],
      ),
    );
  }

  /// Format booking date for display
  String _formatBookingDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${months[date.month - 1]} ${date.day}, ${date.year}';
    } catch (e) {
      return dateStr;
    }
  }
}

/// Stateless checkpoint divider widget to prevent rebuilds
class _CheckpointDivider extends StatefulWidget {
  final String docId;
  final String title;
  final bool isCollapsed;
  final VoidCallback onTap;
  final Function(String)? onTitleComputed;
  final String? messageProductId;
  final Map<String, dynamic>? productCard;

  const _CheckpointDivider({
    super.key,
    required this.docId,
    required this.title,
    required this.isCollapsed,
    required this.onTap,
    this.onTitleComputed,
    this.messageProductId,
    this.productCard,
  });

  @override
  State<_CheckpointDivider> createState() => _CheckpointDividerState();
}

class _CheckpointDividerState extends State<_CheckpointDivider> {
  String? _computedTitle;
  bool _isComputing = false;

  @override
  void initState() {
    super.initState();
    _computeTitle();
  }

  void _computeTitle() async {
    if (_isComputing || widget.onTitleComputed == null) return;
    if (widget.messageProductId == null || widget.productCard == null) return;
    
    _isComputing = true;
    try {
      final itemData = await _fetchItemFromAnyCollection(widget.messageProductId!);
      if (itemData == null) return;
      
      final collection = itemData['_collection'] as String? ?? 'products';
      String itemType = 'product';
      if (collection == 'services') {
        itemType = 'service';
      } else if (collection == 'gigs') {
        itemType = 'gig';
      }
      
      final fullTitle = itemData['title'] ?? widget.productCard!['title'] ?? 'Item';
      
      // Get short title (first word + 2-3 letters of second word)
      String shortTitle;
      final words = fullTitle.toString().trim().split(RegExp(r'\s+'));
      
      if (words.isEmpty) {
        shortTitle = 'Item';
      } else {
        shortTitle = words[0];
        
        // If first word is too long, truncate it
        if (shortTitle.length > 20) {
          shortTitle = '${shortTitle.substring(0, 20)}...';
        } else if (words.length > 1 && words[1].isNotEmpty) {
          // Add 2-3 letters from second word
          final secondWord = words[1];
          final lettersToTake = secondWord.length >= 3 ? 3 : secondWord.length;
          shortTitle += ' ${secondWord.substring(0, lettersToTake)}...';
        }
      }
      
      final computedTitle = ChatCheckpoints.getCheckpointTitle(
        ChatCheckpoints.productQuestion,
        productTitle: shortTitle,
        itemType: itemType,
      );
      
      if (mounted) {
        setState(() {
          _computedTitle = computedTitle;
        });
        widget.onTitleComputed?.call(computedTitle);
      }
    } catch (e) {
      debugPrint('Error computing checkpoint title: $e');
    }
  }

  Future<Map<String, dynamic>?> _fetchItemFromAnyCollection(String itemId) async {
    try {
      var data = await SupabaseService.instance.products
          .select()
          .eq('id', itemId)
          .maybeSingle();
      
      if (data != null) {
        return {...data, '_collection': 'products'};
      }
      
      data = await SupabaseService.instance.services
          .select()
          .eq('id', itemId)
          .maybeSingle();
      
      if (data != null) {
        return {...data, '_collection': 'services'};
      }
      
      data = await SupabaseService.instance.gigs
          .select()
          .eq('id', itemId)
          .maybeSingle();
      
      if (data != null) {
        return {...data, '_collection': 'gigs'};
      }
      
      return null;
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayTitle = _computedTitle ?? widget.title;
    
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        child: Row(
          children: [
            Expanded(
              child: Container(
                height: 1,
                color: Colors.grey[800],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.rotate(
                    angle: widget.isCollapsed ? 0 : 1.5708, // 90 degrees in radians
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      color: Colors.grey[400],
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    displayTitle,
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                height: 1,
                color: Colors.grey[800],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// IG-style gradient bubble: samples color from a screen-spanning gradient
/// based on the bubble's vertical position. As you scroll, each sent message
/// shifts through the gradient colors.
class _ScreenGradientBubble extends StatefulWidget {
  final ValueNotifier<List<Color>> gradientNotifier;
  final ScrollController scrollController;
  final Widget Function(List<Color> gradientColors) builder;

  const _ScreenGradientBubble({
    required this.gradientNotifier,
    required this.scrollController,
    required this.builder,
  });

  @override
  State<_ScreenGradientBubble> createState() => _ScreenGradientBubbleState();
}

class _ScreenGradientBubbleState extends State<_ScreenGradientBubble> {
  List<Color> _colors = [];
  final _key = GlobalKey();

  @override
  void initState() {
    super.initState();
    _colors = widget.gradientNotifier.value;
    widget.gradientNotifier.addListener(_onGradientChanged);
    widget.scrollController.addListener(_recompute);
    WidgetsBinding.instance.addPostFrameCallback((_) => _recompute());
  }

  @override
  void dispose() {
    widget.gradientNotifier.removeListener(_onGradientChanged);
    widget.scrollController.removeListener(_recompute);
    super.dispose();
  }

  void _onGradientChanged() => _recompute();

  void _recompute() {
    final ctx = _key.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final topLeft = box.localToGlobal(Offset.zero);
    final screenH = MediaQuery.of(ctx).size.height;
    final centerY = topLeft.dy + box.size.height / 2;
    final t = (centerY / screenH).clamp(0.0, 1.0);
    final baseColors = widget.gradientNotifier.value;
    if (baseColors.length < 2) return;
    final c = _sampleGradient(baseColors, 1.0 - t);
    final newColors = [c, c];
    if (!_colorsEqual(newColors, _colors)) {
      setState(() => _colors = newColors);
    }
  }

  static Color _sampleGradient(List<Color> colors, double t) {
    if (colors.length == 1) return colors[0];
    final maxIdx = colors.length - 1;
    final scaled = t * maxIdx;
    final lo = scaled.floor().clamp(0, maxIdx - 1);
    final hi = (lo + 1).clamp(0, maxIdx);
    final frac = scaled - lo;
    return Color.lerp(colors[lo], colors[hi], frac)!;
  }

  static bool _colorsEqual(List<Color> a, List<Color> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: _key,
      child: widget.builder(
        _colors.isEmpty ? widget.gradientNotifier.value : _colors,
      ),
    );
  }
}

/// Singleton that streams device tilt from the accelerometer.
/// Multiple widgets share one subscription.
class _TiltProvider extends ChangeNotifier {
  static final _TiltProvider instance = _TiltProvider._();
  _TiltProvider._();

  int _users = 0;
  StreamSubscription? _sub;
  double _tiltX = 0; // -1..1 horizontal
  double _tiltY = 0; // -1..1 vertical
  double _angle = 0; // radians — sweep gradient rotation

  double get tiltX => _tiltX;
  double get tiltY => _tiltY;
  double get angle => _angle;

  void addUser() {
    _users++;
    if (_users == 1) _start();
  }

  void removeUser() {
    _users--;
    if (_users <= 0) {
      _users = 0;
      _sub?.cancel();
      _sub = null;
    }
  }

  void _start() {
    try {
      _sub = SensorsPlatform.instance.accelerometerEventStream().listen((e) {
        // Normalize: gravity ~9.8, clamp to -1..1
        _tiltX = (e.x / 9.8).clamp(-1.0, 1.0);
        _tiltY = (e.y / 9.8).clamp(-1.0, 1.0);
        _angle = math.atan2(e.x, e.y);
        notifyListeners();
      });
    } catch (_) {}
  }
}

/// Liquid glass container with tilt-reactive specular highlight border.
class _LiquidGlass extends StatefulWidget {
  final Widget child;
  final double borderRadius;

  const _LiquidGlass({
    required this.child,
    this.borderRadius = 50,
  });

  @override
  State<_LiquidGlass> createState() => _LiquidGlassState();
}

class _LiquidGlassState extends State<_LiquidGlass> {
  final _tilt = _TiltProvider.instance;

  @override
  void initState() {
    super.initState();
    _tilt.addUser();
    _tilt.addListener(_onTilt);
  }

  void _onTilt() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tilt.removeListener(_onTilt);
    _tilt.removeUser();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.borderRadius;
    return ClipRRect(
      borderRadius: BorderRadius.circular(r),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: CustomPaint(
          painter: _GlassHighlightPainter(
            angle: _tilt.angle,
            tiltX: _tilt.tiltX,
            tiltY: _tilt.tiltY,
            borderRadius: r,
            borderColor: const Color(0xFF4CAF50),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class _GlassHighlightPainter extends CustomPainter {
  final double angle;
  final double tiltX;
  final double tiltY;
  final double borderRadius;
  final Color borderColor;

  _GlassHighlightPainter({
    required this.angle,
    required this.tiltX,
    required this.tiltY,
    required this.borderRadius,
    required this.borderColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = borderRadius;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(r));

    // Base glass fill
    canvas.drawRRect(rrect, Paint()..color = Colors.white.withValues(alpha: 0.06));

    canvas.save();
    canvas.clipRRect(rrect);

    // Inner specular glow that moves with tilt
    final glowCenter = Offset(
      size.width * (0.5 + tiltX * 0.4),
      size.height * (0.5 - tiltY * 0.5),
    );
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.10),
          Colors.white.withValues(alpha: 0.03),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.4, 1.0],
      ).createShader(
        Rect.fromCircle(center: glowCenter, radius: size.width * 0.5),
      );
    canvas.drawRect(rect, glowPaint);
    canvas.restore();

    // Sweep gradient border that rotates with tilt
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..shader = SweepGradient(
        center: Alignment.center,
        transform: GradientRotation(angle - math.pi * 0.33),
        colors: [
          borderColor.withValues(alpha: 0.7),
          borderColor.withValues(alpha: 0.5),
          borderColor.withValues(alpha: 0.12),
          borderColor.withValues(alpha: 0.04),
          borderColor.withValues(alpha: 0.04),
          borderColor.withValues(alpha: 0.12),
          borderColor.withValues(alpha: 0.5),
          borderColor.withValues(alpha: 0.7),
        ],
        stops: const [0.0, 0.08, 0.18, 0.3, 0.7, 0.82, 0.92, 1.0],
      ).createShader(rect);
    canvas.drawRRect(rrect, borderPaint);

    // Blurred glow behind the bright section
    final blurPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)
      ..shader = SweepGradient(
        center: Alignment.center,
        transform: GradientRotation(angle - math.pi * 0.25),
        colors: [
          borderColor.withValues(alpha: 0.22),
          borderColor.withValues(alpha: 0.08),
          borderColor.withValues(alpha: 0.0),
          borderColor.withValues(alpha: 0.0),
          borderColor.withValues(alpha: 0.0),
          borderColor.withValues(alpha: 0.08),
          borderColor.withValues(alpha: 0.22),
        ],
        stops: const [0.0, 0.1, 0.22, 0.5, 0.78, 0.9, 1.0],
      ).createShader(rect);
    canvas.drawRRect(rrect, blurPaint);
  }

  @override
  bool shouldRepaint(_GlassHighlightPainter old) =>
      old.angle != angle || old.tiltX != tiltX || old.tiltY != tiltY;
}

/// Order cancelled card with refund button for buyers
class _OrderCancelledCard extends StatefulWidget {
  final String productTitle;
  final String? orderId;
  final bool isBuyer;

  const _OrderCancelledCard({
    required this.productTitle,
    this.orderId,
    required this.isBuyer,
  });

  @override
  State<_OrderCancelledCard> createState() => _OrderCancelledCardState();
}

class _OrderCancelledCardState extends State<_OrderCancelledCard> {
  bool _isRefunding = false;
  bool _refunded = false;

  @override
  void initState() {
    super.initState();
    _checkRefundStatus();
  }

  Future<void> _checkRefundStatus() async {
    if (widget.orderId == null) return;
    try {
      final order = await SupabaseService.instance.orders
          .select('status, payment')
          .eq('id', widget.orderId!)
          .maybeSingle();
      if (order != null && mounted) {
        final status = order['status']?.toString().toLowerCase() ?? '';
        final payment = order['payment'] as Map<String, dynamic>? ?? {};
        final paymentStatus = payment['status']?.toString().toLowerCase() ?? '';
        if (status == 'refunded' || paymentStatus == 'refunded') {
          setState(() => _refunded = true);
        }
      }
    } catch (_) {}
  }

  Future<void> _processRefund() async {
    if (widget.orderId == null || _isRefunding) return;
    setState(() => _isRefunding = true);

    try {
      final callable = FirebaseFunctions.instance.httpsCallable('refundExpiredOrder');
      await callable.call({
        'orderId': widget.orderId,
      });

      if (mounted) {
        setState(() {
          _refunded = true;
          _isRefunding = false;
        });
        NotificationHelper.showNotification(context, I18n.t('refund_processed'));
      }
    } catch (e) {
      debugPrint('❌ Refund error: $e');
      if (mounted) {
        setState(() => _isRefunding = false);
        NotificationHelper.showNotification(context, '${I18n.t('error')}: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.orange.withValues(alpha: 0.3),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cancel_outlined, color: Colors.orange, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      I18n.t('order_cancelled'),
                      style: const TextStyle(
                        color: Colors.orange,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.productTitle,
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      I18n.t('seller_did_not_ship'),
                      style: TextStyle(color: Colors.grey[500], fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (widget.isBuyer) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: GestureDetector(
                onTap: _refunded || _isRefunding ? null : _processRefund,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: _refunded
                        ? Colors.green.withValues(alpha: 0.15)
                        : Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _refunded
                          ? Colors.green.withValues(alpha: 0.3)
                          : Colors.orange.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Center(
                    child: _isRefunding
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                            ),
                          )
                        : Text(
                            _refunded ? I18n.t('refunded') : I18n.t('refund'),
                            style: TextStyle(
                              color: _refunded ? Colors.green : Colors.orange,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
