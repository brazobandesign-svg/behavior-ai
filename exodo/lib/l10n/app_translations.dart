/// Sistema centralizado de traducciones de Éxodo by Behavior.
///
/// Mantener sincronizado con las claves usadas en `app_translations_*.dart`:
/// cualquier clave añadida en un locale debe existir en los demás.
///
/// Locales soportados:
///   - en (English)
///   - es (Español — default)
///   - fr (Français)
///   - pt (Português)
///   - it (Italiano)
///   - de (Deutsch)
library;

import 'package:flutter/material.dart';

/// Idiomas disponibles en la app. El primero es el default.
class AppLocale {
  final String code;        // 'en', 'es', ...
  final String nativeName;  // 'English', 'Español', ...
  final String flag;        // emoji bandera
  final bool rtl;

  const AppLocale({
    required this.code,
    required this.nativeName,
    required this.flag,
    this.rtl = false,
  });

  Locale toLocale() => Locale(code);

  @override
  bool operator ==(Object other) =>
      other is AppLocale && other.code == code;

  @override
  int get hashCode => code.hashCode;
}

const List<AppLocale> kAppLocales = <AppLocale>[
  AppLocale(code: 'es', nativeName: 'Español',  flag: '🇪🇸'),
  AppLocale(code: 'en', nativeName: 'English',  flag: '🇺🇸'),
  AppLocale(code: 'fr', nativeName: 'Français', flag: '🇫🇷'),
  AppLocale(code: 'pt', nativeName: 'Português', flag: '🇵🇹'),
  AppLocale(code: 'it', nativeName: 'Italiano', flag: '🇮🇹'),
  AppLocale(code: 'de', nativeName: 'Deutsch',  flag: '🇩🇪'),
];

/// Punto de entrada principal: devuelve el mapa de traducciones para un código.
/// Si el código no existe, cae a español (es).
Map<String, String> translationsFor(String code) {
  switch (code) {
    case 'en': return _en;
    case 'fr': return _fr;
    case 'pt': return _pt;
    case 'it': return _it;
    case 'de': return _de;
    case 'es':
    default:   return _es;
  }
}

const Map<String, String> _es = <String, String>{
  // App
  'app.title': 'Éxodo by Behavior',

  // Auth
  'auth.continue_google': 'Continuar con Google',
  'auth.continue_apple':  'Continuar con Apple',
  'auth.continue_guest':  'Entrar como Invitado',

  // Chat
  'chat.placeholder':    'Hablar con Exodo...',
  'chat.placeholder_en': 'Reply to Exodo...',
  'chat.thinking':       'Exodo razonando...',
  'chat.thinking_en':    'Exodo reasoning...',

  // Greetings (time-of-day)
  'greeting.morning':   'Cafecito con Exodo',
  'greeting.afternoon': 'Tarde productiva',
  'greeting.evening':   'La noche es joven',
  'greeting.late':      'Ni la madrugada te detiene',
  'greeting.morning_en':'Morning',
  'greeting.afternoon_en':'Afternoon',
  'greeting.evening_en':'Evening',
  'greeting.late_en':   'Late night hustle',
  'greeting.cold':      'Frío afuera, mejor que un café',
  'greeting.hot':       'Toma algo frío, hace mucho calor',
  'greeting.cold_en':   'Cold outside, better than coffee',
  'greeting.hot_en':    'Grab something cold, really hot',

  // Drawer / menu
  'drawer.new_chat':      'Nuevo chat',
  'drawer.search_chats':  'Buscar conversación',
  'drawer.starred':       'Fijados',
  'drawer.recents':       'Recientes',
  'drawer.incognito':     'Modo Incógnito',
  'drawer.light_mode':    'Modo claro',
  'drawer.dark_mode':     'Modo oscuro',
  'drawer.sign_in':       'Iniciar sesión',
  'drawer.sign_out':      'Cerrar sesión',
  'drawer.upgrade':       'Actualizar a Pro',
  'drawer.language':      'Idioma',

  // Chat context menu
  'ctx.rename':   'Renombrar',
  'ctx.pin':      'Fijar',
  'ctx.unpin':    'Desfijar',
  'ctx.delete':   'Borrar',
  'ctx.cancel':   'Cancelar',

  // Action bar
  'act.copy':     'Copiar',
  'act.share':    'Compartir',
  'act.play':     'Reproducir',
  'act.like':     'Me gusta',
  'act.dislike':  'No me gusta',
  'act.recharge': 'Reformular',
  'live.coming_soon': 'Chat en vivo próximamente — escribe un mensaje para empezar.',
  'mic.permission_required': '⚠️ Permiso de micrófono requerido para dictado de voz.',

  // Sources sheet
  'sources.title': 'Fuentes',
  'sources.title_en': 'Sources',

  // Token bar
  'tokens.used':       'CONSUMIDO',
  'tokens.available':  'DISPONIBLE',
  'tokens.reset_in':   'REINICIO EN',
  'tokens.more':       'MÁS CAPACIDAD',

  // Errors
  'error.network': 'No pudimos conectar. Reintentar.',
  'error.generic': 'Algo salió mal.',

  // Misc
  'common.search_hint': 'Buscar...',
  'common.yes': 'Sí',
  'common.no':  'No',

  // Settings → language picker
  'lang.sheet_title': 'Idioma de la app',
  'lang.sheet_subtitle': 'Selecciona tu idioma preferido',
  'lang.system': 'Predeterminado del sistema',

  // Starters
  'starter.1': 'Resúmeme las noticias de hoy',
  'starter.2': 'Explícame un concepto complejo',
  'starter.3': 'Escríbeme un correo profesional',
  'starter.4': 'Ideas para un proyecto innovador',
};

