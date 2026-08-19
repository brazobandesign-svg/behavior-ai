import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../app/bootstrap.dart';
import '../data/repositories/local_chat_repository.dart';
import 'supabase_service.dart';
import 'chat_service.dart';
import 'connectivity_service.dart';
import '../l10n/app_i18n.dart';

class AppState extends ChangeNotifier {
  final LocalChatRepository localChatRepo = LocalChatRepository();

  UserProfile? profile;
  List<Conversation> conversations = [];
  Conversation? activeConversation;
  List<ChatMessage> currentMessages = [];

  bool isIncognito = false;
  bool showTab2Banner = true;
  bool isDarkMode = true;
  bool guestIsBlocked = false; // Sin bloqueo para guests: acceso ilimitado a Groq $0
  ExodoModelOption selectedModel = exodoModels[0]; // Origo (G1.1)
  double? currentTempC;

  int tokensUsed = 0;
  int get tokensLimit => isPro ? 50000 : 6000;
  DateTime? tokensResetTime;
  bool get isPro => profile?.plan == 'hazak';
  bool isThinking = false;
  bool isGenerating = false;
  String? errorMessage;
  int guestMessagesSessionCount = 0;

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

  bool _initializedSupabase = false;

  AppState({
    String? savedModelId,
    String? savedProfileJson,
    Bootstrap? bootstrap,
  }) {
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
    _connectivitySub = connectivity.onConnectivityChanged.listen((online) {
      _isOnline = online;
      notifyListeners();
    });

    _authSub = SupabaseService.client.auth.onAuthStateChange.listen((data) async {
      final event = data.event;
      if (event == AuthChangeEvent.signedIn ||
          event == AuthChangeEvent.initialSession) {
        ChatService.cancelStream();
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
        ChatService.cancelStream();
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
        });
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
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
      conversations = fetchedConvs;
      localChatRepo.saveConversations(fetchedConvs);
      Bootstrap.saveSnapshot(conversations: conversations);

      final currentUserEmail = SupabaseService.currentUser?.email;
      if (currentUserEmail != null &&
          currentUserEmail.toLowerCase() == 'brazobandesign@gmail.com') {
        if (profile != null && profile!.plan != 'hazak') {
          SupabaseService.client
              .from('profiles')
              .update({'plan': 'hazak'})
              .eq('id', profile!.id)
              .then((_) {})
              .catchError((_) {});
          profile = UserProfile(
            id: profile!.id,
            fullName: profile!.fullName,
            plan: 'hazak',
            avatarUrl: profile!.avatarUrl,
            onboarding: profile!.onboarding,
          );
        }
      }

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
    if (activeConversation?.id == loadingConvId && !isGenerating) {
      currentMessages = fetchedMessages;
      localChatRepo.saveMessages(conv.id, fetchedMessages);
      Bootstrap.saveSnapshot(
        lastConversationId: activeConversation?.id,
        lastMessages: currentMessages,
      );
      notifyListeners();
    }
  }

  void startNewChat({bool resetIncognito = true}) {
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

  Future<void> deleteAccount() async {
    final userId = SupabaseService.client.auth.currentUser?.id;
    if (userId != null) {
      try {
        await SupabaseService.client.from('profiles').delete().eq('id', userId);
      } catch (_) {}
    }
    profile = null;
    _hasCachedSession = false;
    localChatRepo.clearAll().catchError((_) {});
    await SupabaseService.signOut();
    notifyListeners();
  }

  void upgradeToProPlan() {
    // Desactivado hasta conectar pasarela de pago real (Stripe / Google Play).
    // Evita que usuarios en cuenta Free obtengan Pro y pasen al modelo XPi sin pagar.
  }

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
      history: (isIncognito || isGuestUser)
          ? currentMessages
                .where((m) => !m.isThinking)
                .map((m) => {'role': m.role, 'content': m.content})
                .toList()
          : null,
      modelOverride: selectedModel.modelId,
      onChunk: (chunk) {
        final idx = currentMessages.indexWhere((m) => m.id == thinkingId);
        if (idx == -1) return;
        currentMessages[idx] = ChatMessage(
          id: thinkingId,
          conversationId: activeConversation?.id ?? '',
          role: 'assistant',
          content: currentMessages[idx].content + chunk,
          createdAt: currentMessages[idx].createdAt,
        );
        if (!isGuestUser) {
          final currentEst =
              tokensUsed + (currentMessages[idx].content.length ~/ 3) + 35;
          if (currentEst >= tokensLimit) {
            tokensUsed = tokensLimit;
            // [Punto 36 aviso] Usamos _cancelGeneration() (sin mensaje stopped)
            // porque esto lo dispara el límite de tokens, no el usuario.
            _cancelGeneration();
            return;
          }
        }
        notifyListeners();
      },
      onComplete: (fullText, sources) {
        isGenerating = false;
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
        notifyListeners();
      },
      onError: (e) {
        _revertTokens(userTokensEst);
        isGenerating = false;
        errorMessage = e.toString();
        notifyListeners();
      },
    );
  }

