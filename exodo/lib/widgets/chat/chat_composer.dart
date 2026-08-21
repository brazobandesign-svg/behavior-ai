import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';

import '../../models/models.dart';
import '../../services/app_state.dart';
import '../../services/chat_service.dart';
import '../../data/repositories/attachment_storage.dart';
import '../../theme/exodo_theme.dart';
import '../../l10n/app_i18n.dart';

// [Punto 40] Datos temporales de un adjunto antes de leer sus bytes.
// [filePath] apunta a la copia permanente en `attachments/` creada en el
// momento de la selección; los bytes se conservan para el preview y el
// payload multimodal.
class PendingAttachment {
  final String name;
  final String mime;
  final Uint8List bytes;
  final String filePath;
  const PendingAttachment({
    required this.name,
    required this.mime,
    required this.bytes,
    this.filePath = '',
  });
}

/// Adivina el MIME type a partir de la extensión del archivo.
String mimeFromExtension(String fileName) {
  final ext = fileName.split('.').last.toLowerCase();
  switch (ext) {
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'gif':
      return 'image/gif';
    case 'webp':
      return 'image/webp';
    case 'bmp':
      return 'image/bmp';
    case 'svg':
      return 'image/svg+xml';
    case 'pdf':
      return 'application/pdf';
    case 'txt':
    case 'md':
      return 'text/plain';
    case 'json':
      return 'application/json';
    case 'xml':
      return 'application/xml';
    case 'csv':
      return 'text/csv';
    case 'doc':
    case 'docx':
      return 'application/msword';
    case 'bat':
    case 'sh':
      return 'text/plain';
    default:
      return 'application/octet-stream';
  }
}

/// Convierte un string MIME (ej. `audio/m4a`) en un `MediaType` de
/// `package:http_parser`, con fallback seguro a `application/octet-stream`.
MediaType _parseMediaType(String mime) {
  final parts = mime.split('/');
  if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) {
    return MediaType('application', 'octet-stream');
  }
  return MediaType(parts[0], parts[1]);
}

// Regla 5 & 9: Widget supremo de esfera donde cada punto cambia de tamaño aleatoriamente
// Optimizado con context.select para evitar repintado durante el streaming de mensajes.

// MIME type por defecto para el audio grabado. M4A/AAC es el formato nativo
// de iOS y se acepta correctamente por whisper-large-v3-turbo.
const String _kVoiceMime = 'audio/m4a';

class ChatComposer extends StatefulWidget {
  final TextEditingController controller;
  final void Function(List<Attachment>? attachments) onSend;
  final VoidCallback onModelTap;
  final VoidCallback onUpgradeTap;

  const ChatComposer({
    required this.controller,
    required this.onSend,
    required this.onModelTap,
    required this.onUpgradeTap,
    super.key,
  });

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer>
    with SingleTickerProviderStateMixin {
  late AnimationController _auraController;
  bool _hasAttachment = false;
  bool _isRecording = false;
  bool _isLongPressActive = false;
  bool _isTranscribing = false;
  final AudioRecorder _audioRecorder = AudioRecorder();
  String? _activeRecordingPath;
  final List<PendingAttachment> _pendingAttachments = [];

  @override
  void initState() {
    super.initState();
    _auraController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();
  }

  /// Inicia la grabación de audio. Solicita permiso de micrófono si hace falta.
  /// Devuelve `true` si la grabación arrancó correctamente.
  Future<bool> _startRecording() async {
    if (_isRecording || _isTranscribing) return false;
    try {
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        debugPrint('[STT] Permiso de micrófono no concedido');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Por favor concede permiso de micrófono para la entrada por voz.'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        return false;
      }
      final dir = await Directory.systemTemp.createTemp('exodo_voice_');
      final path =
          '${dir.path}/clip_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
      _activeRecordingPath = path;
      if (mounted) {
        setState(() => _isRecording = true);
      }
      debugPrint('[STT] Grabación iniciada en: $path');
      return true;
    } catch (e) {
      debugPrint('[STT] Error al iniciar grabación: $e');
      return false;
    }
  }