const Map<String, String> _en = <String, String>{
  'app.title': 'Exodo by Behavior',

  'auth.continue_google': 'Continue with Google',
  'auth.continue_apple':  'Continue with Apple',
  'auth.continue_guest':  'Continue as Guest',

  'chat.placeholder':    'Reply to Exodo...',
  'chat.placeholder_en': 'Reply to Exodo...',
  'chat.thinking':       'Exodo reasoning...',
  'chat.thinking_en':    'Exodo reasoning...',

  'greeting.morning':    'Morning',
  'greeting.afternoon':  'Afternoon',
  'greeting.evening':    'Evening',
  'greeting.late':       'Late night hustle',
  'greeting.morning_en': 'Morning',
  'greeting.afternoon_en': 'Afternoon',
  'greeting.evening_en': 'Evening',
  'greeting.late_en':    'Late night hustle',
  'greeting.cold':       'Cold outside, better than coffee',
  'greeting.hot':        'Grab something cold, really hot',
  'greeting.cold_en':    'Cold outside, better than coffee',
  'greeting.hot_en':     'Grab something cold, really hot',

  'drawer.new_chat':     'New chat',
  'drawer.search_chats': 'Search chats',
  'drawer.starred':      'Starred',
  'drawer.recents':      'Recents',
  'drawer.incognito':    'Incognito mode',
  'drawer.light_mode':   'Light mode',
  'drawer.dark_mode':    'Dark mode',
  'drawer.sign_in':      'Sign in',
  'drawer.sign_out':     'Sign out',
  'drawer.upgrade':      'Upgrade to Pro',
  'drawer.language':     'Language',

  'ctx.rename':   'Rename',
  'ctx.pin':      'Pin',
  'ctx.unpin':    'Unpin',
  'ctx.delete':   'Delete',
  'ctx.cancel':   'Cancel',

  'act.copy':     'Copy',
  'act.share':    'Share',
  'act.play':     'Play',
  'act.like':     'Like',
  'act.dislike':  'Dislike',
  'act.recharge': 'Recharge',
  'live.coming_soon': 'Live chat coming soon — type a message to start.',
  'mic.permission_required': '⚠️ Microphone permission required for voice dictation.',

  'sources.title':    'Sources',
  'sources.title_en': 'Sources',

  'tokens.used':       'CONSUMED',
  'tokens.available':  'AVAILABLE',
  'tokens.reset_in':   'RESETS IN',
  'tokens.more':       'MORE CAPACITY',

  'error.network':  'We could not connect. Try again.',
  'error.generic':  'Something went wrong.',

  'common.search_hint': 'Search...',
  'common.yes': 'Yes',
  'common.no':  'No',

  'lang.sheet_title':    'App language',
  'lang.sheet_subtitle': 'Select your preferred language',
  'lang.system':         'System default',

  // Starters
  'starter.1': 'Summarize today\'s news',
  'starter.2': 'Explain a complex concept',
  'starter.3': 'Write a professional email',
  'starter.4': 'Ideas for an innovative project',
};

