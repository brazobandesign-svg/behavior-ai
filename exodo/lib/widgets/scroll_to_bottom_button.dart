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
  final VoidCallback? onPressed;

  const ScrollToBottomButton({
    super.key,
    required this.controller,
    required this.messagesCount,
    this.thresholdMessages = 4,
    this.onPressed,
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
    final bgColor = isLight ? const Color(0xFFE8E8E8) : ExodoColors.composerBg;
    final fgColor = ExodoColors.amber;
    final borderColor = isLight ? const Color(0xFFDDDDDD) : Colors.transparent;

    return AnimatedScale(
      scale: 1.0,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutBack,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                widget.onPressed?.call();
                _scrollToBottom();
              },
              customBorder: const CircleBorder(),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: bgColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isGenerating ? Colors.transparent : borderColor,
                    width: 1,
                  ),
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
          if (isGenerating)
            const IgnorePointer(
              child: SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  strokeWidth: 2.0,
                  valueColor: AlwaysStoppedAnimation<Color>(ExodoColors.amber),
                ),
              ),
            ),
        ],
      ),
    );
  }
}