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
  int get tokensLimit => 15000; // Temporal para pruebas (antes isPro ? 300 : 100)
  DateTime? tokensResetTime;
  bool get isPro => profile?.plan == 'hazak';
  bool isThinking = false;
  bool isGenerating = false;
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
    
    if (profile?.plan == 'hazak') {
      selectedModel = exodoModels[1];
    } else {
      selectedModel = exodoModels[0];
    }

    final usage = await SupabaseService.getTodayUsage();
    if (usage != null) {
      tokensUsed = usage['tokens_used'] as int? ?? 0;
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
      tokensResetTime = null;
    }

    startNewChat();
    if (isGuestUser) {
      guestIsBlocked = await _checkHardwareBlocked();
    } else {
      guestIsBlocked = false;
    }
    notifyListeners();
  }

  Future<void> selectConversation(Conversation conv) async {
    if (isIncognito) {
      currentMessages.clear();
    }
    activeConversation = conv;
    isIncognito = false;
    currentMessages = await SupabaseService.getMessages(conv.id);
    notifyListeners();
  }

  void startNewChat({bool resetIncognito = true}) {
    if (resetIncognito) {
      isIncognito = false;
    }
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
    startNewChat(resetIncognito: false);
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

  String? get userAvatarUrl {
    if (profile?.avatarUrl != null && profile!.avatarUrl!.isNotEmpty) {
      return profile!.avatarUrl;
    }
    final user = SupabaseService.currentUser;
    if (user != null && user.userMetadata != null) {
      final meta = user.userMetadata!;
      final url = meta['avatar_url']?.toString() ?? meta['picture']?.toString() ?? meta['photo_url']?.toString();
      if (url != null && url.isNotEmpty) {
        return url;
      }
    }
    return null;
  }

  Future<bool> updateProfileDetails(String newFullName, String newNickname) async {
    if (profile != null) {
      final updatedOnboarding = Map<String, dynamic>.from(profile!.onboarding ?? {});
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
        await SupabaseService.client.from('profiles').update({
          'full_name': newFullName,
          'onboarding': updatedOnboarding,
        }).eq('id', profile!.id);
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
    await SupabaseService.signOut();
    notifyListeners();
  }

  void upgradeToProPlan() {
    // Desactivado hasta conectar pasarela de pago real (Stripe / Google Play).
    // Evita que usuarios en cuenta Free obtengan Pro y pasen al modelo XPi sin pagar.
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
      selectedModel = exodoModels[0];
      SupabaseService.client.from('profiles').update({'plan': 'genesis'}).eq('id', profile!.id);
      notifyListeners();
    }
  }

  Future<void> reformulateLastAssistantMessage(ChatMessage lastAssistant) async {
    if (currentMessages.isEmpty) return;

    final isGuest = isGuestUser;
    if (isGuest) {
      if (guestIsBlocked || guestMessagesSessionCount >= 3) {
        guestIsBlocked = true;
        notifyListeners();
        return;
      }
    } else {
      if (tokensUsed >= tokensLimit) {
        final limitMsg = isPro
            ? AppI18n.instance.t('limit.pro_msg')
            : AppI18n.instance.t('limit.free_msg');
        currentMessages.add(ChatMessage(
          id: 'limit-${DateTime.now().microsecondsSinceEpoch}',
          conversationId: activeConversation?.id ?? 'free',
          role: 'assistant',
          content: limitMsg,
          createdAt: DateTime.now(),
        ));
        notifyListeners();
        return;
      }
    }

    final idx = currentMessages.lastIndexWhere((m) => m.role == 'assistant' && m.id == lastAssistant.id);
    if (idx == -1) return;
    currentMessages.removeAt(idx);
    notifyListeners();

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

  Future<void> _reformulateInBackground(String thinkingId) async {
    final lastUserIdx = currentMessages.lastIndexWhere((m) => m.role == 'user');
    if (lastUserIdx == -1) {
      currentMessages.removeWhere((m) => m.id == thinkingId);
      notifyListeners();
      return;
    }
    final lastUserText = currentMessages[lastUserIdx].content;
    tokensUsed += (lastUserText.length ~/ 3) + 15;

    await ChatService.sendMessageStream(
      conversationId: activeConversation?.id ?? '',
      message: lastUserText,
      history: (isIncognito || isGuestUser) ? currentMessages.where((m) => !m.isThinking).map((m) => {'role': m.role, 'content': m.content}).toList() : null,
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
          final currentEst = tokensUsed + (currentMessages[idx].content.length ~/ 3) + 35;
          if (currentEst >= tokensLimit) {
            tokensUsed = tokensLimit;
            final reason = isPro
                ? AppI18n.instance.t('limit.pro_reason')
                : AppI18n.instance.t('limit.free_reason');
            stopGeneration(reasonText: reason);
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
        } else {
          guestMessagesSessionCount++;
          _recordHardwareMessage();
          SupabaseService.recordGuestIpMessage();
          if (guestMessagesSessionCount >= 3) {
            guestIsBlocked = true;
          }
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
        isGenerating = false;
        errorMessage = e.toString();
        notifyListeners();
      },
    );
  }

  Future<void> sendUserMessage(String text) async {
    if (text.trim().isEmpty) return;
    final isGuest = isGuestUser;
    if (isGuest) {
      if (guestIsBlocked || guestMessagesSessionCount >= 3) {
        guestIsBlocked = true;
        notifyListeners();
        return;
      }
    } else {
      final estNew = tokensUsed + (text.length ~/ 3) + 15;
      if (tokensUsed >= tokensLimit || estNew > tokensLimit) {
        final limitMsg = isPro
            ? AppI18n.instance.t('limit.pro_msg')
            : AppI18n.instance.t('limit.free_msg');
        currentMessages.add(ChatMessage(
          id: 'limit-${DateTime.now().microsecondsSinceEpoch}',
          conversationId: activeConversation?.id ?? 'free',
          role: 'assistant',
          content: limitMsg,
          createdAt: DateTime.now(),
        ));
        notifyListeners();
        return;
      }
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
    currentMessages.removeWhere((m) => m.id == 'error');
    tokensUsed += (text.length ~/ 3) + 15;
    tokensResetTime ??= DateTime.now().add(const Duration(hours: 24));
    final userMsg = ChatMessage(
      id: 'user-${DateTime.now().microsecondsSinceEpoch}',
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
    notifyListeners();

    try {
      final msgId = 'asst-${DateTime.now().microsecondsSinceEpoch}';
      bool firstChunk = true;

      await ChatService.sendMessageStream(
        message: text,
        conversationId: shouldSaveHistory ? activeConversation?.id : null,
        history: (isIncognito || isGuestUser) ? currentMessages.where((m) => !m.isThinking).map((m) => {'role': m.role, 'content': m.content}).toList() : null,
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
              final currentEst = tokensUsed + (currentMessages[idx].content.length ~/ 3) + 35;
              if (!isGuestUser && currentEst >= tokensLimit) {
                tokensUsed = tokensLimit;
                final reason = isPro
                    ? AppI18n.instance.t('limit.pro_reason')
                    : AppI18n.instance.t('limit.free_reason');
                stopGeneration(reasonText: reason);
                return;
              }
            }
          }
          notifyListeners();
        },
        onComplete: (fullText, sources) async {
          isGenerating = false;
          tokensUsed += (fullText.length ~/ 3) + 35;
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
            final sourcesJson = sources.isNotEmpty ? jsonEncode(sources.map((s) => s.toJson()).toList()) : null;
            final contentToSave = sourcesJson != null ? '$fullText\n<!-- SOURCES: $sourcesJson -->' : fullText;
            try {
              await SupabaseService.client.from('messages').insert({
                'conversation_id': activeConversation!.id,
                'role': 'assistant',
                'content': contentToSave,
                if (sources.isNotEmpty) 'sources': sources.map((s) => s.toJson()).toList(),
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
          if (isGuest) {
            guestMessagesSessionCount++;
            _recordHardwareMessage();
            SupabaseService.recordGuestIpMessage();
            if (guestMessagesSessionCount >= 3) {
              guestIsBlocked = true;
            }
          }
          HapticFeedback.vibrate();
          notifyListeners();
        },
        onError: (err) {
          currentMessages.removeWhere((m) => m.isThinking);
          isThinking = false;
          isGenerating = false;
          errorMessage = err.replaceAll('Exception: ', '');
          currentMessages.add(ChatMessage(
            id: 'error',
            conversationId: activeConversation?.id ?? 'incognito',
            role: 'assistant',
            content: '⚠️ $errorMessage',
            createdAt: DateTime.now(),
          ));
          notifyListeners();
        },
      );

    } catch (e) {
      currentMessages.removeWhere((m) => m.isThinking);
      isThinking = false;
      isGenerating = false;
      errorMessage = e.toString().replaceAll('Exception: ', '');
      currentMessages.add(ChatMessage(
        id: 'error',
        conversationId: activeConversation?.id ?? 'incognito',
        role: 'assistant',
        content: '⚠️ $errorMessage',
        createdAt: DateTime.now(),
      ));
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

  void stopGeneration({String? reasonText}) {
    ChatService.cancelStream();
    currentMessages.removeWhere((m) => m.isThinking);
    isThinking = false;
    isGenerating = false;
    
    final stopText = reasonText ?? AppI18n.instance.t('chat.stopped');

    if (currentMessages.isEmpty || currentMessages.last.role != 'assistant' || currentMessages.last.content.trim().isEmpty) {
      if (currentMessages.isNotEmpty && currentMessages.last.role == 'assistant') {
        currentMessages[currentMessages.length - 1] = ChatMessage(
          id: currentMessages.last.id,
          conversationId: currentMessages.last.conversationId,
          role: 'assistant',
          content: stopText,
          createdAt: currentMessages.last.createdAt,
        );
      } else {
        currentMessages.add(ChatMessage(
          id: 'stop-${DateTime.now().microsecondsSinceEpoch}',
          conversationId: activeConversation?.id ?? 'guest',
          role: 'assistant',
          content: stopText,
          createdAt: DateTime.now(),
        ));
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

  // --- CANDADO PERSISTENTE DE HARDWARE VIA SHARED PREFERENCES (24H EXACTAS DESDE EL 1ER MENSAJE) ---
  Future<bool> _checkHardwareBlocked() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final firstMsgStr = prefs.getString('exodo_guest_first_msg_time');
      if (firstMsgStr != null) {
        final firstTime = DateTime.tryParse(firstMsgStr);
        if (firstTime != null && DateTime.now().difference(firstTime).inHours >= 24) {
          await prefs.remove('exodo_guest_first_msg_time');
          await prefs.remove('exodo_guest_hw_count');
          guestMessagesSessionCount = 0;
          return false;
        }
      }
      final count = prefs.getInt('exodo_guest_hw_count') ?? 0;
      guestMessagesSessionCount = count;
      return count >= 3;
    } catch (_) {
      return false;
    }
  }

  Future<void> _recordHardwareMessage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final firstMsgStr = prefs.getString('exodo_guest_first_msg_time');
      if (firstMsgStr == null || (prefs.getInt('exodo_guest_hw_count') ?? 0) == 0) {
        await prefs.setString('exodo_guest_first_msg_time', DateTime.now().toIso8601String());
      }
      await prefs.setInt('exodo_guest_hw_count', guestMessagesSessionCount);
    } catch (_) {}
  }
}