const Map<String, String> _fr = <String, String>{
  'app.title': 'Exodo by Behavior',

  'auth.continue_google': 'Continuer avec Google',
  'auth.continue_apple':  'Continuer avec Apple',
  'auth.continue_guest':  'Continuer en invité',

  'chat.placeholder':    'Parler à Exodo...',
  'chat.placeholder_en': 'Reply to Exodo...',
  'chat.thinking':       'Exodo réfléchit...',
  'chat.thinking_en':    'Exodo reasoning...',

  'greeting.morning':    'Bonjour',
  'greeting.afternoon':  'Bon après-midi',
  'greeting.evening':    'Bonsoir',
  'greeting.late':       'Veille tardive',
  'greeting.morning_en': 'Morning',
  'greeting.afternoon_en': 'Afternoon',
  'greeting.evening_en': 'Evening',
  'greeting.late_en':    'Late night hustle',
  'greeting.cold':       'Froid dehors, mieux qu\'un café',
  'greeting.hot':        'Prends quelque chose de frais',
  'greeting.cold_en':    'Cold outside, better than coffee',
  'greeting.hot_en':     'Grab something cold, really hot',

  'drawer.new_chat':     'Nouvelle conversation',
  'drawer.search_chats': 'Rechercher',
  'drawer.starred':      'Épinglés',
  'drawer.recents':      'Récents',
  'drawer.incognito':    'Mode Incognito',
  'drawer.light_mode':   'Mode clair',
  'drawer.dark_mode':    'Mode sombre',
  'drawer.sign_in':      'Se connecter',
  'drawer.sign_out':     'Se déconnecter',
  'drawer.upgrade':      'Passer à Pro',
  'drawer.language':     'Langue',

  'ctx.rename':   'Renommer',
  'ctx.pin':      'Épingler',
  'ctx.unpin':    'Détacher',
  'ctx.delete':   'Supprimer',
  'ctx.cancel':   'Annuler',

  'act.copy':     'Copier',
  'act.share':    'Partager',
  'act.play':     'Lire',
  'act.like':     'J\'aime',
  'act.dislike':  'Je n\'aime pas',
  'act.recharge': 'Reformuler',
  'live.coming_soon': 'Chat en direct bientôt disponible — tapez un message pour commencer.',
  'mic.permission_required': '⚠️ Autorisation du microphone requise pour la dictée vocale.',

  'sources.title':    'Sources',
  'sources.title_en': 'Sources',

  'tokens.used':       'CONSOMMÉ',
  'tokens.available':  'DISPONIBLE',
  'tokens.reset_in':   'REINIT. DANS',
  'tokens.more':       'PLUS DE CAPACITÉ',

  'error.network':  'Connexion impossible. Réessayer.',
  'error.generic':  'Une erreur est survenue.',

  'common.search_hint': 'Rechercher...',
  'common.yes': 'Oui',
  'common.no':  'Non',

  'lang.sheet_title':    'Langue de l\'application',
  'lang.sheet_subtitle': 'Sélectionnez votre langue préférée',
  'lang.system':         'Par défaut du système',

  // Starters
  'starter.1': 'Résumé les actualités du jour',
  'starter.2': 'Explique un concept complexe',
  'starter.3': 'Écris un e-mail professionnel',
  'starter.4': 'Idées pour un projet innovant',
};

