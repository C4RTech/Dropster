import 'dart:math' as math;
import 'package:flutter/material.dart';

class DropsterAnimatedSymbol extends StatefulWidget {
  final double value; // 0.0 a 1.0 (nivel del tanque)
  final double size;
  final Color? primaryColor;
  final Color? secondaryColor;
  final Duration animationDuration;
  final VoidCallback? onTap;

  const DropsterAnimatedSymbol({
    super.key,
    required this.value,
    this.size = 140,
    this.primaryColor,
    this.secondaryColor,
    this.animationDuration = const Duration(milliseconds: 800),
    this.onTap,
  });

  @override
  State<DropsterAnimatedSymbol> createState() => _DropsterAnimatedSymbolState();
}

class _DropsterAnimatedSymbolState extends State<DropsterAnimatedSymbol>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _glowAnimation;
  late Animation<double> _fillAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.animationDuration,
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    ));

    _glowAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));

    _fillAnimation = Tween<double>(
      begin: 0.0,
      end: widget.value,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));

    _controller.forward();
  }

  @override
  void didUpdateWidget(DropsterAnimatedSymbol oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _fillAnimation = Tween<double>(
        begin: _fillAnimation.value,
        end: widget.value,
      ).animate(CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ));
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = widget.primaryColor ?? const Color(0xFF00CFC8);
    final secondaryColor = widget.secondaryColor ?? const Color(0xFF155263);

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return SizedBox(
            width: widget.size,
            height: widget.size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Efecto de brillo/glow
                Container(
                  width: widget.size * 1.2,
                  height: widget.size * 1.2,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: primaryColor.withOpacity(0.3 * _glowAnimation.value),
                        blurRadius: 20 * _glowAnimation.value,
                        spreadRadius: 5 * _glowAnimation.value,
                      ),
                    ],
                  ),
                ),
                
                // Contenedor principal con el símbolo
                Transform.scale(
                  scale: _scaleAnimation.value,
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          primaryColor.withOpacity(0.1),
                          primaryColor.withOpacity(0.05),
                        ],
                        stops: [0.0, 1.0],
                      ),
                    ),
                    child: Stack(
                      children: [
                        // Imagen del símbolo de Dropster
                        Center(
                          child: Image.asset(
                            'lib/assets/images/Dropster_simbolo.png',
                            width: widget.size * 0.7,
                            height: widget.size * 0.7,
                            fit: BoxFit.contain,
                          ),
                        ),
                        
                        // Indicador de llenado (línea circular)
                        Positioned.fill(
                          child: AnimatedBuilder(
                            animation: _fillAnimation,
                            builder: (context, child) {
                              return CustomPaint(
                                painter: TankLevelPainter(
                                  fillLevel: _fillAnimation.value,
                                  primaryColor: primaryColor,
                                  secondaryColor: secondaryColor,
                                  strokeWidth: 6.0,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class TankLevelPainter extends CustomPainter {
  final double fillLevel;
  final Color primaryColor;
  final Color secondaryColor;
  final double strokeWidth;

  TankLevelPainter({
    required this.fillLevel,
    required this.primaryColor,
    required this.secondaryColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Fondo del círculo (vacío)
    final backgroundPaint = Paint()
      ..color = secondaryColor.withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, backgroundPaint);

    // Llenado del círculo
    if (fillLevel > 0) {
      final fillPaint = Paint()
        ..shader = LinearGradient(
          colors: [primaryColor, secondaryColor],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Rect.fromCircle(center: center, radius: radius))
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      // Calcular el ángulo de llenado (de -90° a 270°)
      final sweepAngle = 2 * math.pi * fillLevel;
      const startAngle = -math.pi / 2; // Comenzar desde arriba

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        fillPaint,
      );
    }
  }

  @override
  bool shouldRepaint(TankLevelPainter oldDelegate) {
    return oldDelegate.fillLevel != fillLevel ||
           oldDelegate.primaryColor != primaryColor ||
           oldDelegate.secondaryColor != secondaryColor ||
           oldDelegate.strokeWidth != strokeWidth;
  }
}

