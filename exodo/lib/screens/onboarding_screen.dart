import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/supabase_service.dart';
import '../services/app_state.dart';
import '../theme/exodo_theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  String? selectedRole;
  bool isSaving = false;

  final List<Map<String, String>> roles = [
    {
      'id': 'docente',
      'title': '📚 Docente / Educación',
      'desc': 'Especializado en el currículo del MINERD, planes de unidad, exámenes y didáctica dominicana.',
    },
    {
      'id': 'abogado',
      'title': '⚖️ Legal / Jurisprudencia',
      'desc': 'Conocimiento profundo de códigos dominicanos, redacción de instancias, contratos y sentencias.',
    },
    {
      'id': 'general',
      'title': '⚡ General / Profesional',
      'desc': 'Asistente veloz para redacción comercial, programación, creatividad y razonamiento diario.',
    },
  ];

  Future<void> _completeOnboarding() async {
    if (selectedRole == null) return;
    setState(() => isSaving = true);

    try {
      await SupabaseService.saveOnboarding({
        'role': selectedRole,
        'completed_at': DateTime.now().toIso8601String(),
      });
      if (mounted) {
        await context.read<AppState>().loadUserData();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error guardando: $e')));
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              Text(
                'Éxodo by Behavior',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(letterSpacing: 2),
              ),
              const SizedBox(height: 12),
              Text(
                '¿Cuál es tu enfoque principal?',
                style: Theme.of(context).textTheme.displayMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Seleccionando tu perfil, Éxodo adapta su razonamiento y base documental a tu profesión.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: ExodoColors.textSecondary),
              ),
              const SizedBox(height: 32),
              Expanded(
                child: ListView.separated(
                  itemCount: roles.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    final role = roles[index];
                    final isSelected = selectedRole == role['id'];

                    return InkWell(
                      onTap: () => setState(() => selectedRole = role['id']),
                      borderRadius: BorderRadius.circular(16),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: isSelected ? ExodoColors.amberGlow : ExodoColors.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected ? ExodoColors.amber : ExodoColors.border,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              role['title']!,
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                color: isSelected ? ExodoColors.amber : ExodoColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              role['desc']!,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: ExodoColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: selectedRole == null || isSaving ? null : _completeOnboarding,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ExodoColors.amber,
                    foregroundColor: ExodoColors.background,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                    elevation: 0,
                  ),
                  child: isSaving
                      ? const CircularProgressIndicator(color: ExodoColors.background)
                      : const Text('Continuar a Éxodo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
