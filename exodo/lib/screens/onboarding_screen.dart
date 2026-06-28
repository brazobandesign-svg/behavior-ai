import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/supabase_service.dart';
import '../services/app_state.dart';
import '../theme/exodo_theme.dart';

bool _isOnbEn(BuildContext context) {
  try {
    if (ui.PlatformDispatcher.instance.locale.languageCode == 'en') return true;
  } catch (_) {}
  return Localizations.localeOf(context).languageCode == 'en';
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  String? selectedRole;
  bool isSaving = false;

  List<Map<String, String>> _getRoles(bool isEn) => [
    {
      'id': 'docente',
      'title': isEn ? '📚 Teacher / Education' : '📚 Docente / Educación',
      'desc': isEn ? 'Specialized in Dominican MINERD curriculum, lesson plans, exams, and pedagogy.' : 'Especializado en el currículo del MINERD, planes de unidad, exámenes y didáctica dominicana.',
    },
    {
      'id': 'abogado',
      'title': isEn ? '⚖️ Legal / Jurisprudence' : '⚖️ Legal / Jurisprudencia',
      'desc': isEn ? 'Deep knowledge of Dominican codes, legal motions, contracts, and court rulings.' : 'Conocimiento profundo de códigos dominicanos, redacción de instancias, contratos y sentencias.',
    },
    {
      'id': 'general',
      'title': isEn ? '⚡ General / Professional' : '⚡ General / Profesional',
      'desc': isEn ? 'Fast assistant for business writing, programming, creativity, and daily reasoning.' : 'Asistente veloz para redacción comercial, programación, creatividad y razonamiento diario.',
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEn = _isOnbEn(context);
    final roles = _getRoles(isEn);

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
                isEn ? 'What is your main focus?' : '¿Cuál es tu enfoque principal?',
                style: Theme.of(context).textTheme.displayMedium,
              ),
              const SizedBox(height: 8),
              Text(
                isEn ? 'By selecting your profile, Exodo adapts its reasoning and knowledge base to your profession.' : 'Seleccionando tu perfil, Éxodo adapta su razonamiento y base documental a tu profesión.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: ExodoColors.textSecondary),
              ),
              const SizedBox(height: 32),
              Expanded(
                child: ListView.separated(
                  itemCount: roles.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 16),
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
                      : Text(isEn ? 'Continue to Exodo' : 'Continuar a Éxodo', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
