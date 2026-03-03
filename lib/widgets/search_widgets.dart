// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import '../services/advanced_search_service.dart';

/// Search suggestions dropdown widget for progressive search
/// Shows relevant suggestions based on current search query
class SearchSuggestionsWidget extends StatelessWidget {
  final String currentQuery;
  final List<Map<String, dynamic>> products;
  final Function(String) onSuggestionSelected;
  final int maxSuggestions;

  const SearchSuggestionsWidget({
    super.key,
    required this.currentQuery,
    required this.products,
    required this.onSuggestionSelected,
    this.maxSuggestions = 8,
  });

  @override
  Widget build(BuildContext context) {
    if (currentQuery.isEmpty) {
      return const SizedBox.shrink();
    }

    final suggestions = AdvancedSearchService.getSuggestions(
      products,
      currentQuery,
    ).take(maxSuggestions).toList();

    if (suggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey[300]!),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: suggestions.map((suggestion) {
          return InkWell(
            onTap: () {
              final newQuery = '$currentQuery $suggestion'.trim();
              onSuggestionSelected(newQuery);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.search,
                    size: 18,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      suggestion,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[800],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    Icons.arrow_outward,
                    size: 16,
                    color: Colors.grey[400],
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Search result badge showing which parts matched (title vs tags)
class SearchResultBadge extends StatelessWidget {
  final Map<String, dynamic> product;
  final String query;

  const SearchResultBadge({
    super.key,
    required this.product,
    required this.query,
  });

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) {
      return const SizedBox.shrink();
    }

    final metadata = AdvancedSearchService.getSearchResultMetadata(
      product,
      query,
    );

    final matchType = metadata['matchType'] as String?;

    Color badgeColor = Colors.grey;
    String badgeLabel = '';
    IconData badgeIcon = Icons.check;

    switch (matchType) {
      case 'title_match':
        badgeColor = Colors.green;
        badgeLabel = 'Title Match';
        badgeIcon = Icons.done;
        break;
      case 'mixed_match':
        badgeColor = Colors.blue;
        badgeLabel = 'Title + Tags';
        badgeIcon = Icons.done_all;
        break;
      case 'partial_match':
        badgeColor = Colors.orange;
        badgeLabel = 'Partial Match';
        badgeIcon = Icons.info;
        break;
      default:
        return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: badgeColor.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(badgeIcon, size: 12, color: badgeColor),
          const SizedBox(width: 4),
          Text(
            badgeLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: badgeColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// Enhanced search bar with progressive search hints
class EnhancedSearchBar extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onSearchSubmitted;
  final List<Map<String, dynamic>> products;
  final bool showSuggestions;

  const EnhancedSearchBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSearchSubmitted,
    required this.products,
    this.showSuggestions = true,
  });

  @override
  State<EnhancedSearchBar> createState() => _EnhancedSearchBarState();
}

class _EnhancedSearchBarState extends State<EnhancedSearchBar> {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            border: Border(
              bottom: BorderSide(color: Colors.grey[300]!),
            ),
          ),
          child: TextField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            onChanged: widget.onChanged,
            onSubmitted: (_) => widget.onSearchSubmitted(),
            decoration: InputDecoration(
              hintText: 'Search products',
              hintStyle: TextStyle(color: Colors.grey[600]),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.blue, width: 2),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              prefixIcon: Icon(Icons.search, color: Colors.grey[600]),
              suffixIcon: widget.controller.text.isNotEmpty
                  ? Container(
                      margin: const EdgeInsets.only(right: 8),
                      decoration: const BoxDecoration(
                        color: Colors.grey,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white, size: 18),
                        onPressed: () {
                          widget.controller.clear();
                          widget.onChanged('');
                        },
                      ),
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
        ),
        if (widget.showSuggestions && widget.focusNode.hasFocus)
          SearchSuggestionsWidget(
            currentQuery: widget.controller.text,
            products: widget.products,
            onSuggestionSelected: (suggestion) {
              widget.controller.text = suggestion;
              widget.onChanged(suggestion);
              widget.onSearchSubmitted();
            },
          ),
      ],
    );
  }
}

/// Progressive search info tooltip
class ProgressiveSearchHint extends StatelessWidget {
  final String currentQuery;

  const ProgressiveSearchHint({
    super.key,
    required this.currentQuery,
  });

  @override
  Widget build(BuildContext context) {
    if (currentQuery.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          '💡 Tip: Type the main term first (e.g., "battery"), then refine (e.g., "battery iphone")',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    final (primaryTerm, secondaryTerms) =
        AdvancedSearchService.parseSearchQuery(currentQuery);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 16,
            color: Colors.blue[600],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                children: [
                  const TextSpan(text: 'Primary: '),
                  TextSpan(
                    text: primaryTerm,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[600],
                    ),
                  ),
                  if (secondaryTerms.isNotEmpty) ...[
                    const TextSpan(text: ' | Secondary: '),
                    TextSpan(
                      text: secondaryTerms.join(', '),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green[600],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
