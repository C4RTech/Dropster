import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class ProfessionalWaterDrop extends StatefulWidget {
  final double value; // 0.0 a 1.0
  final double size;
  final Color? primaryColor;
  final Color? secondaryColor;
  final Duration animationDuration;
  final VoidCallback? onTap;

  const ProfessionalWaterDrop({
    Key? key,
    required this.value,
    this.size = 140,
    this.primaryColor,
    this.secondaryColor,
    this.animationDuration = const Duration(milliseconds: 1500),
    this.onTap,
  }) : super(key: key);

  @override
  State<ProfessionalWaterDrop> createState() => _ProfessionalWaterDropState();
}

class _ProfessionalWaterDropState extends State<ProfessionalWaterDrop>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _glowAnimation;
  late Animation<double> _liquidAnimation;

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

    _liquidAnimation = Tween<double>(
      begin: 0.0,
      end: widget.value,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));

    _controller.forward();
  }

  @override
  void didUpdateWidget(ProfessionalWaterDrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _liquidAnimation = Tween<double>(
        begin: oldWidget.value,
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
    final theme = Theme.of(context);
    final primaryColor = widget.primaryColor ?? theme.colorScheme.secondary;
    final secondaryColor = widget.secondaryColor ?? theme.colorScheme.primary;

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              width: widget.size,
              height: widget.size * 1.3,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Sombra de fondo mejorada
                  Positioned(
                    bottom: 0,
                    child: Container(
                      width: widget.size * 0.8,
                      height: widget.size * 0.12,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(widget.size * 0.06),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.1),
                            Colors.black.withOpacity(0.3),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.25),
                            blurRadius: 15,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Gota principal con múltiples capas
                  Container(
                    width: widget.size,
                    height: widget.size * 1.3,
                    child: Stack(
                      children: [
                        // Capa de fondo con gradiente sutil
                        Container(
                          width: widget.size,
                          height: widget.size * 1.3,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              center: Alignment.topCenter,
                              radius: 0.8,
                              colors: [
                                Colors.white.withOpacity(0.1),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),

                        // Líquido con gradiente mejorado
                        ClipPath(
                          clipper: _WaterDropClipper(),
                          child: AnimatedBuilder(
                            animation: _liquidAnimation,
                            builder: (context, child) {
                              return CustomPaint(
                                size: Size(widget.size, widget.size * 1.3),
                                painter: _LiquidPainter(
                                  fillLevel: _liquidAnimation.value,
                                  primaryColor: primaryColor,
                                  secondaryColor: secondaryColor,
                                ),
                              );
                            },
                          ),
                        ),

                        // Gota SVG principal con efectos mejorados
                        AnimatedBuilder(
                          animation: _glowAnimation,
                          builder: (context, child) {
                            return Container(
                              width: widget.size,
                              height: widget.size * 1.3,
                              decoration: BoxDecoration(
                                boxShadow: [
                                  BoxShadow(
                                    color: primaryColor.withOpacity(
                                        0.4 * _glowAnimation.value),
                                    blurRadius: 25,
                                    spreadRadius: 8,
                                  ),
                                  BoxShadow(
                                    color: secondaryColor.withOpacity(
                                        0.2 * _glowAnimation.value),
                                    blurRadius: 40,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: SvgPicture.asset(
                                'lib/assets/images/water_drop.svg',
                                width: widget.size,
                                height: widget.size * 1.3,
                                colorFilter: ColorFilter.mode(
                                  Colors.white.withOpacity(0.9),
                                  BlendMode.srcATop,
                                ),
                              ),
                            );
                          },
                        ),

                        // Efecto de brillo superior
                        Positioned(
                          top: widget.size * 0.15,
                          left: widget.size * 0.35,
                          child: Container(
                            width: widget.size * 0.3,
                            height: widget.size * 0.2,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  Colors.white.withOpacity(0.6),
                                  Colors.white.withOpacity(0.2),
                                  Colors.transparent,
                                ],
                                stops: [0.0, 0.5, 1.0],
                              ),
                            ),
                          ),
                        ),

                        // Efecto de reflexión lateral
                        Positioned(
                          top: widget.size * 0.4,
                          right: widget.size * 0.15,
                          child: Transform.rotate(
                            angle: 0.3,
                            child: Container(
                              width: widget.size * 0.15,
                              height: widget.size * 0.4,
                              decoration: BoxDecoration(
                                borderRadius:
                                    BorderRadius.circular(widget.size * 0.075),
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.white.withOpacity(0.4),
                                    Colors.white.withOpacity(0.1),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Indicador de nivel (opcional - se puede quitar si no se quiere)
                  if (widget.value > 0)
                    Positioned(
                      bottom: widget.size * 0.1,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          '${(widget.value * 100).toInt()}%',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: secondaryColor,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _WaterDropClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    final width = size.width;
    final height = size.height;

    // Forma de gota más elegante y natural
    path.moveTo(width * 0.5, height * 0.08); // Punta superior más afilada

    // Curva superior izquierda
    path.quadraticBezierTo(
      width * 0.2,
      height * 0.25,
      width * 0.15,
      height * 0.5,
    );

    // Parte inferior izquierda
    path.quadraticBezierTo(
      width * 0.12,
      height * 0.75,
      width * 0.25,
      height * 0.92,
    );

    // Parte inferior central (base de la gota)
    path.quadraticBezierTo(
      width * 0.5,
      height * 0.98,
      width * 0.75,
      height * 0.92,
    );

    // Parte inferior derecha
    path.quadraticBezierTo(
      width * 0.88,
      height * 0.75,
      width * 0.85,
      height * 0.5,
    );

    // Curva superior derecha
    path.quadraticBezierTo(
      width * 0.8,
      height * 0.25,
      width * 0.5,
      height * 0.08,
    );
    path.close();

    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _LiquidPainter extends CustomPainter {
  final double fillLevel;
  final Color primaryColor;
  final Color secondaryColor;

  _LiquidPainter({
    required this.fillLevel,
    required this.primaryColor,
    required this.secondaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    final liquidHeight = height * (1 - fillLevel);

    // Gradiente vertical para el líquido usando colores dinámicos
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        primaryColor.withOpacity(0.9), // Color primario con opacidad
        primaryColor.withOpacity(0.7), // Color primario más claro
        secondaryColor.withOpacity(0.8), // Color secundario
      ],
      stops: [0.0, 0.5, 1.0],
    );
    final rect = Rect.fromLTWH(0, liquidHeight, width, height - liquidHeight);
    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.fill;

    // Superficie curva tipo onda (sin vibración)
    final path = Path();
    path.moveTo(width * 0.15, height);
    path.lineTo(width * 0.15, liquidHeight);
    for (double x = width * 0.15; x <= width * 0.85; x += 1) {
      final progress = (x - width * 0.15) / (width * 0.7);
      final y = liquidHeight + 8 * math.sin(progress * 2 * math.pi);
      path.lineTo(x, y);
    }
    path.lineTo(width * 0.85, height);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return oldDelegate is _LiquidPainter && oldDelegate.fillLevel != fillLevel;
  }
}

class _WaveEffect extends StatefulWidget {
  final double size;
  final Color color;

  const _WaveEffect({
    required this.size,
    required this.color,
  });

  @override
  State<_WaveEffect> createState() => _WaveEffectState();
}

class _WaveEffectState extends State<_WaveEffect>
    with TickerProviderStateMixin {
  late AnimationController _waveController;
  late Animation<double> _waveAnimation;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    _waveAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _waveController,
      curve: Curves.easeInOut,
    ));
    _waveController.repeat();
  }

  @override
  void dispose() {
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _waveAnimation,
      builder: (context, child) {
        return Container(
          width: widget.size,
          height: widget.size * 0.3,
          child: CustomPaint(
            painter: _WavePainter(
              animation: _waveAnimation.value,
              color: widget.color,
            ),
          ),
        );
      },
    );
  }
}

class _WavePainter extends CustomPainter {
  final double animation;
  final Color color;

  _WavePainter({
    required this.animation,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final path = Path();
    final width = size.width;
    final height = size.height;

    path.moveTo(0, height * 0.5);

    for (double x = 0; x <= width; x += 1) {
      final y = height * 0.5 +
          height *
              0.2 *
              math.sin((x / width * 4 * math.pi) + (animation * 2 * math.pi));
      path.lineTo(x, y);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
