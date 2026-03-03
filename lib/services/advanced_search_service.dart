import 'package:flutter/foundation.dart';
import 'supabase_service.dart';

class AdvancedSearchService {
  // Common words to skip
  static const Set<String> _skipWords = {
    'with', 'for', 'to', 'and', 'or', 'the', 'a', 'an',
    'in', 'on', 'at', 'by', 'from', 'of', 'is', 'as'
  };

  /// Parse search query into primary and secondary terms
  static (String, List<String>) parseSearchQuery(String query) {
    final trimmed = query.toLowerCase().trim();
    if (trimmed.isEmpty) {
      return ('', <String>[]);
    }

    final parts = trimmed.split(RegExp(r'\s+'));
    final meaningfulParts = parts.where((part) => 
      part.isNotEmpty && !_skipWords.contains(part)
    ).toList();

    if (meaningfulParts.isEmpty) {
      return ('', <String>[]);
    }

    return (meaningfulParts[0], meaningfulParts.sublist(1));
  }

  /// Parse search query into map (internal use)
  static Map<String, dynamic> _parseSearchQueryMap(String query) {
    final (primary, secondary) = parseSearchQuery(query);
    return {
      'primary': primary,
      'secondary': secondary
    };
  }

  /// Extract tags from product answers
  static List<String> _extractTagsFromAnswers(Map<String, dynamic>? answers) {
    if (answers == null) return [];

    final tags = <String>{};
    
    for (final value in answers.values) {
      if (value != null) {
        final normalized = value.toString().toLowerCase().trim();
        if (normalized.isNotEmpty) {
          tags.add(normalized);
          
          final words = normalized.split(RegExp(r'[\s\-_,\.]+'));
          tags.addAll(words.where((w) => w.isNotEmpty));
          
          final numbers = RegExp(r'\d+').allMatches(normalized);
          tags.addAll(numbers.map((m) => m.group(0)!));
          
          final units = RegExp(r'[a-z]+').allMatches(normalized);
          tags.addAll(units.map((m) => m.group(0)!));
        }
      }
    }
    
    return tags.where((tag) => tag.isNotEmpty).toList();
  }

  /// Check if text matches term
  static bool _matchesTerm(String text, String term) {
    final lowerText = text.toLowerCase();
    final lowerTerm = term.toLowerCase();
    
    if (lowerText.contains(lowerTerm)) {
      return true;
    }
    
    final textNoSpace = lowerText.replaceAll(RegExp(r'[\s\-_]'), '');
    final termNoSpace = lowerTerm.replaceAll(RegExp(r'[\s\-_]'), '');
    if (textNoSpace.contains(termNoSpace)) {
      return true;
    }
    
    return false;
  }

  /// Progressive search with primary and secondary terms
  static List<Map<String, dynamic>> progressiveSearch(
    List<Map<String, dynamic>> products,
    String query,
  ) {
    if (query.isEmpty) {
      return products;
    }

    final parsed = _parseSearchQueryMap(query);
    final primary = parsed['primary'] as String;
    final secondary = parsed['secondary'] as List<String>;

    if (primary.isEmpty) {
      return products;
    }

    debugPrint('[Advanced Search] Primary="$primary", Secondary=$secondary');

    // LEVEL 1: Find products with PRIMARY term in title
    final primaryMatches = products.where((product) {
      final title = (product['title'] ?? '').toString().toLowerCase();
      return _matchesTerm(title, primary);
    }).toList();

    debugPrint('[Advanced Search] Found ${primaryMatches.length} with primary term "$primary"');

    if (primaryMatches.isEmpty) {
      return [];
    }

    if (secondary.isEmpty) {
      return primaryMatches;
    }

    // LEVEL 2: Filter by secondary terms
    final titleMatches = <Map<String, dynamic>>[];
    final tagMatches = <Map<String, dynamic>>[];

    for (final product in primaryMatches) {
      final title = (product['title'] ?? '').toString().toLowerCase();
      final tags = _extractTagsFromAnswers(product['answers'] as Map<String, dynamic>?);
      
      bool allSecondaryFound = true;
      bool allInTitle = true;

      for (final term in secondary) {
        final inTitle = _matchesTerm(title, term);
        final inTags = tags.any((tag) => _matchesTerm(tag, term));

        if (!inTitle && !inTags) {
          allSecondaryFound = false;
          break;
        }

        if (!inTitle) {
          allInTitle = false;
        }
      }

      if (allSecondaryFound) {
        if (allInTitle) {
          titleMatches.add(product);
        } else {
          tagMatches.add(product);
        }
      }
    }

    debugPrint('[Advanced Search] Title matches: ${titleMatches.length}, Tag matches: ${tagMatches.length}');

    return [...titleMatches, ...tagMatches];
  }

