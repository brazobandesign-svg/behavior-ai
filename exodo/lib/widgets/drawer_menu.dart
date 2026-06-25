import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../services/supabase_service.dart';
import '../theme/exodo_theme.dart';

class DrawerMenu extends StatelessWidget {
  const DrawerMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Drawer(
      backgroundColor: ExodoColors.surface,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: ExodoColors.amber,
                    child: Text(
                      state.profile?.fullName?.substring(0, 1).toUpperCase() ?? 'U',
                      style: const TextStyle(color: ExodoColors.background, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(state.profile?.fullName ?? 'Usuario Éxodo', style: Theme.of(context).textTheme.titleMedium),
                        Text(state.profile?.plan == 'hazak' ? '🌟 Plan Hazak Pro' : '⚡ Plan Génesis Gratis', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: ExodoColors.amber)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    state.startNewChat();
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.add, color: ExodoColors.amber),
                  label: const Text('Nuevo Chat', style: TextStyle(color: ExodoColors.amber, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: ExodoColors.amber),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(color: ExodoColors.border),
            Expanded(
              child: state.conversations.isEmpty
                  ? Center(child: Text('Sin conversaciones guardadas', style: Theme.of(context).textTheme.bodySmall))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: state.conversations.length,
                      itemBuilder: (context, index) {
                        final conv = state.conversations[index];
                        final active = state.activeConversation?.id == conv.id;

                        return ListTile(
                          onTap: () {
                            state.selectConversation(conv);
                            Navigator.pop(context);
                          },
                          leading: const Icon(Icons.chat_bubble_outline, size: 18, color: ExodoColors.textSecondary),
                          title: Text(conv.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: active ? ExodoColors.amber : ExodoColors.textPrimary)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          tileColor: active ? ExodoColors.amberGlow : Colors.transparent,
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18, color: ExodoColors.textSecondary),
                            onPressed: () async {
                              await SupabaseService.deleteConversation(conv.id);
                              state.conversations.removeAt(index);
                              if (active) state.startNewChat();
                            },
                          ),
                        );
                      },
                    ),
            ),
            const Divider(color: ExodoColors.border),
            ListTile(
              leading: const Icon(Icons.settings_outlined, color: ExodoColors.textSecondary),
              title: const Text('Ajustes y Privacidad'),
              onTap: () {
                Navigator.pop(context);
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    backgroundColor: ExodoColors.surface,
                    title: const Text('Términos y Privacidad'),
                    content: const Text('Éxodo by Behavior procesa consultas bajo cifrado estricto. En modo incógnito no se guardan registros en DB.'),
                    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar', style: TextStyle(color: ExodoColors.amber)))],
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: ExodoColors.error),
              title: const Text('Cerrar Sesión', style: TextStyle(color: ExodoColors.error)),
              onTap: () async {
                await SupabaseService.signOut();
              },
            ),
          ],
        ),
      ),
    );
  }
}