  /// Detiene la grabación activa y envía el audio al backend para transcripción.
  /// El texto devuelto se concatena al `widget.controller` en la posición del
  /// cursor (o al final si no hay selección).
  Future<void> _stopAndTranscribe() async {
    if (!_isRecording) return;
    final path = _activeRecordingPath;
    setState(() {
      _isRecording = false;
    });
    try {
      final resultPath = await _audioRecorder.stop();
      final finalPath = resultPath ?? path;
      if (finalPath == null) {
        debugPrint('[STT] _stopAndTranscribe: stop() devolvió null');
        return;
      }

      final file = File(finalPath);
      if (!await file.exists()) {
        debugPrint('[STT] Archivo no existe: $finalPath');
        return;
      }
      final length = await file.length();
      if (length < 100) {
        debugPrint('[STT] Clip demasiado corto (${length}B), descartado');
        return;
      }

      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return;

      if (mounted) {
        setState(() => _isTranscribing = true);
      }

      String? transcription;
      try {
        transcription = await _transcribeAudio(bytes);
      } catch (e) {
        debugPrint('[STT] Excepción en transcripción: $e');
      }

      if (!mounted) return;
      setState(() => _isTranscribing = false);

      if (transcription != null && transcription.isNotEmpty) {
        _appendTranscription(transcription);
      } else {
        HapticFeedback.lightImpact();
      }
    } catch (e) {
      debugPrint('[STT] _stopAndTranscribe error: $e');
    } finally {
      _activeRecordingPath = null;
      if (path != null) {
        try {
          await File(path).delete().catchError((_) => File(path));
        } catch (_) {}
      }
      if (mounted) {
        setState(() => _isTranscribing = false);
      }
    }
  }

  /// Envía los bytes de audio al endpoint de transcripción vía multipart.
  /// Itera sobre las URLs candidatas del backend (127.0.0.1, localhost, LAN, Railway).
  Future<String?> _transcribeAudio(Uint8List bytes) async {
    debugPrint('[STT] Iniciando transcripción de ${bytes.length} bytes...');
    final urls = ChatService.voiceTranscribeUrls;
    for (final candidateUrl in urls) {
      try {
        debugPrint('[STT] Intentando transcribir en: $candidateUrl');
        final uri = Uri.parse(candidateUrl);
        final request = http.MultipartRequest('POST', uri)
          ..fields['model'] = 'whisper-large-v3-turbo'
          ..fields['language'] = 'auto'
          ..fields['response_format'] = 'json'
          ..files.add(
            http.MultipartFile.fromBytes(
              'file',
              bytes,
              filename: 'audio.m4a',
              contentType: _parseMediaType(_kVoiceMime),
            ),
          );

        final streamed = await request.send().timeout(
              const Duration(seconds: 5),
            );
        final response = await http.Response.fromStream(streamed);
        if (response.statusCode == 200) {
          final body = jsonDecode(response.body);
          if (body is Map<String, dynamic>) {
            final text = body['text'];
            if (text is String && text.trim().isNotEmpty) {
              debugPrint('[STT] Transcripción exitosa: "$text"');
              return text.trim();
            }
          }
        } else {
          debugPrint('[STT] Error HTTP ${response.statusCode} desde $candidateUrl: ${response.body}');
        }
      } catch (e) {
        debugPrint('[STT] Fallo al conectar con $candidateUrl: $e');
        continue;
      }
    }
    debugPrint('[STT] Todos los candidatos del backend fallaron.');
    return null;
  }