  /// Filter by category (kept for backward compatibility, but not used in search)
  static List<Map<String, dynamic>> filterByCategory(
    List<Map<String, dynamic>> products,
    String category,
  ) {
    if (category == 'all') {
      return products;
    }

    // Note: Products don't have a category field, this is kept for backward compatibility
    return products.where((product) {
      final productCategory = (product['category'] ?? '').toString().toLowerCase();
      return productCategory == category.toLowerCase();
    }).toList();
  }

  /// Get search suggestions from products list
  static List<String> getSuggestions(
    List<Map<String, dynamic>> products,
    String query,
  ) {
    try {
      if (query.isEmpty) return [];

      final suggestions = <String>{};
      for (final product in products) {
        final title = product['title']?.toString() ?? '';
        if (title.toLowerCase().contains(query.toLowerCase())) {
          suggestions.add(title);
        }
      }

      return suggestions.toList();
    } catch (e) {
      debugPrint('Get suggestions error: $e');
      return [];
    }
  }

  /// Get search result metadata for a single product
  static Map<String, dynamic> getSearchResultMetadata(
    Map<String, dynamic> product,
    String query,
  ) {
    try {
      final title = (product['title'] ?? '').toString().toLowerCase();
      final tags = _extractTagsFromAnswers(product['answers'] as Map<String, dynamic>?);
      
      final parsed = _parseSearchQueryMap(query);
      final primary = parsed['primary'] as String;
      final secondary = parsed['secondary'] as List<String>;

      // Check if primary term is in title
      bool primaryInTitle = _matchesTerm(title, primary);
      
      // Check secondary terms - check BOTH title AND tags
      bool allSecondaryInTitle = true;
      for (final term in secondary) {
        final inTitle = _matchesTerm(title, term);
        final inTags = tags.any((tag) => _matchesTerm(tag, term));
        
        if (!inTitle && !inTags) {
          // Term not found anywhere
          allSecondaryInTitle = false;
          break;
        }
        
        if (!inTitle) {
          // Found in tags but not title
          allSecondaryInTitle = false;
        }
      }

      String matchType = 'none';
      if (primaryInTitle && allSecondaryInTitle) {
        matchType = 'title';
      } else if (primaryInTitle) {
        matchType = 'tag';
      }

      return {
        'matchType': matchType,
        'primaryInTitle': primaryInTitle,
        'allSecondaryInTitle': allSecondaryInTitle,
      };
    } catch (e) {
      debugPrint('Get metadata error: $e');
      return {
        'matchType': 'none',
        'primaryInTitle': false,
        'allSecondaryInTitle': false,
      };
    }
  }

  /// Advanced search - fetch products and apply progressive search
  static Future<List<Map<String, dynamic>>> search({
    required String query,
    int limit = 100, // Fetch more products for better client-side filtering
  }) async {
    try {
      // Fetch active, unsold products
      final response = await SupabaseService.instance.products
          .select()
          .eq('status', 'active')
          .eq('sold', false)
          .limit(limit);
      
      final products = List<Map<String, dynamic>>.from(response);

      debugPrint('[Advanced Search] Fetched ${products.length} products from Supabase');

      // If no query, return all products
      if (query.isEmpty) {
        return products;
      }

      // Apply progressive search on client side
      final searchResults = progressiveSearch(products, query);
      
      debugPrint('[Advanced Search] Progressive search returned ${searchResults.length} results');

      return searchResults;
    } catch (e) {
      debugPrint('Search error: $e');
      return [];
    }
  }

  /// Search with full-text search support (if available in Supabase)
  static Future<List<Map<String, dynamic>>> searchWithFullText({
    required String query,
    int limit = 100,
  }) async {
    try {
      var queryBuilder = SupabaseService.instance.products
          .select()
          .eq('status', 'active')
          .eq('sold', false);

      // Use Supabase full-text search if query is provided
      if (query.isNotEmpty) {
        // Use textSearch for full-text search on title column
        // Note: This requires a full-text search index on the title column in Supabase
        queryBuilder = queryBuilder.textSearch('title', query, config: 'english');
      }

      // Fetch products
      final response = await queryBuilder.limit(limit);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Full-text search error: $e, falling back to progressive search');
      // Fallback to regular search if full-text search fails
      return search(query: query, limit: limit);
    }
  }
}