  Future<void> sendUserMessage(
    String text, {
    List<Attachment>? attachments,
  }) async {
    if (text.trim().isEmpty && (attachments == null || attachments.isEmpty)) return;
    final isGuest = isGuestUser;
    errorMessage = null;

    final shouldSaveHistory = !isIncognito && !isGuest;

    // 1. AÑADIR MENSAJE DE USUARIO Y THINKING BUBBLE A LA UI INMEDIATAMENTE (Optimistic UI 0 ms lag)
    currentMessages.removeWhere((m) => m.id == 'error');
    final userTokensEst = (text.length ~/ 3) + 15;
    tokensUsed += userTokensEst;
    tokensResetTime ??= DateTime.now().add(const Duration(hours: 24));
    final userMsg = ChatMessage(
      id: 'user-${DateTime.now().microsecondsSinceEpoch}',
      conversationId: activeConversation?.id ?? 'guest',
      role: 'user',
      content: text,
      attachments: attachments ?? const [],
      createdAt: DateTime.now(),
    );
    currentMessages.add(userMsg);

    isThinking = true;
    isGenerating = true;
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
    if (activeConversation == null && shouldSaveHistory) {
      final effectiveTitle = text.trim().isNotEmpty
          ? (text.length > 30 ? '${text.substring(0, 30)}...' : text)
          : (attachments != null && attachments.isNotEmpty && attachments.first.fileName.isNotEmpty
              ? attachments.first.fileName
              : 'Imagen adjunta');
      try {
        activeConversation = await SupabaseService.createConversation(
          effectiveTitle,
          selectedModel.plan,
          false,
        );
        conversations.insert(0, activeConversation!);
        localChatRepo.saveConversation(activeConversation!);
        for (int i = 0; i < currentMessages.length; i++) {
          if (currentMessages[i].conversationId == 'guest' ||
              currentMessages[i].conversationId == 'incognito' ||
              currentMessages[i].conversationId.isEmpty) {
            currentMessages[i] = ChatMessage(
              id: currentMessages[i].id,
              conversationId: activeConversation!.id,
              role: currentMessages[i].role,
              content: currentMessages[i].content,
              attachments: currentMessages[i].attachments,
              sources: currentMessages[i].sources,
              createdAt: currentMessages[i].createdAt,
              isThinking: currentMessages[i].isThinking,
            );
          }
        }
        notifyListeners();
      } catch (_) {}
    }

    // 3. GUARDAR MENSAJE DE USUARIO EN BD LOCAL Y NUBE EN SEGUNDO PLANO
    if (shouldSaveHistory && activeConversation != null) {
      localChatRepo.saveMessage(userMsg);
      String contentToSave = text.trim();
      if (attachments != null && attachments.isNotEmpty) {
        try {
          final attLight = attachments
              .map((a) => {
                    'filePath': a.filePath,
                    'fileName': a.fileName,
                    'mimeType': a.mimeType,
                  })
              .toList();
          final attJson = jsonEncode(attLight);
          final labels = attachments
              .map((a) =>
                  a.mimeType.startsWith('image/')
                      ? '[Imagen: ${a.fileName}]'
                      : '[Archivo: ${a.fileName}]')
              .join('\n');
          contentToSave = contentToSave.isEmpty
              ? '$labels\n<!-- ATTACHMENTS: $attJson -->'
              : '$contentToSave\n\n$labels\n<!-- ATTACHMENTS: $attJson -->';
        } catch (_) {}
      }
      SupabaseService.client.from('messages').insert({
        'conversation_id': activeConversation!.id,
        'role': 'user',
        'content': contentToSave,
      }).then((_) {}).catchError((_) {});
    }

    try {
      final msgId = 'asst-${DateTime.now().microsecondsSinceEpoch}';
      bool firstChunk = true;
      bool msgIsDegraded = false;

      await ChatService.sendMessageStream(
        message: text,
        conversationId: shouldSaveHistory ? activeConversation?.id : null,
        history: (isIncognito || isGuestUser)
            ? currentMessages
                  .where((m) => !m.isThinking)
                  .map((m) => {'role': m.role, 'content': m.content})
                  .toList()
            : null,
        modelOverride: selectedModel.modelId,
        attachments:
            attachments, // [Punto 40] adjuntos con bytes para multimodal
        onMeta: (meta) {
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
        onChunk: (chunk) {
          if (firstChunk) {
            firstChunk = false;
            currentMessages.removeWhere((m) => m.isThinking);
            isThinking = false;
            currentMessages.add(
              ChatMessage(
                id: msgId,
                conversationId: activeConversation?.id ?? 'incognito',
                role: 'assistant',
                content: chunk,
                createdAt: DateTime.now(),
                isDegraded: msgIsDegraded,
              ),
            );
          } else {
            final idx = currentMessages.indexWhere((m) => m.id == msgId);
            if (idx != -1) {
              currentMessages[idx] = ChatMessage(
                id: msgId,
                conversationId: currentMessages[idx].conversationId,
                role: 'assistant',
                content: currentMessages[idx].content + chunk,
                sources: currentMessages[idx].sources,
                createdAt: currentMessages[idx].createdAt,
                isDegraded: msgIsDegraded,
              );
            }
          }
          notifyListeners();
        },
        onComplete: (fullText, sources) async {
          isGenerating = false;
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
          } else if (firstChunk) {
            currentMessages.removeWhere((m) => m.isThinking);
            isThinking = false;
            currentMessages.add(
              ChatMessage(
                id: msgId,
                conversationId: activeConversation?.id ?? 'incognito',
                role: 'assistant',
                content: fullText,
                sources: sources,
                createdAt: DateTime.now(),
                isDegraded: msgIsDegraded,
              ),
            );
          }
          if (shouldSaveHistory && activeConversation != null && !isGuest) {
            final assistantMsg = ChatMessage(
              id: msgId,
              conversationId: activeConversation!.id,
              role: 'assistant',
              content: fullText,
              sources: sources,
              createdAt: DateTime.now(),
              isDegraded: msgIsDegraded,
            );
            localChatRepo.saveMessage(assistantMsg);

            final sourcesJson = sources.isNotEmpty
                ? jsonEncode(sources.map((s) => s.toJson()).toList())
                : null;
            final contentToSave = sourcesJson != null
                ? '$fullText\n<!-- SOURCES: $sourcesJson -->'
                : fullText;
            try {
              await SupabaseService.client.from('messages').insert({
                'conversation_id': activeConversation!.id,
                'role': 'assistant',
                'content': contentToSave,
                if (sources.isNotEmpty)
                  'sources': sources.map((s) => s.toJson()).toList(),
              });
            } catch (_) {
              try {
                await SupabaseService.client.from('messages').insert({
                  'conversation_id': activeConversation!.id,
                  'role': 'assistant',
                  'content': contentToSave,
                });
              } catch (_) {}
            }
          }
          HapticFeedback.vibrate();
          notifyListeners();
        },
        onError: (err) {
          _revertTokens(userTokensEst);
          currentMessages.removeWhere((m) => m.isThinking);
          isThinking = false;
          isGenerating = false;
          errorMessage = err.replaceAll('Exception: ', '');
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
        },
      );
    } catch (e) {
      _revertTokens(userTokensEst);
      currentMessages.removeWhere((m) => m.isThinking);
      isThinking = false;
      isGenerating = false;
      errorMessage = e.toString().replaceAll('Exception: ', '');
      currentMessages.add(
        ChatMessage(
          id: 'error',
          conversationId: activeConversation?.id ?? 'incognito',
          role: 'assistant',
          content: '⚠️ $errorMessage',
          createdAt: DateTime.now(),
        ),
      );
    }

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
      createdAt: currentMessages[idx].createdAt,
      isThinking: currentMessages[idx].isThinking,
    );
    notifyListeners();
    if (!isIncognito && !isGuestUser && activeConversation != null) {
      try {
        await SupabaseService.client
            .from('messages')
            .update({'content': newContent})
            .eq('conversation_id', activeConversation!.id)
            .eq('role', 'user')
            .eq('content', oldContent);
      } catch (_) {}
    }
  }

  /// Cancela el stream de generación en curso y limpia el estado de UI
  /// (isThinking, isGenerating, mensajes "thinking").
  /// **NO** añade ningún mensaje al chat. Use esto siempre que quiera
  /// parar la generación sin dejar texto residual.
  void _cancelGeneration() {
    ChatService.cancelStream();
    currentMessages.removeWhere((m) => m.isThinking);
    isThinking = false;
    isGenerating = false;
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

}
