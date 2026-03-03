import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../services/supabase_service.dart';

Color getTrustColor(int points) {
  // Color based on deductions, not absolute score
  // Green = No deductions (positive only)
  // Orange/Red = As deductions gather
  // Dark Red = 0 or negative
  
  if (points > 0) {
    // Positive score = Green (no deductions)
    return Colors.green;
  } else if (points == 0) {
    // Zero = Red (all deducted)
    return Colors.red;
  } else {
    // Negative = Dark Red (severe deductions)
    return Colors.red.shade900;
  }
}

/// A minimal badge that shows the user's trust points inside an empty circle.
class TrustBadge extends StatelessWidget {
  final int score;
  final double size;
  const TrustBadge({super.key, required this.score, this.size = 80});

  @override
  Widget build(BuildContext context) {
    // Render a progress circle like in profile page
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        size: Size(size, size),
        painter: TrustScorePainter(progress: 1.0, score: score, color: getTrustColor(score)),
      ),
    );
  }
}

class TrustScorePainter extends CustomPainter {
  final double progress;
  final int score;
  final Color color;
  final double strokeWidth;

  TrustScorePainter({
    required this.progress,
    required this.score,
    required this.color,
    this.strokeWidth = 12,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - (strokeWidth / 2 + 2);

    // Background circle
    final bgPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, bgPaint);

    // Progress arc
    final progressPaint = Paint()
      ..shader = LinearGradient(
        colors: [color, color.withValues(alpha: 0.6)],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final sweepAngle = 2 * math.pi * (score / 100) * progress;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(TrustScorePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.score != score || oldDelegate.color != color;
  }
}

/// Show a minimal Trust modal. Reads the user's document to display points and
/// offers a couple of simple actions: send verification email and request image verification.
Future<void> showTrustModal(BuildContext context) async {
  try {
    final user = SupabaseService.instance.client.auth.currentUser;
    if (user == null) return;

    showModalBottomSheet(
      // ignore: use_build_context_synchronously
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: false,
      barrierColor: Colors.black54,
      barrierLabel: 'Dismiss',
      builder: (ctx) {
        return _TrustModalContent(userId: user.id);
      },
    );
  } catch (e) {
    debugPrint('Error showing trust modal: $e');
  }
}

/// Show trust modal for a specific user (seller/other user)
Future<void> showUserTrustModal(BuildContext context, String userId) async {
  try {
    showModalBottomSheet(
      // ignore: use_build_context_synchronously
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: false,
      barrierColor: Colors.black54,
      barrierLabel: 'Dismiss',
      builder: (ctx) {
        return _TrustModalContent(userId: userId);
      },
    );
  } catch (e) {
    debugPrint('Error showing user trust modal: $e');
  }
}

class _TrustModalContent extends StatefulWidget {
  final String userId;

  const _TrustModalContent({required this.userId});

  @override
  State<_TrustModalContent> createState() => _TrustModalContentState();
}

class _TrustModalContentState extends State<_TrustModalContent> {
  late Future<Map<String, dynamic>> _userDataFuture;
  late Future<List<Map<String, dynamic>>> _violationHistoryFuture;
  bool _showHowTrustWorks = false;

  @override
  void initState() {
    super.initState();
    _userDataFuture = _fetchUserData();
    _violationHistoryFuture = _fetchViolationHistory();
  }

  Future<Map<String, dynamic>> _fetchUserData() async {
    try {
      final doc = await SupabaseService.instance.client
          .from('users')
          .select()
          .eq('id', widget.userId)
          .single();
      return doc;
    } catch (e) {
      debugPrint('Error fetching user data: $e');
      return {};
    }
  }

  Future<List<Map<String, dynamic>>> _fetchViolationHistory() async {
    try {
      final snapshot = await SupabaseService.instance.client
          .from('trust_history')
          .select()
          .eq('user_id', widget.userId)
          .order('created_at', ascending: false);
      
      return snapshot;
    } catch (e) {
      debugPrint('Error fetching trust history: $e');
      return [];
    }
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return 'Unknown date';
    
    try {
      final dateTime = DateTime.parse(timestamp.toString());
      return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
    } catch (e) {
      debugPrint('Error formatting timestamp: $e');
    }
    
    return 'Unknown date';
  }

  int _calculateTrustScore(Map<String, dynamic> userData, List<Map<String, dynamic>> trustHistory) {
    int score = 0;
    
    // Profile image: +10 points (not tracked in trust_history)
    if (userData['profile_image_url'] != null && 
        userData['profile_image_url'].toString().isNotEmpty) {
      score += 10;
    }
    
    // Face verified: +15 points (faceVerification.js writes to trust_history but not trust_score)
    if (userData['profile_image_verified'] == true) {
      score += 15;
    }
    
    // trust_score column = running total from TrustScoreManager (orders, disputes, violations, etc.)
    final trustScore = (userData['trust_score'] as num?)?.toInt() ?? 0;
    score += trustScore;
    
    // Allow negative scores
    return score;
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = SupabaseService.instance.currentUserId;
    final isOwnProfile = widget.userId == currentUserId;

    return FutureBuilder<Map<String, dynamic>>(
      future: _userDataFuture,
      builder: (context, userSnapshot) {
        final userData = userSnapshot.data ?? {};
        
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: _violationHistoryFuture,
          builder: (context, historySnapshot) {
            final trustHistory = historySnapshot.data ?? [];
            final trustScore = _calculateTrustScore(userData, trustHistory);

            return DraggableScrollableSheet(
              initialChildSize: 0.5,
              minChildSize: 0.3,
              maxChildSize: 0.6,
              expand: false,
              builder: (context, scrollController) {
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: ListView(
                    controller: scrollController,
                    physics: const BouncingScrollPhysics(),
                    shrinkWrap: false,
                    children: [
                      const SizedBox(height: 10),

                      // Trust Score Circle - identical to profile page
                      Center(
                        child: SizedBox(
                          width: 120,
                          height: 120,
                          child: CustomPaint(
                            size: const Size(120, 120),
                            painter: TrustScorePainter(
                              progress: 1.0,
                              score: trustScore,
                              color: getTrustColor(trustScore),
                            ),
                            child: Center(
                              child: Text(
                                '$trustScore',
                                style: TextStyle(
                                  color: getTrustColor(trustScore),
                                  fontSize: 36,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  const SizedBox(height: 8),
                  if (isOwnProfile)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Trust Score',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _showHowTrustWorks = !_showHowTrustWorks;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.3),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _showHowTrustWorks ? Icons.close : Icons.info,
                              color: Colors.blue,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    Center(
                      child: Text(
                        (userData['display_name'] as String?) ??
                            (userData['full_name'] as String?) ??
                            'User',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),

                  // Show either how trust works or violation history
                  if (_showHowTrustWorks)
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'How to Gain Trust',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 12),
                        
                        // Image Verification
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Upload & Verify Image',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      '+15 trust points',
                                      style: TextStyle(
                                        color: Colors.green,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.check_circle, color: Colors.green, size: 20),
                            ],
                          ),
                        ),

                        // Successful Orders
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Complete Order (No Problems)',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      '+5 trust points per order',
                                      style: TextStyle(
                                        color: Colors.green,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.check_circle, color: Colors.green, size: 20),
                            ],
                          ),
                        ),

                        // Successful Services
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Complete Service (No Problems)',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      '+5 trust points per service',
                                      style: TextStyle(
                                        color: Colors.green,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.check_circle, color: Colors.green, size: 20),
                            ],
                          ),
                        ),

                        // Re-verify Image
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Re-verify Changed Image',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      '+15 trust points',
                                      style: TextStyle(
                                        color: Colors.green,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.check_circle, color: Colors.green, size: 20),
                            ],
                          ),
                        ),

                        SizedBox(height: 20),
                        Text(
                          'How to Lose Trust',
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 12),

                        // Bad Language
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Inappropriate Language in Chat',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      '-5 trust points per violation',
                                      style: TextStyle(
                                        color: Colors.red,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.cancel, color: Colors.red, size: 20),
                            ],
                          ),
                        ),

                        // Image Policy Violation
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Image Policy Violation',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      '-10 trust points',
                                      style: TextStyle(
                                        color: Colors.red,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.cancel, color: Colors.red, size: 20),
                            ],
                          ),
                        ),

                        // Image Changed
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Change Verified Image',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      '-15 trust points (verification removed)',
                                      style: TextStyle(
                                        color: Colors.red,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.cancel, color: Colors.red, size: 20),
                            ],
                          ),
                        ),

                        // Dispute Loss
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Lose Dispute (Seller)',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      '-10 trust points',
                                      style: TextStyle(
                                        color: Colors.red,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.cancel, color: Colors.red, size: 20),
                            ],
                          ),
                        ),

                        // Return
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Order Return (Seller)',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      '-10 trust points',
                                      style: TextStyle(
                                        color: Colors.red,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.cancel, color: Colors.red, size: 20),
                            ],
                          ),
                        ),

                        // Incomplete Service
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Incomplete Service (Seller)',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      '-10 trust points',
                                      style: TextStyle(
                                        color: Colors.red,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.cancel, color: Colors.red, size: 20),
                            ],
                          ),
                        ),

                        // Fraudulent Product
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Fraudulent Product (3rd Attempt)',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      '-10 trust points',
                                      style: TextStyle(
                                        color: Colors.red,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.cancel, color: Colors.red, size: 20),
                            ],
                          ),
                        ),
                      ],
                    )
                  else
                    // Show Trust History - plain text rows, no containers
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (trustHistory.isEmpty)
                          const Center(
                            child: Text(
                              'No history yet',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          )
                        else
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Render all trust history entries as plain text rows
                              ...trustHistory.map((entry) {
                                final reason = entry['reason'] as String? ?? 'Trust adjustment';
                                final points = (entry['points'] as num?)?.toInt() ?? 0;
                                final timestamp = entry['timestamp'];
                                
                                final isPositive = points >= 0;
                                final color = isPositive ? Colors.green : Colors.red;
                                final pointsText = isPositive ? '+$points' : '$points';
                                
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            reason,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          pointsText,
                                          style: TextStyle(
                                            color: color,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (timestamp != null)
                                      Text(
                                        _formatTimestamp(timestamp),
                                        style: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 10,
                                        ),
                                      ),
                                    const SizedBox(height: 12),
                                  ],
                                );
                              }),
                            ],
                          ),
                      ],
                    ),

                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
            },
          );
      },
    );
  }
}
