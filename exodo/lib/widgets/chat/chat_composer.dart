import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../models/models.dart';
import '../../services/app_state.dart';
import '../../services/supabase_service.dart';
import '../../theme/exodo_theme.dart';
import '../../l10n/app_i18n.dart';

// [Punto 40] Datos temporales de un adjunto antes de leer sus bytes.
class PendingAttachment {
  final String name;
  final String mime;
  final Uint8List bytes;
  const PendingAttachment({
    required this.name,
    required this.mime,
    required this.bytes,
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

// Regla 5 & 9: Widget supremo de esfera donde cada punto cambia de tamaño aleatoriamente
// Optimizado con context.select para evitar repintado durante el streaming de mensajes.
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
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechEnabled = false;
  bool _speechInitialized = false;
  final List<PendingAttachment> _pendingAttachments = [];

  @override
  void initState() {
    super.initState();
    _auraController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();
  }

  Future<void> _ensureSpeechInitialized() async {
    if (_speechInitialized) return;
    try {
      _speechEnabled = await _speech.initialize();
      _speechInitialized = true;
    } catch (_) {
      _speechEnabled = false;
    }
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
                    onTap: () {
                      setState(() {
                        _pendingAttachments.removeAt(i);
                        if (_pendingAttachments.isEmpty) _hasAttachment = false;
                      });
                    },
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
                        color: isLight ? Colors.white : const Color(0xFF141210),
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
                color: isLight ? const Color(0xFFF2F2F7) : const Color(0xFF2C2C2E),
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
                    onTap: () {
                      setState(() {
                        _pendingAttachments.removeAt(i);
                        if (_pendingAttachments.isEmpty) _hasAttachment = false;
                      });
                    },
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
          : const Color(0xFF131313),
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
                      imageQuality: 90,
                    );
                    if (photo != null && mounted) {
                      final bytes = await photo.readAsBytes();
                      setState(() {
                        _hasAttachment = true;
                        _pendingAttachments.add(
                          PendingAttachment(
                            name: photo.name,
                            mime: 'image/jpeg',
                            bytes: Uint8List.fromList(bytes),
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
                      imageQuality: 90,
                    );
                    if (media != null && mounted) {
                      final bytes = await media.readAsBytes();
                      final mime = mimeFromExtension(media.name);
                      setState(() {
                        _hasAttachment = true;
                        _pendingAttachments.add(
                          PendingAttachment(
                            name: media.name,
                            mime: mime,
                            bytes: Uint8List.fromList(bytes),
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
                          _pendingAttachments.add(
                            PendingAttachment(
                              name: f.name,
                              mime: mimeFromExtension(f.name),
                              bytes: f.bytes!,
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

  void _triggerSend() {
    final attachments = <Attachment>[];
    for (final pa in _pendingAttachments) {
      attachments.add(
        Attachment(
          filePath: '',
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
    widget.onSend(attachments.isEmpty ? null : attachments);
  }

  @override
  void dispose() {
    _auraController.dispose();
    super.dispose();
  }

  String _sttLocaleFor(String appLocale) {
    switch (appLocale) {
      case 'es':
        return 'es-DO';
      case 'en':
        return 'en-US';
      case 'fr':
        return 'fr-FR';
      case 'pt':
        return 'pt-BR';
      case 'it':
        return 'it-IT';
      case 'de':
        return 'de-DE';
      default:
        return 'en-US';
    }
  }

  String _getPlaceholder(BuildContext context) {
    return AppI18n.of(context).t('chat.placeholder');
  }

  Widget _buildOfflineInsideCapsule(
    BuildContext context,
    bool isNetworkOffline,
    bool isLight,
  ) {
    final softBlack = const Color(0xFF2A2622);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.cloud_off_rounded,
                size: 20,
                color: ExodoColors.amber,
              ),
              const SizedBox(width: 8),
              Text(
                isNetworkOffline
                    ? AppI18n.of(context).t('network.offline_title')
                    : AppI18n.of(context).t('offline.title'),
                style: GoogleFonts.syne(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isLight ? softBlack : ExodoColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (isNetworkOffline)
            Text(
              AppI18n.of(context).t('network.offline_body'),
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: isLight ? softBlack : ExodoColors.textSecondary,
                height: 1.4,
              ),
            )
          else
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: isLight ? softBlack : ExodoColors.textSecondary,
                  height: 1.4,
                ),
                children: [
                  TextSpan(text: AppI18n.of(context).t('offline.p1')),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: GestureDetector(
                      onTap: () async {
                        HapticFeedback.vibrate();
                        try {
                          await SupabaseService.signOut().timeout(
                            const Duration(seconds: 3),
                            onTimeout: () {},
                          );
                        } catch (_) {}
                      },
                      child: Text(
                        AppI18n.of(context).t('offline.upgrade'),
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: ExodoColors.amber,
                          decoration: TextDecoration.underline,
                          decorationColor: ExodoColors.amber,
                        ),
                      ),
                    ),
                  ),
                  TextSpan(text: AppI18n.of(context).t('offline.p2')),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: GestureDetector(
                      onTap: () async {
                        HapticFeedback.vibrate();
                        try {
                          await SupabaseService.signOut().timeout(
                            const Duration(seconds: 3),
                            onTimeout: () {},
                          );
                        } catch (_) {}
                      },
                      child: Text(
                        AppI18n.of(context).t('offline.signin'),
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: ExodoColors.amber,
                          decoration: TextDecoration.underline,
                          decorationColor: ExodoColors.amber,
                        ),
                      ),
                    ),
                  ),
                  const TextSpan(text: "."),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Selectores finos para evitar repintado durante streaming de chat
    final isGenerating = context.select<AppState, bool>((s) => s.isGenerating);
    final isOnline = context.select<AppState, bool>((s) => s.isOnline);
    final guestIsBlocked = context.select<AppState, bool>((s) => s.guestIsBlocked);
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
                    ? const Color(0xFF1D1D1D)
                    : const Color(0xFFF5F5F5),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                border: isLight
                    ? Border.all(color: const Color(0xFF1D1D1D), width: 1.0)
                    : Border.all(color: Colors.transparent, width: 1.0),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      AppI18n.of(context).t('tokens.more_cap'),
                      style: GoogleFonts.jetBrainsMono(
                        color: isLight
                            ? const Color(0xFFF5F2EB)
                            : const Color(0xFF55514C),
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
                        child: Text(
                          AppI18n.of(context).t('tokens.upgrade_btn'),
                          style: GoogleFonts.jetBrainsMono(
                            color: ExodoColors.amber,
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
                          color: isLight ? Colors.white70 : Colors.black54,
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
                    ? const Color(0xFFE8E8E8)
                    : ExodoColors.composerBg,
                borderRadius: BorderRadius.circular(32),
                border: isLight
                    ? Border.all(color: const Color(0xFFDDDDDD), width: 1.0)
                    : Border.all(color: Colors.transparent, width: 1.0),
              ),
              padding: (guestIsBlocked || !isOnline)
                  ? const EdgeInsets.symmetric(horizontal: 16, vertical: 6)
                  : const EdgeInsets.fromLTRB(20, 8, 18, 8),
              child: guestIsBlocked
                  ? _buildOfflineInsideCapsule(context, false, isLight)
                  : !isOnline
                  ? _buildOfflineInsideCapsule(context, true, isLight)
                  : Column(
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
                                : Colors.white,
                          ),
                          decoration: InputDecoration(
                            hintText: _getPlaceholder(context),
                            hintStyle: GoogleFonts.inter(
                              color: const Color(0xFF7B7872),
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
                                            ? const Color(0xFFFBF9F5)
                                            : const Color(0xFF131313),
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
                                      onTap: widget.onModelTap,
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
                                                  ? const Color(0xFFFBF9F5)
                                                  : const Color(0xFF131313),
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
                                                        GoogleFonts.jetBrainsMono(
                                                          fontSize: 13,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                  ),
                                                ),
                                                const SizedBox(width: 4),
                                                Icon(
                                                  Icons.keyboard_arrow_down,
                                                  size: 16,
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
                                    IconButton(
                                      icon: Icon(
                                        _isRecording
                                            ? Icons.mic
                                            : Icons.mic_none,
                                        color: _isRecording
                                            ? ExodoColors.error
                                            : (shouldShowSend
                                                  ? (isLight
                                                        ? Colors.black54
                                                        : ExodoColors
                                                              .textSecondary)
                                                  : (isLight
                                                        ? Colors.black87
                                                        : Colors.white70)),
                                      ),
                                      onPressed: () async {
                                        HapticFeedback.vibrate();
                                        if (!_isRecording) {
                                          final sttLocaleId = _sttLocaleFor(
                                            AppI18n.of(context).localeCode,
                                          );
                                          await _ensureSpeechInitialized();
                                          if (!mounted) return;
                                          if (_speechEnabled) {
                                            setState(() => _isRecording = true);
                                            await _speech.listen(
                                              onResult: (result) {
                                                widget.controller.text =
                                                    result.recognizedWords;
                                              },
                                              listenOptions:
                                                  stt.SpeechListenOptions(
                                                    partialResults: true,
                                                    localeId: sttLocaleId,
                                                    cancelOnError: true,
                                                  ),
                                            );
                                          }
                                        } else {
                                          setState(() => _isRecording = false);
                                          await _speech.stop();
                                        }
                                      },
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
                                                : const Color(0xFFFBF9F5),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            isGenerating
                                                ? Icons.stop_rounded
                                                : Icons.arrow_upward,
                                            size: isGenerating ? 22 : 19,
                                            color: isLight
                                                ? Colors.white
                                                : const Color(0xFF141210),
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
