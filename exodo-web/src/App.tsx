import React, { useState, useEffect, useLayoutEffect, useRef } from 'react';
import { 
  ChevronUp,
  Sun, 
  Moon, 
  ArrowUp, 
  MessageSquare,
  Plus,
  X,
  ChevronDown,
  Edit2,
  Mic
} from 'lucide-react';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import TextareaAutosize from 'react-textarea-autosize';
import { supabase, type Conversation, type Message, type Source } from './lib/supabase';
import { AuthModal } from './components/AuthModal';
import { ArtifactMessageBody } from './components/ArtifactMessage';
import { DrawerMenu } from './components/DrawerMenu';
import { SidebarRail } from './components/SidebarRail';
import { ModelSelector } from './components/ModelSelector';
import { EXODO_MODELS, type ModelOption } from './types/models';
import { UpgradeModal } from './components/UpgradeModal';
import { SettingsModal } from './components/SettingsModal';
import { ProfileModal } from './components/ProfileModal';
import { LanguageModal } from './components/LanguageModal';
import { BillingModal } from './components/BillingModal';
import { FeedbackModal } from './components/FeedbackModal';
import { ConsentGateModal } from './components/ConsentGateModal';
import { TermsModal } from './components/TermsModal';
import { ExpedientesModal } from './components/ExpedientesModal';
import { SourcesModal } from './components/SourcesModal';
import { ShortcutsModal } from './components/ShortcutsModal';
import { flushSync } from 'react-dom';

// Endpoint oficial de producción de Exodo (Cloud Run con fallback por env)
const BACKEND_BASE_URL = import.meta.env.VITE_BACKEND_URL || 'https://exodo-api-23368377903.us-east1.run.app';

// Cross-fade suave para cambios de tema (evita el flash agresivo dark↔light).
// El update debe comprometer TODO el DOM (React + data-theme) dentro del callback
// para que el snapshot "viejo" y el "nuevo" de la transición sean coherentes.
const applyThemeChange = (update: () => void) => {
  const doc = document as Document & {
    startViewTransition?: (callback: () => void) => unknown;
  };
  if (typeof doc.startViewTransition === 'function' && document.visibilityState === 'visible') {
    doc.startViewTransition(() => flushSync(update));
  } else {
    // Fallback: transición temporal de colores para navegadores sin View Transitions
    const root = document.documentElement;
    root.classList.add('theme-animating');
    void getComputedStyle(root).backgroundColor;
    flushSync(update);
    window.setTimeout(() => root.classList.remove('theme-animating'), 340);
  }
};

// Indicador de pensamiento (paridad ExodoThinkingIndicator): elige al azar una
// de las dos animaciones de carga en cada episodio, color neutro según tema.
const ThinkingIndicator: React.FC = () => {
  const [secs, setSecs] = useState(0);
  const [loaderVariant] = useState<'shuffle' | 'corners'>(() =>
    Math.random() < 0.5 ? 'shuffle' : 'corners'
  );
  useEffect(() => {
    const t0 = Date.now();
    const t = setInterval(() => setSecs(Math.floor((Date.now() - t0) / 1000)), 1000);
    return () => clearInterval(t);
  }, []);
  return (
    <span className="thinking-row">
      <span className={`thinking-loader thinking-loader-${loaderVariant}`} />
      <span className="thinking-label">Pensando</span>
      <span className="thinking-secs">{secs}s</span>
    </span>
  );
};

// ── Doctrina de Fuentes (paridad con _SourcesSheet móvil) ──────────────────

// Etiquetas localizadas de fuentes (paridad con sources.title / sources.consulted de la app móvil).
const SOURCE_LABELS: Record<string, { title: string; consulted: string }> = {
  es: { title: 'Fuentes', consulted: 'Fuentes Consultadas' },
  en: { title: 'Sources', consulted: 'Consulted Sources' },
  fr: { title: 'Sources', consulted: 'Sources consultées sur le web' },
  pt: { title: 'Fontes', consulted: 'Fontes consultadas na web' },
  it: { title: 'Fonti', consulted: 'Fonti consultate sul web' },
  de: { title: 'Quellen', consulted: 'Im Web konsultierte Quellen' },
  ru: { title: 'Источники', consulted: 'Источники, изученные в сети' },
  zh: { title: '参考来源', consulted: '网页搜索参考来源' },
  ja: { title: '情報源', consulted: 'ウェブで参照したソース' },
  ar: { title: 'المصادر', consulted: 'المصادر المستشار بها على الويب' },
  ko: { title: '출처', consulted: '웹에서 참조된 출처' },
  hi: { title: 'स्रोत', consulted: 'वेब पर परामर्श किए गए स्रोत' },
  ht: { title: 'Sous', consulted: 'Sous ki te konsilte sou entènèt' },
};

const getSourceLabels = (locale: string) => {
  const base = (locale || 'es').toLowerCase().split(/[-_]/)[0];
  return SOURCE_LABELS[base] || SOURCE_LABELS.es;
};

const SOURCE_CIRCLE_COLORS = ['#635BFF', '#131313', '#2E90FA', '#C9933A'];

// Iniciales del avatar: favicon del backend → 2 primeras palabras → 2 letras (paridad _sourceInitials).
const sourceInitials = (s: Source) => {
  if (s.favicon && s.favicon.trim()) return s.favicon.trim().toUpperCase();
  const t = (s.title || '').trim();
  if (!t) return '?';
  const parts = t.split(/\s+/).filter(Boolean);
  if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
  return t.slice(0, 2).toUpperCase() || '?';
};

// Filtro cliente (paridad móvil): descarta descargas efímeras e imágenes de mensajes históricos.
const validSourcesOf = (msg: Message): Source[] =>
  (msg.sources || []).filter((s) => {
    const url = (s.url || '').toLowerCase();
    return !(
      url.includes('aliyuncs.com') ||
      url.includes('dashscope-result') ||
      url.endsWith('.png') ||
      url.endsWith('.jpg') ||
      url.endsWith('.jpeg')
    );
  });


// Cita en línea estilo barra/chip (paridad con _SourceChipElementBuilder móvil):
// favicon del sitio + nombre corto, fondo grafito #252525, texto yeso, borde
// sutil, ancho máximo fijo con elipsis; apertura en pestaña nueva.
const chipHost = (href: string) => {
  try {
    return href ? new URL(href, window.location.origin).host : '';
  } catch {
    return '';
  }
};

const markdownComponents = {
  a: ({ node: _node, href, children, ...rest }: React.ComponentProps<'a'> & { node?: unknown }) => {
    const host = chipHost(href || '');
    return (
      <a {...rest} href={href} target="_blank" rel="noopener noreferrer" className="md-source-chip">
        {host && (
          <img
            src={`https://www.google.com/s2/favicons?domain=${host}&sz=32`}
            alt=""
            width={15}
            height={15}
            onError={(e) => {
              e.currentTarget.style.display = 'none';
            }}
          />
        )}
        <span className="md-source-chip-label">{children}</span>
      </a>
    );
  },
};



