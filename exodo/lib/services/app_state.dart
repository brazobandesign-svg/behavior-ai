import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../app/bootstrap.dart';
import '../data/repositories/local_chat_repository.dart';
import '../data/local/db/tables/messages.dart'; // Import LocalMessageStatus enum
import 'supabase_service.dart';
import 'chat_service.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'connectivity_service.dart';
import 'notification_service.dart';
import 'update_service.dart';
import '../l10n/app_i18n.dart';

class AppState extends ChangeNotifier with WidgetsBindingObserver {
  final LocalChatRepository localChatRepo = LocalChatRepository();

  UserProfile? profile;
  List<Conversation> conversations = [];
  Conversation? activeConversation;
  List<ChatMessage> currentMessages = [];

  bool isIncognito = false;
  bool showTab2Banner = true;
  bool isDarkMode = true;
  bool guestIsBlocked = false; // Sin bloqueo para guests: acceso ilimitado a Groq $0
  ExodoModelOption selectedModel = exodoModels[0]; // G1.1 (Free)
  double? currentTempC;

  /// Switcher de intención del chat: auto | flash | deep.
  /// - auto: el clasificador por keywords decide (saludos→flash, análisis→reasoning)
  /// - flash: fuerza la cadena rápida (respuesta <200ms TTFT)
  /// - deep: fuerza razonamiento profundo (qwq-plus, más lento pero elaborado)
  String chatMode = 'auto';

  void setChatMode(String mode) {
    if (mode == chatMode) return;
    if (!const {'auto', 'flash', 'deep'}.contains(mode)) return;
    chatMode = mode;
    notifyListeners();
  }

  /// taskType para el backend: null = auto (el clasificador decide).
  String? get effectiveTaskType {
    switch (chatMode) {
      case 'flash':
        return 'simple';
      case 'deep':
        return 'reasoning';
      default:
        return null;
    }
  }

  int tokensUsed = 0;
  int get tokensLimit => isPro ? 50000 : 6000;
  DateTime? tokensResetTime;
  bool get isPro => profile?.plan == 'hazak';
  bool isThinking = false;
  bool isGenerating = false;
  // [UX #1] El backend avisó (SSE 'generating_image') que está esperando t2i.
  // Mientras sea true, la burbuja thinking muestra el shimmer de imagen.
  bool isGeneratingImage = false;
  String? errorMessage;
  int guestMessagesSessionCount = 0;
  // [Misión down] Último texto cuyo envío falló (para el botón Reintentar
  // de la burbuja de error). Solo texto; los adjuntos no se reintentan.
  String? lastFailedSendText;

  /// Reenvía el último mensaje fallido, si hay. Lo usa el botón Reintentar
  /// de la burbuja de error. No hace nada si ya se está generando.
  Future<void> retryLastFailedSend() async {
    final t = lastFailedSendText;
    if (t == null || t.trim().isEmpty || isGenerating) return;
    lastFailedSendText = null;
    await sendUserMessage(t);
  }

  // ── Privacidad: historial en la nube (elección del usuario) ────────────
  // ON (default): los chats se guardan en Supabase + Drift, visibles en
  // cualquier dispositivo. OFF: los chats NO se persisten en ningún lado
  // (semántica incógnito: solo viven en RAM mientras están en pantalla) —
  // ni el backend de Éxodo guarda el contenido. Solo aplica a usuarios
  // registrados; guests/incógnito ya son efímeros por diseño.
  bool cloudHistoryEnabled = true;
  static const String _cloudHistoryPrefKey = 'exodo_cloud_history';

