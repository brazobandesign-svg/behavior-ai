import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import 'supabase_service.dart';
import 'chat_service.dart';

class AppState extends ChangeNotifier {
  UserProfile? profile;
  List<Conversation> conversations = [];
  Conversation? activeConversation;
  List<ChatMessage> currentMessages = [];
  
  bool isIncognito = false;
  bool showTab2Banner = true;
  bool isDarkMode = true;
  ExodoModelOption selectedModel = exodoModels[0]; // Origo (G1.1)
  
  int tokensUsed = 0;
  int tokensLimit = 15000;
  DateTime? tokensResetTime;
  bool get isPro => profile?.plan == 'hazak' || tokensLimit > 15000;
  bool isThinking = false;
  String? errorMessage;

  AppState() {
    _init();
  }

  Future<void> _init() async {
    SupabaseService.client.auth.onAuthStateChange.listen((data) async {
      final event = data.event;
      if (event == AuthChangeEvent.signedIn || event == AuthChangeEvent.initialSession) {
        await loadUserData();
      } else if (event == AuthChangeEvent.signedOut) {
        profile = null;
        conversations = [];
        activeConversation = null;
        currentMessages = [];
        tokensUsed = 0;
        notifyListeners();
      }
    });
  }

  Future<void> loadUserData() async {
    profile = await SupabaseService.getProfile();
    final currentUserEmail = SupabaseService.currentUser?.email;
    if (currentUserEmail != null && currentUserEmail.toLowerCase() == 'brazobandesign@gmail.com') {
      if (profile?.plan != 'hazak') {
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
    conversations = await SupabaseService.getConversations();
    
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

    if (conversations.isNotEmpty) {
      await selectConversation(conversations.first);
    } else {
      startNewChat();
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
        createdAt: old.createdAt,
      );
      if (activeConversation?.id == convId) {
        activeConversation = conversations[idx];
      }
      SupabaseService.updateConversationTitle(convId, newTitle);
      notifyListeners();
    }
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
    selectedModel = option;
    notifyListeners();
  }

  String get userEmail => SupabaseService.client.auth.currentUser?.email ?? 'overcomingchannel1@gmail.com';

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

  Future<void> sendUserMessage(String text) async {
    if (text.trim().isEmpty) return;
    errorMessage = null;

    // 1. Crear conversación en DB si no existe y no estamos en incógnito
    if (activeConversation == null && !isIncognito) {
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
      conversationId: activeConversation?.id ?? 'incognito',
      role: 'user',
      content: text,
      createdAt: DateTime.now(),
    );
    currentMessages.add(userMsg);

    // 3. Añadir burbuja temporal de pensamiento con animación personalizada
    isThinking = true;
    final thinkingMsg = ChatMessage(
      id: 'thinking',
      conversationId: activeConversation?.id ?? 'incognito',
      role: 'assistant',
      content: '',
      createdAt: DateTime.now(),
      isThinking: true,
    );
    currentMessages.add(thinkingMsg);
    notifyListeners();

    try {
      // 4. Llamar a API
      final res = await ChatService.sendMessage(
        message: text,
        conversationId: isIncognito ? null : activeConversation?.id,
      );

      // Quitar burbuja thinking
      currentMessages.removeWhere((m) => m.isThinking);
      isThinking = false;

      // Actualizar tokens
      tokensUsed = res.tokensUsed;
      tokensLimit = res.tokensLimit;
      if (tokensResetTime == null && tokensUsed > 0) {
        tokensResetTime = DateTime.now().add(const Duration(hours: 24));
      }

      // 5. Añadir respuesta final
      final assistantMsg = ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        conversationId: activeConversation?.id ?? 'incognito',
        role: 'assistant',
        content: res.responseText,
        intentDetected: res.intent,
        createdAt: DateTime.now(),
      );
      currentMessages.add(assistantMsg);
      HapticFeedback.vibrate();

    } catch (e) {
      currentMessages.removeWhere((m) => m.isThinking);
      isThinking = false;
      errorMessage = e.toString().replaceAll('Exception: ', '');
      
      currentMessages.add(ChatMessage(
        id: 'error',
        conversationId: activeConversation?.id ?? 'incognito',
        role: 'assistant',
        content: '⚠️ **Error de red o plan**: $errorMessage',
        createdAt: DateTime.now(),
      ));
    }

    notifyListeners();
  }
}
