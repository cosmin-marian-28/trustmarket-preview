import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/translations.dart';
import 'supabase_service.dart';

class LanguageService {
  static const _prefKey = 'app_lang';

  // Notifier that widgets can listen to for language changes
  static final ValueNotifier<AppLang> languageNotifier = ValueNotifier(AppLang.en);

  static AppLang get current => languageNotifier.value;

  /// Load language from shared preferences. If no pref is present, keep current.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final s = prefs.getString(_prefKey) ?? 'en';
      // Resolve using enum values by name to avoid direct member references
      final lang = AppLang.values.firstWhere(
        (e) => e.name == s,
        orElse: () => AppLang.en,
      );
      languageNotifier.value = lang;
      I18n.current = lang;
    } catch (e) {
      // ignore errors and keep defaults
      debugPrint('LanguageService.load error: $e');
    }
  }

  /// Set language and persist preference. Notifies listeners.
  static Future<void> setLanguage(AppLang lang) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, lang.name);
    } catch (e) {
      debugPrint('LanguageService.save error: $e');
    }
    languageNotifier.value = lang;
    I18n.current = lang;
    // Persist selection to Supabase for logged-in users
    try {
      final user = SupabaseService.instance.client.auth.currentUser;
      if (user != null) {
        await SupabaseService.instance.client
            .from('users')
            .update({
              'preferred_language': lang.name,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', user.id);
      }
    } catch (e) {
      debugPrint('LanguageService: could not persist language to Supabase: $e');
    }
  }
}