  Future<void> setCloudHistoryEnabled(bool enabled) async {
    if (cloudHistoryEnabled == enabled) return;
    cloudHistoryEnabled = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_cloudHistoryPrefKey, enabled);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _loadCloudHistoryPref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      cloudHistoryEnabled = prefs.getBool(_cloudHistoryPrefKey) ?? true;
    } catch (_) {}
  }

  // ── Streaming suavizado (FIX jerky rendering 2026-08-20) ──────────────
  // Los deltas del stream se acumulan en un buffer mutable y se materializan
  // en currentMessages a cadencia de frame (~33ms). Antes, CADA token hacía
  // indexWhere + copia del ChatMessage + notifyListeners(), reconstruyendo
  // el árbol de widgets a la velocidad de llegada de tokens (10-40/s).
  final StringBuffer _streamBuffer = StringBuffer();
  Timer? _streamFlushTimer;
  String? _streamingMsgId;
  bool _streamingIsDegraded = false;
  DateTime? _streamingCreatedAt;
  bool Function(String content)? _streamGuard;
  static const Duration _streamFlushInterval = Duration(milliseconds: 33);

  // ── Segundo plano: notificación "Ver respuesta de Éxodo" ──────────────
  // Si el usuario sale de la app mientras Éxodo sigue escribiendo, al
  // terminar la generación se lanza una notificación local con el logo de
  // la app y el texto localizado. El tap abre la app con la respuesta ahí.
  AppLifecycleState _lifecycleStatus = AppLifecycleState.resumed;
  bool get isAppInBackground => _lifecycleStatus != AppLifecycleState.resumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleStatus = state;
    if (state == AppLifecycleState.paused && isGenerating) {
      // Garantía absoluta: servicio en primer plano mientras la app está
      // fuera de pantalla y Éxodo sigue escribiendo.
      _startForegroundService();
    } else if (state == AppLifecycleState.resumed) {
      // De vuelta en pantalla el servicio deja de ser necesario; si aún
      // genera, la respuesta termina normal (la notificación de fin ya no
      // aplica porque el usuario está mirando).
      _stopForegroundService();
    }
    // Al volver al primer plano con un APK de actualización ya descargado,
    // mostrar la notificación de instalación (única interrupción del flujo).
    if (state == AppLifecycleState.resumed) {
      final apkPath = UpdateService.instance.readyToInstall.value;
      if (apkPath != null && !_updateNotified) {
        _updateNotified = true;
        NotificationService.instance.showUpdateReady(
          title: 'Éxodo',
          body: AppI18n.instance.t('notification.update_ready_body'),
          payload: 'install_update',
        );
      }
    }
  }

  bool _updateNotified = false;

  /// [Fix LG V60 #3] Aviso heads-up al terminar en segundo plano: título
  /// "Éxodo ha respondido" + primeros 80 caracteres de la respuesta como
  /// cuerpo; fallback al texto localizado genérico si no hay contenido.
  void _notifyIfBackground({String? responsePreview}) {
    if (!isAppInBackground) return;
    var body = AppI18n.instance.t('notification.response_ready');
    final preview = responsePreview?.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (preview != null && preview.isNotEmpty) {
      body = preview.length > 80 ? '${preview.substring(0, 80)}…' : preview;
    }
    NotificationService.instance.showReplyReady(
      title: 'Éxodo ha respondido',
      body: body,
    );
    _stopForegroundService();
  }

  /// Mapa de avisos estructurados del backend => texto localizado.
  String? _noticeText(String code) {
    switch (code) {
      case 'image_login_required':
        return AppI18n.instance.t('notice.image_login_required');
      case 'image_daily_limit_reached':
        return AppI18n.instance.t('notice.image_daily_limit_reached');
      case 'image_generation_failed':
        return AppI18n.instance.t('notice.image_generation_failed');
      default:
        return null;
    }
  }

  // ── Foreground service: GARANTÍA de generación en 2do plano ────────────
  // Un proceso en background puede ser muerto por Android en cualquier
  // momento; con el servicio activo (tipo dataSync) el sistema no mata el
  // proceso mientras Éxodo sigue escribiendo. Se enciende al pasar a
  // background con generación activa y se apaga al volver o al terminar.
  bool _fgsInitialized = false;

  Future<void> _initForegroundService() async {
    if (_fgsInitialized) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'exodo_generating',
        channelName: 'Éxodo está escribiendo',
        channelDescription: 'Mantiene viva la respuesta cuando sales de la app',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowAutoRestart: false,
        stopWithTask: false,
      ),
    );
    _fgsInitialized = true;
  }

  Future<void> _startForegroundService() async {
    if (!isGenerating) return;
    try {
      await _initForegroundService();
      if (await FlutterForegroundTask.isRunningService) return;
      await FlutterForegroundTask.startService(
        serviceId: 3001,
        notificationTitle: 'Éxodo',
        notificationText: AppI18n.instance.t('notification.writing_in_background'),
        notificationIcon: const NotificationIcon(
          metaDataName: 'com.behavior.exodo.notification_icon',
          backgroundColor: Color(0xFFC9933A),
        ),
      );
    } catch (_) {}
  }

  Future<void> _stopForegroundService() async {
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (_) {}
  }

  // [Punto 43] Conectividad: la app detecta si hay internet en tiempo real.
  bool _isOnline = true;
  bool get isOnline => _isOnline;
  StreamSubscription<bool>? _connectivitySub;
  StreamSubscription<AuthState>? _authSub;

  bool? _hasCachedSession;
  bool get hasSession {
    final u = SupabaseService.currentUser;
    if (u != null) return true;
    return _hasCachedSession ?? false;
  }

  bool get isGuestUser {
    final u = SupabaseService.currentUser;
    if (u == null) return _hasCachedSession == true;
    return u.isAnonymous == true ||
        (u.email == null || u.email!.trim().isEmpty);
  }

  void continueAsGuest() {
    _hasCachedSession = true;
    notifyListeners();
  }

  /// Callback registrado por ChatComposer para cancelar y silenciar la grabación de voz activa
  VoidCallback? onCancelVoiceRecording;

  void cancelActiveVoiceRecording() {
    onCancelVoiceRecording?.call();
  }

  /// Cita de texto seleccionada en la respuesta para "Preguntar a Éxodo"
  String? quotedSnippet;
  VoidCallback? onRequestComposerFocus;

  /// [Fix LG V60 #5] Auto-scroll del chat al final al fijar una cita nueva,
  /// para que el composer + chip de cita queden a la vista.
  VoidCallback? onRequestChatScrollToBottom;

  void setQuotedSnippet(String snippet) {
    quotedSnippet = snippet.trim();
    onRequestComposerFocus?.call();
    onRequestChatScrollToBottom?.call();
    notifyListeners();
  }

  void clearQuotedSnippet() {
    if (quotedSnippet == null) return;
    quotedSnippet = null;
    notifyListeners();
  }

  /// [F1] Sesión activa de streaming LLM: garantiza aislamiento atómico y descarta carreras
  GenerationSession? _activeSession;

  bool _initializedSupabase = false;

  AppState({
    String? savedModelId,
    String? savedProfileJson,
    Bootstrap? bootstrap,
  }) {
    // Preferencia de privacidad (fire-and-forget: el default true solo
    // afecta el guardado al ENVIAR, no hay UI que parpadee).
    _loadCloudHistoryPref();
    WidgetsBinding.instance.addObserver(this);
    // Auto-actualización silenciosa (APK directo): chequeo + descarga en
    // background sin avisar; al terminar, notificación de instalación.
    unawaited(UpdateService.instance.checkAndDownloadSilently());
    UpdateService.instance.readyToInstall.addListener(() {
      if (UpdateService.instance.readyToInstall.value != null &&
          !isAppInBackground) {
        _updateNotified = true;
        NotificationService.instance.showUpdateReady(
          title: 'Éxodo',
          body: AppI18n.instance.t('notification.update_ready_body'),
          payload: 'install_update',
        );
      }
    });
    if (bootstrap != null) {
      _hasCachedSession = bootstrap.hasAuthToken;
      if (bootstrap.selectedModelId != null) {
        final found = exodoModels.where((m) => m.id == bootstrap.selectedModelId);
        if (found.isNotEmpty) selectedModel = found.first;
      }
      if (bootstrap.cachedProfile != null) {
        profile = bootstrap.cachedProfile;
        if (bootstrap.selectedModelId == null) {
          selectedModel = profile?.plan == 'hazak' ? exodoModels[1] : exodoModels[0];
        }
      }
      if (bootstrap.cachedConversations.isNotEmpty) {
        conversations = List.from(bootstrap.cachedConversations);
      }
      if (bootstrap.cachedLastMessages.isNotEmpty) {
        currentMessages = List.from(bootstrap.cachedLastMessages);
      }
      if (bootstrap.cachedTheme != null) {
        isDarkMode = bootstrap.cachedTheme != 'light';
      }
      if (bootstrap.cachedTokensUsed != null) {
        tokensUsed = bootstrap.cachedTokensUsed!;
      }
      if (bootstrap.lastConversationId != null && conversations.isNotEmpty) {
        try {
          activeConversation = conversations.firstWhere(
            (c) => c.id == bootstrap.lastConversationId,
          );
        } catch (_) {}
      }
    } else {
      // Carga Cache-First instantánea en el milisegundo 0 para el primer frame
      if (savedModelId != null) {
        final found = exodoModels.where((m) => m.id == savedModelId);
        if (found.isNotEmpty) {
          selectedModel = found.first;
        }
      }
      if (savedProfileJson != null) {
        try {
          profile = UserProfile.fromJson(jsonDecode(savedProfileJson));
          if (savedModelId == null) {
            selectedModel = profile?.plan == 'hazak' ? exodoModels[1] : exodoModels[0];
          }
        } catch (_) {}
      }
    }
  }

  void initAfterSupabase() {
    if (_initializedSupabase) return;
    _initializedSupabase = true;
    _init();
    _fetchWeather();
  }

  Future<void> _fetchWeather() async {
    try {
      final res = await http.get(
        Uri.parse(
          'https://api.open-meteo.com/v1/forecast?latitude=18.4861&longitude=-69.9312&current=temperature_2m',
        ),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        currentTempC = data['current']['temperature_2m'] as double?;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _init() async {
    // [Punto 43] Inicializar detector de conectividad.
    final connectivity = ConnectivityService();
    connectivity.init();
    _isOnline = connectivity.isOnline;
    _connectivitySub = connectivity.onConnectivityChanged.listen((online) async {
      _isOnline = online;
      if (online) {
        await _flushOutboxQueue();
      }
      notifyListeners();
    });

    // Flush any queued messages on startup if online
    if (_isOnline) {
      await _flushOutboxQueue();
    }

    _authSub = SupabaseService.client.auth.onAuthStateChange.listen((data) async {
      final event = data.event;
      if (event == AuthChangeEvent.signedIn ||
          event == AuthChangeEvent.initialSession) {
        _activeSession?.cancel();
        _activeSession = null;
        // Si el usuario acaba de iniciar sesión de cero (signedIn), limpiamos los mensajes.
        // En initialSession (arranque de app con sesión ya activa), no borramos los mensajes
        // optimistas que ya estén en pantalla o cargados desde caché para evitar parpadeos.
        if (event == AuthChangeEvent.signedIn) {
          currentMessages = [];
          isThinking = false;
          isGenerating = false;
        }
        await loadUserData();
      } else if (event == AuthChangeEvent.signedOut) {
        _activeSession?.cancel();
        _activeSession = null;
        profile = null;
        conversations = [];
        activeConversation = null;
        currentMessages = [];
        tokensUsed = 0;
        tokensResetTime = null;
        selectedModel = exodoModels[0];
        isThinking = false;
        isGenerating = false;
        guestMessagesSessionCount = 0;
        // Forzar que RootSwitcher redirija a AuthScreen inmediatamente.
        _hasCachedSession = false;
        // Limpiar base de datos local Drift para evitar fugas de datos entre cuentas.
        localChatRepo.clearAll().catchError((_) {});
        // Limpiar toda la caché de SharedPreferences para un arranque limpio.
        SharedPreferences.getInstance().then((prefs) {
          prefs.remove('exodo_selected_model');
          prefs.remove('exodo_cached_profile');
          prefs.remove('exodo_cached_conversations');
          prefs.remove('exodo_cached_last_messages');
          prefs.remove('exodo_last_conversation_id');
          prefs.remove('exodo_tokens_used');
          prefs.remove('exodo_theme');
          // Consentimientos: al cerrar sesión se olvidan para que el PRÓXIMO
          // login (cualquier cuenta) vuelva a pasar el gate.
          prefs.remove('exodo_age_confirmed');
          prefs.remove('exodo_consent');
        });
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _streamFlushTimer?.cancel();
    _connectivitySub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> loadUserData() async {
    // 1. CACHE-FIRST (Optimistic UI): Leer al instante del disco local (0-5ms)
    // para que la interfaz muestre el chat inmediatamente sin esperar a internet.
    final prefs = await SharedPreferences.getInstance();
    final savedModelId = prefs.getString('exodo_selected_model');
    if (savedModelId != null) {
      final found = exodoModels.where((m) => m.id == savedModelId);
      if (found.isNotEmpty) {
        selectedModel = found.first;
      }
    }
    final savedProfileJson = prefs.getString('exodo_cached_profile');
    if (savedProfileJson != null) {
      try {
        profile = UserProfile.fromJson(jsonDecode(savedProfileJson));
        if (savedModelId == null) {
          selectedModel = profile?.plan == 'hazak' ? exodoModels[1] : exodoModels[0];
        }
      } catch (_) {}
    }

    final currentUserId = SupabaseService.currentUser?.id;
    if (currentUserId != null) {
      final localConvs = await localChatRepo.getConversations(userId: currentUserId);
      if (localConvs.isNotEmpty) {
        conversations = localConvs;
        notifyListeners();
      }
    }

    startNewChat();
    notifyListeners(); // ¡Abre el chat en pantalla inmediatamente!

    // 2. BACKGROUND SYNC: Consultar la nube de Supabase en segundo plano sin bloquear.
    Future.wait<dynamic>([
      SupabaseService.getProfile().catchError((_) => null),
      (isGuestUser || isIncognito)
          ? Future.value(<Conversation>[])
          : SupabaseService.getConversations().catchError((_) => <Conversation>[]),
      SupabaseService.getTodayUsage().catchError((_) => null),
    ]).then((results) {
      final fetchedProfile = results[0] as UserProfile?;
      final fetchedConvs = results[1] as List<Conversation>;
      final usage = results[2] as Map<String, dynamic>?;
      guestIsBlocked = false;

      if (fetchedProfile != null) {
        profile = fetchedProfile;
        try {
          prefs.setString('exodo_cached_profile', jsonEncode({
            'id': profile!.id,
            'full_name': profile!.fullName,
            'plan': profile!.plan,
            'avatar_url': profile!.avatarUrl,
            'onboarding': profile!.onboarding,
          }));
        } catch (_) {}
      }

      if (activeConversation != null && !fetchedConvs.any((c) => c.id == activeConversation!.id)) {
        fetchedConvs.insert(0, activeConversation!);
      }
      // Privacidad (historial en nube OFF): conservar las conversaciones
      // SOLO-dispositivo tras la sync — sin este merge, reemplazar la lista
      // con las de la nube las borraba del drawer en cada arranque.
      final cloudIds = fetchedConvs.map((c) => c.id).toSet();
      final localOnly = conversations.where((c) => !cloudIds.contains(c.id)).toList();
      conversations = [...localOnly, ...fetchedConvs];
      localChatRepo.saveConversations(fetchedConvs);
      Bootstrap.saveSnapshot(conversations: conversations);

      // S1: La asignacion y verificacion del plan se gestiona 100% en backend y Stripe webhook
      if (savedModelId == null) {
        selectedModel = profile?.plan == 'hazak' ? exodoModels[1] : exodoModels[0];
      }

      if (usage != null) {
        tokensUsed = usage['tokens_used'] as int? ?? 0;
        if (tokensUsed > 0) {
          if (usage['created_at'] != null) {
            tokensResetTime = DateTime.tryParse(
              usage['created_at'].toString(),
            )?.toLocal().add(const Duration(hours: 24));
          } else {
            tokensResetTime = DateTime.now().add(const Duration(hours: 24));
          }
        } else {
          tokensResetTime = null;
        }
      } else {
        tokensUsed = 0;
        tokensResetTime = null;
      }

      notifyListeners();
    }).catchError((_) {});
  }

  Future<void> selectConversation(Conversation conv) async {
    cancelActiveVoiceRecording();
    if (isGenerating) {
      _cancelGeneration();
    }
    // [Sprint 0] Ownership check: verificar que la conversación pertenece al usuario actual.
    final currentUserId = SupabaseService.currentUser?.id;
    if (currentUserId != null && conv.userId != currentUserId) {
      if (kDebugMode) {
        debugPrint(
          '[AppState] selectConversation bloqueado: conv.userId=${conv.userId} != currentUserId=$currentUserId',
        );
      }
      return;
    }
    if (isIncognito) {
      currentMessages.clear();
    }
    activeConversation = conv;
    isIncognito = false;

    // 1. Carga instantánea desde SQLite local (0 ms)
    final localMsgs = await localChatRepo.getMessages(conv.id);
    if (activeConversation?.id == conv.id && !isGenerating && localMsgs.isNotEmpty) {
      currentMessages = localMsgs;
      notifyListeners();
    }

    // 2. Sincronización en segundo plano con Supabase
    final loadingConvId = conv.id;
    final fetchedMessages = await SupabaseService.getMessages(conv.id);
    // FIX (30-ago): conversación solo-local (privacidad OFF) => la nube
    // devuelve vacío y el merge borraba los mensajes que SÍ estaban en
    // Drift: la conversación se abría vacía. Si la nube no trae NADA pero
    // el dispositivo sí, conservamos lo local.
    if (fetchedMessages.isEmpty && localMsgs.isNotEmpty) {
      if (activeConversation?.id == loadingConvId && !isGenerating) {
        currentMessages = localMsgs;
        notifyListeners();
      }
      return;
    }
    if (activeConversation?.id == loadingConvId && !isGenerating) {
      // [Fix persistencia de fotos] La tabla `messages` de Supabase solo
      // guarda texto, por lo que las copias traídas de la nube llegan SIN
      // adjuntos. Antes de reemplazar la UI y el historial local se
      // fusionan los adjuntos de las filas SQLite; sin este merge, cada
      // sincronización borraba las fotos del chat al cambiar de
      // conversación.
      final merged = _mergeLocalData(fetchedMessages, localMsgs);
      // Persistencia del aviso eco: la nube no guarda isDegraded — heredarlo
      // de la copia local para que el aviso sobreviva a cerrar/abrir la app.
      for (int i = 0; i < merged.length; i++) {
        if (!merged[i].isDegraded) {
          final localMatch = localMsgs.firstWhere(
            (l) => l.id == merged[i].id || (l.role == merged[i].role && l.content.trim() == merged[i].content.trim() && l.content.trim().isNotEmpty),
            orElse: () => merged[i],
          );
          if (localMatch.isDegraded) {
            merged[i] = ChatMessage(
              id: merged[i].id,
              conversationId: merged[i].conversationId,
              role: merged[i].role,
              content: merged[i].content,
              sources: merged[i].sources,
              attachments: merged[i].attachments,
              createdAt: merged[i].createdAt,
              isDegraded: true,
            );
          }
        }
      }
      currentMessages = merged;
      // Reemplazo atómico del historial local en vez de upsert: los ids de
      // la nube (UUID) difieren de los locales (`user-*`/`asst-*`) y el
      // upsert acumulaba filas duplicadas por mensaje.
      localChatRepo.replaceMessages(conv.id, merged);
      Bootstrap.saveSnapshot(
        lastConversationId: activeConversation?.id,
        lastMessages: currentMessages,
      );
      notifyListeners();
    }
  }

  /// Fusiona los adjuntos y fuentes (sources) de los mensajes locales (SQLite)
  /// en las copias traídas de Supabase para garantizar persistencia 100% íntegra.
  /// Implementa estrategia de emparejamiento multi-nivel:
  /// 1. Coincidencia exacta por id.
  /// 2. Coincidencia por rol + contenido no vacío.
  /// 3. Coincidencia por rol ('user') con contenido vacío por proximidad temporal.
  /// 4. Coincidencia posicional para mensajes de usuario restantes.
  /// 5. Safety Net: si queda algún mensaje local con adjuntos/fuentes no emparejado,
  ///    se inserta en el orden cronológico correcto.
  List<ChatMessage> _mergeLocalData(
    List<ChatMessage> cloud,
    List<ChatMessage> local,
  ) {
    final pool = local.where((l) => l.attachments.isNotEmpty || l.sources.isNotEmpty).toList();
    if (pool.isEmpty) return cloud;

    int mergedCount = 0;
    final mergedCloud = cloud.map((m) {
      if (pool.isEmpty) return m;

      int idx = -1;

      // Nivel 1: Match exacto por id
      idx = pool.indexWhere((l) => l.id == m.id);

      // Nivel 2: Match por rol + contenido no vacío
      if (idx == -1 && m.content.trim().isNotEmpty) {
        idx = pool.indexWhere(
          (l) => l.role == m.role && l.content.trim() == m.content.trim(),
        );
      }

      // Nivel 3: Match para contenido vacío ('') entre mensajes de usuario
      if (idx == -1 && m.role == 'user' && m.content.trim().isEmpty) {
        int bestIdx = -1;
        int minDiffMs = 999999999;
        for (int i = 0; i < pool.length; i++) {
          final l = pool[i];
          if (l.role == 'user' && l.content.trim().isEmpty) {
            final diff = (l.createdAt.millisecondsSinceEpoch - m.createdAt.millisecondsSinceEpoch).abs();
            if (diff < minDiffMs) {
              minDiffMs = diff;
              bestIdx = i;
            }
          }
        }
        if (bestIdx != -1) {
          idx = bestIdx;
        }
      }

      // Nivel 4: Match posicional si solo queda un mensaje de usuario
      if (idx == -1 && m.role == 'user') {
        idx = pool.indexWhere((l) => l.role == 'user');
      }

      if (idx == -1) return m;

      final match = pool.removeAt(idx);
      mergedCount++;
      return ChatMessage(
        id: m.id,
        conversationId: m.conversationId,
        role: m.role,
        content: m.content,
        intentDetected: m.intentDetected ?? match.intentDetected,
        modelCalled: m.modelCalled ?? match.modelCalled,
        sources: m.sources.isNotEmpty ? m.sources : match.sources,
        attachments: match.attachments.isNotEmpty ? match.attachments : m.attachments,
        createdAt: m.createdAt,
        isThinking: m.isThinking,
        isDegraded: m.isDegraded,
      );
    }).toList();

    // Nivel 5 (Safety Net): Si quedan mensajes locales con adjuntos o fuentes que no
    // vinieron en la respuesta de la nube, agregarlos preservando el orden.
    if (pool.isNotEmpty) {
      if (kDebugMode) {
        debugPrint(
          '[AppState] _mergeLocalData: Reteniendo ${pool.length} mensajes locales con datos no sincronizados en nube',
        );
      }
      final result = <ChatMessage>[...mergedCloud, ...pool];
      result.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return result;
    }

    if (kDebugMode && mergedCount > 0) {
      debugPrint(
        '[AppState] _mergeLocalData: Fusionados con éxito $mergedCount mensajes con datos locales',
      );
    }

    return mergedCloud;
  }

  /// Idioma efectivo de la interfaz para el backend (default 'es').
  String get effectiveLocale {
    final code = AppI18n.instance.localeCode;
    return code.trim().isEmpty ? 'es' : code.trim();
  }

  /// Garantiza variedad de títulos: si ya existe una conversación con el mismo
  /// título, agrega sufijo " ·2", " ·3"... (el usuario puede abrir 20 chats
  /// diciendo "hola" y ninguno debe verse clonado).
  String _makeUniqueTitle(String base) {
    final clean = base.trim();
    if (clean.isEmpty) return clean;
    final existing = conversations.map((c) => c.title.trim()).toSet();
    if (!existing.contains(clean)) return clean;
    var n = 2;
    while (existing.contains('$clean ·$n')) {
      n++;
    }
    return '$clean ·$n';
  }

  /// Genera un título ultra-conciso (2 a 4 palabras) en segundo plano llamando
  /// al endpoint LLM del backend `/api/chat/title` con qwen3.7-flash.
  void _requestLLMTitle({
    required String conversationId,
    required String userText,
    required String assistantText,
  }) {
    unawaited(() async {
      try {
        final generatedTitle = await ChatService.generateTitle(
          conversationId: conversationId,
          userText: userText,
          assistantText: assistantText,
          locale: effectiveLocale,
        );

        if (generatedTitle != null && generatedTitle.trim().isNotEmpty) {
          final cleanTitle = _makeUniqueTitle(generatedTitle);
          if (kDebugMode) {
            debugPrint('[AppState] LLM Title Generated: "$cleanTitle" for conv $conversationId');
          }
          if (activeConversation?.id == conversationId) {
            activeConversation = activeConversation!.copyWith(title: cleanTitle);
          }
          final idx = conversations.indexWhere((c) => c.id == conversationId);
          if (idx != -1) {
            conversations[idx] = conversations[idx].copyWith(title: cleanTitle);
          }
          await localChatRepo.updateConversationTitle(conversationId, cleanTitle);
          if (!isGuestUser && !isIncognito && cloudHistoryEnabled) {
            SupabaseService.updateConversationTitle(conversationId, cleanTitle).catchError((_) {});
          }
          Bootstrap.saveSnapshot(conversations: conversations);
          notifyListeners();
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[AppState] LLM titling error: $e');
        }
      }
    }());
  }

  void startNewChat({bool resetIncognito = true}) {
    cancelActiveVoiceRecording();
    _cancelGeneration();
    if (resetIncognito) {
      isIncognito = false;
    }
    activeConversation = null;
    currentMessages = [];
    Bootstrap.saveSnapshot(
      lastConversationId: '',
      lastMessages: [],
    );
    notifyListeners();
  }

  /// Mueve la conversación con id [convId] al tope de [conversations]
  /// (MRU). No hace nada si la lista está vacía, la conversación no
  /// existe, o ya está en el índice 0. Persiste el snapshot local y
  /// dispara `notifyListeners()` únicamente cuando hubo reordenamiento
  /// real, evitando rebuilds innecesarios del Drawer.
  void _bubbleConversationToTop(String convId) {
    if (conversations.isEmpty) return;
    final idx = conversations.indexWhere((c) => c.id == convId);
    if (idx <= 0) return;
    final conv = conversations.removeAt(idx);
    conversations.insert(0, conv);
    Bootstrap.saveSnapshot(conversations: conversations);
    notifyListeners();
  }

  void renameConversation(String convId, String newTitle) {
    final idx = conversations.indexWhere((c) => c.id == convId);
    if (idx != -1) {
      final old = conversations[idx];
      conversations[idx] = Conversation(
        id: convId,
        userId: old.userId,
        title: newTitle,
        modelPlan: old.modelPlan,
        isIncognito: old.isIncognito,
        isStarred: old.isStarred,
        createdAt: old.createdAt,
      );
      if (activeConversation?.id == convId) {
        activeConversation = conversations[idx];
      }
      localChatRepo.renameConversation(convId, newTitle);
      SupabaseService.updateConversationTitle(convId, newTitle);
      Bootstrap.saveSnapshot(conversations: conversations);
      notifyListeners();
    }
  }

  void toggleStarConversation(String convId) {
    final idx = conversations.indexWhere((c) => c.id == convId);
    if (idx != -1) {
      final old = conversations[idx];
      final newStarred = !old.isStarred;
      conversations[idx] = Conversation(
        id: convId,
        userId: old.userId,
        title: old.title,
        modelPlan: old.modelPlan,
        isIncognito: old.isIncognito,
        isStarred: newStarred,
        createdAt: old.createdAt,
      );
      if (activeConversation?.id == convId) {
        activeConversation = conversations[idx];
      }
      localChatRepo.toggleStarred(convId, newStarred);
      SupabaseService.toggleConversationStarred(convId, newStarred);
      Bootstrap.saveSnapshot(conversations: conversations);
      notifyListeners();
    }
  }

  Future<void> deleteConversation(String convId) async {
    final wasActive = activeConversation?.id == convId;
    conversations.removeWhere((c) => c.id == convId);
    localChatRepo.deleteConversation(convId);
    Bootstrap.saveSnapshot(conversations: conversations);
    if (wasActive) {
      // Fase 3: continuidad tras borrado.
      // Si quedan conversaciones, saltar a la más reciente (conversations ya viene
      // ordenada por updatedAt desc desde Supabase). Si la lista queda vacía,
      // mantener el comportamiento de chat nuevo.
      if (conversations.isNotEmpty) {
        await selectConversation(conversations.first);
      } else {
        startNewChat();
      }
    } else {
      notifyListeners();
    }
    await SupabaseService.deleteConversation(convId);
  }

  void toggleIncognito() {
    isIncognito = !isIncognito;
    if (isIncognito) {
      selectedModel = exodoModels[0];
    }
    startNewChat(resetIncognito: false);
  }

  void toggleTheme() {
    isDarkMode = !isDarkMode;
    Bootstrap.saveSnapshot(theme: isDarkMode ? 'dark' : 'light');
    notifyListeners();
  }

  /// Sale de incógnito y limpia mensajes. Llamado desde chat_screen
  /// al abrir el drawer estando en incógnito.
  void exitIncognitoAndClear() {
    cancelActiveVoiceRecording();
    currentMessages.clear();
    isIncognito = false;
    notifyListeners();
  }

  void dismissTab2Banner() {
    showTab2Banner = false;
    notifyListeners();
  }

  void selectModelOption(ExodoModelOption option) {
    if (isIncognito) return;
    if (option.plan == 'hazak' && !isPro) {
      return;
    }
    selectedModel = option;
    Bootstrap.saveSnapshot(selectedModelId: option.id);
    notifyListeners();
  }

  String get userEmail => SupabaseService.client.auth.currentUser?.email ?? '';

  String? get userAvatarUrl {
    if (profile?.avatarUrl != null && profile!.avatarUrl!.isNotEmpty) {
      return profile!.avatarUrl;
    }
    final user = SupabaseService.currentUser;
    if (user != null && user.userMetadata != null) {
      final meta = user.userMetadata!;
      final url =
          meta['avatar_url']?.toString() ??
          meta['picture']?.toString() ??
          meta['photo_url']?.toString();
      if (url != null && url.isNotEmpty) {
        return url;
      }
    }
    return null;
  }

  Future<bool> updateProfileDetails(
    String newFullName,
    String newNickname,
  ) async {
    if (profile != null) {
      final updatedOnboarding = Map<String, dynamic>.from(
        profile!.onboarding ?? {},
      );
      updatedOnboarding['nickname'] = newNickname;

      final oldProfile = profile;
      profile = UserProfile(
        id: profile!.id,
        fullName: newFullName,
        plan: profile!.plan,
        avatarUrl: profile!.avatarUrl,
        onboarding: updatedOnboarding,
      );
      notifyListeners();

      try {
        await SupabaseService.client
            .from('profiles')
            .update({'full_name': newFullName, 'onboarding': updatedOnboarding})
            .eq('id', profile!.id);
        return true;
      } catch (e) {
        profile = oldProfile;
        notifyListeners();
        return false;
      }
    }
    return false;
  }

  /// P3 monetización: revalida el perfil contra la nube. Se llama al volver a
  /// primer plano: si el usuario pagó en el navegador (Stripe), el webhook ya
  /// actualizó `profiles.plan` y Pro se activa SIN reiniciar la app.
  Future<void> refreshProfileFromCloud() async {
    try {
      if (!hasSession || isGuestUser || isIncognito) return;
      final fetched = await SupabaseService.getProfile().catchError((_) => null);
      if (fetched != null && fetched.plan != (profile?.plan ?? '')) {
        final old = profile;
        profile = fetched;
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('exodo_cached_profile', jsonEncode({
            'id': fetched.id,
            'full_name': fetched.fullName,
            'plan': fetched.plan,
            'avatar_url': fetched.avatarUrl,
            'onboarding': fetched.onboarding,
          }));
        } catch (_) {}
        debugPrint('[AppState] plan actualizado tras resume: ${old?.plan} -> ${fetched.plan}');
        notifyListeners();
      } else if (fetched != null) {
        profile = fetched;
      }
    } catch (_) {}
  }

  /// Borra la cuenta del usuario. Devuelve false si la purga remota falló
  /// (la UI debe avisar y permitir reintentar — ya no nos callamos).
  Future<bool> deleteAccount() async {
    final userId = SupabaseService.client.auth.currentUser?.id;
    if (userId != null) {
      var remoteDeleted = false;
      try {
        // P0 auditoría: purga total vía RPC SECURITY DEFINER
        // (007_delete_user_account.sql). Antes era un DELETE directo sobre
        // profiles que RLS rechazaba al no existir política DELETE.
        // La RPC purga profiles + conversations + expedientes + auth.users.
        await SupabaseService.client.rpc('delete_user_account');
        remoteDeleted = true;
      } catch (e) {
        // P3: una purga remota fallida (RLS/red) no debe dejar datos
        // huérfanos en la nube con los datos locales ya borrados.
        debugPrint('[AppState] deleteAccount: fallo RPC delete_user_account: $e');
        try {
          await SupabaseService.client.rpc('delete_user_account');
          remoteDeleted = true;
        } catch (e2) {
          debugPrint('[AppState] deleteAccount: reintento falló, se aborta limpieza: $e2');
        }
      }
      // Si la cuenta sigue viva en la nube, conservar sesión y datos locales
      // para que el usuario reintente (consistencia > apariencia) Y AVISAR.
      if (!remoteDeleted) {
        errorMessage = AppI18n.instance.t('error.delete_account_failed');
        notifyListeners();
        return false;
      }
    }
    profile = null;
    _hasCachedSession = false;
    localChatRepo.clearAll().catchError((_) {});
    // Cuenta borrada = todo borrado: consentimientos incluidos. Si vuelve a
    // hacer login, pasa el gate de nuevo (decisión del dueño 30-ago).
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('exodo_age_confirmed');
      await prefs.remove('exodo_consent');
    } catch (_) {}
    await SupabaseService.signOut();
    notifyListeners();
    return true;
  }

  // [Punto 4] `upgradeToProPlan` eliminado: era código muerto (cero callers;
  // el flujo real vive en StripeService.startCheckoutSession vía UpgradeModal)
  // y sus 3 SnackBars violaban la política de silencio en pagos.

  // [Punto 39] Borra todo el historial de conversaciones del usuario.
  // conecta con Supabase: elimina todas las conversations del user_id actual
  // (los mensajes se borran en cascada ON DELETE CASCADE).
  // Limpia localmente: conversaciones, conversación activa, mensajes actuales.
  Future<void> clearHistory() async {
    await SupabaseService.deleteAllConversations();
    conversations = [];
    activeConversation = null;
    currentMessages = [];
    // Limpiar la base de datos local y la caché de arranque.
    localChatRepo.clearAll().catchError((_) {});
    Bootstrap.saveSnapshot(
      conversations: [],
      lastMessages: [],
      lastConversationId: '',
    );
    notifyListeners();
  }

  Future<void> cancelProPlan() async {
    if (profile != null) {
      profile = UserProfile(
        id: profile!.id,
        fullName: profile!.fullName,
        plan: 'genesis',
        avatarUrl: profile!.avatarUrl,
        onboarding: profile!.onboarding,
      );
      selectedModel = exodoModels[0];
      await SupabaseService.client
          .from('profiles')
          .update({'plan': 'genesis'})
          .eq('id', profile!.id);
      notifyListeners();
    }
  }

  Future<void> reformulateLastAssistantMessage(
    ChatMessage lastAssistant,
  ) async {
    if (currentMessages.isEmpty) return;

    final isGuest = isGuestUser;
    if (!isGuest) {
      if (tokensUsed >= tokensLimit) {
        final limitMsg = isPro
            ? AppI18n.instance.t('limit.pro_msg')
            : AppI18n.instance.t('limit.free_msg');
        currentMessages.add(
          ChatMessage(
            id: 'limit-${DateTime.now().microsecondsSinceEpoch}',
            conversationId: activeConversation?.id ?? 'free',
            role: 'assistant',
            content: limitMsg,
            createdAt: DateTime.now(),
          ),
        );
        notifyListeners();
        return;
      }
    }

    final idx = currentMessages.lastIndexWhere(
      (m) => m.role == 'assistant' && m.id == lastAssistant.id,
    );
    if (idx == -1) return;
    currentMessages.removeAt(idx);
    notifyListeners();

    final thinkingId = 'reformulate-${DateTime.now().microsecondsSinceEpoch}';
    currentMessages.add(
      ChatMessage(
        id: thinkingId,
        conversationId: activeConversation?.id ?? '',
        role: 'assistant',
        content: '',
        createdAt: DateTime.now(),
        isThinking: true,
      ),
    );
    notifyListeners();

    try {
      isGenerating = true;
      notifyListeners();
      await _reformulateInBackground(thinkingId);
    } catch (e) {
      isGenerating = false;
      currentMessages.removeWhere((m) => m.id == thinkingId);
      errorMessage = e.toString();
      notifyListeners();
    }
  }

  // ── Streaming suavizado: helpers del buffer de deltas ─────────────────

  /// Procesa un delta del stream. En el PRIMER delta convierte la burbuja
  /// "thinking" en el mensaje asistente activo; los siguientes se acumulan
  /// en el buffer sin tocar la lista ni notificar listeners.
  /// [guard] (opcional) se evalúa en cada flush con el contenido acumulado;
  /// si devuelve true, la generación se cancela (p. ej. límite de tokens).
  void _handleStreamChunk(
    String msgId,
    String chunk, {
    required bool isDegraded,
    bool Function(String content)? guard,
  }) {
    if (_streamingMsgId != msgId) {
      if (_streamingMsgId != null) _endStreamingMessage();
      // Preservar createdAt de la burbuja thinking si ya existía.
      final existingIdx = currentMessages.indexWhere((m) => m.id == msgId);
      _streamingCreatedAt = existingIdx != -1
          ? currentMessages[existingIdx].createdAt
          : DateTime.now();
      currentMessages.removeWhere((m) => m.isThinking);
      isThinking = false;
      _streamingMsgId = msgId;
      _streamingIsDegraded = isDegraded;
      _streamGuard = guard;
      _streamBuffer.clear();
      _materializeStreamingMessage();
    }
    _streamBuffer.write(chunk);
    _streamFlushTimer ??= Timer(_streamFlushInterval, _flushStreamBuffer);
  }

  /// Vuelca el buffer acumulado al mensaje activo: UNA copia de ChatMessage
  /// y UN notifyListeners() por frame, independiente de la tasa de tokens.
  void _flushStreamBuffer() {
    _streamFlushTimer = null;
    if (_streamingMsgId == null) return;
    _materializeStreamingMessage();
    final guard = _streamGuard;
    if (guard != null && _streamingMsgId != null && guard(_streamBuffer.toString())) {
      // El guard canceló la generación (límite de tokens); _cancelGeneration()
      // ya limpió el estado del stream.
    }
  }

  void _materializeStreamingMessage() {
    final id = _streamingMsgId;
    if (id == null) return;
    final content = _streamBuffer.toString();
    final idx = currentMessages.indexWhere((m) => m.id == id);
    if (idx == -1) {
      currentMessages.add(
        ChatMessage(
          id: id,
          conversationId: activeConversation?.id ?? 'incognito',
          role: 'assistant',
          content: content,
          createdAt: _streamingCreatedAt ?? DateTime.now(),
          isDegraded: _streamingIsDegraded,
        ),
      );
    } else {
      currentMessages[idx] = ChatMessage(
        id: id,
        conversationId: currentMessages[idx].conversationId,
        role: 'assistant',
        content: content,
        sources: currentMessages[idx].sources,
        createdAt: currentMessages[idx].createdAt,
        isDegraded: _streamingIsDegraded,
      );
    }
    notifyListeners();
  }

  /// Finaliza la sesión de streaming: materializa los deltas pendientes
  /// (≤1 frame) y limpia timers/estado.
  void _endStreamingMessage() {
    _streamFlushTimer?.cancel();
    _streamFlushTimer = null;
    _streamGuard = null;
    if (_streamingMsgId != null) {
      _materializeStreamingMessage();
      _streamingMsgId = null;
    }
    _streamBuffer.clear();
  }

  void _revertTokens(int amount) {
    if (isGuestUser || isIncognito) return;
    tokensUsed -= amount;
    if (tokensUsed < 0) tokensUsed = 0;
  }

  Future<void> _reformulateInBackground(String thinkingId) async {
    final lastUserIdx = currentMessages.lastIndexWhere((m) => m.role == 'user');
    if (lastUserIdx == -1) {
      currentMessages.removeWhere((m) => m.id == thinkingId);
      notifyListeners();
      return;
    }
    final lastUserText = currentMessages[lastUserIdx].content;
    final userTokensEst = (lastUserText.length ~/ 3) + 15;
    tokensUsed += userTokensEst;

    await ChatService.sendMessageStream(
      conversationId: activeConversation?.id ?? '',
      message: lastUserText,
      history: (isIncognito || isGuestUser || !cloudHistoryEnabled)
          ? currentMessages
                .where((m) => !m.isThinking)
                .map((m) => {'role': m.role, 'content': m.content})
                .toList()
          : null,
      modelOverride: selectedModel.modelId,
      taskType: effectiveTaskType,
      locale: effectiveLocale,
      onNotice: (code) {
        final text = _noticeText(code);
        if (text == null) return;
        currentMessages.removeWhere((m) => m.isThinking || m.id == thinkingId);
        isThinking = false;
        isGenerating = false;
        currentMessages.add(
          ChatMessage(
            id: 'notice-${DateTime.now().microsecondsSinceEpoch}',
            conversationId: activeConversation?.id ?? 'guest',
            role: 'system',
            content: text,
            createdAt: DateTime.now(),
          ),
        );
        _endStreamingMessage();
        notifyListeners();
      },
      onChunk: (chunk) {
        // FIX jerky streaming: los deltas se acumulan en el buffer y se
        // materializan a cadencia de frame (~33ms), no por cada token.
        // DOCTRINA soft cap: SIN guard de corte por tokens — el flujo jamás
        // se interrumpe por cuota (producción degradará a Groq Modo Eco vía
        // isDegraded del backend; el medidor es informativo).
        _handleStreamChunk(
          thinkingId,
          chunk,
          isDegraded: false,
        );
      },
      onComplete: (fullText, sources) {
        _endStreamingMessage();
        isGenerating = false;
        _notifyIfBackground(responsePreview: fullText);
        if (!isGuestUser) {
          tokensUsed += (fullText.length ~/ 3) + 35;
          if (tokensUsed > tokensLimit) tokensUsed = tokensLimit;
        }
        final idx = currentMessages.indexWhere((m) => m.id == thinkingId);
        if (idx == -1) return;
        currentMessages[idx] = ChatMessage(
          id: thinkingId,
          conversationId: activeConversation?.id ?? '',
          role: 'assistant',
          content: fullText,
          sources: sources,
          createdAt: currentMessages[idx].createdAt,
        );
        if (activeConversation != null && !isGuestUser) {
          localChatRepo.saveMessage(currentMessages[idx]);
        }
        notifyListeners();
      },
      onError: (e) {
        _endStreamingMessage();
        _revertTokens(userTokensEst);
        isGenerating = false;
        _stopForegroundService();
        if (isAppInBackground) return;
        errorMessage = e.toString();
        notifyListeners();
      },
    );
  }

  Future<void> sendUserMessage(
    String text, {
    List<Attachment>? attachments,
  }) async {
    var effectiveText = text;
    if (quotedSnippet != null && quotedSnippet!.isNotEmpty) {
      final q = quotedSnippet!;
      clearQuotedSnippet();
      if (effectiveText.trim().isEmpty) {
        effectiveText = '> $q';
      } else {
        effectiveText = '> $q\n\n$effectiveText';
      }
    }

    if (effectiveText.trim().isEmpty && (attachments == null || attachments.isEmpty)) return;
    final isGuest = isGuestUser;
    errorMessage = null;
    lastFailedSendText = null;

    // Privacidad por capas: saveLocally ⇒ persiste en Drift (este
    // dispositivo); syncToCloud ⇒ además persiste en Supabase. Con el toggle
    // OFF el historial SOLO vive en el teléfono: sobrevive reinicios y Éxodo
    // mantiene contexto (nada de "no me acuerdo"), pero ningún servidor
    // guarda la conversación — el backend recibe únicamente la ventana del
    // turno en curso, igual que en incógnito, y no la almacena.
    final saveLocally = !isIncognito && !isGuest;
    final syncToCloud = saveLocally && cloudHistoryEnabled;
    final sendHistoryWindow = isIncognito || isGuest || !cloudHistoryEnabled;

    // 1. AÑADIR MENSAJE DE USUARIO Y THINKING BUBBLE A LA UI INMEDIATAMENTE (Optimistic UI 0 ms lag)
    currentMessages.removeWhere((m) => m.id == 'error');
    final userTokensEst = (effectiveText.length ~/ 3) + 15;
    tokensUsed += userTokensEst;
    tokensResetTime ??= DateTime.now().add(const Duration(hours: 24));
    final userMsg = ChatMessage(
      id: 'user-${DateTime.now().microsecondsSinceEpoch}',
      conversationId: activeConversation?.id ?? 'guest',
      role: 'user',
      content: effectiveText,
      attachments: attachments ?? const [],
      createdAt: DateTime.now(),
    );
    currentMessages.add(userMsg);

    // OFFLINE OUTBOX: Si no hay conexión, guardar en Drift con status='queued' y retornar
    if (!_isOnline) {
      if (saveLocally && activeConversation != null) {
        // Guardar en Drift con status queued
        await localChatRepo.saveMessage(userMsg);
        await localChatRepo.updateMessageStatus(userMsg.id, LocalMessageStatus.queued);
      }
      // Agregar badge visual de offline al mensaje
      final offlineMsg = ChatMessage(
        id: 'offline-${DateTime.now().microsecondsSinceEpoch}',
        conversationId: activeConversation?.id ?? 'guest',
        role: 'system',
        content: 'Mensaje en cola. Se enviará automáticamente cuando recuperes conexión.',
        createdAt: DateTime.now(),
      );
      currentMessages.add(offlineMsg);
      notifyListeners();
      return; // Retornar sin hacer HTTP
    }

    isThinking = true;
    isGenerating = true;
    isGeneratingImage = false;
    final thinkingMsg = ChatMessage(
      id: 'thinking',
      conversationId: activeConversation?.id ?? 'guest',
      role: 'assistant',
      content: '',
      createdAt: DateTime.now(),
      isThinking: true,
    );
    currentMessages.add(thinkingMsg);
    notifyListeners(); // ¡Aparece en pantalla en el milisegundo que el usuario pulsa Enviar!

    // 2. CREAR CONVERSACIÓN EN BD (si no existe) SIN DETENER LA UI
    // PERF (TTFT): el ID de la conversación se genera EN EL CLIENTE (UUID v4)
    // y la inserción en la nube vuela en background. Así el primer mensaje
    // sale de inmediato sin esperar el roundtrip de creación (~300-800 ms).
    // El backend tolera la creación optimista: assertConversationOwner admite
    // conversaciones aún no insertadas y su saveMessage ocurre cuando el LLM
    // termina (varios segundos después, con la inserción ya completada).
    if (activeConversation == null && saveLocally) {
      // Título inicial provisional: texto del usuario o 'Nuevo chat'
      final effectiveTitleRaw = text.trim().isNotEmpty
          ? (text.trim().length > 30 ? '${text.trim().substring(0, 30)}...' : text.trim())
          : 'Nuevo chat';
      final effectiveTitle = _makeUniqueTitle(effectiveTitleRaw);

      final convId = ChatService.generateSessionId(); // UUID v4 real
      final placeholder = Conversation(
        id: convId,
        userId: SupabaseService.client.auth.currentUser?.id ?? 'local',
        title: effectiveTitle,
        modelPlan: selectedModel.plan,
        createdAt: DateTime.now(),
      );
      conversations.insert(0, placeholder);
      activeConversation = placeholder;
      localChatRepo.saveConversation(placeholder);

      // Re-etiquetar los mensajes en pantalla (user + thinking) al UUID real.
      for (int i = 0; i < currentMessages.length; i++) {
        final cid = currentMessages[i].conversationId;
        if (cid == 'guest' || cid == 'incognito' || cid.isEmpty) {
          currentMessages[i] = ChatMessage(
            id: currentMessages[i].id,
            conversationId: convId,
            role: currentMessages[i].role,
            content: currentMessages[i].content,
            attachments: currentMessages[i].attachments,
            sources: currentMessages[i].sources,
            createdAt: currentMessages[i].createdAt,
            isThinking: currentMessages[i].isThinking,
          );
        }
      }
      notifyListeners(); // El chat ya aparece en el Drawer sin esperar red

      // Inserción en la nube SIN bloquear el envío del mensaje — solo cuando
      // el usuario permite historial en la nube (privacidad ON). Con OFF, la
      // conversación queda exclusivamente en Drift bajo el mismo UUID.
      if (syncToCloud) {
      unawaited(
        SupabaseService.createConversation(
          effectiveTitle,
          selectedModel.plan,
          false,
          id: convId,
        ).then((remoteConv) {
          final idx = conversations.indexWhere((c) => c.id == convId);
          if (idx != -1) {
            conversations[idx] = remoteConv;
          }
          if (activeConversation?.id == convId) {
            activeConversation = remoteConv;
          }
          localChatRepo.saveConversation(remoteConv);
          notifyListeners();
        }).catchError((Object e) {
          // Degradado: sin nube se conserva la conversación local bajo el
          // mismo UUID; el historial en la nube se recuperará con conectividad.
          debugPrint('[AppState] createConversation falló, modo solo-local: $e');
        }),
      );
      }
    } else if (saveLocally) {
      _bubbleConversationToTop(activeConversation!.id);
    }

    // 3. GUARDAR MENSAJE DE USUARIO EN BD LOCAL Y NUBE EN SEGUNDO PLANO
    if (saveLocally && activeConversation != null) {
      final effectiveUserMsg = ChatMessage(
        id: userMsg.id,
        conversationId: activeConversation!.id,
        role: userMsg.role,
        content: userMsg.content,
        intentDetected: userMsg.intentDetected,
        modelCalled: userMsg.modelCalled,
        sources: userMsg.sources,
        attachments: userMsg.attachments,
        createdAt: userMsg.createdAt,
        isThinking: userMsg.isThinking,
        isDegraded: userMsg.isDegraded,
      );
      localChatRepo.saveMessage(effectiveUserMsg);
    }

    final msgId = 'asst-${DateTime.now().microsecondsSinceEpoch}';
    final capturedConvId = activeConversation?.id;

    // [F1] Cancelar cualquier sesión anterior y crear una sesión limpia con ID único
    _activeSession?.cancel();
    final session = GenerationSession(
      id: ChatService.generateSessionId(),
      conversationId: capturedConvId,
    );
    _activeSession = session;

    // Aviso estructurado del backend (p. ej. imagen sin sesión): reemplaza la
    // burbuja thinking por un mensaje de sistema estilo disclaimer.
    var noticeShown = false;
    void handleNotice(String code) {
      if (session.isCancelled || _activeSession?.id != session.id) return;
      final text = _noticeText(code);
      if (text == null) return;
      noticeShown = true;
      currentMessages.removeWhere((m) => m.isThinking || m.id == msgId);
      isThinking = false;
      currentMessages.add(
        ChatMessage(
          id: 'notice-${DateTime.now().microsecondsSinceEpoch}',
          conversationId: activeConversation?.id ?? 'guest',
          role: 'system',
          content: text,
          createdAt: DateTime.now(),
        ),
      );
      isGenerating = false;
      isGeneratingImage = false;
      _endStreamingMessage();
      HapticFeedback.selectionClick();
      notifyListeners();
    }

    try {
      bool msgIsDegraded = false;

      await ChatService.sendMessageStream(
        message: text,
        conversationId: syncToCloud ? capturedConvId : null,
        // Sin historial en nube (privacidad OFF) el backend no puede leer la
        // conversación de la DB: se envía la ventana local como en incógnito.
        history: sendHistoryWindow
            ? currentMessages
                  .where((m) => !m.isThinking)
                  .map((m) => {'role': m.role, 'content': m.content})
                  .toList()
            : null,
        modelOverride: selectedModel.modelId,
        taskType: effectiveTaskType,
        locale: effectiveLocale,
        attachments:
            attachments, // [Punto 40] adjuntos con bytes para multimodal
        session: session, // [F1] Sesión atómica
        onMeta: (meta) {
          if (session.isCancelled || _activeSession?.id != session.id) return;
          if (meta['isDegraded'] == true) {
            msgIsDegraded = true;
            final idx = currentMessages.indexWhere((m) => m.id == msgId);
            if (idx != -1) {
              currentMessages[idx] = ChatMessage(
                id: msgId,
                conversationId: currentMessages[idx].conversationId,
                role: 'assistant',
                content: currentMessages[idx].content,
                sources: currentMessages[idx].sources,
                createdAt: currentMessages[idx].createdAt,
                isDegraded: true,
              );
              notifyListeners();
            }
          }
        },
        onNotice: handleNotice,
        onGeneratingImage: () {
          if (session.isCancelled || _activeSession?.id != session.id) return;
          if (noticeShown) return;
          // [UX #1] Fin del "thinking" genérico: mostrar shimmer de imagen.
          isGeneratingImage = true;
          notifyListeners();
        },
        onChunk: (chunk) {
          if (session.isCancelled || _activeSession?.id != session.id) return;
          if (noticeShown) return;
          // FIX jerky streaming: append directo al buffer del mensaje activo;
          // la lista y los listeners se actualizan a cadencia de frame (~33ms)
          // en lugar de reconstruirse por cada token.
          _handleStreamChunk(msgId, chunk, isDegraded: msgIsDegraded);
        },
        onComplete: (fullText, sources) async {
          if (session.isCancelled || _activeSession?.id != session.id) return;
          if (noticeShown) {
            _endStreamingMessage();
            isGenerating = false;
            isGeneratingImage = false;
            HapticFeedback.vibrate();
            notifyListeners();
            return;
          }
          _endStreamingMessage();
          isGenerating = false;
          isGeneratingImage = false;
          if (!isGuestUser) {
            tokensUsed += (fullText.length ~/ 3) + 35;
          }
          final idx = currentMessages.indexWhere((m) => m.id == msgId);
          if (idx != -1) {
            currentMessages[idx] = ChatMessage(
              id: msgId,
              conversationId: currentMessages[idx].conversationId,
              role: 'assistant',
              content: fullText,
              sources: sources,
              createdAt: currentMessages[idx].createdAt,
              isDegraded: msgIsDegraded,
            );
          } else {
            // El stream cerró sin chunks visibles (p. ej. solo 'done'): crear
            // el mensaje final directamente.
            currentMessages.removeWhere((m) => m.isThinking);
            isThinking = false;
            if (activeConversation?.id == capturedConvId) {
              currentMessages.add(
                ChatMessage(
                  id: msgId,
                  conversationId: capturedConvId ?? 'incognito',
                  role: 'assistant',
                  content: fullText,
                  sources: sources,
                  createdAt: DateTime.now(),
                  isDegraded: msgIsDegraded,
                ),
              );
            }
          }
          if (saveLocally && capturedConvId != null && !isGuest) {
            final assistantMsg = ChatMessage(
              id: msgId,
              conversationId: capturedConvId,
              role: 'assistant',
              content: fullText,
              sources: sources,
              createdAt: DateTime.now(),
              isDegraded: msgIsDegraded,
            );
            localChatRepo.saveMessage(assistantMsg);

            // Titulado LLM Dinámico en Segundo Plano (unawaited)
            final assistantTurns = currentMessages.where((m) => m.role == 'assistant' && !m.isThinking).length;
            if (assistantTurns <= 1) {
              _requestLLMTitle(
                conversationId: capturedConvId,
                userText: text,
                assistantText: fullText,
              );
            }
          }
          _notifyIfBackground(responsePreview: fullText);
          HapticFeedback.vibrate();
          notifyListeners();
        },
        onError: (err) {
          if (session.isCancelled || _activeSession?.id != session.id) return;
          _endStreamingMessage();
          _stopForegroundService();
          _revertTokens(userTokensEst);
          if (activeConversation?.id == capturedConvId) {
            currentMessages.removeWhere((m) => m.id == msgId || m.isThinking);
            isThinking = false;
            isGenerating = false;
            isGeneratingImage = false;
            errorMessage = err.replaceAll('Exception: ', '');
            lastFailedSendText = effectiveText;
            currentMessages.add(
              ChatMessage(
                id: 'error',
                conversationId: capturedConvId ?? 'incognito',
                role: 'assistant',
                content: '⚠️ $errorMessage',
                createdAt: DateTime.now(),
              ),
            );
            notifyListeners();
          }
        },
      );
    } catch (e) {
      if (session.isCancelled || _activeSession?.id != session.id) return;
      _endStreamingMessage();
      _revertTokens(userTokensEst);
      currentMessages.removeWhere((m) => m.id == msgId || m.isThinking);
      isThinking = false;
      isGenerating = false;
      isGeneratingImage = false;
      errorMessage = e.toString().replaceAll('Exception: ', '');
      lastFailedSendText = effectiveText;
      currentMessages.add(
        ChatMessage(
          id: 'error',
          conversationId: activeConversation?.id ?? 'incognito',
          role: 'assistant',
          content: '⚠️ $errorMessage',
          createdAt: DateTime.now(),
        ),
      );
      notifyListeners();
    }

    notifyListeners();
  }

  /// [F4] Mensaje actualmente en modo edición en el composer
  ChatMessage? editingMessage;

  void startEditingMessage(ChatMessage msg) {
    editingMessage = msg;
    notifyListeners();
  }

  void cancelEditingMessage() {
    editingMessage = null;
    notifyListeners();
  }

  Future<void> updateUserMessage(String id, String newContent) async {
    final idx = currentMessages.indexWhere((m) => m.id == id);
    if (idx == -1) return;
    final oldContent = currentMessages[idx].content;
    currentMessages[idx] = ChatMessage(
      id: currentMessages[idx].id,
      conversationId: currentMessages[idx].conversationId,
      role: currentMessages[idx].role,
      content: newContent,
      intentDetected: currentMessages[idx].intentDetected,
      modelCalled: currentMessages[idx].modelCalled,
      sources: currentMessages[idx].sources,
      attachments: currentMessages[idx].attachments,
      createdAt: currentMessages[idx].createdAt,
      isThinking: currentMessages[idx].isThinking,
    );
    notifyListeners();
    await localChatRepo.updateMessageContent(id, newContent);
    if (!isIncognito && !isGuestUser && activeConversation != null) {
      try {
        // C6: acotar el update por VENTANA DE TIEMPO del mensaje editado.
        // Matchear solo por contenido tocaba TODAS las filas idénticas.
        final t = currentMessages[idx].createdAt;
        await SupabaseService.client
            .from('messages')
            .update({'content': newContent})
            .eq('conversation_id', activeConversation!.id)
            .eq('role', 'user')
            .eq('content', oldContent)
            .gte('created_at', t.toUtc().subtract(const Duration(seconds: 10)).toIso8601String())
            .lte('created_at', t.toUtc().add(const Duration(seconds: 10)).toIso8601String());
      } catch (_) {}
    }
  }

  /// [F4] Edita un mensaje enviado por el usuario, limpia la respuesta vieja y regenera una nueva respuesta.
  Future<void> editAndRegenerateUserMessage(
    ChatMessage originalMsg,
    String newContent,
  ) async {
    if (newContent.trim().isEmpty) return;

    // 1. Cancelar cualquier generación activa previa
    _cancelGeneration();

    // 2. Encontrar índice del mensaje del usuario
    final userIdx = currentMessages.indexWhere((m) => m.id == originalMsg.id);
    if (userIdx == -1) return;

    final editedUserMsg = ChatMessage(
      id: originalMsg.id,
      conversationId: originalMsg.conversationId,
      role: originalMsg.role,
      content: newContent.trim(),
      intentDetected: originalMsg.intentDetected,
      modelCalled: originalMsg.modelCalled,
      sources: originalMsg.sources,
      attachments: originalMsg.attachments,
      createdAt: originalMsg.createdAt,
      isThinking: false,
      isDegraded: false,
    );

    // 3. Truncar mensajes posteriores (eliminar respuestas viejas)
    currentMessages = currentMessages.sublist(0, userIdx + 1);
    currentMessages[userIdx] = editedUserMsg;

    // 4. Actualizar en SQLite (Drift)
    await localChatRepo.updateMessageContent(
      editedUserMsg.id,
      editedUserMsg.content,
    );
    if (activeConversation != null) {
      await localChatRepo.db.messagesDao.deleteAfter(
        activeConversation!.id,
        editedUserMsg.createdAt,
      );
    }

    notifyListeners();

    final shouldSaveHistory = !isIncognito && !isGuestUser;

    // 5. Iniciar generación de la nueva respuesta
    final asstMsgId = 'asst-${DateTime.now().microsecondsSinceEpoch}';
    final capturedConvId = activeConversation?.id;

    isThinking = true;
    isGenerating = true;
    isGeneratingImage = false;
    final thinkingMsg = ChatMessage(
      id: 'thinking',
      conversationId: capturedConvId ?? 'guest',
      role: 'assistant',
      content: '',
      createdAt: DateTime.now(),
      isThinking: true,
    );
    currentMessages.add(thinkingMsg);
    notifyListeners();

    final session = GenerationSession(
      id: ChatService.generateSessionId(),
      conversationId: capturedConvId,
    );
    _activeSession = session;

    try {
      bool msgIsDegraded = false;
      await ChatService.sendMessageStream(
        message: newContent.trim(),
        conversationId:
            (shouldSaveHistory && activeConversation != null)
                ? capturedConvId
                : null,
        history:
            (isIncognito || isGuestUser)
                ? currentMessages
                    .where((m) => !m.isThinking && m.id != asstMsgId)
                    .map((m) => {'role': m.role, 'content': m.content})
                    .toList()
                : null,
        modelOverride: selectedModel.modelId,
        attachments: editedUserMsg.attachments,
        session: session,
        onMeta: (meta) {
          if (session.isCancelled || _activeSession?.id != session.id) return;
          if (meta['isDegraded'] == true) {
            msgIsDegraded = true;
          }
        },
        onChunk: (chunk) {
          if (session.isCancelled || _activeSession?.id != session.id) return;
          _handleStreamChunk(asstMsgId, chunk, isDegraded: msgIsDegraded);
        },
        onComplete: (fullText, sources) async {
          if (session.isCancelled || _activeSession?.id != session.id) return;
          _endStreamingMessage();
          isGenerating = false;
          if (!isGuestUser) {
            tokensUsed += (fullText.length ~/ 3) + 35;
          }

          final finalMsg = ChatMessage(
            id: asstMsgId,
            conversationId: capturedConvId ?? 'guest',
            role: 'assistant',
            content: fullText,
            sources: sources,
            createdAt: DateTime.now(),
            isDegraded: msgIsDegraded,
          );

          if (shouldSaveHistory && activeConversation != null) {
            await localChatRepo.saveMessage(finalMsg);
            if (!isGuestUser && !isIncognito) {
              SupabaseService.client
                  .from('messages')
                  .insert({
                    'conversation_id': activeConversation!.id,
                    'role': 'assistant',
                    'content': fullText,
                  })
                  .then((_) {})
                  .catchError((_) {});
            }
          }
          notifyListeners();
        },
        onError: (err) {
          if (session.isCancelled || _activeSession?.id != session.id) return;
          _endStreamingMessage();
          isGenerating = false;
          final idx = currentMessages.indexWhere((m) => m.id == asstMsgId);
          if (idx != -1) {
            currentMessages[idx] = ChatMessage(
              id: asstMsgId,
              conversationId: capturedConvId ?? 'guest',
              role: 'assistant',
              content: '⚠️ $err',
              createdAt: DateTime.now(),
            );
          }
          notifyListeners();
        },
      );
    } catch (_) {
      isGenerating = false;
      _endStreamingMessage();
      notifyListeners();
    }
  }

  /// Cancela el stream de generación en curso y limpia el estado de UI
  /// Cancela el stream de generación en curso y limpia el estado de UI
  /// (isThinking, isGenerating, mensajes "thinking").
  /// **NO** añade ningún mensaje al chat. Use esto siempre que quiera
  /// parar la generación sin dejar texto residual.
  void _cancelGeneration() {
    _endStreamingMessage(); // materializa deltas pendientes y limpia timers
    _activeSession?.cancel();
    _activeSession = null;
    _stopForegroundService();
    currentMessages.removeWhere((m) => m.isThinking);
    if (activeConversation != null && currentMessages.isNotEmpty) {
      for (final m in currentMessages) {
        localChatRepo.saveMessage(m);
      }
    }
    isThinking = false;
    isGenerating = false;
    isGeneratingImage = false;
    notifyListeners();
  }

  /// Para la generación y añade un mensaje "stopped" / razón al chat.
  /// Solo debe llamarse cuando el usuario **explícitamente** detuvo la
  /// generación (botón Stop) y quiere ver un mensaje de confirmación.
  /// [Punto 36 aviso] Antes, este método también era llamado internamente
  /// desde onChunk al exceder tokens, lo que causaba que el mensaje
  /// "You stopped..." apareciera en TODAS las cuentas al iniciar sesión.
  /// Ahora esos callers usan `_cancelGeneration()` directamente.
  void stopGeneration({String? reasonText}) {
    _cancelGeneration();

    final stopText = reasonText ?? AppI18n.instance.t('chat.stopped');

    if (currentMessages.isEmpty ||
        currentMessages.last.role != 'assistant' ||
        currentMessages.last.content.trim().isEmpty) {
      if (currentMessages.isNotEmpty &&
          currentMessages.last.role == 'assistant') {
        currentMessages[currentMessages.length - 1] = ChatMessage(
          id: currentMessages.last.id,
          conversationId: currentMessages.last.conversationId,
          role: 'assistant',
          content: stopText,
          createdAt: currentMessages.last.createdAt,
        );
      } else {
        currentMessages.add(
          ChatMessage(
            id: 'stop-${DateTime.now().microsecondsSinceEpoch}',
            conversationId: activeConversation?.id ?? 'guest',
            role: 'assistant',
            content: stopText,
            createdAt: DateTime.now(),
          ),
        );
      }
    } else {
      final lastMsg = currentMessages.last;
      currentMessages[currentMessages.length - 1] = ChatMessage(
        id: lastMsg.id,
        conversationId: lastMsg.conversationId,
        role: 'assistant',
        content: '${lastMsg.content}\n\n*[$stopText]*',
        sources: lastMsg.sources,
        createdAt: lastMsg.createdAt,
      );
    }

    notifyListeners();
  }

  /// Desencola y envía todos los mensajes pendientes de la cola offline (outbox).
  /// Se invoca automáticamente cuando ConnectivityService detecta restauración de red
  /// y al arrancar la app si ya hay conexión. Cada mensaje se despacha secuencialmente
  /// a través de ChatService.sendMessageStream; al completar se marca como 'sent' en Drift.
  Future<void> _flushOutboxQueue() async {
    if (isGenerating) return; // No flush mientras hay un stream activo
    
    final queued = await localChatRepo.getQueuedMessages();
    if (queued.isEmpty) return;

    // Limpiar cualquier placeholder visual de "mensaje en cola" antes de enviar
    currentMessages.removeWhere((m) => m.id.startsWith('offline-'));
    notifyListeners();

    for (final msg in queued) {
      if (!_isOnline) break; // Si se pierde la red a mitad de cola, detener
      try {
        await localChatRepo.updateMessageStatus(msg.id, LocalMessageStatus.sending);
        // C2: reenviar al chat ORIGEN del mensaje, no al que esté abierto.
        // Sin esto, un encolado del chat A aterrizaba en el chat B activo.
        final targetId = msg.conversationId;
        if (targetId.isNotEmpty && activeConversation?.id != targetId) {
          final tIdx = conversations.indexWhere((c) => c.id == targetId);
          if (tIdx == -1) {
            // La conversación origen ya no existe: no hay dónde entregarlo.
            await localChatRepo.updateMessageStatus(msg.id, LocalMessageStatus.failed);
            continue;
          }
          await selectConversation(conversations[tIdx]);
        }
        // Si el mensaje ya estaba en currentMessages como placeholder, remover para evitar duplicado
        currentMessages.removeWhere((m) => m.id == msg.id);

        await sendUserMessage(
          msg.content,
          attachments: msg.attachments.isNotEmpty ? msg.attachments : null,
        );
        // P0-4: Borrar la fila encolada original tras el reenvio exitoso para evitar duplicacion permanente en Drift
        await localChatRepo.deleteMessageById(msg.id);
      } catch (e) {
        debugPrint('[Outbox] Error enviando mensaje en cola: $e');
        await localChatRepo.updateMessageStatus(msg.id, LocalMessageStatus.failed);
      }
    }
  }
}
