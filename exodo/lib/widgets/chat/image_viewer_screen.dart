import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../l10n/app_i18n.dart';
import '../../services/export/exporters.dart';
import '../../theme/exodo_theme.dart';
import 'image_generating_placeholder.dart';

/// Visor a pantalla completa para imágenes generadas por Éxodo.
///
/// - [InteractiveViewer] para paneo y zoom táctil.
/// - Fondo oscuro translúcido/negro.
/// - Acciones: descargar/guardar en galería (gal) y compartir (share sheet).
class ImageViewerScreen extends StatefulWidget {
  final String imageUrl;
  final String? heroTag;

  const ImageViewerScreen({
    super.key,
    required this.imageUrl,
    this.heroTag,
  });

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  bool _saving = false;

  Uri get _uri => Uri.tryParse(widget.imageUrl) ?? Uri();

  Future<Uint8List> _downloadBytes() async {
    final resp = await http.get(_uri).timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}');
    }
    return resp.bodyBytes;
  }

  String _extension() {
    final base = _uri.path;
    final dot = base.lastIndexOf('.');
    if (dot != -1 && dot < base.length - 1) {
      final ext = base.substring(dot + 1).toLowerCase();
      if (RegExp(r'^[a-z0-9]{2,5}$').hasMatch(ext)) return '.$ext';
    }
    return '.png';
  }

  Future<void> _saveToGallery() async {
    if (_saving) return;
    setState(() => _saving = true);
    HapticFeedback.lightImpact();

    try {
      final bytes = await _downloadBytes();

      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        final granted = await Gal.requestAccess();
        if (!granted) {
          throw Exception('Permiso de galería denegado');
        }
      }

      await Gal.putImageBytes(bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppI18n.of(context).t('image.saved')),
          backgroundColor: ExodoColors.surface,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      HapticFeedback.mediumImpact();
    } catch (e) {
      debugPrint('[ImageViewer] guardar en galería falló: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppI18n.of(context).t('image.save_error')),
            backgroundColor: ExodoColors.error,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _shareImage() async {
    if (_saving) return;
    setState(() => _saving = true);
    HapticFeedback.lightImpact();
    final messenger = ScaffoldMessenger.of(context);

    try {
      final bytes = await _downloadBytes();
      final dir = await getTemporaryDirectory();
      final file = File(
        p.join(
          dir.path,
          'exodo_imagen_${DateTime.now().millisecondsSinceEpoch}${_extension()}',
        ),
      );
      await file.writeAsBytes(bytes);
      if (!mounted) return;

      await ShareService.instance.shareFile(
        file,
        subject: 'Imagen generada por Éxodo',
      );
    } catch (e) {
      debugPrint('[ImageViewer] compartir imagen falló: $e');
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(AppI18n.of(context).t('image.save_error')),
          backgroundColor: ExodoColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppI18n.of(context).t;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.55),
        elevation: 0,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            tooltip: t('image.download'),
            onPressed: _saving ? null : _saveToGallery,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: ExodoColors.amber,
                    ),
                  )
                : const Icon(Icons.download_rounded),
          ),
          IconButton(
            tooltip: t('act.share'),
            onPressed: _saving ? null : _shareImage,
            icon: const Icon(Icons.share_outlined),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 5.0,
              clipBehavior: Clip.none,
              child: Center(
                child: Image.network(
                  widget.imageUrl,
                  fit: BoxFit.contain,
                  width: double.infinity,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    final total = loadingProgress.expectedTotalBytes;
                    final progress = total != null && total > 0
                        ? loadingProgress.cumulativeBytesLoaded / total
                        : null;
                    return ExodoShimmer(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        width: 240,
                        height: 240,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 30,
                                height: 30,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: ExodoColors.amber,
                                ),
                              ),
                              if (progress != null) ...[
                                const SizedBox(height: 12),
                                Text(
                                  '${(progress * 100).toStringAsFixed(0)}%',
                                  style: const TextStyle(color: Colors.white70),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stack) => const Center(
                    child: Text(
                      'No se pudo cargar la imagen',
                      style: TextStyle(color: Colors.white70),
                    ),
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