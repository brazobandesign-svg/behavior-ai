import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../theme/exodo_theme.dart';

/// Botón flotante "scroll to bottom" que aparece cuando el usuario
/// ha scrolleado arriba en una conversación larga.
///
/// Diseñado para Éxodo:
///   • Solo aparece cuando hay mensajes y el usuario NO está al final.
///   • Tap = animación suave al último mensaje.
///   • Esquina inferior derecha, encima del composer.
///   • Circular con tinte ámbar Éxodo + ícono chevron-down.
///   • Haptic feedback al tap.
///   • Misma forma/peso visual que el botón de enviar del composer
///     (40dp, círculo, fondo oscuro en dark / claro en light).
class ScrollToBottomButton extends StatefulWidget {
  final ScrollController controller;
  final int messagesCount;
  final int thresholdMessages;

  const ScrollToBottomButton({
    super.key,
    required this.controller,
    required this.messagesCount,
    this.thresholdMessages = 4,
  });

  @override
  State<ScrollToBottomButton> createState() => ScrollToBottomButtonState();
}

class ScrollToBottomButtonState extends State<ScrollToBottomButton> {
  bool _isAtBottom = true;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
    _isAtBottom = _checkAtBottom();
  }

  @override
  void didUpdateWidget(covariant ScrollToBottomButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onScroll);
      widget.controller.addListener(_onScroll);
    }
    // Si la cantidad de mensajes cambió (probablemente creció), forzar
    // re-evaluación de "estoy al final" porque la lista se hizo más larga.
    if (oldWidget.messagesCount != widget.messagesCount) {
      _isAtBottom = _checkAtBottom();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  bool _checkAtBottom() {
    if (!widget.controller.hasClients) return true;
    final pos = widget.controller.position;
    if (!pos.hasContentDimensions) return true;
    // Tolerancia pequeña para detectar scroll hacia arriba
    return pos.pixels >= pos.maxScrollExtent - 15;
  }

  void _onScroll() {
    if (!mounted) return;
    final atBottom = _checkAtBottom();
    if (atBottom != _isAtBottom) {
      setState(() => _isAtBottom = atBottom);
    }
  }

  void _scrollToBottom() {
    if (!widget.controller.hasClients) return;
    final pos = widget.controller.position;
    if (!pos.hasContentDimensions) return;
    widget.controller.animateTo(
      pos.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isGenerating = context.watch<AppState>().isGenerating;

    if (widget.messagesCount == 0) {
      return const SizedBox.shrink();
    }
    if (_isAtBottom) return const SizedBox.shrink();

    final isLight = Theme.of(context).brightness == Brightness.light;
    final bgColor = isLight ? const Color(0xFFE5DECF) : ExodoColors.composerBg;
    final fgColor = ExodoColors.amber;
    final borderColor = isLight ? const Color(0xFFD4CEBF) : Colors.transparent;

    return AnimatedScale(
      scale: 1.0,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutBack,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (isGenerating)
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(ExodoColors.amber),
              ),
            ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                _scrollToBottom();
              },
              customBorder: const CircleBorder(),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: bgColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: borderColor, width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isLight ? 0.10 : 0.45),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: fgColor,
                  size: 22,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}