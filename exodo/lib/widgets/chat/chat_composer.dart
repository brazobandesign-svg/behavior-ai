import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
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
import '../../services/supabase_service.dart';
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

// Regla 5 & 9: Widget supremo de esfera donde cada punto cambia de tamaño aleatoriamente
// Optimizado con context.select para evitar repintado durante el streaming de mensajes.

/// Modos de envío de audio a transcripción (VOZ-1 FASE 1).
enum _VoiceSendMode {
  /// Parcial acumulativo del bloque en curso: REEMPLAZA el parcial mostrado.
  partial,

  /// Bloque consolidado por pausa VAD: entra al texto confirmado.
  block,

  /// Audio canónico de TODA la sesión al soltar: REEMPLAZA todo.
  canonical,
}

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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  /// Duración máxima de una sesión de voz (59s de timeout si no detecta voz).
  static const Duration _kVoiceSessionMax = Duration(seconds: 59);

  late AnimationController _auraController;
  bool _hasAttachment = false;
  bool _isRecording = false;
  bool _isTranscribing = false;
  // Reciclable por sesión: los streams del plugin son de suscripción única.
  AudioRecorder _audioRecorder = AudioRecorder();
  StreamSubscription<Uint8List>? _pcmSub;
  Timer? _recordingTimer;
  Timer? _waveTicker;
  Timer? _sessionCapTimer;
  int _recordingSeconds = 0;
  // Guarda de reentrada para no ejecutar dos stops en paralelo.
  bool _isStoppingVoice = false;
  // Guarda contra arranques concurrentes de sesión (toques rápidos).
  bool _isStartingVoice = false;
  // ── VOZ-1: stream PCM16 16k mono + VAD + pseudo-streaming ──
  // Audio canónico de TODA la sesión (para la transcripción final) y audio
  // del bloque de voz en curso (para los envíos acumulativos parciales).
  final BytesBuilder _sessionPcm = BytesBuilder(copy: false);
  final BytesBuilder _blockPcm = BytesBuilder(copy: false);
  DateTime _voiceSessionStart = DateTime.now();
  // VAD: piso de ruido dinámico (calibración ~300ms) → umbral = piso + 6dB.
  // El prior -30dB refleja una sala típica; si los primeros chunks traen
  // señal real, el mínimo observado lo corrige a la baja.
  bool _calibrating = false;
  double _calibMinDb = -30.0;
  double _vadThresholdDb = -24.0; // prior hasta calibrar (-30 + 6)
  DateTime _lastVadEvent = DateTime.now();
  bool _blockActive = false;
  DateTime _blockStart = DateTime.now();
  int _blockVocalMs = 0;
  int _blockSilenceMs = 0;
  int _totalVocalMs = 0;
  DateTime _lastPartialSend = DateTime.now();
  // Pseudo-streaming: seq monotónico anti-desorden + textos consolidados.
  int _reqSeq = 0;
  int _appliedSeq = 0;
  final List<String> _confirmedTexts = [];
  String _partialText = '';
  final List<http.Client> _activeUploads = [];
  // ── Motor de ondas: envolvente reactiva en tiempo real ──
  final ValueNotifier<double> _voiceLevel = ValueNotifier<double>(0.05);
  double _waveEnv = 0.05;
  double _waveTarget = 0.05;
  DateTime _lastWaveEvent = DateTime.now();
  final List<PendingAttachment> _pendingAttachments = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _auraController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Al salir de primer plano se libera el micrófono de inmediato y se
    // consolida el texto (Whisper cubre si el STT en vivo no capturó nada).
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden) &&
        _isRecording &&
        !_isStoppingVoice) {
      unawaited(_stopAndTranscribe());
    }
  }

  // ── Motor de ondas ─────────────────────────────────────────────────────────
  // Convierte amplitud de audio RMS en una onda reactiva y viva:
  // envolvente con ataque rápido / caída suave (60 FPS sin saltos).

  void _pushWaveLevel(double normalizedLevel) {
    _lastWaveEvent = DateTime.now();
    _waveTarget = normalizedLevel.clamp(0.0, 1.0);
    // Envelope follower (Qwen DSP): Ataque rápido al hablar (0.35), Release suave con inercia (0.88)
    final alpha = _waveTarget > _waveEnv ? 0.35 : 0.88;
    _waveEnv = alpha * _waveEnv + (1.0 - alpha) * _waveTarget;
    _commitWaveBar();
  }

  void _commitWaveBar() {
    _voiceLevel.value = _waveEnv.clamp(0.0, 1.0);
  }

  void _startWaveTickers() {
    _waveTicker?.cancel();
    _waveTicker = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (!_isRecording) return;
      final since = DateTime.now().difference(_lastWaveEvent).inMilliseconds;
      if (since < 45) return;
      _waveEnv = _waveEnv + (_waveTarget - _waveEnv) * 0.15;
      _commitWaveBar();
    });

    // Timeout de 59 segundos si la sesión se queda abierta.
    _sessionCapTimer?.cancel();
    _sessionCapTimer = Timer(_kVoiceSessionMax, () {
      if (!_isRecording) return;
      if (_isStoppingVoice) {
        _isStoppingVoice = false;
      }
      debugPrint('[VOZ] 59s alcanzados sin confirmación: deteniendo automáticamente');
      unawaited(_stopAndTranscribe());
    });
  }

  void _stopWaveTickers() {
    _waveTicker?.cancel();
    _waveTicker = null;
    _sessionCapTimer?.cancel();
    _sessionCapTimer = null;
  }

  /// Inicia la sesión de voz: grabación local inmediata (micrófono
  /// exclusivo de la grabadora) y transcripción con Whisper del backend al
  /// detener. Flujo validado: 200-650 ms, calidad alta.
  ///
  /// Nota de arquitectura: el STT on-device de Google se retiró de este
  /// flujo tras medirlo en el dispositivo real — su servicio cae cada 6-28 s
  /// y su motor offline es "ambient oneshot" en inglés; era la fuente de
  /// cortes bruscos, texto pobre y ondas sin reactividad.
  Future<bool> _startRecording() async {
    if (_isRecording ||
        _isTranscribing ||
        _isStoppingVoice ||
        _isStartingVoice) {
      return false;
    }
    _isStartingVoice = true;
    try {
      // Timeout: si el canal nativo no responde, liberar en vez de dejar el
      // botón muerto en silencio.
      final hasPermission = await _audioRecorder
          .hasPermission()
          .timeout(const Duration(seconds: 4), onTimeout: () => false);
      if (!hasPermission) {
        debugPrint('[VOZ] Permiso de micrófono no concedido o sin respuesta');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('El micrófono no respondió. Intenta de nuevo.'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        return false;
      }

      if (!await _startVoiceStream()) return false;

      _recordingSeconds = 0;
      _waveEnv = 0.0;
      _waveTarget = 0.0;
      _voiceLevel.value = 0.12;
      _sessionPcm.clear();
      _blockPcm.clear();
      _voiceSessionStart = DateTime.now();
      _calibrating = true;
      _calibMinDb = -30.0;
      _blockActive = false;
      _blockVocalMs = 0;
      _blockSilenceMs = 0;
      _totalVocalMs = 0;
      _lastVadEvent = DateTime.now();
      _lastPartialSend = DateTime.now();
      _reqSeq = 0;
      _appliedSeq = 0;
      _confirmedTexts.clear();
      _partialText = '';

      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted && _isRecording) {
          setState(() => _recordingSeconds++);
        }
      });
      _startWaveTickers();

      if (mounted) {
        setState(() => _isRecording = true);
      }
      debugPrint('[VOZ] Sesión de voz iniciada (stream PCM 16k mono)');
      return true;
    } catch (e) {
      debugPrint('[VOZ] Error al iniciar sesión de voz: $e');
      await _abortVoiceSession();
      return false;
    } finally {
      _isStartingVoice = false;
    }
  }

  /// VOZ-1: arranca el stream PCM16 16k mono. La amplitud se calcula del
  /// propio PCM (RMS→dBFS): cero dependencia de onAmplitudeChanged, que
  /// congelaba o entregaba -Infinity en algunos dispositivos al grabar.
  Future<bool> _startVoiceStream() async {
    try {
      // Los streams del plugin son de suscripción única: reciclar la
      // grabadora en cada sesión.
      try {
        await _audioRecorder.dispose();
      } catch (_) {}
      _audioRecorder = AudioRecorder();

      final stream = await _audioRecorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );
      _pcmSub?.cancel();
      _pcmSub = stream.listen(
        _onPcmChunk,
        onError: (Object e) => debugPrint('[VOZ] error de stream: $e'),
        cancelOnError: false,
      );
      return true;
    } catch (e) {
      debugPrint('[VOZ] Error iniciando stream: $e');
      return false;
    }
  }

  /// Cada chunk alimenta: el buffer canónico, el buffer del bloque de voz
  /// activo, y el medidor de ondas (RMS del propio PCM).
  /// Cada chunk alimenta: el buffer canónico, el buffer del bloque de voz
  /// activo, y el medidor de ondas (RMS real del propio PCM).
  void _onPcmChunk(Uint8List chunk) {
    if (!_isRecording) return;
    _sessionPcm.add(chunk);
    if (_blockActive) _blockPcm.add(chunk);
    final normLevel = _calcChunkNormalizedRms(chunk);
    final db = _rmsToDb(chunk);
    _vadTick(db);
    _pushWaveLevel(normLevel);
  }

  /// Calcula la amplitud normalizada (0.0 a 1.0) con Noise Gate en dBFS.
  double _calcChunkNormalizedRms(Uint8List pcm) {
    final n = pcm.length ~/ 2;
    if (n == 0) return 0.0;
    final bd = ByteData.sublistView(pcm);
    double sumSq = 0;
    for (var i = 0; i < n; i++) {
      final v = bd.getInt16(i * 2, Endian.little);
      sumSq += v * v;
    }
    final rms = math.sqrt(sumSq / n);
    if (rms <= 1e-4) return 0.0;

    // Conversión a dBFS logarítmico [-96.0 a 0.0]
    final dbfs = 20.0 * (math.log(rms / 32768.0) / math.ln10);

    // Noise Gate: piso de silencio a -48 dBFS
    const noiseFloorDb = -48.0;
    const gateRangeDb = 38.0; // Rango útil de -48 a -10 dBFS

    if (dbfs < noiseFloorDb) {
      return 0.0; // Silencio absoluto -> onda plana (3.0px)
    }

    final gated = ((dbfs - noiseFloorDb) / gateRangeDb).clamp(0.0, 1.0);

    // Curva perceptual de respuesta (potencia 0.70)
    final visual = math.pow(gated, 0.70).clamp(0.0, 1.0).toDouble();
    return visual;
  }

  /// RMS de las muestras Int16 → dBFS.
  double _rmsToDb(Uint8List pcm) {
    final n = pcm.length ~/ 2;
    if (n == 0) return -96.0;
    final bd = ByteData.sublistView(pcm);
    double sumSq = 0;
    for (var i = 0; i < n; i++) {
      final v = bd.getInt16(i * 2, Endian.little);
      sumSq += v * v;
    }
    final rms = math.sqrt(sumSq / n);
    if (rms <= 0) return -96.0;
    return 20.0 * (math.log(rms / 32768.0) / math.ln10);
  }

  // ── VAD con piso de ruido dinámico (VOZ-1 FASE 0) ─────────────────────────
  // Primeros ~300ms: observar el mínimo dB de la sala → umbral = piso + 6dB.
  // Después: abrir bloque de voz con señal ≥ umbral, consolidarlo con pausa
  // >500ms, y disparar envíos acumulativos parciales mientras se habla.

  void _vadTick(double db) {
    final now = DateTime.now();
    final deltaMs =
        now.difference(_lastVadEvent).inMilliseconds.clamp(0, 500).toInt();
    _lastVadEvent = now;

    if (_calibrating) {
      if (db > -90 && db < _calibMinDb) _calibMinDb = db;
      final sinceStart = now.difference(_voiceSessionStart).inMilliseconds;
      if (sinceStart >= 300) {
        _calibrating = false;
        _vadThresholdDb = (_calibMinDb + 5.0).clamp(-50.0, -18.0);
        debugPrint('[VAD] calibrado: piso=${_calibMinDb.toStringAsFixed(1)}dB '
            'umbral=${_vadThresholdDb.toStringAsFixed(1)}dB');
      }
      return;
    }

    final voiceOpen = db >= _vadThresholdDb;

    if (!_blockActive) {
      if (voiceOpen) {
        _blockActive = true;
        _blockStart = now;
        _blockVocalMs = 0;
        _blockSilenceMs = 0;
        _lastPartialSend = now;
        _blockPcm.clear();
      }
      return;
    }

    if (voiceOpen) {
      _blockVocalMs += deltaMs;
      _totalVocalMs += deltaMs;
      _blockSilenceMs = 0;
    } else {
      _blockSilenceMs += deltaMs;
    }

    // Envío parcial acumulativo: ≥400ms de voz y cada ~1.2s para actualizar el texto en vivo.
    if (_blockVocalMs >= 400 &&
        now.difference(_lastPartialSend).inMilliseconds >= 1200 &&
        _blockPcm.length >= 16000) {
      _lastPartialSend = now;
      _sendVoiceWav(_snapshotBlock(), mode: _VoiceSendMode.partial);
    }

    // Consolidación del bloque: pausa >500ms o tope de 6s hablando.
    if (_blockSilenceMs > 500 ||
        now.difference(_blockStart).inMilliseconds >= 6000) {
      _consolidateBlock();
    }
  }

  /// Copia del audio acumulado del bloque SIN vaciar el builder (el bloque
  /// sigue creciendo hasta consolidarse).
  Uint8List _snapshotBlock() {
    return Uint8List.fromList(_blockPcm.toBytes());
  }

  void _consolidateBlock() {
    final bytes = _blockPcm.toBytes();
    final vocal = _blockVocalMs;
    _blockActive = false;
    _blockPcm.clear();
    if (vocal >= 600 && bytes.length >= 16000) {
      debugPrint('[VAD] bloque consolidado (${vocal}ms voz, ${bytes.length}B)');
      HapticFeedback.mediumImpact();
      _sendVoiceWav(bytes, mode: _VoiceSendMode.block);
    } else {
      debugPrint('[VAD] bloque descartado (${vocal}ms voz, ${bytes.length}B)');
    }
  }

  /// Envuelve PCM16 16k mono en un contenedor WAV (header RIFF de 44 bytes).
  Uint8List _wrapWav(Uint8List pcm) {
    final out = Uint8List(44 + pcm.length);
    final h = ByteData.view(out.buffer, 0, 44);
    void w(int off, String s) {
      for (var i = 0; i < s.length; i++) {
        out[off + i] = s.codeUnitAt(i);
      }
    }

    w(0, 'RIFF');
    h.setUint32(4, 36 + pcm.length, Endian.little);
    w(8, 'WAVE');
    w(12, 'fmt ');
    h.setUint32(16, 16, Endian.little); // tamaño fmt
    h.setUint16(20, 1, Endian.little); // PCM
    h.setUint16(22, 1, Endian.little); // mono
    h.setUint32(24, 16000, Endian.little); // sample rate
    h.setUint32(28, 32000, Endian.little); // byte rate
    h.setUint16(32, 2, Endian.little); // block align
    h.setUint16(34, 16, Endian.little); // bits
    w(36, 'data');
    h.setUint32(40, pcm.length, Endian.little);
    out.setRange(44, out.length, pcm);
    return out;
  }

  /// Arranca la grabación local para transcribir con Whisper al detener.
  /// Detiene la sesión de voz (VOZ-1): aborta envíos pendientes, consolida
  /// el bloque en curso y lanza la transcripción canónica del audio TOTAL,
  /// que reemplaza cualquier parcial mostrado.
  Future<void> _stopAndTranscribe({bool sendAfter = false}) async {
    if (!_isRecording || _isStoppingVoice) {
      debugPrint('[VOZ] stop ignorado (rec=$_isRecording, stopping=$_isStoppingVoice)');
      return;
    }
    _isStoppingVoice = true;
    try {
      // Abortar envíos pendientes: el canónico es la única verdad restante.
      _abortPendingUploads();

      _recordingTimer?.cancel();
      _recordingTimer = null;
      _stopWaveTickers();
      await _pcmSub?.cancel();
      _pcmSub = null;
      try {
        await _audioRecorder
            .stop()
            .timeout(const Duration(seconds: 5), onTimeout: () => null);
      } catch (_) {}

      if (mounted) {
        setState(() => _isRecording = false);
      }

      // Consolidar el bloque en curso si tiene voz suficiente (no se pierde
      // la última frase dicha aunque no hubiera pausa >500ms).
      if (_blockActive && _blockVocalMs >= 600 && _blockPcm.length >= 16000) {
        _consolidateBlock();
      } else {
        _blockActive = false;
        _blockPcm.clear();
      }

      final canonical = _sessionPcm.toBytes();
      _sessionPcm.clear();

      // Sin voz real en toda la sesión: descartar sin "procesar" nada.
      if (_totalVocalMs < 600 || canonical.length < 32000) {
        debugPrint('[VOZ] sesión sin voz (${_totalVocalMs}ms): descartada');
        HapticFeedback.lightImpact();
        return;
      }

      if (mounted) {
        setState(() => _isTranscribing = true);
      }

      final text = await _sendVoiceWav(
        canonical,
        mode: _VoiceSendMode.canonical,
      );

      if (!mounted) return;
      setState(() => _isTranscribing = false);

      if (text != null && text.isNotEmpty) {
        // El canónico ya reemplazó el campo dentro de _sendVoiceWav.
        _confirmedTexts.clear();
        _partialText = '';
        HapticFeedback.selectionClick();
        if (sendAfter) _triggerSend();
      } else {
        // El canónico falló: conservar el texto ensamblado por bloques.
        final assembled = _confirmedTexts.join(' ');
        if (assembled.isNotEmpty) {
          widget.controller.text = assembled;
          widget.controller.selection = TextSelection.collapsed(
            offset: assembled.length,
          );
        }
        HapticFeedback.lightImpact();
      }
    } catch (e) {
      debugPrint('[VOZ] _stopAndTranscribe error: $e');
    } finally {
      if (mounted) {
        setState(() => _isTranscribing = false);
      }
      _isStoppingVoice = false;
    }
  }

  /// Aborta todas las subidas en vuelo (cierre de socket = fallo inmediato
  /// en el await y descarte del resultado por seq).
  void _abortPendingUploads() {
    for (final c in List<http.Client>.of(_activeUploads)) {
      try {
        c.close();
      } catch (_) {}
    }
    _activeUploads.clear();
  }

  /// Libera el micrófono y descarta la sesión de voz SIN transcribir.
  /// Se usa al enviar texto tecleado mientras se graba y al desmontar.
  Future<void> _abortVoiceSession() async {
    _abortPendingUploads();
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _stopWaveTickers();
    await _pcmSub?.cancel();
    _pcmSub = null;
    try {
      await _audioRecorder.stop();
    } catch (_) {}
    _sessionPcm.clear();
    _blockPcm.clear();
    _blockActive = false;
    _confirmedTexts.clear();
    _partialText = '';
    if (mounted) {
      setState(() {
        _isRecording = false;
        _isTranscribing = false;
      });
    } else {
      _isRecording = false;
      _isTranscribing = false;
    }
  }

  /// VOZ-1 FASE 1 — envío de audio WAV al backend con JWT, seq_id y prompt
  /// de continuidad. Devuelve el texto transcrito (o null si todo falló).
  /// Aplica el resultado según [mode] respetando el orden por seq: una
  /// respuesta vieja jamás pisa una más nueva.
  Future<String?> _sendVoiceWav(Uint8List pcm, {required _VoiceSendMode mode}) async {
    final seq = ++_reqSeq;
    final wav = _wrapWav(pcm);
    final prompt = mode == _VoiceSendMode.canonical ? '' : _promptFromConfirmed();
    final label = mode.toString().split('.').last;
    debugPrint('[VOZ] envío $label seq=$seq (${wav.length}B${prompt.isNotEmpty ? ', prompt="${prompt.length}c"' : ''})');

    final jwt = SupabaseService.client.auth.currentSession?.accessToken;
    if (jwt == null) {
      debugPrint('[VOZ] sin JWT de sesión: no se envía (C9 requiere auth)');
      return null;
    }

    final client = http.Client();
    _activeUploads.add(client);
    try {
      for (final candidateUrl in ChatService.voiceTranscribeUrls) {
        try {
          final request = http.MultipartRequest('POST', Uri.parse(candidateUrl))
            ..fields['language'] = 'auto'
            ..fields['seq_id'] = seq.toString()
            ..files.add(
              http.MultipartFile.fromBytes(
                'file',
                wav,
                filename: 'clip.wav',
                contentType: MediaType('audio', 'wav'),
              ),
            );
          if (prompt.isNotEmpty) request.fields['prompt'] = prompt;
          request.headers['Authorization'] = 'Bearer $jwt';

          final streamed = await client
              .send(request)
              .timeout(const Duration(seconds: 8));
          final response = await http.Response.fromStream(streamed);

          if (response.statusCode == 200) {
            final body = jsonDecode(response.body);
            final text = body is Map && body['text'] is String
                ? (body['text'] as String).trim()
                : '';
            debugPrint('[VOZ] respuesta $label seq=$seq: "$text" (${response.body.length}B)');
            if (text.isNotEmpty && seq > _appliedSeq && mounted) {
              _applyVoiceText(text, seq: seq, mode: mode);
            }
            return text.isNotEmpty ? text : null;
          }
          debugPrint('[VOZ] HTTP ${response.statusCode} en $candidateUrl');
        } catch (e) {
          debugPrint('[VOZ] fallo $candidateUrl: $e');
        }
      }
      debugPrint('[VOZ] $label seq=$seq: todos los candidatos fallaron');
      return null;
    } finally {
      _activeUploads.remove(client);
      client.close();
    }
  }

  /// Aplica una transcripción según su modo y seq (monotónico).
  void _applyVoiceText(String text, {required int seq, required _VoiceSendMode mode}) {
    _appliedSeq = seq;
    switch (mode) {
      case _VoiceSendMode.partial:
        // El parcial del bloque en curso REEMPLAZA al anterior.
        _partialText = text;
        _refreshVoiceField();
        break;
      case _VoiceSendMode.block:
        // Bloque consolidado: entra al texto confirmado y limpia el parcial.
        _confirmedTexts.add(text);
        _partialText = '';
        _refreshVoiceField();
        break;
      case _VoiceSendMode.canonical:
        // Transcripción total canónica: REEMPLAZA todo lo mostrado.
        _confirmedTexts.clear();
        _partialText = '';
        widget.controller.text = text;
        widget.controller.selection =
            TextSelection.collapsed(offset: text.length);
        break;
    }
  }

  /// Reconstruye el campo: texto confirmado + parcial en curso directamente en el cajón.
  void _refreshVoiceField() {
    final confirmed = _confirmedTexts.join(' ').trim();
    final partial = _partialText.trim();
    final text = partial.isEmpty
        ? confirmed
        : (confirmed.isEmpty ? partial : '$confirmed $partial');
    if (text.isEmpty) return;
    widget.controller.text = text;
    widget.controller.selection =
        TextSelection.collapsed(offset: text.length);
  }

  /// Últimas palabras del texto confirmado: viaja como `prompt` de Whisper
  /// para dar continuidad entre bloques (acta VOZ-1).
  String _promptFromConfirmed() {
    if (_confirmedTexts.isEmpty) return '';
    final last = _confirmedTexts.last;
    final words = last.trim().split(RegExp(r'\s+'));
    if (words.length <= 12) return last.trim();
    return words.sublist(words.length - 12).join(' ');
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
    // Si hay una sesión de dictado activa, el texto parcial actual es el que
    // se envía. Se baja _isRecording ANTES para que los resultados tardíos
    // del STT no sobrescriban el campo ya enviado, y se libera el micrófono
    // en segundo plano sin retrasar el envío.
    if (_isRecording) {
      unawaited(_abortVoiceSession());
    }

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
    WidgetsBinding.instance.removeObserver(this);
    _auraController.dispose();
    _voiceLevel.dispose();
    _abortPendingUploads();
    _pcmSub?.cancel();
    _pcmSub = null;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _stopWaveTickers();
    // Best-effort: si todavía hay una grabación activa al desmontar el
    // widget, la cancelamos para no dejar el micrófono abierto.
    try {
      _audioRecorder.stop();
    } catch (_) {}
    _audioRecorder.dispose();
    super.dispose();
  }

  String _getPlaceholder(BuildContext context) {
    if (_isRecording) {
      return 'Escuchando…';
    }
    if (_isTranscribing) {
      return 'Transcribiendo voz...';
    }
    return AppI18n.of(context).t('chat.placeholder');
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
                        // VOZ-2 Punto 3 — morphing de estados con
                        // AnimatedSwitcher (250ms, escala + fade) entre
                        // Reposo ➔ Grabando ➔ Transcribiendo.
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, anim) => FadeTransition(
                            opacity: anim,
                            child: ScaleTransition(
                              scale: Tween<double>(begin: 0.96, end: 1.0)
                                  .animate(anim),
                              child: child,
                            ),
                          ),
                          child: _isRecording
                              ? _LiveVoiceWaveform(
                                  key: const ValueKey('voz-grabando'),
                                  level: _voiceLevel,
                                  isLight: isLight,
                                  onStop: () =>
                                      unawaited(_stopAndTranscribe()),
                                )
                              : _isTranscribing
                                  ? _TranscribingIndicator(
                                      key: const ValueKey('voz-transcribiendo'),
                                      isLight: isLight,
                                    )
                                  : const SizedBox.shrink(
                                      key: ValueKey('voz-reposo')),
                        ),
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
                                final shouldShowSend = hasText || _hasAttachment;

                                // 1. GRABANDO: Un único botón de STOP en la derecha (#252525)
                                if (_isRecording) {
                                  return GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () async {
                                      HapticFeedback.mediumImpact();
                                      await _stopAndTranscribe();
                                    },
                                    child: Container(
                                      width: 40,
                                      height: 40,
                                      margin: const EdgeInsets.symmetric(horizontal: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF252525),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: isLight ? Colors.transparent : Colors.white24,
                                          width: 1.0,
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.stop_rounded,
                                        size: 24,
                                        color: Colors.white,
                                      ),
                                    ),
                                  );
                                }

                                // 2. GENERANDO LLM: Botón Stop para cancelar respuesta
                                if (isGenerating) {
                                  return GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      HapticFeedback.mediumImpact();
                                      state.stopGeneration();
                                    },
                                    child: Container(
                                      width: 38,
                                      height: 38,
                                      margin: const EdgeInsets.symmetric(horizontal: 2),
                                      decoration: BoxDecoration(
                                        color: isLight
                                            ? const Color(0xFF131313)
                                            : ExodoColors.textPrimary,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.stop_rounded,
                                        size: 22,
                                        color: isLight
                                            ? Colors.white
                                            : const Color(0xFF141414),
                                      ),
                                    ),
                                  );
                                }

                                // 3. CON TEXTO / ADJUNTOS: Botón de ENVIAR (Flecha)
                                if (shouldShowSend) {
                                  return GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: _triggerSend,
                                    child: Container(
                                      width: 38,
                                      height: 38,
                                      margin: const EdgeInsets.symmetric(horizontal: 2),
                                      decoration: BoxDecoration(
                                        color: isLight
                                            ? const Color(0xFF131313)
                                            : ExodoColors.textPrimary,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.arrow_upward,
                                        size: 19,
                                        color: isLight
                                            ? Colors.white
                                            : const Color(0xFF141414),
                                      ),
                                    ),
                                  );
                                }

                                // 4. EN REPOSO VACÍO: Botón de MICRÓFONO para iniciar grabación
                                return GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: _isTranscribing
                                      ? null
                                      : () async {
                                          HapticFeedback.lightImpact();
                                          await _startRecording();
                                        },
                                  child: Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Icon(
                                      _isTranscribing
                                          ? Icons.hourglass_top_rounded
                                          : Icons.mic_none,
                                      size: 26,
                                      color: _isTranscribing
                                          ? ExodoColors.amber
                                          : (isLight
                                              ? Colors.black87
                                              : Colors.white70),
                                    ),
                                  ),
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

  const _ShimmeringUpgradeText({
    required this.text,
    required this.style,
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
    // Ciclo total: ~6.2 segundos. Durante el primer 45% (~2.8s) la luz
    // cruza lentamente de forma inclinada. El 55% restante permanece en reposo ámbar.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6200),
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

        if (progress <= 0.45) {
          // Fase activa: paso de luz pura inclinado de izquierda a derecha (cinemático y pausado)
          final t = progress / 0.45;
          final curveT = Curves.easeInOutCubic.transform(t);
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
              colors: const [
                ExodoColors.amber,
                ExodoColors.amber,
                Colors.white,
                ExodoColors.amber,
                ExodoColors.amber,
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

/// Detector visual de ondas de audio en vivo que reacciona directamente al micrófono
class _LiveVoiceWaveform extends StatelessWidget {
  final ValueNotifier<double> level;
  final bool isLight;
  final VoidCallback onStop;

  const _LiveVoiceWaveform({
    super.key,
    required this.level,
    required this.isLight,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isLight ? const Color(0xFFF3ECE1) : const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLight
              ? const Color(0xFF252525).withValues(alpha: 0.25)
              : Colors.white24,
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          // Punto indicador #252525
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: isLight ? const Color(0xFF252525) : Colors.white70,
              shape: BoxShape.circle,
            ),
          ),
          // Detector de ondas de audio
          Expanded(
            child: SizedBox(
              height: 28,
              child: AnimatedBuilder(
                animation: level,
                builder: (context, _) {
                  return CustomPaint(
                    painter: _AudioWaveBarsPainter(
                      level: level.value,
                      isLight: isLight,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dibuja barras de audio vivas en tiempo real con altura reactiva proporcional al volumen
class _AudioWaveBarsPainter extends CustomPainter {
  final double level;
  final bool isLight;

  _AudioWaveBarsPainter({required this.level, required this.isLight});

  @override
  void paint(Canvas canvas, Size size) {
    const count = 30;
    final totalWidth = size.width;
    final step = totalWidth / count;
    final barWidth = (step * 0.55).clamp(2.5, 6.0);
    final cy = size.height / 2;

    final barColor = isLight ? const Color(0xFF252525) : const Color(0xFFE2E2E2);

    final paint = Paint()
      ..color = barColor
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.fill;

    final isSilent = level < 0.02;

    for (var i = 0; i < count; i++) {
      final x = i * step + (step - barWidth) / 2;

      double barH;
      if (isSilent) {
        // Silencio absoluto: línea de reposo plana y serena (3.0px)
        barH = 3.0;
      } else {
        final normalizedPos = ((i - count / 2).abs()) / (count / 2);
        final bellFactor = 0.25 + 0.75 * math.cos(normalizedPos * math.pi / 2);
        final harmonic = math.sin(i * 0.75 + level * 5.0) * 0.12 * level;
        final dynamicLevel = (level + harmonic).clamp(0.0, 1.0);
        barH = (3.0 + dynamicLevel * (size.height - 4.0) * bellFactor).clamp(3.0, size.height);
      }

      final rrect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x + barWidth / 2, cy),
          width: barWidth,
          height: barH,
        ),
        Radius.circular(barWidth / 2),
      );
      canvas.drawRRect(rrect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AudioWaveBarsPainter oldDelegate) {
    return oldDelegate.level != level;
  }
}

class _TranscribingIndicator extends StatelessWidget {
  final bool isLight;
  const _TranscribingIndicator({super.key, required this.isLight});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isLight ? const Color(0xFFF2EEE7) : const Color(0xFF202020),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(ExodoColors.amber),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Procesando voz...',
            style: TextStyle(
              fontFamily: 'AnthropicSans',
              fontSize: 12,
              color: isLight ? const Color(0xFF171615) : Colors.white70,
            ),
          ),
        ],
      ),
    );
  }
}

