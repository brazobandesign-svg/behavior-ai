import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import 'supabase_service.dart';
import 'chat_service.dart';
import '../l10n/app_i18n.dart';

class AppState extends ChangeNotifier {
  UserProfile? profile;
  List<Conversation> conversations = [];
  Conversation? activeConversation;
  List<ChatMessage> currentMessages = [];
  
  bool isIncognito = false;
  bool showTab2Banner = true;
  bool isDarkMode = true;
  bool guestIsBlocked = false;
  ExodoModelOption selectedModel = exodoModels[0]; // Origo (G1.1)
  double? currentTempC;
  
  int tokensUsed = 0;
  int tokensLimit = 15000;
  DateTime? tokensResetTime;
  bool get isPro => profile?.plan == 'hazak' || tokensLimit > 15000;
  bool isThinking = false;
  String? errorMessage;
  int guestMessagesSessionCount = 0;

  bool get isGuestUser {
    final u = SupabaseService.currentUser;
    if (u == null) return false;
    return u.isAnonymous == true || (u.email == null || u.email!.trim().isEmpty);
  }

  AppState() {
    _init();
    _fetchWeather();
  }

  Future<void> _fetchWeather() async {
    try {
      final res = await http.get(Uri.parse('https://api.open-meteo.com/v1/forecast?latitude=18.4861&longitude=-69.9312&current=temperature_2m'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        currentTempC = data['current']['temperature_2m'] as double?;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _init() async {
    SupabaseService.client.auth.onAuthStateChange.listen((data) async {
      final event = data.event;
      if (event == AuthChangeEvent.signedIn || event == AuthChangeEvent.initialSession) {
        stopGeneration();
        await loadUserData();
      } else if (event == AuthChangeEvent.signedOut) {
        stopGeneration();
        profile = null;
        conversations = [];
        activeConversation = null;
        currentMessages = [];
        tokensUsed = 0;
        selectedModel = exodoModels[0];
        notifyListeners();
      }
    });
  }

  Future<void> loadUserData() async {
    profile = await SupabaseService.getProfile();
    final currentUserEmail = SupabaseService.currentUser?.email;
    if (currentUserEmail != null && currentUserEmail.toLowerCase() == 'brazobandesign@gmail.com') {
      if (profile != null && profile!.plan != 'hazak') {
        SupabaseService.client.from('profiles').update({'plan': 'hazak'}).eq('id', profile!.id);
        profile = UserProfile(
          id: profile!.id,
          fullName: profile!.fullName,
          plan: 'hazak',
          avatarUrl: profile!.avatarUrl,
          onboarding: profile!.onboarding,
        );
      }
    }
    if (isGuestUser || isIncognito) {
      conversations = [];
    } else {
      conversations = await SupabaseService.getConversations();
    }
    
    final usage = await SupabaseService.getTodayUsage();
    if (usage != null) {
      tokensUsed = usage['tokens_used'] as int? ?? 0;
      tokensLimit = usage['tokens_limit'] as int? ?? 15000;
      if (tokensUsed > 0) {
        if (usage['created_at'] != null) {
          tokensResetTime = DateTime.tryParse(usage['created_at'].toString())?.toLocal().add(const Duration(hours: 24));
        } else {
          tokensResetTime = DateTime.now().add(const Duration(hours: 24));
        }
      } else {
        tokensResetTime = null;
      }
    } else {
      tokensUsed = 0;
      tokensLimit = profile?.plan == 'hazak' ? 150000 : 15000;
      tokensResetTime = null;
    }

    startNewChat();
    if (isGuestUser) {
      final ipBlocked = await SupabaseService.isGuestIpBlocked();
      final hwBlocked = await _checkHardwareBlocked();
      guestIsBlocked = ipBlocked || hwBlocked || guestMessagesSessionCount >= 3;
    } else {
      guestIsBlocked = false;
    }
    notifyListeners();
  }

  Future<void> selectConversation(Conversation conv) async {
    activeConversation = conv;
    isIncognito = conv.isIncognito;
    currentMessages = await SupabaseService.getMessages(conv.id);
    notifyListeners();
  }

  void startNewChat() {
    activeConversation = null;
    currentMessages = [];
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
      SupabaseService.updateConversationTitle(convId, newTitle);
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
      SupabaseService.toggleConversationStarred(convId, newStarred);
      notifyListeners();
    }
  }

  Future<void> deleteConversation(String convId) async {
    final wasActive = activeConversation?.id == convId;
    conversations.removeWhere((c) => c.id == convId);
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
    startNewChat();
    notifyListeners();
  }

  void toggleTheme() {
    isDarkMode = !isDarkMode;
    notifyListeners();
  }

  void dismissTab2Banner() {
    showTab2Banner = false;
    notifyListeners();
  }

  void selectModelOption(ExodoModelOption option) {
    if (option.plan == 'hazak' && !isPro) {
      return;
    }
    selectedModel = option;
    notifyListeners();
  }

  String get userEmail => SupabaseService.client.auth.currentUser?.email ?? '';

  void updateProfileName(String newName) {
    if (profile != null) {
      profile = UserProfile(
        id: profile!.id,
        fullName: newName,
        plan: profile!.plan,
        avatarUrl: profile!.avatarUrl,
        onboarding: profile!.onboarding,
      );
      SupabaseService.client.from('profiles').update({'full_name': newName}).eq('id', profile!.id);
      notifyListeners();
    }
  }

  void upgradeToProPlan() {
    if (profile != null) {
      profile = UserProfile(
        id: profile!.id,
        fullName: profile!.fullName,
        plan: 'hazak',
        avatarUrl: profile!.avatarUrl,
        onboarding: profile!.onboarding,
      );
      tokensLimit = 150000;
      SupabaseService.client.from('profiles').update({'plan': 'hazak'}).eq('id', profile!.id);
      notifyListeners();
    }
  }

  void cancelProPlan() {
    if (profile != null) {
      profile = UserProfile(
        id: profile!.id,
        fullName: profile!.fullName,
        plan: 'genesis',
        avatarUrl: profile!.avatarUrl,
        onboarding: profile!.onboarding,
      );
      tokensLimit = 15000;
      SupabaseService.client.from('profiles').update({'plan': 'genesis'}).eq('id', profile!.id);
      notifyListeners();
    }
  }

  Future<void> reformulateLastAssistantMessage(ChatMessage lastAssistant) async {
    if (currentMessages.isEmpty) return;
    // Quitamos la última respuesta del asistente; el backend deberá regenerarla
    // cuando llegue el siguiente sendUserMessage o automáticamente.
    final idx = currentMessages.lastIndexWhere((m) => m.role == 'assistant' && m.id == lastAssistant.id);
    if (idx == -1) return;
    currentMessages.removeAt(idx);
    notifyListeners();

    // Re-insertamos un placeholder "thinking" para que la UI muestre que se reformula.
    final thinkingId = 'reformulate-${DateTime.now().microsecondsSinceEpoch}';
    currentMessages.add(ChatMessage(
      id: thinkingId,
      conversationId: activeConversation?.id ?? '',
      role: 'assistant',
      content: '',
      createdAt: DateTime.now(),
      isThinking: true,
    ));
    notifyListeners();

    // Disparamos la reformulación en background.
    try {
      await _reformulateInBackground(thinkingId);
    } catch (e) {
      currentMessages.removeWhere((m) => m.id == thinkingId);
      errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> _reformulateInBackground(String thinkingId) async {
    // Encuentra el último mensaje del usuario para reformular su respuesta.
    final lastUserIdx = currentMessages.lastIndexWhere((m) => m.role == 'user');
    if (lastUserIdx == -1) {
      currentMessages.removeWhere((m) => m.id == thinkingId);
      notifyListeners();
      return;
    }
    final lastUserText = currentMessages[lastUserIdx].content;
    // Marcamos el mensaje como re-formulación para que el backend lo sepa.
    final userMsg = ChatMessage(
      id: 'reform-${DateTime.now().microsecondsSinceEpoch}',
      conversationId: activeConversation?.id ?? '',
      role: 'user',
      content: lastUserText,
      createdAt: DateTime.now(),
    );
    currentMessages.add(userMsg);
    notifyListeners();
    await ChatService.sendMessageStream(
      conversationId: activeConversation?.id ?? '',
      message: lastUserText,
      history: isIncognito ? currentMessages.where((m) => !m.isThinking).map((m) => {'role': m.role, 'content': m.content}).toList() : null,
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
        notifyListeners();
      },
      onComplete: (fullText, sources) {
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
        errorMessage = e.toString();
        notifyListeners();
      },
    );
  }

  Future<void> sendUserMessage(String text) async {
    if (text.trim().isEmpty) return;
    final isGuest = isGuestUser;
    if (isGuest && (guestIsBlocked || guestMessagesSessionCount >= 3 || await _checkHardwareBlocked())) {
      guestIsBlocked = true;
      notifyListeners();
      return;
    }

    errorMessage = null;

    final shouldSaveHistory = !isIncognito && !isGuest;

    // 1. Crear conversación en DB si no existe y debemos guardar historial
    if (activeConversation == null && shouldSaveHistory) {
      final title = text.length > 30 ? '${text.substring(0, 30)}...' : text;
      activeConversation = await SupabaseService.createConversation(
        title,
        selectedModel.plan,
        false,
      );
      conversations.insert(0, activeConversation!);
    }

    // 2. Añadir mensaje de usuario a UI
    final userMsg = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      conversationId: activeConversation?.id ?? 'guest',
      role: 'user',
      content: text,
      createdAt: DateTime.now(),
    );
    currentMessages.add(userMsg);
    if (shouldSaveHistory && activeConversation != null) {
      try {
        await SupabaseService.client.from('messages').insert({
          'conversation_id': activeConversation!.id,
          'role': 'user',
          'content': text,
        });
      } catch (_) {}
    }

    // 3. Añadir burbuja temporal de pensamiento con animación personalizada
    isThinking = true;
    final thinkingMsg = ChatMessage(
      id: 'thinking',
      conversationId: activeConversation?.id ?? 'guest',
      role: 'assistant',
      content: '',
      createdAt: DateTime.now(),
      isThinking: true,
    );
    currentMessages.add(thinkingMsg);
    notifyListeners();

    try {
      final msgId = DateTime.now().millisecondsSinceEpoch.toString();
      bool firstChunk = true;

      await ChatService.sendMessageStream(
        message: text,
        conversationId: shouldSaveHistory ? activeConversation?.id : null,
        history: isIncognito ? currentMessages.where((m) => !m.isThinking).map((m) => {'role': m.role, 'content': m.content}).toList() : null,
        modelOverride: selectedModel.modelId,
        onChunk: (chunk) {
          if (firstChunk) {
            firstChunk = false;
            currentMessages.removeWhere((m) => m.isThinking);
            isThinking = false;
            currentMessages.add(ChatMessage(
              id: msgId,
              conversationId: activeConversation?.id ?? 'incognito',
              role: 'assistant',
              content: chunk,
              createdAt: DateTime.now(),
            ));
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
              );
            }
          }
          notifyListeners();
        },
        onComplete: (fullText, sources) async {
          final idx = currentMessages.indexWhere((m) => m.id == msgId);
          if (idx != -1) {
            currentMessages[idx] = ChatMessage(
              id: msgId,
              conversationId: currentMessages[idx].conversationId,
              role: 'assistant',
              content: fullText,
              sources: sources,
              createdAt: currentMessages[idx].createdAt,
            );
          } else if (firstChunk) {
            currentMessages.removeWhere((m) => m.isThinking);
            isThinking = false;
            currentMessages.add(ChatMessage(
              id: msgId,
              conversationId: activeConversation?.id ?? 'incognito',
              role: 'assistant',
              content: fullText,
              sources: sources,
              createdAt: DateTime.now(),
            ));
          }
          if (shouldSaveHistory && activeConversation != null) {
            try {
              await SupabaseService.client.from('messages').insert({
                'conversation_id': activeConversation!.id,
                'role': 'assistant',
                'content': fullText,
              });
            } catch (_) {}
          }
          HapticFeedback.vibrate();
          notifyListeners();
        },
        onError: (err) {
          currentMessages.removeWhere((m) => m.isThinking);
          isThinking = false;
          errorMessage = err.replaceAll('Exception: ', '');
          final isEn = AppI18n.instance.localeCode == 'en';
          currentMessages.add(ChatMessage(
            id: 'error',
            conversationId: activeConversation?.id ?? 'incognito',
            role: 'assistant',
            content: isEn ? '⚠️ **Network or plan error**: $errorMessage' : '⚠️ **Error de red o plan**: $errorMessage',
            createdAt: DateTime.now(),
          ));
          notifyListeners();
        },
      );

    } catch (e) {
      currentMessages.removeWhere((m) => m.isThinking);
      isThinking = false;
      errorMessage = e.toString().replaceAll('Exception: ', '');
      final isEn = AppI18n.instance.localeCode == 'en';
      
      currentMessages.add(ChatMessage(
        id: 'error',
        conversationId: activeConversation?.id ?? 'incognito',
        role: 'assistant',
        content: isEn ? '⚠️ **Network or plan error**: $errorMessage' : '⚠️ **Error de red o plan**: $errorMessage',
        createdAt: DateTime.now(),
      ));
    }

    if (isGuest) {
      guestMessagesSessionCount++;
      await _recordHardwareMessage();
      final ipBlocked = await SupabaseService.recordGuestIpMessage();
      if (guestMessagesSessionCount >= 3 || ipBlocked) {
        guestIsBlocked = true;
      }
    }

    notifyListeners();
  }

  void updateUserMessage(String id, String newContent) {
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
        SupabaseService.client.from('messages').update({'content': newContent})
            .eq('conversation_id', activeConversation!.id)
            .eq('role', 'user')
            .eq('content', oldContent);
      } catch (_) {}
    }
  }

  void stopGeneration() {
    ChatService.cancelStream();
    currentMessages.removeWhere((m) => m.isThinking);
    isThinking = false;
    notifyListeners();
  }

  // --- CANDADO PERSISTENTE DE HARDWARE VIA SHARED PREFERENCES ---
  Future<bool> _checkHardwareBlocked() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final date = prefs.getString('exodo_guest_hw_date');
      final count = prefs.getInt('exodo_guest_hw_count') ?? 0;
      final today = DateTime.now().toIso8601String().substring(0, 10);
      if (date != today) return false;
      guestMessagesSessionCount = count;
      return count >= 3;
    } catch (_) {
      return false;
    }
  }

  Future<void> _recordHardwareMessage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().toIso8601String().substring(0, 10);
      int count = guestMessagesSessionCount;
      if (prefs.getString('exodo_guest_hw_date') == today) {
        final existing = prefs.getInt('exodo_guest_hw_count') ?? 0;
        if (existing > count) count = existing;
      }
      guestMessagesSessionCount = count;
      await prefs.setString('exodo_guest_hw_date', today);
      await prefs.setInt('exodo_guest_hw_count', count);
    } catch (_) {}
  }
}