  /// Inserta el texto transcrito en el `TextEditingController`, respetando
  /// la posición del cursor. Si no hay texto previo, lo reemplaza.
  void _appendTranscription(String text) {
    final controller = widget.controller;
    final selection = controller.selection;
    final current = controller.text;
    if (!selection.isValid) {
      controller.text = current.isEmpty
          ? text
          : (current.endsWith(' ') ? '$current$text' : '$current $text');
      controller.selection =
          TextSelection.collapsed(offset: controller.text.length);
      return;
    }
    final start = selection.start;
    final end = selection.end;
    final needsSpaceBefore =
        start > 0 && current[start - 1] != ' ' && current[start - 1] != '\n';
    final insertion = (needsSpaceBefore ? ' ' : '') + text;
    final newText = current.replaceRange(start, end, insertion);
    controller.text = newText;
    controller.selection =
        TextSelection.collapsed(offset: start + insertion.length);
  }

  Widget _buildAttachmentPreview() {
    if (_pendingAttachments.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 4),
        itemCount: _pendingAttachments.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final att = _pendingAttachments[i];
          final isImage = att.mime.startsWith('image/');
          final isLight = Theme.of(context).brightness == Brightness.light;
          if (isImage) {
            return Stack(
              children: [
                Container(
                  width: 62,
                  height: 62,
                  margin: const EdgeInsets.only(top: 6, right: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isLight ? const Color(0xFFD1D1D6) : const Color(0xFF3A3A3C),
                      width: 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: Image.memory(
                      att.bytes,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: () => _removePendingAt(i),
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: isLight ? const Color(0xFF131313) : const Color(0xFFFBF9F5),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.close,
                        size: 13,
                        color: isLight ? Colors.white : const Color(0xFF141414),
                      ),
                    ),
                  ),
                ),
              ],
            );
          } else {
            return Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isLight ? Colors.white : ExodoColors.modelChipBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isLight ? const Color(0xFFD1D1D6) : const Color(0xFF3A3A3C),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.insert_drive_file_rounded, size: 18, color: ExodoColors.amber),
                  const SizedBox(width: 8),
                  Text(
                    att.name.length > 18 ? '${att.name.substring(0, 15)}...' : att.name,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      color: isLight ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _removePendingAt(i),
                    child: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: isLight ? Colors.black54 : Colors.white70,
                    ),
                  ),
                ],
              ),
            );
          }
        },
      ),
    );
  }

  void _showAttachmentMenu() {
    HapticFeedback.vibrate();
    final isLight = Theme.of(context).brightness == Brightness.light;

    showModalBottomSheet(
      context: context,
      backgroundColor: isLight
          ? const Color(0xFFF5F2EB)
          : ExodoColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(
                  Icons.camera_alt_rounded,
                  color: ExodoColors.amber,
                ),
                title: Text(
                  AppI18n.of(context).t('attach.camera'),
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: isLight ? Colors.black87 : Colors.white,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    final picker = ImagePicker();
                    final photo = await picker.pickImage(
                      source: ImageSource.camera,
                      maxWidth: 1536,
                      maxHeight: 1536,
                      imageQuality: 80,
                    );
                    if (photo != null && mounted) {
                      final bytes = await photo.readAsBytes();
                      // Copia inmediata a almacenamiento permanente: la
                      // caché del picker es volátil y el OS puede purgarla
                      // antes de que el mensaje se guarde.
                      final permanentPath =
                          await AttachmentStorage.instance.persistPickedFile(
                        sourcePath: photo.path,
                        fileName: photo.name,
                      );
                      setState(() {
                        _hasAttachment = true;
                        _pendingAttachments.add(
                          PendingAttachment(
                            name: photo.name,
                            mime: 'image/jpeg',
                            bytes: Uint8List.fromList(bytes),
                            filePath: permanentPath,
                          ),
                        );
                      });
                    }
                  } catch (e) {
                    // Error silencioso
                  }
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_library_rounded,
                  color: ExodoColors.amber,
                ),
                title: Text(
                  AppI18n.of(context).t('attach.gallery'),
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: isLight ? Colors.black87 : Colors.white,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    final picker = ImagePicker();
                    final media = await picker.pickImage(
                      source: ImageSource.gallery,
                      maxWidth: 1536,
                      maxHeight: 1536,
                      imageQuality: 80,
                    );
                    if (media != null && mounted) {
                      final bytes = await media.readAsBytes();
                      final mime = mimeFromExtension(media.name);
                      // Misma copia inmediata a almacenamiento permanente
                      // que en el flujo de cámara.
                      final permanentPath =
                          await AttachmentStorage.instance.persistPickedFile(
                        sourcePath: media.path,
                        fileName: media.name,
                      );
                      setState(() {
                        _hasAttachment = true;
                        _pendingAttachments.add(
                          PendingAttachment(
                            name: media.name,
                            mime: mime,
                            bytes: Uint8List.fromList(bytes),
                            filePath: permanentPath,
                          ),
                        );
                      });
                    }
                  } catch (e) {
                    // Error silencioso
                  }
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.folder_open_rounded,
                  color: ExodoColors.amber,
                ),
                title: Text(
                  AppI18n.of(context).t('attach.files'),
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: isLight ? Colors.black87 : Colors.white,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    final res = await FilePicker.platform.pickFiles(
                      allowMultiple: true,
                      withData: true,
                    );
                    if (res != null && res.files.isNotEmpty && mounted) {
                      int added = 0;
                      for (final f in res.files) {
                        if (f.bytes != null && f.bytes!.isNotEmpty) {
                          // Documentos: misma garantía de persistencia que
                          // las imágenes cuando el picker expone la ruta.
                          var permanentPath = '';
                          if (f.path != null && f.path!.isNotEmpty) {
                            permanentPath =
                                await AttachmentStorage.instance
                                    .persistPickedFile(
                              sourcePath: f.path!,
                              fileName: f.name,
                            );
                          }
                          _pendingAttachments.add(
                            PendingAttachment(
                              name: f.name,
                              mime: mimeFromExtension(f.name),
                              bytes: f.bytes!,
                              filePath: permanentPath,
                            ),
                          );
                          added++;
                        }
                      }
                      if (added > 0) {
                        setState(() => _hasAttachment = true);
                      }
                    }
                  } catch (e) {
                    // Error silencioso
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Quita un adjunto pendiente (botón X del preview). Borra además su
  /// copia permanente: al no llegar a enviarse, ningún mensaje la
  /// referenciaría y quedaría huérfana en disco.
  void _removePendingAt(int i) {
    final removed = _pendingAttachments.removeAt(i);
    if (_pendingAttachments.isEmpty) _hasAttachment = false;
    setState(() {});
    if (removed.filePath.isNotEmpty) {
      try {
        File(removed.filePath).deleteSync();
      } catch (_) {}
    }
  }

  void _triggerSend() {
    final attachments = <Attachment>[];
    for (final pa in _pendingAttachments) {
      attachments.add(
        Attachment(
          filePath: pa.filePath,
          fileName: pa.name,
          bytes: pa.bytes,
          mimeType: pa.mime,
        ),
      );
    }

    setState(() {
      _hasAttachment = false;
      _isRecording = false;
      _pendingAttachments.clear();
    });

    // Desenfocar y vibrar ligero tras enviar
    FocusManager.instance.primaryFocus?.unfocus();
    HapticFeedback.lightImpact();

    // Enviar: si hay adjuntos, pasarlos; si no, null.
    widget.onSend(attachments.isEmpty ? null : attachments);
  }

  @override
  void dispose() {
    _auraController.dispose();
    // Best-effort: si todavía hay una grabación activa al desmontar el
    // widget, la cancelamos para no dejar el mic abierto.
    try {
      _audioRecorder.stop();
    } catch (_) {}
    _audioRecorder.dispose();
    super.dispose();
  }

  String _getPlaceholder(BuildContext context) {
    if (_isRecording) {
      return 'Grabando voz... (Toca para enviar)';
    }
    if (_isTranscribing) {
      return 'Transcribiendo voz...';
    }
    return AppI18n.of(context).t('chat.placeholder');
  }


  Widget _buildRecordingMicIcon() {
    return AnimatedBuilder(
      animation: _auraController,
      builder: (context, _) {
        final t = _auraController.value;
        final pulse = 0.6 + 0.4 * ((math.sin(t * math.pi * 2) + 1) / 2);
        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            const Icon(Icons.mic, color: ExodoColors.error),
            Positioned(
              top: -2,
              right: -2,
              child: Container(
                width: 8 + 4 * pulse,
                height: 8 + 4 * pulse,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ExodoColors.error.withValues(alpha: 0.9),
                  boxShadow: [
                    BoxShadow(
                      color: ExodoColors.error.withValues(alpha: 0.5 * pulse),
                      blurRadius: 6 * pulse,
                      spreadRadius: 1 * pulse,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
  @override
  Widget build(BuildContext context) {
    // Selectores finos para evitar repintado durante streaming de chat
    final isGenerating = context.select<AppState, bool>((s) => s.isGenerating);
    final showTab2Banner = context.select<AppState, bool>((s) => s.showTab2Banner);
    final isIncognito = context.select<AppState, bool>((s) => s.isIncognito);
    final isPro = context.select<AppState, bool>((s) => s.isPro);
    final isDarkMode = context.select<AppState, bool>((s) => s.isDarkMode);
    final selectedModel = context.select<AppState, ExodoModelOption>((s) => s.selectedModel);
    final profile = context.select<AppState, UserProfile?>((s) => s.profile);

    final isLight = !isDarkMode && !isIncognito;
    final state = context.read<AppState>();

    return Padding(
      padding: const EdgeInsets.only(left: 14, right: 14, bottom: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Visibility(
            visible:
                showTab2Banner &&
                !isIncognito &&
                !isPro &&
                profile != null,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: Container(
              width: MediaQuery.of(context).size.width * 0.86,
              padding: const EdgeInsets.fromLTRB(16, 8, 14, 22),
              decoration: BoxDecoration(
                color: isLight
                    ? const Color(0xFF252525)
                    : ExodoColors.textPrimary,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                border: isLight
                    ? Border.all(color: const Color(0xFF252525), width: 1.0)
                    : Border.all(color: Colors.transparent, width: 1.0),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      AppI18n.of(context).t('tokens.more_cap'),
                      style: TextStyle(fontFamily: 'AnthropicSans', 
                        color: isLight
                            ? ExodoColors.textPrimary
                            : ExodoColors.background,
                        fontSize: 12.0,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onUpgradeTap,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 4,
                        ),
                        child: _ShimmeringUpgradeText(
                          text: AppI18n.of(context).t('tokens.upgrade_btn'),
                          style: const TextStyle(
                            fontFamily: 'AnthropicSans',
                            fontWeight: FontWeight.bold,
                            fontSize: 12.0,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => state.dismissTab2Banner(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Icon(
                          Icons.close,
                          size: 16,
                          color: isLight ? ExodoColors.textPrimary : ExodoColors.background,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          Transform.translate(
            offset: const Offset(0, -14),
            child: Container(
              decoration: BoxDecoration(
                color: isLight
                    ? ExodoColors.textPrimary
                    : ExodoColors.composerBg,
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: Colors.transparent, width: 1.0),
                boxShadow: isLight
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.16),
                          blurRadius: 20,
                          offset: const Offset(0, 5),
                        ),
                      ]
                    : null,
              ),
              padding: const EdgeInsets.fromLTRB(20, 8, 18, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                        _buildAttachmentPreview(),
                        TextField(
                          controller: widget.controller,
                          maxLines: 4,
                          minLines: 1,
                          maxLength: 16000,
                          maxLengthEnforcement:
                              MaxLengthEnforcement.truncateAfterCompositionEnds,
                          buildCounter:
                              (
                                context, {
                                required currentLength,
                                required isFocused,
                                maxLength,
                              }) => null,
                          onSubmitted: (_) => _triggerSend(),
                          style: TextStyle(
                            fontSize: 16,
                            color: isLight
                                ? const Color(0xFF171615)
                                : ExodoColors.textPrimary,
                          ),
                          decoration: InputDecoration(
                            hintText: _getPlaceholder(context),
                            hintStyle: GoogleFonts.inter(
                              color: ExodoColors.textSecondary,
                              fontSize: 16,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 8,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  InkWell(
                                    onTap: _showAttachmentMenu,
                                    borderRadius: BorderRadius.circular(20),
                                    child: Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: isLight
                                            ? Colors.white
                                            : ExodoColors.modelChipBg,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.add,
                                        size: 20,
                                        color: isLight
                                            ? const Color(0xFF171615)
                                            : Colors.white70,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: GestureDetector(
                                      onTap: isIncognito
                                          ? () {
                                              HapticFeedback.selectionClick();
                                            }
                                          : widget.onModelTap,
                                      child: AnimatedBuilder(
                                        animation: _auraController,
                                        builder: (context, _) {
                                          final isXpiPro =
                                              isPro &&
                                              (selectedModel.id ==
                                                      'ehyeh' ||
                                                  selectedModel.title ==
                                                      'XPi');
                                          final t = _auraController.value;
                                          return Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isLight
                                                  ? Colors.white
                                                  : ExodoColors.modelChipBg,
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              border: Border.all(
                                                color: isXpiPro
                                                    ? ExodoColors.amber.withValues(
                                                        alpha:
                                                            0.40 +
                                                            0.60 *
                                                                ((math.sin(
                                                                          t *
                                                                              math.pi *
                                                                              2,
                                                                        ) +
                                                                        1) /
                                                                    2),
                                                      )
                                                    : Colors.transparent,
                                                width: 1.0,
                                              ),
                                              boxShadow: isXpiPro
                                                  ? [
                                                      BoxShadow(
                                                        color: ExodoColors.amber
                                                            .withValues(
                                                              alpha:
                                                                  0.15 +
                                                                  0.25 *
                                                                      ((math.sin(t * math.pi * 2) +
                                                                              1) /
                                                                          2),
                                                            ),
                                                        blurRadius: 10,
                                                        spreadRadius: 1,
                                                        offset: Offset(
                                                          6 *
                                                              math.cos(
                                                                t * math.pi * 2,
                                                              ),
                                                          3 *
                                                              math.sin(
                                                                t * math.pi * 2,
                                                              ),
                                                        ),
                                                      ),
                                                      BoxShadow(
                                                        color: ExodoColors.amber.withValues(
                                                          alpha:
                                                              0.10 +
                                                              0.18 *
                                                                  ((math.cos(
                                                                            t *
                                                                                math.pi *
                                                                                2 *
                                                                                1.3,
                                                                          ) +
                                                                          1) /
                                                                      2),
                                                        ),
                                                        blurRadius: 14,
                                                        spreadRadius: 0,
                                                        offset: Offset(
                                                          -5 *
                                                              math.sin(
                                                                t * math.pi * 2,
                                                              ),
                                                          -3 *
                                                              math.cos(
                                                                t * math.pi * 2,
                                                              ),
                                                        ),
                                                      ),
                                                    ]
                                                  : null,
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    selectedModel.title,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style:
                                                        TextStyle(fontFamily: 'AnthropicSans', 
                                                          fontSize: 13,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                  ),
                                                ),
                                                const SizedBox(width: 4),
                                                Icon(
                                                  isIncognito
                                                      ? Icons.lock_outline
                                                      : Icons.keyboard_arrow_down,
                                                  size: isIncognito ? 13 : 16,
                                                  color: isLight
                                                      ? const Color(0xFF171615)
                                                      : Colors.white70,
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            AnimatedBuilder(
                              animation: widget.controller,
                              builder: (context, _) {
                                final hasText = widget.controller.text
                                    .trim()
                                    .isNotEmpty;
                                final shouldShowSend =
                                    hasText || _hasAttachment || _isRecording;

                                return Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onLongPressStart: _isTranscribing
                                          ? null
                                          : (_) async {
                                              HapticFeedback.mediumImpact();
                                              _isLongPressActive = true;
                                              await _startRecording();
                                            },
                                      onLongPressEnd: _isTranscribing
                                          ? null
                                          : (_) async {
                                              _isLongPressActive = false;
                                              HapticFeedback.lightImpact();
                                              await _stopAndTranscribe();
                                            },
                                      child: IconButton(
                                        icon: _isRecording
                                            ? _buildRecordingMicIcon()
                                            : Icon(
                                                _isTranscribing
                                                    ? Icons.hourglass_top_rounded
                                                    : Icons.mic_none,
                                                color: _isTranscribing
                                                    ? ExodoColors.amber
                                                    : (shouldShowSend
                                                        ? (isLight
                                                              ? Colors.black54
                                                              : ExodoColors
                                                                    .textSecondary)
                                                        : (isLight
                                                              ? Colors.black87
                                                              : Colors.white70)),
                                              ),
                                        onPressed: _isTranscribing
                                            ? null
                                            : () async {
                                                // Tap-to-toggle: si está
                                                // grabando, paramos. Si no,
                                                // iniciamos. Se ignora si el
                                                // usuario también hizo
                                                // long-press (manejado por
                                                // el GestureDetector padre).
                                                if (_isLongPressActive) return;
                                                HapticFeedback.vibrate();
                                                if (_isRecording) {
                                                  await _stopAndTranscribe();
                                                } else {
                                                  await _startRecording();
                                                }
                                              },
                                      ),
                                    ),
                                    if (shouldShowSend || isGenerating)
                                      GestureDetector(
                                        onTap: () async {
                                          if (isGenerating) {
                                            HapticFeedback.mediumImpact();
                                            state.stopGeneration();
                                          } else if (shouldShowSend) {
                                            _triggerSend();
                                          }
                                        },
                                        child: Container(
                                          width: 38,
                                          height: 38,
                                          margin: const EdgeInsets.only(
                                            left: 2,
                                            right: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isLight
                                                ? const Color(0xFF131313)
                                                : ExodoColors.textPrimary,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            isGenerating
                                                ? Icons.stop_rounded
                                                : Icons.arrow_upward,
                                            size: isGenerating ? 22 : 19,
                                            color: isLight
                                                ? Colors.white
                                                : const Color(0xFF141414),
                                          ),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Aplica un barrido fluido de luz blanca pura de izquierda a derecha
/// de forma periódica sobre el texto ámbar "Actualizar", manteniendo su color
/// base sin descender a cero opacidad.
class _ShimmeringUpgradeText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final Color baseColor;
  final Color highlightColor;

  const _ShimmeringUpgradeText({
    required this.text,
    required this.style,
    this.baseColor = ExodoColors.amber,
    this.highlightColor = Colors.white,
  });

  @override
  State<_ShimmeringUpgradeText> createState() => _ShimmeringUpgradeTextState();
}

class _ShimmeringUpgradeTextState extends State<_ShimmeringUpgradeText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // Ciclo total: ~4.6 segundos. Durante el primer 40% (~1.84s) la luz
    // cruza suavemente de forma inclinada. El 60% restante permanece en reposo.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4600),
    )..repeat();
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
        final progress = _controller.value;
        double sweep;

        if (progress <= 0.40) {
          // Fase activa: paso de luz pura inclinado de izquierda a derecha (más lento y suave)
          final t = progress / 0.40;
          final curveT = Curves.easeInOutSine.transform(t);
          sweep = -2.8 + (5.6 * curveT);
        } else {
          // Fase de reposo: la luz se queda fuera del rango visible
          sweep = 3.5;
        }

        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment(sweep - 1.3, -0.7),
              end: Alignment(sweep + 1.3, 0.7),
              colors: [
                widget.baseColor,
                widget.baseColor,
                widget.highlightColor,
                widget.baseColor,
                widget.baseColor,
              ],
              stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
            ).createShader(bounds);
          },
          child: Text(
            widget.text,
            style: widget.style.copyWith(color: Colors.white),
          ),
        );
      },
    );
  }
}