const Map<String, String> _pt = <String, String>{
  'app.title': 'Exodo by Behavior',

  'auth.continue_google': 'Continuar com Google',
  'auth.continue_apple':  'Continuar com Apple',
  'auth.continue_guest':  'Entrar como convidado',

  'chat.placeholder':    'Falar com Exodo...',
  'chat.placeholder_en': 'Reply to Exodo...',
  'chat.thinking':       'Exodo pensando...',
  'chat.thinking_en':    'Exodo reasoning...',

  'greeting.morning':    'Bom dia',
  'greeting.afternoon':  'Boa tarde',
  'greeting.evening':    'Boa noite',
  'greeting.late':       'Noite adentro',
  'greeting.morning_en': 'Morning',
  'greeting.afternoon_en': 'Afternoon',
  'greeting.evening_en': 'Evening',
  'greeting.late_en':    'Late night hustle',
  'greeting.cold':       'Frio lá fora, melhor que café',
  'greeting.hot':        'Toma algo gelado',
  'greeting.cold_en':    'Cold outside, better than coffee',
  'greeting.hot_en':     'Grab something cold, really hot',

  'drawer.new_chat':     'Nova conversa',
  'drawer.search_chats': 'Buscar',
  'drawer.starred':      'Fixados',
  'drawer.recents':      'Recentes',
  'drawer.incognito':    'Modo Incógnito',
  'drawer.light_mode':   'Modo claro',
  'drawer.dark_mode':    'Modo escuro',
  'drawer.sign_in':      'Entrar',
  'drawer.sign_out':     'Sair',
  'drawer.upgrade':      'Atualizar para Pro',
  'drawer.language':     'Idioma',

  'ctx.rename':   'Renomear',
  'ctx.pin':      'Fixar',
  'ctx.unpin':    'Desafixar',
  'ctx.delete':   'Excluir',
  'ctx.cancel':   'Cancelar',

  'act.copy':     'Copiar',
  'act.share':    'Compartilhar',
  'act.play':     'Reproduzir',
  'act.like':     'Curtir',
  'act.dislike':  'Não curtir',
  'act.recharge': 'Reformular',
  'live.coming_soon': 'Chat ao vivo em breve — digite uma mensagem para começar.',
  'mic.permission_required': '⚠️ Permissão de microfone necessária para ditado por voz.',

  'sources.title':    'Fontes',
  'sources.title_en': 'Sources',

  'tokens.used':       'CONSUMIDO',
  'tokens.available':  'DISPONÍVEL',
  'tokens.reset_in':   'RESET EM',
  'tokens.more':       'MAIS CAPACIDADE',

  'error.network':  'Não foi possível conectar. Tente de novo.',
  'error.generic':  'Algo deu errado.',

  'common.search_hint': 'Buscar...',
  'common.yes': 'Sim',
  'common.no':  'Não',

  'lang.sheet_title':    'Idioma do app',
  'lang.sheet_subtitle': 'Selecione seu idioma preferido',
  'lang.system':         'Padrão do sistema',

  // Starters
  'starter.1': 'Resuma as notícias de hoje',
  'starter.2': 'Explique um conceito complexo',
  'starter.3': 'Escreva um e-mail profissional',
  'starter.4': 'Ideias para um projeto inovador',
};

const Map<String, String> _it = <String, String>{
  'app.title': 'Exodo by Behavior',

  'auth.continue_google': 'Continua con Google',
  'auth.continue_apple':  'Continua con Apple',
  'auth.continue_guest':  'Entra come ospite',

  'chat.placeholder':    'Parla con Exodo...',
  'chat.placeholder_en': 'Reply to Exodo...',
  'chat.thinking':       'Exodo sta ragionando...',
  'chat.thinking_en':    'Exodo reasoning...',

  'greeting.morning':    'Buongiorno',
  'greeting.afternoon':  'Buon pomeriggio',
  'greeting.evening':    'Buonasera',
  'greeting.late':       'Notte fonda',
  'greeting.morning_en': 'Morning',
  'greeting.afternoon_en': 'Afternoon',
  'greeting.evening_en': 'Evening',
  'greeting.late_en':    'Late night hustle',
  'greeting.cold':       'Freddo fuori, meglio del caffè',
  'greeting.hot':        'Prendi qualcosa di freddo',
  'greeting.cold_en':    'Cold outside, better than coffee',
  'greeting.hot_en':     'Grab something cold, really hot',

  'drawer.new_chat':     'Nuova chat',
  'drawer.search_chats': 'Cerca',
  'drawer.starred':      'Fissati',
  'drawer.recents':      'Recenti',
  'drawer.incognito':    'Modalità Incognito',
  'drawer.light_mode':   'Modo chiaro',
  'drawer.dark_mode':    'Modo scuro',
  'drawer.sign_in':      'Accedi',
  'drawer.sign_out':     'Esci',
  'drawer.upgrade':      'Passa a Pro',
  'drawer.language':     'Lingua',

  'ctx.rename':   'Rinomina',
  'ctx.pin':      'Fissa',
  'ctx.unpin':    'Togli',
  'ctx.delete':   'Elimina',
  'ctx.cancel':   'Annulla',

  'act.copy':     'Copia',
  'act.share':    'Condividi',
  'act.play':     'Riproduci',
  'act.like':     'Mi piace',
  'act.dislike':  'Non mi piace',
  'act.recharge': 'Riformula',
  'live.coming_soon': 'Chat live in arrivo — scrivi un messaggio per iniziare.',
  'mic.permission_required': '⚠️ Permesso del microfono richiesto per la dettatura vocale.',

  'sources.title':    'Fonti',
  'sources.title_en': 'Sources',

  'tokens.used':       'CONSUMATO',
  'tokens.available':  'DISPONIBILE',
  'tokens.reset_in':   'RESET TRA',
  'tokens.more':       'PIÙ CAPACITÀ',

  'error.network':  'Impossibile connettersi. Riprova.',
  'error.generic':  'Qualcosa è andato storto.',

  'common.search_hint': 'Cerca...',
  'common.yes': 'Sì',
  'common.no':  'No',

  'lang.sheet_title':    'Lingua dell\'app',
  'lang.sheet_subtitle': 'Seleziona la lingua preferita',
  'lang.system':         'Predefinito di sistema',

  // Starters
  'starter.1': 'Riassumi le notizie di oggi',
  'starter.2': 'Spiega un concetto complesso',
  'starter.3': 'Scrivi un\'email professionale',
  'starter.4': 'Idee per un progetto innovativo',
};

