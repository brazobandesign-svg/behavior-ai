import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../screens/auth_screen.dart';
import '../screens/chat_screen.dart';

/// RootSwitcher desacoplado de la inicialización asíncrona de Supabase.
/// Renderiza ChatScreen o AuthScreen inmediatamente en el Frame 0
/// sin pantallas ni bucles de carga, reaccionando a los cambios de AppState.
class RootSwitcher extends StatelessWidget {
  final bool initialHasSession;

  const RootSwitcher({
    super.key,
    this.initialHasSession = false,
  });

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    // Decisión instantánea en el frame 0 desde el estado cacheado
    final hasSession = state.hasSession;

    if (hasSession) {
      return const ChatScreen();
    }
    return const AuthScreen();
  }
}
