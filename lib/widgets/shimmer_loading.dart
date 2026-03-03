import 'package:flutter/material.dart';

// ─── Synchronized shimmer animation ───

/// Place ONE of these at the top of a page/scaffold to drive all
/// [ShimmerLoading] descendants with the same animation tick.
/// If no [ShimmerScope] ancestor exists, [ShimmerLoading] creates its own
/// controller (backwards-compatible).
class ShimmerScope extends StatefulWidget {
  final Widget child;
  const ShimmerScope({super.key, required this.child});

  @override
  State<ShimmerScope> createState() => _ShimmerScopeState();
}

class _ShimmerScopeState extends State<ShimmerScope>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ShimmerProvider(
      animation: _controller,
      child: widget.child,
    );
  }
}

class _ShimmerProvider extends InheritedWidget {
  final Animation<double> animation;
  const _ShimmerProvider({required this.animation, required super.child});

  static _ShimmerProvider? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ShimmerProvider>();

  @override
  bool updateShouldNotify(_ShimmerProvider old) => animation != old.animation;
}

/// Animated shimmer effect. Syncs with [ShimmerScope] if one exists above,
/// otherwise runs its own animation.
class ShimmerLoading extends StatefulWidget {
  final Widget child;
  const ShimmerLoading({super.key, required this.child});

  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading>
    with SingleTickerProviderStateMixin {
  AnimationController? _ownController;

  Animation<double> _resolveAnimation(BuildContext context) {
    final provider = _ShimmerProvider.of(context);
    if (provider != null) {
      _ownController?.dispose();
      _ownController = null;
      return provider.animation;
    }
    _ownController ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    return _ownController!;
  }

  @override
  void dispose() {
    _ownController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final anim = _resolveAnimation(context);
    return AnimatedBuilder(
      animation: anim,
      builder: (context, _) {
        final v = anim.value;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: const [
                Color(0xFF2A2A2A),
                Color(0xFF3A3A3A),
                Color(0xFF2A2A2A),
              ],
              stops: [
                (v - 0.3).clamp(0.0, 1.0),
                v.clamp(0.0, 1.0),
                (v + 0.3).clamp(0.0, 1.0),
              ],
            ).createShader(bounds);
          },
          child: widget.child,
        );
      },
    );
  }
}

// ─── Building blocks ───

/// A single ghost rectangle.
class GhostBox extends StatelessWidget {
  final double? width;
  final double height;
  final double borderRadius;

  const GhostBox({
    super.key,
    this.width,
    this.height = 16,
    this.borderRadius = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

/// Ghost circle for avatar placeholders.
class GhostCircle extends StatelessWidget {
  final double radius;
  const GhostCircle({super.key, this.radius = 20});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: const BoxDecoration(
        color: Color(0xFF2A2A2A),
        shape: BoxShape.circle,
      ),
    );
  }
}

// ─── Pre-built skeleton layouts ───

/// Ghost card for a user row (avatar + name).
class GhostUserRow extends StatelessWidget {
  const GhostUserRow({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          GhostCircle(radius: 20),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GhostBox(width: 120, height: 14),
                SizedBox(height: 6),
                GhostBox(width: 80, height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Ghost card for stats row (3 stat items).
class GhostStatsRow extends StatelessWidget {
  const GhostStatsRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(3, (_) {
          return const Column(
            children: [
              GhostBox(width: 28, height: 28, borderRadius: 14),
              SizedBox(height: 8),
              GhostBox(width: 32, height: 20),
              SizedBox(height: 4),
              GhostBox(width: 48, height: 12),
            ],
          );
        }),
      ),
    );
  }
}

/// Ghost card for a text block / description.
class GhostTextBlock extends StatelessWidget {
  final int lines;
  const GhostTextBlock({super.key, this.lines = 3});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(lines, (i) {
          return Padding(
            padding: EdgeInsets.only(bottom: i < lines - 1 ? 8 : 0),
            child: GhostBox(
              width: i == lines - 1 ? 160 : double.infinity,
              height: 14,
            ),
          );
        }),
      ),
    );
  }
}

/// Ghost for a profile header (avatar + title + subtitle).
class GhostProfileHeader extends StatelessWidget {
  const GhostProfileHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GhostCircle(radius: 35),
        SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GhostBox(width: 180, height: 16),
              SizedBox(height: 8),
              GhostBox(width: 100, height: 14),
            ],
          ),
        ),
      ],
    );
  }
}

/// Full-page ghost skeleton for detail pages.
class GhostDetailPage extends StatelessWidget {
  const GhostDetailPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 50, 20, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GhostBox(width: double.infinity, height: 220, borderRadius: 24),
          SizedBox(height: 16),
          GhostProfileHeader(),
          SizedBox(height: 16),
          GhostTextBlock(lines: 4),
          SizedBox(height: 16),
          GhostStatsRow(),
        ],
      ),
    );
  }
}

/// A single ghost product card matching the real ProductCardWidget shape.
/// Real card: 85/15 flex split, 24 border radius, price pill top center,
/// circle cutout bottom-right, title centered in bottom 15%.
class GhostProductCard extends StatelessWidget {
  const GhostProductCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
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
            children: [
              // Image section — 85% of card
              Expanded(
                flex: 85,
                child: Container(
                  color: const Color(0xFF2A2A2A),
                  child: Stack(
                    children: [
                      // Price pill ghost at top center
                      Positioned(
                        top: 5,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            width: 60,
                            height: 22,
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.1),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Title section — 15% of card
              Expanded(
                flex: 15,
                child: Container(
                  color: const Color(0xFF1A1A1A),
                  child: const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: GhostBox(width: 80, height: 13),
                    ),
                  ),
                ),
              ),
            ],
          ),
          // Circle cutout area bottom-right (matches real 38px circle)
          Positioned(
            bottom: 0,
            right: 0,
            child: FractionalTranslation(
              translation: const Offset(0, -0.15),
              child: Transform.translate(
                offset: const Offset(-5, -20),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: const BoxDecoration(
                    color: Color(0xFF1A1A1A),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
          // Favorite button ghost on top of circle
          Positioned(
            bottom: 0,
            right: 0,
            child: FractionalTranslation(
              translation: const Offset(0, -0.15),
              child: Transform.translate(
                offset: const Offset(-8, -24),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: Color(0xFF2A2A2A),
                    shape: BoxShape.circle,
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

/// Ghost card for list mode — matches the real list card (80px height, image left, text right).
class GhostListCard extends StatelessWidget {
  const GhostListCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      height: 80,
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          // Image placeholder
          Container(
            width: 80,
            height: 80,
            decoration: const BoxDecoration(
              color: Color(0xFF2A2A2A),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(24),
                bottomLeft: Radius.circular(24),
              ),
            ),
          ),
          // Text placeholder
          const Expanded(
            child: Padding(
              padding: EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GhostBox(width: double.infinity, height: 14),
                  SizedBox(height: 8),
                  GhostBox(width: 80, height: 16),
                ],
              ),
            ),
          ),
          // Favorite button placeholder
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: GhostCircle(radius: 16),
          ),
        ],
      ),
    );
  }
}
