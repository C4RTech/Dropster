import 'package:flutter/material.dart';

class CircularCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final Color? borderColor;
  final VoidCallback? onTap;
  final bool showBorder;
  final double size;
  final String? subtitle;

  const CircularCard({
    Key? key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.borderColor,
    this.onTap,
    this.showBorder = true,
    this.size = 120,
    this.subtitle,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withOpacity(0.1),
          border: showBorder
              ? Border.all(
                  color: borderColor ?? color,
                  width: 2,
                )
              : null,
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: color,
              size: size * 0.3,
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: size * 0.15,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                style: TextStyle(
                  fontSize: size * 0.08,
                  color: color.withOpacity(0.7),
                ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: size * 0.08,
                fontWeight: FontWeight.w500,
                color: color.withOpacity(0.8),
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class AnimatedCircularCard extends StatefulWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final Color? borderColor;
  final VoidCallback? onTap;
  final bool showBorder;
  final double size;
  final String? subtitle;
  final Duration animationDuration;

  const AnimatedCircularCard({
    Key? key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.borderColor,
    this.onTap,
    this.showBorder = true,
    this.size = 120,
    this.subtitle,
    this.animationDuration = const Duration(milliseconds: 300),
  }) : super(key: key);

  @override
  State<AnimatedCircularCard> createState() => _AnimatedCircularCardState();
}

class _AnimatedCircularCardState extends State<AnimatedCircularCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.animationDuration,
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    ));
    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    ));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Opacity(
            opacity: _opacityAnimation.value,
            child: CircularCard(
              title: widget.title,
              value: widget.value,
              icon: widget.icon,
              color: widget.color,
              borderColor: widget.borderColor,
              onTap: widget.onTap,
              showBorder: widget.showBorder,
              size: widget.size,
              subtitle: widget.subtitle,
            ),
          ),
        );
      },
    );
  }
}

class StatusCircularCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final bool isActive;
  final VoidCallback? onTap;
  final double size;

  const StatusCircularCard({
    Key? key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.isActive,
    this.onTap,
    this.size = 120,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CircularCard(
      title: title,
      value: value,
      icon: icon,
      color: isActive ? color : Colors.grey,
      borderColor: isActive ? color : Colors.grey,
      onTap: onTap,
      size: size,
      subtitle: isActive ? 'Activo' : 'Inactivo',
    );
  }
}
