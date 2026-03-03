import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase_options.dart';

/// Singleton service for Supabase operations
class SupabaseService {
  static SupabaseService? _instance;
  static SupabaseClient? _client;

  SupabaseService._();

  static SupabaseService get instance {
    _instance ??= SupabaseService._();
    return _instance!;
  }

  /// Initialize Supabase
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
    );
    _client = Supabase.instance.client;
  }

  /// Get the Supabase client
  SupabaseClient get client {
    if (_client == null) {
      throw Exception('Supabase not initialized. Call SupabaseService.initialize() first.');
    }
    return _client!;
  }

  /// Auth helpers
  User? get currentUser => client.auth.currentUser;
  String? get currentUserId => currentUser?.id;
  bool get isAuthenticated => currentUser != null;

  /// Sign up with email and password
  Future<AuthResponse> signUp(String email, String password) async {
    return await client.auth.signUp(
      email: email,
      password: password,
    );
  }

  /// Sign in with email and password
  Future<AuthResponse> signIn(String email, String password) async {
    return await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  /// Sign out
  Future<void> signOut() async {
    await client.auth.signOut();
  }

  /// Get auth state changes stream
  Stream<AuthState> get authStateChanges => client.auth.onAuthStateChange;

  /// Database helpers
  PostgrestQueryBuilder get users => client.from('users');
  PostgrestQueryBuilder get products => client.from('products');
  PostgrestQueryBuilder get services => client.from('services');
  PostgrestQueryBuilder get serviceReviews => client.from('service_reviews');
  PostgrestQueryBuilder get gigs => client.from('gigs');
  PostgrestQueryBuilder get conversations => client.from('conversations');
  PostgrestQueryBuilder get messages => client.from('messages');
  PostgrestQueryBuilder get orders => client.from('orders');
  PostgrestQueryBuilder get serviceOrders => client.from('service_orders');
  PostgrestQueryBuilder get bookings => client.from('bookings');
  PostgrestQueryBuilder get disputes => client.from('disputes');
  PostgrestQueryBuilder get offers => client.from('offers');
  PostgrestQueryBuilder get promotions => client.from('promotions');
  PostgrestQueryBuilder get notifications => client.from('notifications');
  PostgrestQueryBuilder get identityVerifications => client.from('identity_verifications');
  PostgrestQueryBuilder get faceDescriptors => client.from('face_descriptors');
  PostgrestQueryBuilder get savedPaymentMethods => client.from('saved_payment_methods');
  PostgrestQueryBuilder get trustHistory => client.from('trust_history');
  PostgrestQueryBuilder get supportConversations => client.from('support_conversations');
  PostgrestQueryBuilder get supportMessages => client.from('support_messages');
  PostgrestQueryBuilder get productAnalysisCache => client.from('product_analysis_cache');
  PostgrestQueryBuilder get productQuestionCache => client.from('product_question_cache');
  PostgrestQueryBuilder get customRequests => client.from('custom_requests');
  PostgrestQueryBuilder get imageReports => client.from('image_reports');
  PostgrestQueryBuilder get draftProducts => client.from('draft_products');
  PostgrestQueryBuilder get productViews => client.from('product_views');

  /// Storage helpers
  SupabaseStorageClient get storage => client.storage;
  
  String getPublicUrl(String bucket, String path) {
    return storage.from(bucket).getPublicUrl(path);
  }

  Future<String> uploadFile({
    required String bucket,
    required String path,
    required Uint8List fileBytes,
    String? contentType,
  }) async {
    debugPrint('📤 [UPLOAD] bucket: "$bucket", path: "$path", size: ${fileBytes.length} bytes');
    try {
      await storage.from(bucket).uploadBinary(
        path,
        fileBytes,
        fileOptions: FileOptions(
          contentType: contentType,
          upsert: true,
        ),
      );
      final url = getPublicUrl(bucket, path);
      debugPrint('✅ [UPLOAD] Success: $url');
      return url;
    } catch (e) {
      debugPrint('❌ [UPLOAD] Failed: $e');
      rethrow;
    }
  }

  Future<void> deleteFile(String bucket, String path) async {
    await storage.from(bucket).remove([path]);
  }
}
