import 'package:flutter/material.dart';
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
  ExodoModelOption selectedModel = EXODO_MODELS[0]; // Origon (G1.1)
  
  int tokensUsed = 0;
  int tokensLimit = 15000;
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
    conversations = await SupabaseService.getConversations();
    
    final usage = await SupabaseService.getTodayUsage();
    if (usage != null) {
      tokensUsed = usage['tokens_used'] as int? ?? 0;
      tokensLimit = usage['tokens_limit'] as int? ?? 15000;
    } else {
      tokensUsed = 0;
      tokensLimit = profile?.plan == 'hazak' ? 150000 : 15000;
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

  void toggleIncognito() {
    isIncognito = !isIncognito;
    if (isIncognito) {
      // Regla: En modo incógnito iniciar nuevo chat
      startNewChat();
    }
    notifyListeners();
  }

  void selectModelOption(ExodoModelOption option) {
    selectedModel = option;
    notifyListeners();
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
