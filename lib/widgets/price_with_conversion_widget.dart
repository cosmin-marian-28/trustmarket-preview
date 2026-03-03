import 'package:flutter/material.dart';
import '../services/currency_service.dart';
import '../services/currency_conversion_service.dart';
import '../constants/translations.dart';

/// Controller to share state between price display and button
class PriceConversionController extends ChangeNotifier {
  bool _isConverted = false;
  double? _convertedPrice;
  bool _isLoading = false;
  String? _error;
  
  bool get isConverted => _isConverted;
  double? get convertedPrice => _convertedPrice;
  bool get isLoading => _isLoading;
  String? get error => _error;
  
  void setConverted(bool value, double? price) {
    _isConverted = value;
    _convertedPrice = price;
    notifyListeners();
  }
  
  void setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
  
  void setError(String? value) {
    _error = value;
    notifyListeners();
  }
}

/// Widget that displays a price with optional currency conversion
class PriceWithConversion extends StatefulWidget {
  final double price;
  final String originalCurrency;
  final TextStyle? style;
  final bool showConvertButton;
  final bool autoConvert;
  final bool buttonOnly;
  final PriceConversionController? controller; // Shared controller
  
  const PriceWithConversion({
    super.key,
    required this.price,
    required this.originalCurrency,
    this.style,
    this.showConvertButton = true,
    this.autoConvert = false,
    this.buttonOnly = false,
    this.controller,
  });

  @override
  State<PriceWithConversion> createState() => _PriceWithConversionState();
}

class _PriceWithConversionState extends State<PriceWithConversion> {
  late PriceConversionController _controller;
  bool _isOwnController = false;

  @override
  void initState() {
    super.initState();
    
    // Use provided controller or create our own
    if (widget.controller != null) {
      _controller = widget.controller!;
      _isOwnController = false;
    } else {
      _controller = PriceConversionController();
      _isOwnController = true;
    }
    
    _controller.addListener(_onControllerChanged);
    
    if (widget.autoConvert && widget.originalCurrency != CurrencyService.current) {
      _convertCurrency();
    }
  }
  
  @override
  void didUpdateWidget(PriceWithConversion oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // If price changed while converted, update the converted price proportionally
    // without calling the API again
    if (oldWidget.price != widget.price && _controller.isConverted && _controller.convertedPrice != null) {
      final ratio = widget.price / oldWidget.price;
      final newConvertedPrice = _controller.convertedPrice! * ratio;
      _controller.setConverted(true, newConvertedPrice);
      return;
    }
    
    // If autoConvert changed, reconvert
    if (oldWidget.autoConvert != widget.autoConvert) {
      if (widget.autoConvert && widget.originalCurrency != CurrencyService.current) {
        _convertCurrency();
      } else if (!widget.autoConvert) {
        _controller.setConverted(false, null);
      }
    }
  }
  
  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    if (_isOwnController) {
      _controller.dispose();
    }
    super.dispose();
  }
  
  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _convertCurrency() async {
    if (widget.originalCurrency == CurrencyService.current) {
      _controller.setConverted(false, null);
      return;
    }

    _controller.setLoading(true);
    _controller.setError(null);

    try {
      final converted = await CurrencyService.convertPrice(
        amount: widget.price,
        fromCurrency: widget.originalCurrency,
      );

      if (mounted) {
        _controller.setConverted(converted != null, converted);
        _controller.setLoading(false);
        if (converted == null) {
          _controller.setError(I18n.t('conversion_failed'));
        }
      }
    } catch (e) {
      if (mounted) {
        _controller.setLoading(false);
        _controller.setError(I18n.t('conversion_error'));
      }
    }
  }

  void _toggleConversion() {
    if (_controller.isConverted) {
      _controller.setConverted(false, null);
      _controller.setError(null);
    } else {
      _convertCurrency();
    }
  }

  @override
  Widget build(BuildContext context) {
    final userCurrency = CurrencyService.current;
    final showButton = widget.showConvertButton && 
                       widget.originalCurrency != userCurrency;

    // If buttonOnly mode, just return the button
    if (widget.buttonOnly) {
      if (!showButton) return const SizedBox.shrink();
      
      return GestureDetector(
        onTap: _controller.isLoading ? null : _toggleConversion,
        child: Container(
          width: 40, // Match height of Make an Offer button
          height: 40, // Match height of Make an Offer button
          decoration: BoxDecoration(
            color: _controller.isConverted ? Colors.green.withValues(alpha: 0.2) : Colors.grey[900],
            shape: BoxShape.circle, // Keep it round
          ),
          child: Icon(
            _controller.isConverted ? Icons.undo : Icons.currency_exchange,
            size: 16, // Icon size to fit nicely in circle
            color: _controller.isConverted ? Colors.green : Colors.grey[400],
          ),
        ),
      );
    }

    // Normal mode: price + button below
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_controller.isLoading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                ),
              )
            else
              Text(
                _controller.isConverted && _controller.convertedPrice != null
                    ? CurrencyConversionService.formatPrice(_controller.convertedPrice!, userCurrency)
                    : CurrencyConversionService.formatPrice(widget.price, widget.originalCurrency),
                style: widget.style ?? const TextStyle(
                  color: Colors.green,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
        if (_controller.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _controller.error!,
              style: const TextStyle(
                color: Colors.red,
                fontSize: 12,
              ),
            ),
          ),
        if (showButton)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: GestureDetector(
              onTap: _controller.isLoading ? null : _toggleConversion,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _controller.isConverted ? Colors.grey[700] : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _controller.isConverted ? Colors.grey : Colors.green,
                    width: 2,
                  ),
                ),
                child: Icon(
                  _controller.isConverted ? Icons.undo : Icons.currency_exchange,
                  size: 20,
                  color: _controller.isConverted ? Colors.grey[300] : Colors.green,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
