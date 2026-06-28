import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/exodo_theme.dart';
import '../l10n/app_i18n.dart';
import '../services/widget_service.dart';

/// Sección/Pantalla interactiva para previsualizar y elegir los Widgets Horizontales
/// estilo Grok & X con estética elegante, dark y acentos en ámbar.
class HorizontalWidgetsPreview extends StatefulWidget {
  const HorizontalWidgetsPreview({super.key});

  static void show(BuildContext context) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: ExodoColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 650),
          child: const HorizontalWidgetsPreview(),
        ),
      ),
    );
  }

  @override
  State<HorizontalWidgetsPreview> createState() => _HorizontalWidgetsPreviewState();
}

class _HorizontalWidgetsPreviewState extends State<HorizontalWidgetsPreview> {
  final TextEditingController _chatController = TextEditingController();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _chatController.addListener(() {
      final textNotEmpty = _chatController.text.trim().isNotEmpty;
      if (textNotEmpty != _hasText) {
        setState(() {
          _hasText = textNotEmpty;
        });
      }
    });
  }

  @override
  void dispose() {
    _chatController.dispose();
    super.dispose();
  }

  void _onPinWidget(String type, String name) async {
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Sincronizando widget $name...', style: GoogleFonts.inter(color: Colors.white)),
        backgroundColor: const Color(0xFF221F1C),
        duration: const Duration(seconds: 2),
      ),
    );
    await WidgetService.instance.requestPinWidget(type: type);
  }

  @override
  Widget build(BuildContext context) {
    final isEn = AppI18n.of(context).localeCode == 'en';

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Indicador del BottomSheet
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Encabezado
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: ExodoColors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: ExodoColors.amber.withValues(alpha: 0.3)),
                  ),
                  child: const Icon(Icons.widgets_rounded, color: ExodoColors.amber, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isEn ? 'Grok Style Widgets' : 'Widgets Horizontales',
                        style: GoogleFonts.syne(fontSize: 20, fontWeight: FontWeight.bold, color: ExodoColors.textPrimary),
                      ),
                      Text(
                        isEn ? 'Sleek dark aesthetics inspired by Grok & X' : 'Estética elegante dark inspirada en Grok & X',
                        style: GoogleFonts.inter(fontSize: 13, color: ExodoColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),

            // SECCIÓN 1: WIDGET BOTÓN / FUNCIÓN INTERNA
            Text(
              isEn ? 'OPTION 1 · QUICK LAUNCH BOX' : 'OPCIÓN 1 · ACCESO DIRECTO',
              style: GoogleFonts.jetBrainsMono(fontSize: 12, fontWeight: FontWeight.w600, color: ExodoColors.amber, letterSpacing: 1.0),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => _onPinWidget('horizontal', isEn ? 'Quick Launch' : 'Acceso Directo'),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF161412),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: ExodoColors.border),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: Row(
                  children: [
                    Image.asset('assets/images/Logo_behavior.png', width: 28, height: 28),
                    const SizedBox(width: 12),
                    Text(
                      'Éxodo AI',
                      style: GoogleFonts.syne(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(isEn ? 'Open App' : 'Abrir App', style: GoogleFonts.inter(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w500)),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_forward_rounded, size: 14, color: Colors.white70),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),

            // SECCIÓN 2: WIDGET CAMPO DE TEXTO INTERACTIVO
            Text(
              isEn ? 'OPTION 2 · INTERACTIVE CHAT BAR' : 'OPCIÓN 2 · BARRA DE CHAT INTERACTIVA',
              style: GoogleFonts.jetBrainsMono(fontSize: 12, fontWeight: FontWeight.w600, color: ExodoColors.amber, letterSpacing: 1.0),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E1C19), Color(0xFF141210)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: _hasText ? ExodoColors.amber.withValues(alpha: 0.6) : const Color(0xFF332C24),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _hasText ? ExodoColors.amber.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.5),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Logo
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Image.asset('assets/images/Logo_behavior.png', width: 24, height: 24),
                  ),
                  const SizedBox(width: 8),
                  // Nombre en medio
                  Text(
                    'Éxodo',
                    style: GoogleFonts.syne(fontSize: 15, fontWeight: FontWeight.bold, color: ExodoColors.amber),
                  ),
                  Container(
                    height: 18,
                    width: 1,
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    color: Colors.white24,
                  ),
                  // Campo de texto
                  Expanded(
                    child: TextField(
                      controller: _chatController,
                      style: GoogleFonts.inter(fontSize: 14.5, color: Colors.white),
                      decoration: InputDecoration(
                        hintText: isEn ? 'Chat...' : 'Chat...',
                        hintStyle: GoogleFonts.inter(fontSize: 14.5, color: Colors.white38),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onSubmitted: (val) {
                        if (val.trim().isNotEmpty) {
                          _onPinWidget('horizontal', 'Chat Bar');
                        }
                      },
                    ),
                  ),
                  // Botón de Enviar
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _hasText ? ExodoColors.amber : Colors.white.withValues(alpha: 0.08),
                    ),
                    child: IconButton(
                      icon: Icon(
                        Icons.arrow_upward_rounded,
                        size: 20,
                        color: _hasText ? Colors.black : Colors.white30,
                      ),
                      onPressed: _hasText
                          ? () {
                              _onPinWidget('horizontal', 'Chat Bar');
                            }
                          : null,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              isEn
                  ? '💡 Tip: Type anything in the placeholder and hit send to test the live reactivity!'
                  : '💡 Consejo: Escribe en el campo para ver la activación instantánea del botón de envío estilo Grok.',
              style: GoogleFonts.inter(fontSize: 12, color: ExodoColors.textSecondary, fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 32),

            // Botón de confirmación / cerrar
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: ExodoColors.amber,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                onPressed: () => Navigator.pop(context),
                child: Text(
                  isEn ? 'Done' : 'Listo',
                  style: GoogleFonts.syne(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