export default function App() {
  // Estados de sesión y autenticación
  const [session, setSession] = useState<any>(null);
  const [userProfile, setUserProfile] = useState<{ plan?: string; full_name?: string; onboarding?: any } | null>(null);
  const [showAuthModal, setShowAuthModal] = useState(false);

  // Estados de interfaz exacta a móvil
  const [theme, setTheme] = useState<'dark' | 'light'>(() => (localStorage.getItem('exodo_theme') as 'dark' | 'light') || 'dark');
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [isIncognito, setIsIncognito] = useState(false);
  // Paridad Flutter (main.dart / exodo_theme.dart): Incógnito siempre fuerza tema oscuro
  const effectiveTheme: 'dark' | 'light' = isIncognito ? 'dark' : theme;
  // Invitado (paridad isGuestUser de app_state.dart): usuario anónimo de
  // Supabase = solo local, sin nube (sin perfil, sin conversaciones en DB,
  // sin medidor), modelo bloqueado y sin upgrade — como la app.
  const isGuestUser = !!session?.user?.is_anonymous;
  const [showAccountMenu, setShowAccountMenu] = useState(false);
  const [showProfileMenu, setShowProfileMenu] = useState(false);
  const [showLanguageMenu, setShowLanguageMenu] = useState(false);
  const [locale, setLocale] = useState<string>(() => {
    const saved = localStorage.getItem('exodo_web_locale') || localStorage.getItem('exodo_language');
    if (saved) return saved;
    return (navigator.language || 'es').toLowerCase();
  });
  const [showBillingMenu, setShowBillingMenu] = useState(false);
  const [showPlansModal, setShowPlansModal] = useState(false);
  const [showModelSelector, setShowModelSelector] = useState(false);
  const [showExpedientes, setShowExpedientes] = useState(false);
  const [chatNotice, setChatNotice] = useState<string | null>(null);
  // Feedback de mensajes (paridad _AssistantActionsBar móvil: modal con
  // comentario → insert en tabla `feedback`; envío silencioso).
  const [feedbackTarget, setFeedbackTarget] = useState<{ msg: Message; isLike: boolean } | null>(null);
  // Consent gate (paridad _maybeShowConsentGate de chat_screen.dart): edad +
  // nube en el primer login con cuenta. Sin aceptar edad no se continúa.
  const [showConsentGate, setShowConsentGate] = useState(false);
  // Terms & Privacy (paridad settings.legal_body).
  const [showTerms, setShowTerms] = useState(false);
  // Atajos de teclado (referencia visual de shortcuts).
  const [showShortcuts, setShowShortcuts] = useState(false);
  const [isCheckingOut, setIsCheckingOut] = useState(false);
  // Historial en la nube (paridad setCloudHistoryEnabled de app_state.dart):
  // OFF = turnos efímeros (no se crea conversación en DB ni se envía
  // conversationId al backend, como incógnito pero con UI normal).
  const [cloudHistoryEnabled, setCloudHistoryEnabled] = useState<boolean>(() => {
    try {
      const saved = localStorage.getItem('exodo_cloud_history');
      return saved === null ? true : saved === '1';
    } catch { return true; }
  });
  const toggleCloudHistory = (v: boolean) => {
    setCloudHistoryEnabled(v);
    try { localStorage.setItem('exodo_cloud_history', v ? '1' : '0'); } catch (_) {}
  };
  // Medidor de tokens (paridad app_state.dart): user_usage por período diario UTC.
  const [tokensUsed, setTokensUsed] = useState(0);
  const tokensLimit = userProfile?.plan === 'hazak' ? 50000 : 6000;

  // Período diario en AST (America/Santo_Domingo, UTC-4), igual que el
  // backend (tokenCounter.getAstDates). Con UTC el medidor se desfasaba ±4h.
  const astToday = () => {
    const now = new Date();
    const ast = new Date(now.getTime() - 4 * 3600 * 1000);
    return ast.toISOString().slice(0, 10);
  };

  const fetchTodayUsage = async () => {
    if (!session?.user || isIncognito || session.user.is_anonymous) {
      setTokensUsed(0);
      return;
    }
    try {
      const { data } = await supabase
        .from('user_usage')
        .select('tokens_used')
        .eq('user_id', session.user.id)
        .eq('period', astToday())
        .maybeSingle();
      setTokensUsed(data?.tokens_used ?? 0);
    } catch (_) {}
  };
  const [selectedModel, setSelectedModel] = useState<ModelOption>(EXODO_MODELS[0]);
  const [showUpgradeBanner, setShowUpgradeBanner] = useState(true);

  // Estados de conversación
  const [conversations, setConversations] = useState<Conversation[]>(() => {
    try {
      const cached = localStorage.getItem('exodo_web_cached_convs');
      if (cached) {
        const parsedList = JSON.parse(cached);
        if (Array.isArray(parsedList) && parsedList.length > 0) {
          return parsedList;
        }
      }
      const temp = localStorage.getItem('exodo_web_temp_conv');
      if (temp) {
        const parsed = JSON.parse(temp);
        if (parsed && parsed.id && parsed.id.startsWith('conv-')) {
          return [parsed];
        }
      }
    } catch (_) {}
    return [];
  });
  const [activeConvId, setActiveConvId] = useState<string | null>(() => {
    const saved = localStorage.getItem('exodo_web_active_conv');
    return saved && saved !== 'null' && saved !== 'new' ? saved : null;
  });
  const [messages, setMessages] = useState<Message[]>([]);
  const [isInitializing, setIsInitializing] = useState(true);
  const [openSourcesId, setOpenSourcesId] = useState<string | null>(null);
  const [drafts, setDrafts] = useState<Record<string, string>>(() => {
    try {
      const saved = localStorage.getItem('exodo_web_drafts');
      if (saved) return JSON.parse(saved);
    } catch {}
    
    // Migrar draft viejo una sola vez
    const oldDraft = localStorage.getItem('exodo_web_draft_input');
    if (oldDraft) {
      const active = localStorage.getItem('exodo_web_active_conv') || 'initial';
      const migrated = { [active]: oldDraft };
      localStorage.setItem('exodo_web_drafts', JSON.stringify(migrated));
      localStorage.removeItem('exodo_web_draft_input');
      return migrated;
    }
    return {};
  });

  const currentConvKey = activeConvId || 'initial';
  const input = drafts[currentConvKey] || '';
  const setInput = (val: string | ((prev: string) => string)) => {
    setDrafts(prev => {
      const cur = prev[currentConvKey] || '';
      const next = typeof val === 'function' ? (val as (p: string) => string)(cur) : val;
      const newDrafts = { ...prev, [currentConvKey]: next };
      localStorage.setItem('exodo_web_drafts', JSON.stringify(newDrafts));
      return newDrafts;
    });
  };
  const [isStreaming, setIsStreaming] = useState(false);
  // Guard síncrono anti-doble-envío: isStreaming (estado) no se actualiza a
  // tiempo entre dos clicks del mismo tick (doble-click / Ctrl+Enter+click),
  // así que el segundo handler ve el closure viejo y vuelve a enviar. El ref
  // se muta al instante y bloquea el reenvío idéntico.
  const isSendingRef = useRef(false);

  const messagesEndRef = useRef<HTMLDivElement>(null);

  const messagesListRef = useRef<HTMLDivElement>(null);
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const [showScrollDown, setShowScrollDown] = useState(false);
  const [isComposerScrollable, setIsComposerScrollable] = useState(false);

  const handleScroll = () => {
    if (messagesListRef.current) {
      const { scrollTop, scrollHeight, clientHeight } = messagesListRef.current;
      setShowScrollDown(scrollHeight - scrollTop - clientHeight > 80);
    }
  };

  // Los drafts se guardan automáticamente en setInput

  // Sincronización de tema (Paridad Flutter: Incógnito siempre fuerza dark theme)
  // useLayoutEffect: el atributo cambia dentro del mismo commit que los estilos
  // inline derivados de effectiveTheme, para que applyThemeChange capture snapshots coherentes
  useLayoutEffect(() => {
    document.documentElement.setAttribute('data-theme', effectiveTheme);
    if (!isIncognito) {
      localStorage.setItem('exodo_theme', theme);
    }
  }, [effectiveTheme, isIncognito, theme]);

  // Idioma del documento: <html lang> real (a11y, correctores, voces TTS) y
  // dirección RTL para árabe (paridad Flutter, que espeja la UI con intl).
  useLayoutEffect(() => {
    const base = (locale || 'es').toLowerCase().split(/[-_]/)[0];
    document.documentElement.lang = base;
    document.documentElement.dir = base === 'ar' ? 'rtl' : 'ltr';
  }, [locale]);

  // ── Atajos de teclado globales (sin conflicto con el navegador) ──
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      const el = e.target as HTMLElement;
      const isTyping =
        el.tagName === 'INPUT' ||
        el.tagName === 'TEXTAREA' ||
        el.isContentEditable;

      // Esc — siempre (cerrar modal/drawer activo), incluso si está escribiendo
      if (e.key === 'Escape') {
        // Los modales individuales ya manejan su propio Esc,
        // pero el drawer no tiene uno — lo cerramos aquí.
        if (drawerOpen) { setDrawerOpen(false); return; }
        return; // deja que los modales lo capturen
      }

      // Los demás atajos solo si NO está escribiendo
      if (isTyping) {
        // Excepción: Ctrl+Enter para enviar mensaje sí funciona mientras escribe
        if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) {
          e.preventDefault();
          handleSendMessage();
          return;
        }
        return;
      }

      // / → foco al composer
      if (e.key === '/' && !e.ctrlKey && !e.altKey && !e.metaKey) {
        e.preventDefault();
        try { document.querySelector<HTMLTextAreaElement>('.composer-input')?.focus(); } catch (_) {}
        return;
      }

      // Alt+N → Nuevo chat
      if (e.altKey && e.key.toLowerCase() === 'n') {
        e.preventDefault();
        handleCreateNewChat();
        return;
      }

      // Alt+I → Toggle incógnito
      if (e.altKey && e.key.toLowerCase() === 'i') {
        e.preventDefault();
        handleToggleIncognito();
        return;
      }

      // Alt+D → Toggle dark/light
      if (e.altKey && e.key.toLowerCase() === 'd') {
        e.preventDefault();
        toggleTheme();
        return;
      }

      // Alt+E → Abrir expedientes
      if (e.altKey && e.key.toLowerCase() === 'e') {
        e.preventDefault();
        setShowExpedientes(true);
        return;
      }

      // Alt+M → Toggle menú lateral
      if (e.altKey && e.key.toLowerCase() === 'm') {
        e.preventDefault();
        setDrawerOpen((prev) => !prev);
        return;
      }

      // Ctrl+Shift+S → Buscar chats (abre drawer en modo búsqueda)
      if (e.ctrlKey && e.shiftKey && e.key.toLowerCase() === 's') {
        e.preventDefault();
        setDrawerOpen(true);
        return;
      }

      // Alt+S → Abrir configuración
      if (e.altKey && e.key.toLowerCase() === 's') {
        e.preventDefault();
        setShowAccountMenu(true);
        return;
      }

      // Alt+? → Mostrar atajos
      if (e.altKey && (e.key === '?' || e.key === '/')) {
        e.preventDefault();
        setShowShortcuts(true);
        return;
      }
    };
    document.addEventListener('keydown', handler);
    return () => document.removeEventListener('keydown', handler);
  });

  // Sincronización de sesión y Realtime
  useEffect(() => {
    // Detectar posibles errores de redirección OAuth devueltos por Google / Supabase en la URL
    const params = new URLSearchParams(window.location.search);
    const hashParams = new URLSearchParams(window.location.hash.substring(1));
    const oauthError = params.get('error') || hashParams.get('error');
    const oauthErrorDesc = params.get('error_description') || hashParams.get('error_description');
    
    if (oauthError) {
      console.error('Error de OAuth detectado en URL tras redirección:', oauthError, oauthErrorDesc);
      alert(`No se pudo iniciar sesión con Google.\nError: ${oauthError}\nDescripción: ${decodeURIComponent(oauthErrorDesc || 'Desconocida')}\n\n⚠️ Consejo: Verifica en tu proyecto de Supabase (zyvaakfsnlqlgrjdigkr -> Authentication -> URL Configuration -> Redirect URLs) que la URL "${window.location.origin}" esté agregada a la lista blanca de redirecciones permitidas.`);
    }

    // Retorno de OAuth (Google/GitHub): Supabase canjea automáticamente el ?code=
    // mediante PKCE en initializePromise (detectSessionInUrl: true).
    // getSession() espera internamente a que initializePromise complete el canje.
    const finishOAuthReturn = () => {
      if (window.location.search.includes('code=') || window.location.hash.includes('access_token=')) {
        window.history.replaceState({}, document.title, window.location.pathname);
      }
    };

    const sessionTimeout = setTimeout(() => {
      supabase.auth.getSession().then(({ data: { session }, error }) => {
        if (error) {
          console.error('Error al obtener sesión OAuth:', error);
          if (window.location.search.includes('code=')) {
            alert(`No se completó el acceso: ${error.message}`);
          }
          finishOAuthReturn();
          return;
        }
        if (session) {
          setSession(session);
          if (session.user) {
            if (!session.user.is_anonymous) {
              fetchProfile(session.user.id);
              fetchConversations();
              fetchTodayUsage();
            }
            setShowAuthModal(false);
          }
        }
        finishOAuthReturn();
      }).catch((err) => {
        console.error('Error inesperado al obtener sesión:', err);
        finishOAuthReturn();
      });
    }, 150);

    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
      setSession(session);
      if (session?.user) {
        if (!session.user.is_anonymous) {
          fetchProfile(session.user.id);
          fetchConversations();
          fetchTodayUsage();
          processBillingReturn();
          maybeShowConsentGate();
        } else {
          // Invitado: limpiar restos de una sesión anterior con cuenta.
          setUserProfile(null);
          setTokensUsed(0);
        }
        // Solo un login REAL cierra la puerta de acceso. Una sesión anónima
        // (auto sign-in de voz, restore en background) no debe cerrar el
        // modal mientras el usuario elige proveedor; el botón invitado ya
        // cierra explícito en handleGuestSignIn.
        if (!session.user.is_anonymous) {
          setShowAuthModal(false);
        }
        if (window.location.search.includes('code=') || window.location.hash.includes('access_token=')) {
          window.history.replaceState({}, document.title, window.location.pathname);
        }
      } else {
        setUserProfile(null);
      }
    });

    const channel = supabase
      .channel('realtime-conversations')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'conversations' }, () => {
        fetchConversations();
      })
      .subscribe();

    fetchConversations();

    return () => {
      clearTimeout(sessionTimeout);
      subscription.unsubscribe();
      supabase.removeChannel(channel);
    };
  }, []);

  const isFirstMountRef = useRef(true);

  useEffect(() => {
    if (isFirstMountRef.current) {
      isFirstMountRef.current = false;
      if (activeConvId && !activeConvId.startsWith('conv-') && activeConvId !== 'initial') {
        fetchMessages(activeConvId).finally(() => setIsInitializing(false));
      } else {
        setIsInitializing(false);
      }
    }
  }, [activeConvId]);

  async function fetchProfile(userId: string) {
    try {
      const { data } = await supabase
        .from('profiles')
        .select('plan, full_name, onboarding')
        .eq('id', userId)
        .single();
      if (data) {
        setUserProfile(data);
      }
    } catch (_) {}
  }

  async function fetchConversations() {
    try {
      const { data, error } = await supabase
        .from('conversations')
        .select('*')
        .order('updated_at', { ascending: false });
      if (!error && data) {
        setConversations((prev) => {
          // Preservar el chat temporal ('conv-...') de New Chat para que no se borre al sincronizar al volver de otra ventana
          const unsaved = prev.filter((c) => c.id.startsWith('conv-'));
          const dataIds = new Set(data.map((d) => d.id));
          return [...unsaved.filter((u) => !dataIds.has(u.id)), ...data];
        });
      }
      } catch (e) {
        console.warn('Error fetching conversations:', e);
      }
    }

  // ── CRUD de conversaciones (paridad con la app: renombrar / fijar / eliminar) ──
  const toggleStarred = async (conv: Conversation) => {
    const next = !conv.is_starred;
    setConversations((prev) => prev.map((c) => (c.id === conv.id ? { ...c, is_starred: next } : c)));
    if (!conv.id.startsWith('conv-')) {
      const { error } = await supabase.from('conversations').update({ is_starred: next }).eq('id', conv.id);
      if (error) console.warn('Error fijando conversación:', error.message);
    }
  };

  const renameConversation = async (convId: string, newTitle: string) => {
    if (!newTitle) return;
    const conv = conversations.find((c) => c.id === convId);
    if (!conv || conv.title === newTitle) return;
    setConversations((prev) => prev.map((c) => (c.id === convId ? { ...c, title: newTitle } : c)));
    if (!convId.startsWith('conv-')) {
      const { error } = await supabase.from('conversations').update({ title: newTitle }).eq('id', convId);
      if (error) console.warn('Error renombrando conversación:', error.message);
    }
  };

  const deleteConversation = async (convId: string) => {
    setConversations((prev) => prev.filter((c) => c.id !== convId));
    if (!convId.startsWith('conv-')) {
      // La FK ON DELETE CASCADE borra los mensajes asociados.
      const { error } = await supabase.from('conversations').delete().eq('id', convId);
      if (error) console.warn('Error eliminando conversación:', error.message);
    }
    if (activeConvId === convId) {
      handleCreateNewChat();
    }
  };

  // ── Consent gate (paridad _maybeShowConsentGate) ──
  const maybeShowConsentGate = () => {
    try {
      if (localStorage.getItem('exodo_age_confirmed') === '1') return;
    } catch (_) { return; }
    // Marcar antes de mostrar (paridad FIX doble-diálogo: un remount no repite).
    try { localStorage.setItem('exodo_age_confirmed', '1'); } catch (_) {}
    setShowConsentGate(true);
  };

  const acceptConsent = async (cloudConsent: boolean) => {
    const ts = new Date().toISOString();
    try {
      localStorage.setItem('exodo_consent', JSON.stringify({ age: true, cloud: cloudConsent, ts, v: 1 }));
    } catch (_) {}
    toggleCloudHistory(cloudConsent);
    setShowConsentGate(false);
    // Registro en la nube, best-effort (paridad móvil: onboarding).
    try {
      if (session?.user) {
        const existing = (userProfile?.onboarding && typeof userProfile.onboarding === 'object')
          ? { ...userProfile.onboarding } : {};
        (existing as any)['age_confirmed'] = true;
        (existing as any)['cloud_history_consent'] = cloudConsent;
        (existing as any)['consent_ts'] = ts;
        await supabase.from('profiles').update({ onboarding: existing }).eq('id', session.user.id);
        setUserProfile((prev) => (prev ? { ...prev, onboarding: existing } : prev));
      }
    } catch (_) {}
  };

  // ── Stripe Checkout real (paridad StripeService + web_billing_adapter:
  // misma pestaña; el retorno ?session_id=&status= lo procesa el arranque) ──
  const startCheckout = async (isAnnual: boolean) => {
    if (!session?.user || isGuestUser || isCheckingOut) {
      if (isGuestUser || !session?.user) {
        setShowPlansModal(false);
        setShowAuthModal(true);
      }
      return;
    }
    setIsCheckingOut(true);
    try {
      const res = await fetch(`${BACKEND_BASE_URL}/api/stripe/checkout`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...(session?.access_token ? { Authorization: `Bearer ${session.access_token}` } : {}),
        },
        body: JSON.stringify({ isAnnual, origin: window.location.origin }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok || !data?.url) throw new Error(data?.error || 'Error al crear sesión de pago');
      window.location.href = data.url;
    } catch (e: any) {
      setChatNotice(e?.message || 'No se pudo iniciar el pago.');
      setTimeout(() => setChatNotice(null), 4000);
      setIsCheckingOut(false);
    }
  };

  // Retorno de Stripe (?session_id + /success | /canceled): refrescar perfil
  // con reintentos (el webhook tarda segundos en escribir plan='hazak').
  const processBillingReturn = async () => {
    try {
      const path = window.location.pathname;
      const params = new URLSearchParams(window.location.search);
      const isSuccess = path.includes('success') || params.get('status') === 'success';
      const isCanceled = path.includes('canceled') || params.get('status') === 'canceled';
      if (!isSuccess && !isCanceled) return;
      const es = (locale || 'es').toLowerCase().startsWith('es');
      if (isCanceled) {
        setChatNotice(es ? 'Pago cancelado. Sigues en Free.' : 'Payment canceled. Still on Free.');
        setTimeout(() => setChatNotice(null), 4000);
      } else {
        for (let i = 0; i < 6; i++) {
          await new Promise((r) => setTimeout(r, 2500));
          if (session?.user) await fetchProfile(session.user.id);
          // fetchProfile actualiza userProfile async; revalidamos vía lectura directa
          try {
            if (!session?.user) break;
            const { data } = await supabase.from('profiles').select('plan').eq('id', session.user.id).single();
            if ((data as any)?.plan === 'hazak') break;
          } catch (_) {}
        }
        if (session?.user) await fetchProfile(session.user.id);
        setChatNotice(es ? '¡Bienvenido a XPi PRO!' : 'Welcome to XPi PRO!');
        setTimeout(() => setChatNotice(null), 5000);
      }
      window.history.replaceState({}, document.title, '/');
    } catch (_) {}
  };

  // ── Titulado LLM en segundo plano (paridad app_state: tras cada turno,
  // POST /api/chat/title y se actualiza título local + Supabase) ──
  const refreshTitleInBackground = (convId: string | null, userText: string, assistantText: string) => {
    if (!convId || convId.startsWith('conv-') || !session?.user || isGuestUser || isIncognito || !cloudHistoryEnabled) return;
    (async () => {
      try {
        const res = await fetch(`${BACKEND_BASE_URL}/api/chat/title`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            ...(session?.access_token ? { Authorization: `Bearer ${session.access_token}` } : {}),
          },
          body: JSON.stringify({
            conversationId: convId,
            messages: [
              { role: 'user', content: userText },
              { role: 'assistant', content: (assistantText || '').slice(0, 300) },
            ],
            locale: locale || 'es',
          }),
        });
        const data = await res.json().catch(() => ({}));
        const title = typeof data?.title === 'string' ? data.title.trim() : '';
        if (!title) return;
        setConversations((prev) => prev.map((c) => (c.id === convId ? { ...c, title } : c)));
        await supabase.from('conversations').update({ title }).eq('id', convId);
      } catch (_) {}
    })();
  };

  // ── Compartir respuesta (paridad share móvil: contenido + Play URL) ──
  const shareMessage = async (content: string) => {
    const es = (locale || 'es').toLowerCase().startsWith('es');
    const text = `${content}\n\n${es ? 'Descarga Exodo AI en Google Play:' : 'Download Exodo AI on Google Play:'}\nhttps://play.google.com/store/apps/details?id=com.behavior.exodo`;
    try {
      if (navigator.share) {
        await navigator.share({ title: 'Exodo AI', text });
        return;
      }
      throw new Error('no-share');
    } catch (_) {
      try {
        await navigator.clipboard.writeText(text);
        setChatNotice(es ? 'Respuesta copiada para compartir.' : 'Answer copied to share.');
        setTimeout(() => setChatNotice(null), 3000);
      } catch (_) {}
    }
  };

  // ── Editar mensaje propio (paridad startEditingMessage simplificada:
  // carga el texto en el composer para reenviarlo corregido) ──
  const editMessage = (msg: Message) => {
    setInput(msg.content);
    scrollToBottom();
    try { document.querySelector<HTMLTextAreaElement>('.composer-input')?.focus(); } catch (_) {}
  };
  // ── Ajustes de cuenta (paridad móvil: exportar datos / borrar cuenta) ──
  const exportMyData = async () => {
    setShowAccountMenu(false);
    setShowProfileMenu(false);
    try {
      const convs = conversations.filter((c) => !c.id.startsWith('conv-'));
      const rows: string[] = [];
      for (const c of convs) {
        const { data: msgs } = await supabase
          .from('messages')
          .select('role, content, created_at')
          .eq('conversation_id', c.id)
          .order('created_at');
        const body = (msgs || [])
          .map((m: any) => {
            const who = m.role === 'user' ? 'Tú' : 'Exodo';
            const time = m.created_at ? new Date(m.created_at).toLocaleString() : '';
            return `<p><strong>${who}</strong> <small>${time}</small></p><div>${(m.content || '').replace(/</g, '&lt;')}</div><hr>`;
          })
          .join('');
        rows.push(`<section><h2>${(c.title || '').replace(/</g, '&lt;')}</h2>${body}</section>`);
      }
      const html = `<!doctype html><html lang="es"><head><meta charset="utf-8"><title>Exodo — Mis datos</title>
<style>body{font-family:sans-serif;max-width:720px;margin:24px auto;padding:0 16px;background:#F5F2EB;color:#171615}h1{color:#C9933A}section{background:#fff;border-radius:12px;padding:16px;margin:16px 0}small{color:#9E9689}</style>
</head><body><h1>Exodo — Mis datos</h1><p>${convs.length} conversación(es) · ${new Date().toLocaleString()}</p>${rows.join('')}</body></html>`;
      const blob = new Blob([html], { type: 'text/html;charset=utf-8' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `exodo-datos-${new Date().toISOString().slice(0, 10)}.html`;
      a.click();
      URL.revokeObjectURL(url);
    } catch (e) {
      console.warn('Error exportando datos:', e);
    }
  };

  const deleteMyAccount = async () => {
    setShowAccountMenu(false);
    const confirmed = window.confirm('¿Borrar tu cuenta y TODOS tus datos (conversaciones, expedientes, perfil)? Esta acción es permanente y no se puede deshacer.');
    if (!confirmed) return;
    try {
      // RPC SECURITY DEFINER (007_delete_user_account.sql): purga profiles +
      // conversations + expedientes + auth.users. Igual que la app móvil.
      const { error } = await supabase.rpc('delete_user_account');
      if (error) throw error;
    } catch (e: any) {
      alert(`No se pudo borrar la cuenta: ${e?.message || e}. Intenta de nuevo.`);
      return;
    }
    try { await supabase.auth.signOut(); } catch (_) {}
    Object.keys(localStorage)
      .filter((k) => k.startsWith('exodo_'))
      .forEach((k) => localStorage.removeItem(k));
    window.location.reload();
  };

  // ── Perfil (paridad updateProfileDetails de app_state.dart) ──
  const saveProfile = async (fullName: string, nickname: string) => {
    if (!session?.user) return false;
    const name = fullName.trim();
    const nick = nickname.trim();
    const prev = userProfile;
    const updatedOnboarding = { ...(prev?.onboarding || {}), nickname: nick };
    setUserProfile({ ...(prev || {}), full_name: name, onboarding: updatedOnboarding });
    try {
      const { error } = await supabase
        .from('profiles')
        .update({ full_name: name, onboarding: updatedOnboarding })
        .eq('id', session.user.id);
      if (error) throw error;
      return true;
    } catch (e) {
      console.warn('Error guardando perfil:', e);
      setUserProfile(prev);
      return false;
    }
  };

  // ── Cancelar Pro (paridad cancelProPlan de app_state.dart) ──
  const cancelProPlan = async () => {
    if (!session?.user) return;
    const es = (locale || 'es').toLowerCase().startsWith('es');
    try {
      const { error } = await supabase.from('profiles').update({ plan: 'genesis' }).eq('id', session.user.id);
      if (error) throw error;
      setUserProfile((prev) => (prev ? { ...prev, plan: 'genesis' } : prev));
      setSelectedModel(EXODO_MODELS[0]);
      setChatNotice(es ? 'Has regresado al plan G1.1 Gratis' : 'You have returned to G1.1 Free plan');
    } catch (e) {
      setChatNotice(es ? 'No se pudo cancelar. Intenta de nuevo.' : 'Could not cancel. Try again.');
    }
    setTimeout(() => setChatNotice(null), 4000);
  };
  // FK cascade borra mensajes; resetea estado local + cachés web) ──
  // ── Limpiar historial (paridad clearHistory: borra conversations en nube,
  // FK cascade borra mensajes; resetea estado local + cachés web) ──
  const clearHistory = async () => {
    const confirmed = window.confirm('¿Borrar TODO tu historial de conversaciones? Esta acción no se puede deshacer.');
    if (!confirmed) return;
    try {
      if (session?.user) {
        const { error } = await supabase.from('conversations').delete().eq('user_id', session.user.id);
        if (error) throw error;
      }
    } catch (e: any) {
      alert(`No se pudo borrar el historial: ${e?.message || e}. Intenta de nuevo.`);
      return;
    }
    setConversations([]);
    setShowProfileMenu(false);
    handleCreateNewChat();
    localStorage.removeItem('exodo_web_temp_conv');
  };

  async function fetchMessages(convId: string) {
    try {
      const { data, error } = await supabase
        .from('messages')
        .select('*')
        .eq('conversation_id', convId)
        .order('created_at', { ascending: true });
      if (!error && data) {
        setMessages(data);
      }
    } catch (e) {
      console.warn('Error fetching messages:', e);
    }
  }

  const isNearBottom = () => {
    if (!messagesListRef.current) return true;
    const { scrollTop, scrollHeight, clientHeight } = messagesListRef.current;
    return scrollHeight - scrollTop - clientHeight < 160;
  };

  const scrollToBottom = (smooth: boolean = false) => {
    if (smooth) {
      messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
    } else {
      if (messagesListRef.current) {
        messagesListRef.current.scrollTop = messagesListRef.current.scrollHeight;
      } else {
        messagesEndRef.current?.scrollIntoView({ behavior: 'auto' });
      }
    }
  };

  const handleCreateNewChat = () => {
    setActiveConvId(null);
    setMessages([]);
    setInput('');
    setPendingAttachments([]);
    localStorage.removeItem('exodo_web_active_conv');
    localStorage.removeItem('exodo_web_temp_conv');
    setDrawerOpen(false);
  };

  // Sale de incógnito y limpia los mensajes efímeros (paridad exitIncognitoAndClear de app_state.dart)
  const exitIncognitoAndClear = () => {
    setIsIncognito(false);
    setMessages([]);
    setInput('');
    setPendingAttachments([]);
    setActiveConvId(null);
  };

  // Abre el menú lateral; si está en incógnito, sale y limpia los chats efímeros (paridad chat_screen.dart onDrawerChanged)
  const handleOpenDrawer = () => {
    if (isIncognito) {
      exitIncognitoAndClear();
    }
    setDrawerOpen(true);
  };

  // Alterna modo incógnito (paridad toggleIncognito de app_state.dart)
  const handleToggleIncognito = () => {
    const nextVal = !isIncognito;
    // La entrada/salida de Incógnito también cambia el tema → cross-fade suave
    applyThemeChange(() => {
      setIsIncognito(nextVal);
      if (nextVal) {
        setSelectedModel(EXODO_MODELS[0]);
      }
      // Limpia el stage efímero en memoria sin escribir en localStorage ni base de datos
      setMessages([]);
      setInput('');
      setPendingAttachments([]);
      setActiveConvId(null);
      if (!nextVal) {
        localStorage.removeItem('exodo_web_temp_conv');
        localStorage.removeItem('exodo_web_active_conv');
      }
    });
  };

  // Cambio dark↔light con cross-fade suave (misma sensación calmada que la app)
  const toggleTheme = () => {
    applyThemeChange(() => setTheme(theme === 'dark' ? 'light' : 'dark'));
  };

  const handleSendMessage = async (e?: React.FormEvent) => {
    if (e) e.preventDefault();
    if (isSendingRef.current) return;
    if ((!input.trim() && pendingAttachments.length === 0) || isStreaming) return;
    isSendingRef.current = true;

    // Paridad móvil (chat_screen: gate de tokens): si se acabó la cuota se
    // abre Planes (vibra) pero el mensaje SE ENVÍA igual.
    if (!isGuestUser && !isIncognito && tokensUsed >= tokensLimit) {
      try { navigator.vibrate(60); } catch (_) {}
      setShowPlansModal(true);
    }

    const userText = input.trim();
    const outgoingAttachments = pendingAttachments.map((a) => ({ mime_type: a.mime, file_name: a.name, base64: a.base64 }));
    const outgoingPreviews = pendingAttachments.map((a) => ({ name: a.name, mime: a.mime, preview: a.preview }));
    setInput('');
    setPendingAttachments([]);

    let currentConvId = activeConvId;

    // Si es un chat nuevo o temporal y hay cuenta real con historial en la nube,
    // crear la conversación real en DB primero. Invitado e incógnito:
    // sin persistencia en la nube (paridad guest/incognito móvil).
    const persistToCloud = !!session?.user && !isIncognito && !isGuestUser && cloudHistoryEnabled;
    if ((!currentConvId || currentConvId.startsWith('conv-')) && persistToCloud) {
      const titleSeed = userText || outgoingAttachments[0]?.file_name || 'Nueva conversación';
      const { data, error } = await supabase.from('conversations').insert({
        user_id: session.user.id,
        title: titleSeed.length > 35 ? titleSeed.substring(0, 35) + '...' : titleSeed,
        model_plan: selectedModel.plan || 'genesis',
        is_incognito: false
      }).select().single();

      if (!error && data) {
        currentConvId = data.id;
        setActiveConvId(currentConvId);
        if (currentConvId) {
          localStorage.setItem('exodo_web_active_conv', currentConvId);
        }
        localStorage.removeItem('exodo_web_temp_conv');
        
        setConversations((prev) => {
          const filtered = prev.filter((c) => activeConvId ? c.id !== activeConvId : true);
          return [data, ...filtered];
        });
      }
    } else if (!currentConvId && !isIncognito) {
      // Invitado: chat puramente local
      const guestConvId = `conv-${Date.now()}`;
      currentConvId = guestConvId;
      setActiveConvId(guestConvId);
      const newConv: Conversation = {
        id: guestConvId,
        user_id: session?.user?.id || 'guest',
        title: (userText || 'Nueva conversación').slice(0, 35),
        model: selectedModel.id,
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString()
      };
      setConversations((prev) => [newConv, ...prev.filter((c) => !c.id.startsWith('conv-'))]);
      localStorage.setItem('exodo_web_active_conv', guestConvId);
      localStorage.setItem('exodo_web_temp_conv', JSON.stringify(newConv));
    }

    const userMsg: Message = {
      id: `msg-user-${Date.now()}`,
      conversation_id: isIncognito ? 'incognito' : (currentConvId || 'default'),
      role: 'user',
      content: userText,
      created_at: new Date().toISOString(),
      attachments: outgoingPreviews.length > 0 ? outgoingPreviews : undefined
    };

    const thinkingMsg: Message = {
      id: `msg-thinking-${Date.now()}`,
      conversation_id: isIncognito ? 'incognito' : (currentConvId || 'default'),
      role: 'assistant',
      content: 'Pensando...',
      created_at: new Date().toISOString(),
      isThinking: true
    };

    // Paridad móvil (sendHistoryWindow): enviar la ventana de turnos previos
    // para que el LLM tenga memoria continua y no repita saludos ante cada mensaje.
    const historyPayload = messages
      .filter((m) => !m.isThinking && typeof m.content === 'string' && m.content.trim().length > 0)
      .map((m) => ({ role: m.role, content: m.content.trim() }))
      .slice(-20);

    setMessages((prev) => [...prev, userMsg, thinkingMsg]);
    setIsStreaming(true);
    setTimeout(() => scrollToBottom(true), 50);
    let finalAssistantText = '';

    try {
      const backendEndpoint = `${BACKEND_BASE_URL}/api/chat`;

      const res = await fetch(backendEndpoint, {
        method: 'POST',
        headers: { 
          'Content-Type': 'application/json',
          ...(session?.access_token ? { Authorization: `Bearer ${session.access_token}` } : {})
        },
        body: JSON.stringify({
          message: userText,
          conversationId: persistToCloud && currentConvId && !currentConvId.startsWith('conv-') ? currentConvId : undefined,
          history: historyPayload,
          model_override: selectedModel.id,
          isIncognito: isIncognito || !cloudHistoryEnabled,
          locale: locale || 'es',
          attachments: outgoingAttachments.length > 0 ? outgoingAttachments : undefined
        })
      });

      if (res.ok && res.body) {
        const reader = res.body.getReader();
        const decoder = new TextDecoder();
        let accumulatedText = '';
        let hasStartedAssistantMessage = false;
        let isDegradedResponse = false;
        const assistantMsgId = `msg-asst-${Date.now()}`;

        let sseBuffer = '';
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;

          sseBuffer += decoder.decode(value, { stream: true });
          const lines = sseBuffer.split('\n');
          sseBuffer = lines.pop() || '';

          for (const rawLine of lines) {
            const line = rawLine.trim();
            if (!line.startsWith('data:')) continue;
            const dataStr = line.replace(/^data:\s*/, '').trim();
            if (dataStr === '[DONE]') continue;
            try {
              const parsed = JSON.parse(dataStr);
              if (parsed.type === 'meta') {
                if (parsed.isDegraded) {
                  isDegradedResponse = true;
                  if (hasStartedAssistantMessage) {
                    setMessages((prev) =>
                      prev.map((m) => (m.id === assistantMsgId ? { ...m, isDegraded: true } : m))
                    );
                  }
                }
              } else if (parsed.type === 'notice') {
                const noticeText: Record<string, string> = {
                  image_login_required: 'Inicia sesión para generar imágenes.',
                  image_daily_limit_reached: 'Límite diario de imágenes alcanzado.',
                  image_generation_failed: 'No se pudo generar la imagen.',
                  web_searching: 'Consultando la web…',
                };
                setChatNotice(noticeText[parsed.code] || parsed.code || 'Aviso de Exodo.');
                setTimeout(() => setChatNotice(null), 5000);
              } else if (parsed.type === 'generating_image') {
                setChatNotice('Sintetizando imagen...');
              } else if (parsed.type === 'done') {
                finalAssistantText = parsed.content || accumulatedText;
                const sources = Array.isArray(parsed.sources) ? parsed.sources : [];
                if (!hasStartedAssistantMessage) {
                  hasStartedAssistantMessage = true;
                  setMessages((prev) => [
                    ...prev.filter((m) => !m.isThinking),
                    {
                      id: assistantMsgId,
                      conversation_id: isIncognito ? 'incognito' : (currentConvId || 'default'),
                      role: 'assistant',
                      content: finalAssistantText,
                      sources,
                      isDegraded: isDegradedResponse,
                      created_at: new Date().toISOString()
                    }
                  ]);
                } else {
                  setMessages((prev) =>
                    prev.map((m) =>
                      m.id === assistantMsgId
                        ? {
                            ...m,
                            content: finalAssistantText,
                            sources,
                            isDegraded: isDegradedResponse || m.isDegraded
                          }
                        : m
                    )
                  );
                }
                if (isNearBottom()) {
                  scrollToBottom(false);
                }
              } else if (parsed.content) {
                accumulatedText += parsed.content;
                if (!hasStartedAssistantMessage) {
                  hasStartedAssistantMessage = true;
                  setMessages((prev) => [
                    ...prev.filter((m) => !m.isThinking),
                    {
                      id: assistantMsgId,
                      conversation_id: isIncognito ? 'incognito' : (currentConvId || 'default'),
                      role: 'assistant',
                      content: accumulatedText,
                      isDegraded: isDegradedResponse,
                      created_at: new Date().toISOString()
                    }
                  ]);
                } else {
                  setMessages((prev) =>
                    prev.map((m) =>
                      m.id === assistantMsgId ? { ...m, content: accumulatedText } : m
                    )
                  );
                }
                if (isNearBottom()) {
                  scrollToBottom(false);
                }
              }
            } catch (_) {}
          }
        }
      } else {
        const errorData = await res.json().catch(() => null);
        throw new Error(errorData?.error || `Error del servidor (${res.status})`);
      }
    } catch (err: any) {
      console.error('[Exodo Chat Error]:', err);
      setMessages((prev) => prev.filter((m) => !m.isThinking));
      const errMsg = err?.message || 'Error de conexión con Exodo.';
      setChatNotice(errMsg);
      setTimeout(() => setChatNotice(null), 4000);
    } finally {
      isSendingRef.current = false;
      setIsStreaming(false);
      // Refrescar el medidor de tokens tras cada turno (paridad móvil).
      fetchTodayUsage();
      // Titulado LLM en segundo plano (paridad app_state).
      refreshTitleInBackground(currentConvId, userText, finalAssistantText);
    }
  };

  // Nombre visible del idioma actual (paridad _currentLocaleFlag móvil).
  const localeDisplayName = (() => {
    const map: Record<string, string> = {
      es: 'Español (Latinoamérica)', en: 'English (US)', en_GB: 'English (UK)',
      pt_BR: 'Português (Brasil)', pt: 'Português (Portugal)', fr: 'Français',
      ht: 'Kreyòl Ayisyen', it: 'Italiano', de: 'Deutsch', ru: 'Русский',
      zh: '中文', ja: '日本語', ar: 'العربية', ko: '한국어', hi: 'हिन्दी',
    };
    if (!locale || locale.startsWith('es')) return map.es;
    return map[locale] || map[locale.split(/[-_]/)[0]] || 'English (US)';
  })();

  const getUserDisplayName = () => {
    if (userProfile?.full_name && userProfile.full_name.trim().length > 0) {
      return userProfile.full_name.trim();
    }
    if (session?.user?.email) {
      const emailName = session.user.email.split('@')[0];
      return emailName.charAt(0).toUpperCase() + emailName.slice(1);
    }
    return 'User';
  };

  const getExodoGreeting = () => {
    if (isIncognito) return 'Modo Incógnito';
    const name = getUserDisplayName();
    const hour = new Date().getHours();
    if (hour < 12) return `Buenos días, ${name}`;
    if (hour < 18) return `Buenas tardes, ${name}`;
    return `Buenas noches, ${name}`;
  };

  // Adjuntos pendientes (paridad ChatComposer móvil: imágenes a visión,
  // documentos a extracción de texto; el backend los recibe en `attachments`
  // como {mime_type, file_name, base64}).
  const [pendingAttachments, setPendingAttachments] = useState<Array<{ name: string; mime: string; base64: string; preview?: string }>>([]);
  const fileInputRef = React.useRef<HTMLInputElement | null>(null);
  // Voz (paridad composer móvil: mic en reposo/vacío → grabar → transcribir
  // vía POST /api/voice/transcribe e insertar el texto en el composer).
  const [isRecording, setIsRecording] = useState(false);
  const [isTranscribing, setIsTranscribing] = useState(false);
  const mediaRecorderRef = React.useRef<MediaRecorder | null>(null);
  const audioChunksRef = React.useRef<Blob[]>([]);

  const voiceEndpoint = (path: string) => `${BACKEND_BASE_URL}${path}`;

  // Los endpoints de voz exigen JWT válido (C9 backend: sin token → 401).
  // Paridad móvil: el visitante sin sesión entra como invitado anónimo de
  // Supabase antes de transcribir; si el canje falla, el 401 muestra su aviso.
  const ensureVoiceToken = async (): Promise<string | null> => {
    if (session?.access_token) return session.access_token;
    try {
      const { data } = await supabase.auth.signInAnonymously();
      return data?.session?.access_token || null;
    } catch (_) {
      return null;
    }
  };

  const startRecording = async () => {
    if (isRecording || isTranscribing || isStreaming) return;
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const rec = new MediaRecorder(stream, { mimeType: MediaRecorder.isTypeSupported('audio/webm') ? 'audio/webm' : undefined });
      audioChunksRef.current = [];
      rec.ondataavailable = (e) => { if (e.data && e.data.size > 0) audioChunksRef.current.push(e.data); };
      rec.onstop = () => {
        stream.getTracks().forEach((t) => t.stop());
        transcribeRecording();
      };
      mediaRecorderRef.current = rec;
      rec.start();
      setIsRecording(true);
    } catch (_) {
      setChatNotice('No se pudo acceder al micrófono.');
      setTimeout(() => setChatNotice(null), 3000);
    }
  };

  const stopRecording = () => {
    try { mediaRecorderRef.current?.stop(); } catch (_) {}
    setIsRecording(false);
  };

  const transcribeRecording = async () => {
    const chunks = audioChunksRef.current;
    audioChunksRef.current = [];
    if (chunks.length === 0) return;
    setIsTranscribing(true);
    const es = !(locale || 'es').toLowerCase().startsWith('en');
    try {
      const blob = new Blob(chunks, { type: 'audio/webm' });
      const form = new FormData();
      form.append('file', blob, 'nota.webm');
      const token = await ensureVoiceToken();
      const res = await fetch(voiceEndpoint('/api/voice/transcribe'), {
        method: 'POST',
        headers: { ...(token ? { Authorization: `Bearer ${token}` } : {}) },
        body: form,
      });
      const data = await res.json().catch(() => ({}));
      const text = typeof data?.text === 'string' ? data.text.trim() : '';
      if (text) setInput((prev) => (prev ? `${prev} ${text}` : text));
      else if (res.status === 401 || data?.error === 'authentication_required') {
        setChatNotice(es ? 'Inicia sesión para usar el dictado por voz.' : 'Sign in to use voice dictation.');
        setTimeout(() => setChatNotice(null), 3000);
      } else {
        setChatNotice(es ? 'No se entendió el audio. Intenta de nuevo.' : "We couldn't understand the audio. Try again.");
        setTimeout(() => setChatNotice(null), 3000);
      }
    } catch (_) {
      setChatNotice(es ? 'No se pudo transcribir el audio.' : 'Audio transcription failed.');
      setTimeout(() => setChatNotice(null), 3000);
    } finally {
      setIsTranscribing(false);
    }
  };

  const pickAttachments = () => {
    fileInputRef.current?.click();
  };

  const onFilesPicked = async (files: FileList | null) => {
    if (!files || files.length === 0) return;
    const MAX_FILES = 3;
    const MAX_BYTES = 5 * 1024 * 1024;
    const room = Math.max(0, MAX_FILES - pendingAttachments.length);
    const chosen = Array.from(files).slice(0, room);
    const read: Array<{ name: string; mime: string; base64: string; preview?: string }> = [];
    for (const f of chosen) {
      if (f.size > MAX_BYTES) {
        setChatNotice(`"${f.name}" supera 5 MB y no se adjuntó.`);
        setTimeout(() => setChatNotice(null), 4000);
        continue;
      }
      const base64: string = await new Promise<string>((resolve, reject) => {
        const r = new FileReader();
        r.onload = () => resolve(String(r.result || ''));
        r.onerror = reject;
        r.readAsDataURL(f);
      }).catch(() => '');
      if (!base64) continue;
      const b64 = base64.includes(',') ? base64.split(',')[1] : base64;
      read.push({
        name: f.name,
        mime: f.type || 'application/octet-stream',
        base64: b64,
        preview: f.type.startsWith('image/') ? base64 : undefined,
      });
    }
    if (read.length > 0) setPendingAttachments((prev) => [...prev, ...read].slice(0, MAX_FILES));
  };

  const renderChatComposer = (isPinned: boolean = false) => {
    return (
    <div style={{ width: '100%', maxWidth: 820, margin: '0 auto', position: 'relative', display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
      {showUpgradeBanner && !isIncognito && userProfile?.plan !== 'hazak' && (
        <div style={{
          width: 'min(90%, 330px)',
          padding: '3px 14px 22px 14px',
          position: 'relative' as const,
          zIndex: 1,
          marginBottom: -19,
          background: 'var(--banner-bg, #252525)',
          border: '1px solid var(--banner-border, transparent)',
          borderBottom: 'none',
          borderRadius: '16px 16px 0 0',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          flexWrap: 'nowrap',
          gap: '8px',
          boxSizing: 'border-box' as const,
          textAlign: 'center'
        }}>
          <span style={{ fontFamily: 'AnthropicSans, sans-serif', fontSize: '11.5px', fontWeight: 600, color: 'var(--banner-text, #F5F2EB)', lineHeight: 1.1 }}>
            {locale?.toLowerCase().startsWith('en') ? 'More capacity with XPi PRO' : 'Más capacidad con XPi PRO'}
          </span>
          <button
            type="button"
            onClick={() => {
              if (isGuestUser || !session?.user) {
                setShowAuthModal(true);
                return;
              }
              setShowPlansModal(true);
            }}
            style={{
              background: 'none',
              border: 'none',
              cursor: 'pointer',
              padding: '2px 4px',
              fontFamily: 'AnthropicSans, sans-serif',
              fontSize: '11.5px',
              fontWeight: 700,
              color: 'var(--amber-exodo)',
              display: 'inline-flex',
              alignItems: 'center'
            }}
          >
            {locale?.toLowerCase().startsWith('en') ? 'Upgrade' : 'Actualizar'}
          </button>
          <button
            type="button"
            onClick={() => setShowUpgradeBanner(false)}
            style={{
              background: 'none',
              border: 'none',
              cursor: 'pointer',
              padding: '2px 4px',
              display: 'flex',
              alignItems: 'center'
            }}
            title={locale?.toLowerCase().startsWith('en') ? 'Dismiss' : 'Cerrar'}
          >
            <X size={14} color="var(--banner-text, #F5F2EB)" />
          </button>
        </div>
      )}
      <div style={{
        width: '100%',
        position: 'relative',
        zIndex: 2,
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center'
      }}>
        <form 
          className="composer-container" 
          onSubmit={handleSendMessage} 
          style={{
            width: '100%', 
            maxWidth: 820,
            margin: '0 auto',
            background: 'var(--surface-input)',
            border: 'none',
            outline: 'none',
            boxShadow: 'var(--shadow-composer, none)',
            borderRadius: 24,
            padding: isPinned ? '14px 20px 10px 20px' : '18px 20px 14px 20px',
            display: 'flex',
            flexDirection: 'column',
            transition: 'background 0.25s ease, box-shadow 0.25s ease'
          }}
        >
          {pendingAttachments.length > 0 && (
            <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', padding: '0 6px 10px 6px' }}>
              {pendingAttachments.map((a, i) => (
                <div key={`${a.name}-${i}`} style={{ position: 'relative', width: 56, height: 56, borderRadius: 12, overflow: 'hidden', background: 'var(--surface-card)', border: '1px solid var(--border-color)', display: 'flex', alignItems: 'center', justifyContent: 'center' }} title={a.name}>
                  {a.preview ? (
                    <img src={a.preview} alt={a.name} style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                  ) : (
                    <span style={{ fontSize: '0.6rem', color: 'var(--text-secondary)', padding: 4, textAlign: 'center', overflow: 'hidden' }}>{a.name}</span>
                  )}
                  <button
                    type="button"
                    onClick={() => setPendingAttachments((prev) => prev.filter((_, j) => j !== i))}
                    style={{ position: 'absolute', top: 2, right: 2, width: 18, height: 18, borderRadius: '50%', background: 'rgba(0,0,0,0.65)', color: '#fff', border: 'none', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 0 }}
                    title="Quitar"
                  >
                    <X size={12} />
                  </button>
                </div>
              ))}
            </div>
          )}
          <div style={{ position: 'relative', width: '100%', display: 'flex' }}>
            <TextareaAutosize
              ref={textareaRef as any}
              className="composer-input"
              placeholder={locale?.toLowerCase().startsWith('en') ? 'Ask Exodo...' : 'Habla con Exodo...'}
              value={input}
              onChange={(e) => setInput(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter' && !e.shiftKey) {
                  e.preventDefault();
                  handleSendMessage();
                }
              }}
              minRows={1}
              maxRows={12}
              onHeightChange={(height) => {
                setIsComposerScrollable(height >= 260);
                if (messagesListRef.current) {
                  const { scrollTop, scrollHeight, clientHeight } = messagesListRef.current;
                  if (scrollHeight - scrollTop - clientHeight < 150) {
                    messagesEndRef.current?.scrollIntoView({ behavior: 'auto', block: 'end' });
                  }
                }
              }}
              style={{
                width: '100%',
                background: 'transparent',
                border: 'none',
                outline: 'none',
                boxShadow: 'none',
                color: 'var(--text-primary)',
                fontSize: '16px',
                fontFamily: 'var(--font-sans)',
                resize: 'none',
                padding: '10px 6px',
                paddingRight: isComposerScrollable ? '26px' : '6px',
                overflowY: isComposerScrollable ? 'auto' : 'hidden'
              }}
            />
            {isComposerScrollable && (
              <div style={{ position: 'absolute', right: -5, top: 4, bottom: 4, width: 16, display: 'flex', flexDirection: 'column', justifyContent: 'space-between', alignItems: 'center', pointerEvents: 'none', zIndex: 10 }}>
                <button
                  type="button"
                  onClick={() => textareaRef.current?.scrollTo({ top: 0, behavior: 'smooth' })}
                  style={{ pointerEvents: 'auto', width: 16, height: 16, background: 'var(--surface-input)', border: 'none', borderRadius: '4px', color: '#505050', display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer', opacity: 0.9 }}
                  title="Ir al inicio"
                >
                  <ChevronUp size={16} />
                </button>
                <button
                  type="button"
                  onClick={() => textareaRef.current?.scrollTo({ top: textareaRef.current.scrollHeight, behavior: 'smooth' })}
                  style={{ pointerEvents: 'auto', width: 16, height: 16, background: 'var(--surface-input)', border: 'none', borderRadius: '4px', color: '#505050', display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer', opacity: 0.9 }}
                  title="Ir al final"
                >
                  <ChevronDown size={16} />
                </button>
              </div>
            )}
          </div>

          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              <button 
                type="button" 
                className="icon-btn" 
                style={{ width: 36, height: 36, borderRadius: '50%', background: 'var(--model-chip-bg)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}
                title="Adjuntar archivos"
                onClick={pickAttachments}
              >
                <Plus size={20} color="var(--chip-icon-color)" />
              </button>
              <input
                ref={fileInputRef}
                type="file"
                multiple
                accept="image/*,.pdf,.txt,.md,.csv"
                style={{ display: 'none' }}
                onChange={(e) => { onFilesPicked(e.target.files); e.target.value = ''; }}
              />

              <ModelSelector
                selectedModel={selectedModel}
                onSelectModel={(m) => setSelectedModel(m)}
                isOpen={showModelSelector}
                onToggleOpen={() => setShowModelSelector(!showModelSelector)}
                onClose={() => setShowModelSelector(false)}
                userPlan={userProfile?.plan}
                isIncognito={isIncognito}
                isGuestUser={isGuestUser || !session?.user}
                onRequireUpgrade={() => setShowPlansModal(true)}
                locale={locale}
                theme={effectiveTheme}
              />
            </div>

            {((input.trim() || pendingAttachments.length > 0) && !isRecording && !isTranscribing) ? (
            <button
              type="submit"
              disabled={isStreaming}
              style={{
                width: 38,
                height: 38,
                borderRadius: '50%',
                background: !isStreaming ? 'var(--send-btn-bg)' : 'var(--send-btn-disabled)',
                color: !isStreaming ? 'var(--send-btn-color)' : 'var(--text-muted)',
                border: 'none',
                outline: 'none',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                cursor: !isStreaming ? 'pointer' : 'default',
                transition: 'background 0.2s ease, color 0.2s ease'
              }}
              title="Enviar"
            >
              <ArrowUp size={19} strokeWidth={2.5} />
            </button>
            ) : (
            <button
              type="button"
              onClick={() => { if (isRecording) stopRecording(); else startRecording(); }}
              disabled={isTranscribing || isStreaming}
              style={{
                width: 38, height: 38, background: 'transparent', border: 'none', outline: 'none',
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                cursor: (isTranscribing || isStreaming) ? 'default' : 'pointer', padding: 8,
              }}
              title={isRecording ? 'Detener y transcribir' : isTranscribing ? 'Transcribiendo...' : 'Dictar por voz'}
            >
              <Mic
                size={26}
                color={isRecording || isTranscribing ? 'var(--amber-exodo)' : 'var(--text-secondary)'}
                style={isRecording ? { animation: 'micPulse 1.2s ease-in-out infinite' } : undefined}
              />
            </button>
            )}
          </div>
        </form>
        <div style={{ marginTop: isPinned ? 4 : 10, marginBottom: isPinned ? 2 : 0, textAlign: 'center', fontFamily: 'AnthropicSans, sans-serif', fontSize: '12px', color: 'var(--text-secondary)' }}>
          {locale?.toLowerCase().startsWith('en')
            ? 'Exodo is AI and may make mistakes. Please verify responses.'
            : 'Exodo es IA y puede cometer errores. Por favor verifica las respuestas.'}
        </div>
      </div>
    </div>
  );
  };

  return (
    <div className="app-container">
      {/* 1. Barra lateral de iconos sin textos (Estilo Gemini Web: visible y clickeable) */}
      <SidebarRail
        isDrawerOpen={drawerOpen}
        onToggleDrawer={() => setDrawerOpen((prev) => !prev)}
        // Sin sesión también cuenta como invitado: si no, un visitante fresco
        // ve el botón Expedientes y sus queries a Supabase fallan siempre.
        isGuestUser={isGuestUser || !session?.user}
        userProfile={userProfile}
        userEmail={session?.user?.email}
        onOpenAuth={() => setShowAuthModal(true)}
        onOpenSettings={() => setShowAccountMenu(true)}
        onOpenExpedientes={() => setShowExpedientes(true)}
        onStartSearch={() => setDrawerOpen(true)}
        locale={locale}
      />

      {/* 2. Drawer Menu Deslizable (con nombres de opciones y conversaciones al tocar menú) */}
      <DrawerMenu
        isOpen={drawerOpen}
        onClose={() => setDrawerOpen(false)}
        conversations={conversations}
        activeConvId={activeConvId}
        onSelectConversation={(id) => {
          if (isIncognito) {
            setIsIncognito(false);
          }
          setActiveConvId(id);
          localStorage.setItem('exodo_web_active_conv', id);
          localStorage.removeItem('exodo_web_temp_conv');
          fetchMessages(id);
        }}
        onCreateNewChat={handleCreateNewChat}
        theme={effectiveTheme}
        onToggleTheme={toggleTheme}
        isIncognito={isIncognito}
        onToggleIncognito={handleToggleIncognito}
        isGuestUser={isGuestUser}
        userProfile={userProfile}
        userEmail={session?.user?.email}
        onOpenAuth={() => setShowAuthModal(true)}
        onOpenSettings={() => setShowAccountMenu(true)}
        onOpenExpedientes={() => setShowExpedientes(true)}
        onRenameConversation={renameConversation}
        onToggleStarConversation={toggleStarred}
        onDeleteConversation={deleteConversation}
        onSearchMessages={async (q) => {
          try {
            const { data } = await supabase
              .from('messages')
              .select('conversation_id')
              .ilike('content', `%${q.replace(/[%_]/g, '')}%`)
              .limit(100);
            return (data || []).map((r: any) => r.conversation_id).filter(Boolean);
          } catch (_) {
            return [];
          }
        }}
        locale={locale}
      />

      {/* 3. Área Principal de Chat Exacta a Móvil / Claude Centrado */}
      <main className={`chat-main ${isIncognito ? 'incognito-mode' : ''}`}>
        {/* Barra superior responsiva al zoom (solo iconos derechos ya que menú está en la barra lateral) */}
        <header className="chat-header-bar">
          <button
            type="button"
            className="icon-btn header-hamburger"
            onClick={handleOpenDrawer}
            title="Menú"
          >
            <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-start', gap: 5, padding: '4px 2px' }}>
              <div style={{ width: 20, height: 2, background: 'var(--text-primary)', borderRadius: 1 }} />
              <div style={{ width: 20, height: 2, background: 'var(--text-primary)', borderRadius: 1 }} />
              <div style={{ width: 12, height: 2, background: 'var(--text-primary)', borderRadius: 1 }} />
            </div>
          </button>

          {isIncognito ? (
            <>
              <div style={{ flex: 1, textAlign: 'center', fontSize: '16px', fontWeight: 600, color: 'var(--text-primary)', letterSpacing: '-0.2px', fontFamily: 'AnthropicSans, sans-serif' }}>
                {locale?.toLowerCase().startsWith('en') ? 'Incognito' : 'Incógnito'}
              </div>
              <button
                type="button"
                className="icon-btn"
                onClick={handleToggleIncognito}
                title={locale?.toLowerCase().startsWith('en') ? 'Exit incognito' : 'Salir de incógnito'}
              >
                <X size={21} />
              </button>
            </>
          ) : (
            <>
              <div style={{ flex: 1 }} />
              <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                <button
                  type="button"
                  className="icon-btn"
                  onClick={handleCreateNewChat}
                  title="Nuevo chat"
                >
                  <MessageSquare size={21} />
                </button>

                <button
                  type="button"
                  className="icon-btn"
                  onClick={toggleTheme}
                  title="Cambiar tema"
                >
                  {theme === 'dark' ? <Sun size={21} /> : <Moon size={21} />}
                </button>

                <button
                  type="button"
                  className="icon-btn"
                  onClick={handleToggleIncognito}
                  title="Modo Incógnito"
                >
                  <div
                    className="mask-icon-incognito"
                    style={{
                      width: 21,
                      height: 21,
                      backgroundColor: 'var(--text-secondary)'
                    }}
                  />
                </button>
              </div>
            </>
          )}
        </header>

        {isInitializing ? (
          <div style={{ flex: 1 }} />
        ) : messages.length === 0 ? (
          <div className="welcome-center">
            {/* Paridad chat_stage móvil: saludo centrado 22px bold (2 líneas)
                + watermark debajo (40% ancho, aspecto 7.02, gap 16).
                En modo incógnito: Solo disclaimer centrado, sin saludo ni watermark de Exodo */}
            <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', marginBottom: 'clamp(28px, 5vh, 44px)', padding: '0 24px', flexShrink: 0, width: '100%' }}>
              {!isIncognito ? (
                <>
                  <div className="greeting-text-exodo" style={{ textAlign: 'center', maxWidth: '100%', overflow: 'hidden', display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical' }}>
                    {getExodoGreeting()}
                  </div>
                  <img
                    src={effectiveTheme === 'dark' ? '/watermark2.png' : '/watermark1.png'}
                    alt=""
                    draggable={false}
                    style={{
                      width: 'min(22vw, 170px)',
                      aspectRatio: '7.0208',
                      objectFit: 'contain',
                      marginTop: 12,
                      pointerEvents: 'none',
                      userSelect: 'none',
                      opacity: 0.9,
                    }}
                  />
                </>
              ) : (
                <div
                  style={{
                    fontFamily: 'AnthropicSans, sans-serif',
                    fontSize: '14px',
                    fontWeight: 400,
                    color: 'var(--text-secondary)',
                    textAlign: 'center',
                    maxWidth: 480,
                    lineHeight: 1.4,
                    letterSpacing: '-0.1px',
                    padding: '0 24px',
                  }}
                >
                  {locale?.toLowerCase().startsWith('en')
                    ? 'Incognito chats are not saved to history.'
                    : 'Los chats de incógnito no se guardan en el historial.'}
                </div>
              )}
            </div>

            {/* Cajón de escritura exacto a móvil (#252525 con selector de modelos) */}
            {renderChatComposer(false)}
          </div>
        ) : (
          <>
            <div className="messages-list" ref={messagesListRef} onScroll={handleScroll}>
              <div className="messages-wrapper">
                {messages.map((msg, index) => {
                  if (msg.role === 'assistant' && !msg.content.trim() && !msg.isThinking) return null;
                  const isThisMsgStreaming = isStreaming && index === messages.length - 1;

                  return (
                  <div key={msg.id} className={`msg-row ${msg.role}`}>
                    <div style={{ display: 'flex', flexDirection: 'column', alignItems: msg.role === 'user' ? 'flex-end' : 'flex-start', maxWidth: msg.role === 'user' ? '82%' : '100%', width: msg.role === 'assistant' ? '100%' : 'fit-content' }}>
                      {/* Paridad móvil: contenido vacío + adjuntos = solo adjuntos, sin marco */}
                      {!(msg.role === 'user' && !msg.content.trim() && msg.attachments && msg.attachments.length > 0) && (
                      <div className="msg-bubble markdown-body">
                        {msg.isThinking ? (
                          <ThinkingIndicator />
                        ) : msg.role === 'assistant' ? (
                          <ArtifactMessageBody
                            content={msg.content}
                            isStreaming={isThisMsgStreaming}
                            renderMarkdown={(text) => (
                              <ReactMarkdown remarkPlugins={[remarkGfm]} components={markdownComponents}>
                                {text}
                              </ReactMarkdown>
                            )}
                          />
                        ) : (
                          <ReactMarkdown remarkPlugins={[remarkGfm]} components={markdownComponents}>
                            {msg.content}
                          </ReactMarkdown>
                        )}
                      </div>
                      )}

                      {msg.role === 'user' && msg.attachments && msg.attachments.length > 0 && (
                        <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', marginTop: msg.content.trim() ? 8 : 0, maxWidth: '82%', justifyContent: 'flex-end' }}>
                          {msg.attachments.map((a, i) => (
                            a.preview ? (
                              <div key={i} style={{ width: 72, height: 72, borderRadius: 14, overflow: 'hidden' }} title={a.name}>
                                <img src={a.preview} alt={a.name} style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                              </div>
                            ) : (
                              <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 6, padding: '8px 12px 8px 8px', borderRadius: 10, background: 'rgba(128,128,128,0.15)' }} title={a.name}>
                                <span style={{ fontSize: '13px', color: 'var(--text-primary)', fontFamily: 'Inter, sans-serif', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', maxWidth: 140 }}>{a.name}</span>
                              </div>
                            )
                          ))}
                        </div>
                      )}

                      {msg.role === 'assistant' && msg.isDegraded && (
                        <div className="eco-notice">
                          Modo Eco: cuota diaria de alta potencia agotada — respondiendo con el modelo ligero hasta las 12:00 AM.
                        </div>
                      )}

                      {msg.role === 'assistant' && (() => {
                        const vs = validSourcesOf(msg);
                        if (vs.length === 0) return null;
                        const label = getSourceLabels(locale).title;
                        return (
                          <button
                            type="button"
                            className="sources-capsule"
                            onClick={() => setOpenSourcesId(msg.id)}
                          >
                            <span className="sources-capsule-label">
                              {vs.length > 1 ? `${label} · ${vs.length}` : label}
                            </span>
                            <span
                              className="sources-avatar-stack"
                              style={{ width: Math.min(vs.length, 4) * 12 + 8 }}
                            >
                              {vs.slice(0, 4).map((s, i) => (
                                <span
                                  key={`${s.url}-${i}`}
                                  className="source-avatar"
                                  style={{
                                    left: i * 12,
                                    background: SOURCE_CIRCLE_COLORS[i % SOURCE_CIRCLE_COLORS.length]
                                  }}
                                >
                                  {sourceInitials(s)}
                                </span>
                              ))}
                            </span>
                          </button>
                        );
                      })()}
                      
                      {msg.role === 'user' && (
                        <div className="user-msg-actions">
                          <span>{new Date(msg.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</span>
                          <button onClick={() => editMessage(msg)} title="Editar">
                            <Edit2 size={13} />
                          </button>
                          <button onClick={() => navigator.clipboard.writeText(msg.content)} title="Copiar">
                            <div style={{ width: 13, height: 13, backgroundColor: 'currentColor', WebkitMaskImage: 'url(/copy-2-svgrepo-com.png)', WebkitMaskSize: 'contain', WebkitMaskRepeat: 'no-repeat', maskImage: 'url(/copy-2-svgrepo-com.png)', maskSize: 'contain', maskRepeat: 'no-repeat' }} />
                          </button>
                        </div>
                      )}

                      {msg.role === 'assistant' && !msg.isThinking && !isThisMsgStreaming && msg.content.trim().length > 0 && msg.id !== 'welcome-1' && (
                        <div className="ai-actions-bar">
                          <button className="action-btn" onClick={() => navigator.clipboard.writeText(msg.content)} title="Copiar">
                            <div style={{ width: 16, height: 16, backgroundColor: 'var(--text-secondary)', WebkitMaskImage: 'url(/copy-2-svgrepo-com.png)', WebkitMaskSize: 'contain', WebkitMaskRepeat: 'no-repeat', maskImage: 'url(/copy-2-svgrepo-com.png)', maskSize: 'contain', maskRepeat: 'no-repeat' }} />
                          </button>
                          <button className="action-btn" onClick={() => setFeedbackTarget({ msg, isLike: true })} title="Me gusta">
                            <div style={{ width: 16, height: 16, backgroundColor: 'var(--text-secondary)', WebkitMaskImage: 'url(/like-1-svgrepo-com.png)', WebkitMaskSize: 'contain', WebkitMaskRepeat: 'no-repeat', maskImage: 'url(/like-1-svgrepo-com.png)', maskSize: 'contain', maskRepeat: 'no-repeat' }} />
                          </button>
                          <button className="action-btn" onClick={() => setFeedbackTarget({ msg, isLike: false })} title="No me gusta">
                            <div style={{ width: 16, height: 16, backgroundColor: 'var(--text-secondary)', WebkitMaskImage: 'url(/like-1-svgrepo-com.png)', WebkitMaskSize: 'contain', WebkitMaskRepeat: 'no-repeat', maskImage: 'url(/like-1-svgrepo-com.png)', maskSize: 'contain', maskRepeat: 'no-repeat', transform: 'scaleY(-1)' }} />
                          </button>
                          <button className="action-btn" onClick={() => shareMessage(msg.content)} title="Compartir">
                            <div style={{ width: 16, height: 16, backgroundColor: 'var(--text-secondary)', WebkitMaskImage: 'url(/share-svgrepo-com.png)', WebkitMaskSize: 'contain', WebkitMaskRepeat: 'no-repeat', maskImage: 'url(/share-svgrepo-com.png)', maskSize: 'contain', maskRepeat: 'no-repeat' }} />
                          </button>
                        </div>
                      )}
                    </div>
                  </div>
                  );
                })}
                <div ref={messagesEndRef} />
              </div>
            </div>

            {showScrollDown && (
              <button
                onClick={() => scrollToBottom(true)}
                style={{
                  position: 'absolute',
                  bottom: '90px',
                  right: '24px',
                  width: '40px',
                  height: '40px',
                  borderRadius: '20px',
                  backgroundColor: effectiveTheme === 'light' ? '#F5F2EB' : 'var(--surface-input)',
                  border: effectiveTheme === 'light' ? '1px solid #EAE5D9' : 'none',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  cursor: 'pointer',
                  zIndex: 20,
                  boxShadow: effectiveTheme === 'light' ? '0 2px 8px rgba(0,0,0,0.1)' : '0 2px 8px rgba(0,0,0,0.45)'
                }}
              >
                <ChevronDown size={24} color="var(--amber-exodo)" />
              </button>
            )}

            {chatNotice && (
              <div className="chat-notice-toast">{chatNotice}</div>
            )}
            <div className="composer-pinned" style={{ width: '100%', display: 'flex', justifyContent: 'center' }}>
              {renderChatComposer(true)}
            </div>
          </>
        )}
      </main>



      {/* Modal exacto de AuthScreen móvil (sin pestañas de correo) */}
      <AuthModal
        isOpen={showAuthModal}
        onClose={() => setShowAuthModal(false)}
        onSuccess={() => fetchConversations()}
      />

      {/* Hoja modal de Fuentes (paridad _SourcesSheet móvil con Google S2 favicons) */}
      {(() => {
        const openMsg = messages.find((m) => m.id === openSourcesId);
        const vs = openMsg ? validSourcesOf(openMsg) : [];
        return (
          <SourcesModal
            isOpen={Boolean(openSourcesId && vs.length > 0)}
            sources={vs}
            onClose={() => setOpenSourcesId(null)}
            locale={locale}
            theme={effectiveTheme}
          />
        );
      })()}

      {/* Settings Modal (paridad _ClaudeAccountModal) */}
      <SettingsModal
        isOpen={showAccountMenu}
        onClose={() => setShowAccountMenu(false)}
        session={session}
        userProfile={userProfile}
        isGuestUser={isGuestUser || !session?.user}
        locale={locale}
        localeDisplayName={localeDisplayName}
        cloudHistoryEnabled={cloudHistoryEnabled}
        onToggleCloudHistory={toggleCloudHistory}
        onOpenProfile={() => setShowProfileMenu(true)}
        onOpenLanguage={() => setShowLanguageMenu(true)}
        onOpenBilling={() => setShowBillingMenu(true)}
        onOpenShortcuts={() => setShowShortcuts(true)}
        onOpenTerms={() => setShowTerms(true)}
        onSignOut={() => supabase.auth.signOut()}
        theme={effectiveTheme}
      />

      {/* Profile Modal (paridad ProfileScreen) */}
      <ProfileModal
        isOpen={showProfileMenu}
        onClose={() => setShowProfileMenu(false)}
        userProfile={userProfile}
        session={session}
        onSaveProfile={saveProfile}
        onExportData={exportMyData}
        onClearHistory={clearHistory}
        onDeleteAccount={deleteMyAccount}
        locale={locale}
        theme={effectiveTheme}
      />

      {/* Language Modal (paridad _showLanguageSheet) */}
      <LanguageModal
        isOpen={showLanguageMenu}
        onClose={() => setShowLanguageMenu(false)}
        currentLocale={locale}
        onSelectLocale={(selectedCode) => {
          setLocale(selectedCode);
          localStorage.setItem('exodo_web_locale', selectedCode);
          setShowAccountMenu(true);
        }}
        theme={effectiveTheme}
      />

      {/* Billing Modal (paridad _showBillingModal) */}
      <BillingModal
        isOpen={showBillingMenu}
        onClose={() => setShowBillingMenu(false)}
        userProfile={userProfile}
        tokensUsed={tokensUsed}
        tokensLimit={tokensLimit}
        onOpenUpgrade={() => setShowPlansModal(true)}
        onCancelProPlan={cancelProPlan}
        locale={locale}
        theme={effectiveTheme}
      />

      {/* Plans / Upgrade Modal (Paridad exacta con UpgradeModal de model_selector.dart) */}
      <UpgradeModal
        isOpen={showPlansModal}
        onClose={() => setShowPlansModal(false)}
        onStartCheckout={startCheckout}
        isCheckingOut={isCheckingOut}
        isGuestUser={isGuestUser}
        locale={locale}
        theme={effectiveTheme}
      />

      {/* Feedback Modal (paridad showFeedbackModal móvil) */}
      <FeedbackModal
        isOpen={Boolean(feedbackTarget)}
        target={feedbackTarget}
        userId={session?.user?.id}
        onClose={() => setFeedbackTarget(null)}
        onSuccessNotice={(msg) => {
          setChatNotice(msg);
          setTimeout(() => setChatNotice(null), 3000);
        }}
        locale={locale}
        theme={effectiveTheme}
      />

      {/* Consent Gate Modal (paridad _maybeShowConsentGate móvil) */}
      <ConsentGateModal
        isOpen={showConsentGate}
        onAccept={acceptConsent}
        locale={locale}
        theme={effectiveTheme}
      />

      {/* Terms & Privacy Modal (paridad settings.legal_body) */}
      <TermsModal
        isOpen={showTerms}
        onClose={() => setShowTerms(false)}
        locale={locale}
        theme={effectiveTheme}
      />

      {/* Módulo de Expedientes (paridad expedientes_screen.dart) */}
      <ExpedientesModal
        isOpen={showExpedientes}
        onClose={() => setShowExpedientes(false)}
        isGuestUser={isGuestUser}
        locale={locale}
        theme={effectiveTheme}
      />

      {/* Referencia de Atajos de Teclado */}
      <ShortcutsModal
        isOpen={showShortcuts}
        onClose={() => setShowShortcuts(false)}
        locale={locale}
        theme={effectiveTheme}
      />
    </div>
  );
}
