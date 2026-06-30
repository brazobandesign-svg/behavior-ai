import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'l10n/app_i18n.dart';
import 'l10n/app_translations.dart';
import 'services/supabase_service.dart';
import 'services/app_state.dart';
import 'theme/exodo_theme.dart';
import 'screens/auth_screen.dart';
import 'screens/chat_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // ignore: discarded_futures
  SupabaseService.initialize();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
      ],
      child: const AppI18nProvider(child: ExodoApp()),
    ),
  );
}

class ExodoApp extends StatelessWidget {
  const ExodoApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final userLocale = context.currentLocaleCode; // del AppI18nProvider

    return MaterialApp(
      title: AppI18n.of(context).t('app.title'),
      debugShowCheckedModeBanner: false,
      theme: ExodoTheme.lightTheme,
      darkTheme: ExodoTheme.darkTheme,
      themeMode: (state.isDarkMode || state.isIncognito) ? ThemeMode.dark : ThemeMode.light,
      themeAnimationDuration: Duration.zero,
      themeAnimationCurve: Curves.linear,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: kAppLocales.map((l) {
        final parts = l.code.split('_');
        return parts.length > 1 ? Locale(parts[0], parts[1]) : Locale(parts[0], '');
      }).toList(growable: false),
      locale: _resolveLocale(userLocale),
      localeResolutionCallback: (deviceLocale, supportedLocales) {
        if (deviceLocale != null) {
          for (final supported in supportedLocales) {
            if (supported.languageCode == deviceLocale.languageCode &&
                (supported.countryCode == deviceLocale.countryCode || supported.countryCode == null || supported.countryCode!.isEmpty)) {
              return supported;
            }
          }
          for (final supported in supportedLocales) {
            if (supported.languageCode == deviceLocale.languageCode) {
              return supported;
            }
          }
        }
        return const Locale('es', '');
      },
      home: _RootSwitcher(key: ValueKey(userLocale ?? 'es')),
      onUnknownRoute: (settings) => MaterialPageRoute(
        builder: (_) => _RootSwitcher(key: ValueKey(userLocale ?? 'es')),
      ),
    );
  }
}

Locale? _resolveLocale(String? appLocale) {
  if (appLocale == null) return null;
  if (!kAppLocales.any((l) => l.code == appLocale)) return null;
  final parts = appLocale.split('_');
  return parts.length > 1 ? Locale(parts[0], parts[1]) : Locale(parts[0], '');
}

class _RootSwitcher extends StatefulWidget {
  const _RootSwitcher({super.key});

  @override
  State<_RootSwitcher> createState() => _RootSwitcherState();
}

class _RootSwitcherState extends State<_RootSwitcher> {
  StreamSubscription<AuthState>? _authSub;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _initAuth();
  }

  Future<void> _initAuth() async {
    while (true) {
      try {
        SupabaseService.client;
        break;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      if (!mounted) return;
    }
    if (!mounted) return;
    _authSub = SupabaseService.client.auth.onAuthStateChange.listen((data) {
      if (mounted) setState(() {});
    });
    setState(() {
      _ready = true;
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AppState>();

    if (!_ready) {
      return const Scaffold(
        backgroundColor: ExodoColors.background,
        body: SizedBox.shrink(),
      );
    }

    final user = SupabaseService.currentUser;
    if (user == null) {
      return const AuthScreen();
    }
    return const ChatScreen();
  }
}