const Map<String, String> _de = <String, String>{
  'app.title': 'Exodo by Behavior',

  'auth.continue_google': 'Mit Google fortfahren',
  'auth.continue_apple':  'Mit Apple fortfahren',
  'auth.continue_guest':  'Als Gast fortfahren',

  'chat.placeholder':    'Mit Exodo sprechen...',
  'chat.placeholder_en': 'Reply to Exodo...',
  'chat.thinking':       'Exodo denkt nach...',
  'chat.thinking_en':    'Exodo reasoning...',

  'greeting.morning':    'Guten Morgen',
  'greeting.afternoon':  'Guten Tag',
  'greeting.evening':    'Guten Abend',
  'greeting.late':       'Späte Nacht',
  'greeting.morning_en': 'Morning',
  'greeting.afternoon_en': 'Afternoon',
  'greeting.evening_en': 'Evening',
  'greeting.late_en':    'Late night hustle',
  'greeting.cold':       'Kalt draußen, besser als Kaffee',
  'greeting.hot':        'Nimm etwas Kaltes',
  'greeting.cold_en':    'Cold outside, better than coffee',
  'greeting.hot_en':     'Grab something cold, really hot',

  'drawer.new_chat':     'Neuer Chat',
  'drawer.search_chats': 'Suchen',
  'drawer.starred':      'Angeheftet',
  'drawer.recents':      'Zuletzt',
  'drawer.incognito':    'Inkognito-Modus',
  'drawer.light_mode':   'Heller Modus',
  'drawer.dark_mode':    'Dunkler Modus',
  'drawer.sign_in':      'Anmelden',
  'drawer.sign_out':     'Abmelden',
  'drawer.upgrade':      'Auf Pro upgraden',
  'drawer.language':     'Sprache',

  'ctx.rename':   'Umbenennen',
  'ctx.pin':      'Anheften',
  'ctx.unpin':    'Lösen',
  'ctx.delete':   'Löschen',
  'ctx.cancel':   'Abbrechen',

  'act.copy':     'Kopieren',
  'act.share':    'Teilen',
  'act.play':     'Abspielen',
  'act.like':     'Mag ich',
  'act.dislike':  'Mag ich nicht',
  'act.recharge': 'Neu formulieren',
  'live.coming_soon': 'Live-Chat bald verfügbar — gib eine Nachricht ein, um zu starten.',
  'mic.permission_required': '⚠️ Mikrofon-Berechtigung für Sprachdiktat erforderlich.',

  'sources.title':    'Quellen',
  'sources.title_en': 'Sources',

  'tokens.used':       'VERBRAUCHT',
  'tokens.available':  'VERFÜGBAR',
  'tokens.reset_in':   'RESET IN',
  'tokens.more':       'MEHR KAPAZITÄT',

  'error.network':  'Verbindung fehlgeschlagen. Erneut versuchen.',
  'error.generic':  'Etwas ist schiefgelaufen.',

  'common.search_hint': 'Suchen...',
  'common.yes': 'Ja',
  'common.no':  'Nein',

  'lang.sheet_title':    'App-Sprache',
  'lang.sheet_subtitle': 'Wähle deine bevorzugte Sprache',
  'lang.system':         'Systemstandard',

  // Starters
  'starter.1': 'Fasse die heutigen Nachrichten zusammen',
  'starter.2': 'Erkläre ein komplexes Konzept',
  'starter.3': 'Schreibe eine professionelle E-Mail',
  'starter.4': 'Ideen für ein innovatives Projekt',
};
