import React, { useState, useEffect, useRef } from 'react';
import { 
  ChevronRight, 
  ChevronUp,
  ArrowLeft,
  Sun, 
  Moon, 
  ArrowUp, 
  MessageSquare,
  LogOut,
  Plus,
  Check,
  X,
  Search,
  Download,
  Pin,
  Lock,
  ChevronDown,
  PanelLeftClose,
  MoreVertical,
  Edit2,
  Trash2,
  Globe,
  Smartphone,
  Zap,
  ExternalLink,
  Mic
} from 'lucide-react';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import TextareaAutosize from 'react-textarea-autosize';
import { supabase, type Conversation, type Message, type Source } from './lib/supabase';
import { AuthModal } from './components/AuthModal';
import { ArtifactMessageBody } from './components/ArtifactMessage';

// Indicador de pensamiento (paridad ExodoThinkingIndicator: esferas ámbar
// en onda + cronómetro en segundos).
const ThinkingIndicator: React.FC = () => {
  const [secs, setSecs] = useState(0);
  useEffect(() => {
    const t0 = Date.now();
    const t = setInterval(() => setSecs(Math.floor((Date.now() - t0) / 1000)), 1000);
    return () => clearInterval(t);
  }, []);
  return (
    <span className="thinking-row">
      <span className="thinking-dots"><span /><span /><span /></span>
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

const openSourceUrl = (url: string) => {
  window.open(url, '_blank', 'noopener,noreferrer');
};

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

const PsychologyIcon = ({ size = 14, color = 'currentColor' }: { size?: number; color?: string }) => (
  <svg width={size} height={size} viewBox="0 -960 960 960" fill="currentColor" style={{ flexShrink: 0, color }}>
    <path d="m434-410 4 32q1 8 6.5 13t13.5 5h44q8 0 13.5-5t6.5-13l4-32q8-3 14.5-7t11.5-9l30 13q7 3 14 1t11-9l22-38q4-7 2.5-14t-7.5-12l-26-19q2-8 2-16t-2-16l26-19q6-5 7.5-12t-2.5-14l-22-38q-4-7-11-9t-14 1l-30 13q-5-5-11.5-9t-14.5-7l-4-32q-1-8-6.5-13t-13.5-5h-44q-8 0-13.5 5t-6.5 13l-4 32q-8 3-14.5 7t-11.5 9l-30-13q-7-3-14-1t-11 9l-22 38q-4 7-2.5 14t7.5 12l26 19q-2 8-2 16t2 16l-26 19q-6 5-7.5 12t2.5 14l22 38q4 7 11 9t14-1l30-13q5 5 11.5 9t14.5 7Zm3.5-67.5Q420-495 420-520t17.5-42.5Q455-580 480-580t42.5 17.5Q540-545 540-520t-17.5 42.5Q505-460 480-460t-42.5-17.5ZM240-252q-57-52-88.5-121.5T120-520q0-150 105-255t255-105q125 0 221.5 73.5T827-615l52 205q5 19-7 34.5T840-360h-80v120q0 33-23.5 56.5T680-160h-80v40q0 17-11.5 28.5T560-80q-17 0-28.5-11.5T520-120v-80q0-17 11.5-28.5T560-240h120v-160q0-17 11.5-28.5T720-440h68l-38-155q-23-91-98-148t-172-57q-116 0-198 81t-82 197q0 60 24.5 114t69.5 96l26 24v168q0 17-11.5 28.5T280-80q-17 0-28.5-11.5T240-120v-132Zm254-188Z"/>
  </svg>
);

const MaterialProfileIcon = ({ size = 22, color = 'currentColor' }: { size?: number; color?: string }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill={color} style={{ flexShrink: 0 }}>
    <path d="M12 5.9c1.16 0 2.1.94 2.1 2.1s-.94 2.1-2.1 2.1S9.9 9.16 9.9 8s.94-2.1 2.1-2.1m0 9c2.97 0 6.1 1.46 6.1 2.1v1.1H5.9V17c0-.64 3.13-2.1 6.1-2.1M12 4C9.79 4 8 5.79 8 8s1.79 4 4 4 4-1.79 4-4-1.79-4-4-4zm0 9c-2.67 0-8 1.34-8 4v3h16v-3c0-2.66-5.33-4-8-4z"/>
  </svg>
);

const MaterialBillingIcon = ({ size = 22, color = 'currentColor' }: { size?: number; color?: string }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill={color} style={{ flexShrink: 0 }}>
    <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8zm.31-8.86c-1.77-.45-2.34-.94-2.34-1.67 0-.84.79-1.43 2.1-1.43 1.38 0 1.9.66 1.94 1.64h1.71c-.05-1.34-.87-2.57-2.49-2.97V5H10.9v1.69c-1.51.32-2.72 1.3-2.72 2.81 0 1.79 1.49 2.69 3.66 3.21 1.95.46 2.34 1.15 2.34 1.87 0 .53-.39 1.64-2.25 1.64-1.74 0-2.33-.89-2.41-1.76H7.7c.14 1.86 1.49 2.85 3.2 3.19V19h2.33v-1.64c1.51-.32 2.76-1.37 2.76-2.99 0-2.02-1.63-2.69-3.68-3.23z"/>
  </svg>
);

const MaterialPrivacyIcon = ({ size = 22, color = 'currentColor' }: { size?: number; color?: string }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill={color} style={{ flexShrink: 0 }}>
    <path d="M12 1L3 5v6c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V5l-9-4zm0 2.18l7 3.12v4.7c0 4.67-3.13 8.9-7 10.02-3.87-1.12-7-5.35-7-10.02V6.3l7-3.12zM11 7h2v2h-2zm0 4h2v6h-2z"/>
  </svg>
);

export default function App() {
  // Estados de sesión y autenticación
  const [session, setSession] = useState<any>(null);
  const [userProfile, setUserProfile] = useState<{ plan?: string; full_name?: string; onboarding?: any } | null>(null);
  const [showAuthModal, setShowAuthModal] = useState(false);

  // Estados de interfaz exacta a móvil
  const [theme, setTheme] = useState<'dark' | 'light'>(() => (localStorage.getItem('exodo_theme') as 'dark' | 'light') || 'dark');
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [isIncognito, setIsIncognito] = useState(false);
  // Invitado (paridad isGuestUser de app_state.dart): usuario anónimo de
  // Supabase = solo local, sin nube (sin perfil, sin conversaciones en DB,
  // sin medidor), modelo bloqueado y sin upgrade — como la app.
  const isGuestUser = !!session?.user?.is_anonymous;
  const [searchQuery, setSearchQuery] = useState('');
  const [showSearchBox, setShowSearchBox] = useState(false);
  // Paridad móvil: tap en el logo del drawer muestra el badge de versión.
  const [showWebVersion, setShowWebVersion] = useState(false);
  const [showTokenPopup, setShowTokenPopup] = useState(false);
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
  const [isAnnualPlan, setIsAnnualPlan] = useState(false);
  const [openMenuId, setOpenMenuId] = useState<string | null>(null);
  const [hoveredConvId, setHoveredConvId] = useState<string | null>(null);
  const [renamingId, setRenamingId] = useState<string | null>(null);
  const [renameDraft, setRenameDraft] = useState('');
  const [chatNotice, setChatNotice] = useState<string | null>(null);
  // Feedback de mensajes (paridad _AssistantActionsBar móvil: modal con
  // comentario → insert en tabla `feedback`; envío silencioso).
  const [feedbackTarget, setFeedbackTarget] = useState<{ msg: Message; isLike: boolean } | null>(null);
  const [feedbackComment, setFeedbackComment] = useState('');
  // Consent gate (paridad _maybeShowConsentGate de chat_screen.dart): edad +
  // nube en el primer login con cuenta. Sin aceptar edad no se continúa.
  const [showConsentGate, setShowConsentGate] = useState(false);
  const [consentAge, setConsentAge] = useState(false);
  const [consentCloud, setConsentCloud] = useState(true);
  // Terms & Privacy (paridad settings.legal_body).
  const [showTerms, setShowTerms] = useState(false);
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
  const [selectedModel, setSelectedModel] = useState({    id: 'origo',
    title: 'G1.1',
    subtitle: 'Origo',
    plan: 'genesis',
    description: 'Modelo capaz para tareas diarias.'
  });
  const [showUpgradeBanner, setShowUpgradeBanner] = useState(true);

  // Estados de conversación
  const [conversations, setConversations] = useState<Conversation[]>(() => {
    try {
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
  const [messages, setMessages] = useState<Message[]>([
    {
      id: 'welcome-1',
      conversation_id: 'initial',
      role: 'assistant',
      content: 'Hola. ¿En qué trabajamos hoy?',
      created_at: new Date().toISOString()
    }
  ]);
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

  // Sincronización de tema
  useEffect(() => {
    document.documentElement.setAttribute('data-theme', theme);
    localStorage.setItem('exodo_theme', theme);
  }, [theme]);

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

    // Retraso de 100ms en getSession para no competir con el bloqueo interno (_acquireLock) de Supabase
    const sessionTimeout = setTimeout(() => {
      supabase.auth.getSession().then(({ data: { session }, error }) => {
        if (error) {
          console.error('Error al obtener sesión / intercambiar código de Google:', error);
          if (window.location.search.includes('code=')) {
            alert(`Error al verificar la autenticación con Google: ${error.message}\n\nPor favor intenta de nuevo o verifica la configuración del dominio.`);
          }
        }
        if (session) setSession(session);
        if (session?.user) {
          // Invitado: sin nube (paridad guest móvil: todo local).
          if (!session.user.is_anonymous) {
            fetchProfile(session.user.id);
            fetchConversations();
            fetchTodayUsage();
          }
          setShowAuthModal(false);
          if (window.location.search.includes('code=') || window.location.hash.includes('access_token=')) {
            window.history.replaceState({}, document.title, window.location.pathname);
          }
        }
      });
    }, 100);

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
        setShowAuthModal(false);
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

  useEffect(() => {
    if (activeConvId && !activeConvId.startsWith('conv-') && activeConvId !== 'initial') {
      fetchMessages(activeConvId).finally(() => setIsInitializing(false));
    } else {
      setIsInitializing(false);
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
  const commitRename = async (convId: string) => {
    const newTitle = renameDraft.trim();
    setRenamingId(null);
    if (!newTitle) return;
    const conv = conversations.find((c) => c.id === convId);
    if (!conv || conv.title === newTitle) return;
    setConversations((prev) => prev.map((c) => (c.id === convId ? { ...c, title: newTitle } : c)));
    if (!convId.startsWith('conv-')) {
      const { error } = await supabase.from('conversations').update({ title: newTitle }).eq('id', convId);
      if (error) console.warn('Error renombrando conversación:', error.message);
    }
  };

  const toggleStarred = async (conv: Conversation) => {
    const next = !conv.is_starred;
    setConversations((prev) => prev.map((c) => (c.id === conv.id ? { ...c, is_starred: next } : c)));
    if (!conv.id.startsWith('conv-')) {
      const { error } = await supabase.from('conversations').update({ is_starred: next }).eq('id', conv.id);
      if (error) console.warn('Error fijando conversación:', error.message);
    }
  };

  const deleteConversation = async (convId: string) => {
    const conv = conversations.find((c) => c.id === convId);
    const title = conv?.title || 'esta conversación';
    // Paridad móvil (_showDeleteConfirmationDialog): confirmación previa.
    const confirmed = window.confirm(`¿Eliminar conversación?\n\n"${title}"\n\nEsta acción no se puede deshacer.`);
    if (!confirmed) return;
    setOpenMenuId(null);
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
    setConsentAge(false);
    setConsentCloud(cloudHistoryEnabled);
    setShowConsentGate(true);
  };

  const acceptConsent = async () => {
    if (!consentAge) return;
    const ts = new Date().toISOString();
    try {
      localStorage.setItem('exodo_consent', JSON.stringify({ age: true, cloud: consentCloud, ts, v: 1 }));
    } catch (_) {}
    toggleCloudHistory(consentCloud);
    setShowConsentGate(false);
    // Registro en la nube, best-effort (paridad móvil: onboarding).
    try {
      if (session?.user) {
        const existing = (userProfile?.onboarding && typeof userProfile.onboarding === 'object')
          ? { ...userProfile.onboarding } : {};
        (existing as any)['age_confirmed'] = true;
        (existing as any)['cloud_history_consent'] = consentCloud;
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
      if (isGuestUser) { try { navigator.vibrate?.(10); } catch (_) {} }
      return;
    }
    setIsCheckingOut(true);
    try {
      const base = import.meta.env.PROD
        ? 'https://behavior-ai-production.up.railway.app'
        : 'http://localhost:3000';
      const res = await fetch(`${base}/api/stripe/checkout`, {
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
        const base = import.meta.env.PROD
          ? 'https://behavior-ai-production.up.railway.app'
          : 'http://localhost:3000';
        const res = await fetch(`${base}/api/chat/title`, {
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
  // ── Feedback (paridad submitFeedback de supabase_service.dart) ──
  const submitFeedback = async () => {
    const target = feedbackTarget;
    if (!target || !session?.user) { setFeedbackTarget(null); return; }
    const es = (locale || 'es').toLowerCase().startsWith('es');
    try {
      const { error } = await supabase.from('feedback').insert({
        user_id: session.user.id,
        is_like: target.isLike,
        comment: feedbackComment.trim(),
        message_excerpt: target.msg.content.length > 500 ? target.msg.content.substring(0, 500) : target.msg.content,
        conversation_id: activeConvId && !activeConvId.startsWith('conv-') ? activeConvId : null,
        app_locale: es ? 'es' : 'en',
        app_version: 'web',
      });
      if (error) throw error;
      setChatNotice(es ? '¡Gracias por tu feedback!' : 'Thanks for your feedback!');
    } catch (e) {
      console.warn('Error enviando feedback:', e);
      setChatNotice(es ? 'No se pudo enviar el feedback. Intenta de nuevo.' : 'Could not send feedback. Please try again.');
    }
    setTimeout(() => setChatNotice(null), 3000);
    setFeedbackTarget(null);
    setFeedbackComment('');
  };

  // ── Compartir respuesta (paridad share móvil: contenido + Play URL) ──
  const shareMessage = async (content: string) => {
    const es = (locale || 'es').toLowerCase().startsWith('es');
    const text = `${content}\n\n${es ? 'Descarga Éxodo AI en Google Play:' : 'Download Exodo AI on Google Play:'}\nhttps://play.google.com/store/apps/details?id=com.behavior.exodo`;
    try {
      if (navigator.share) {
        await navigator.share({ title: 'Éxodo AI', text });
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
            const who = m.role === 'user' ? 'Tú' : 'Éxodo';
            const time = m.created_at ? new Date(m.created_at).toLocaleString() : '';
            return `<p><strong>${who}</strong> <small>${time}</small></p><div>${(m.content || '').replace(/</g, '&lt;')}</div><hr>`;
          })
          .join('');
        rows.push(`<section><h2>${(c.title || '').replace(/</g, '&lt;')}</h2>${body}</section>`);
      }
      const html = `<!doctype html><html lang="es"><head><meta charset="utf-8"><title>Éxodo — Mis datos</title>
<style>body{font-family:sans-serif;max-width:720px;margin:24px auto;padding:0 16px;background:#F5F2EB;color:#171615}h1{color:#C9933A}section{background:#fff;border-radius:12px;padding:16px;margin:16px 0}small{color:#9E9689}</style>
</head><body><h1>Éxodo — Mis datos</h1><p>${convs.length} conversación(es) · ${new Date().toLocaleString()}</p>${rows.join('')}</body></html>`;
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
      setSelectedModel({ id: 'origo', title: 'G1.1', subtitle: 'Origo', plan: 'genesis', description: 'Modelo rápido para uso general' });
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
      if (!error && data && data.length > 0) {
        setMessages(data);
      }
    } catch (e) {
      console.warn('Error fetching messages:', e);
    }
  }

  const scrollToBottom = () => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  };

  const handleCreateNewChat = () => {
    const newConvId = `conv-${Date.now()}`;
    const newConv: Conversation = {
      id: newConvId,
      user_id: session?.user?.id || 'current-user',
      title: 'Nueva Conversación',
      model: 'hazak',
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString()
    };
    setConversations((prev) => {
      const filtered = prev.filter((c) => !c.id.startsWith('conv-'));
      return [newConv, ...filtered];
    });
    setActiveConvId(newConvId);
    localStorage.setItem('exodo_web_active_conv', newConvId);
    localStorage.setItem('exodo_web_temp_conv', JSON.stringify(newConv));
    setMessages([
      {
        id: `sys-${Date.now()}`,
        conversation_id: newConvId,
        role: 'assistant',
        content: 'Hola. ¿En qué trabajamos hoy?',
        created_at: new Date().toISOString()
      }
    ]);
    setDrawerOpen(false);
  };

  const handleToggleIncognito = () => {
    const newValue = !isIncognito;
    setIsIncognito(newValue);
    if (newValue) {
      setSelectedModel({
        id: 'origo',
        title: 'G1.1',
        subtitle: 'Origo',
        plan: 'genesis',
        description: 'Modelo rápido para uso general'
      });
    }
    handleCreateNewChat();
  };

  const handleSendMessage = async (e?: React.FormEvent) => {
    if (e) e.preventDefault();
    if ((!input.trim() && pendingAttachments.length === 0) || isStreaming) return;

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

    // Si es un chat temporal y hay cuenta real con historial en la nube,
    // crear la conversación real en DB primero. Invitado e incógnito:
    // todo local, sin nube (paridad guest móvil).
    const persistToCloud = !!session?.user && !isIncognito && !isGuestUser && cloudHistoryEnabled;
    if (currentConvId && currentConvId.startsWith('conv-') && persistToCloud) {
      const titleSeed = userText || outgoingAttachments[0]?.file_name || 'Nueva conversación';
      const { data, error } = await supabase.from('conversations').insert({
        user_id: session.user.id,
        title: titleSeed.length > 35 ? titleSeed.substring(0, 35) + '...' : titleSeed,
        model_plan: selectedModel.plan || 'genesis',
        is_incognito: isIncognito
      }).select().single();

      if (!error && data) {
        currentConvId = data.id;
        setActiveConvId(currentConvId);
        if (currentConvId) {
          localStorage.setItem('exodo_web_active_conv', currentConvId);
        }
        localStorage.removeItem('exodo_web_temp_conv');
        
        setConversations((prev) => {
          const filtered = prev.filter((c) => c.id !== activeConvId);
          return [data, ...filtered];
        });
      }
    }

    const userMsg: Message = {
      id: `msg-user-${Date.now()}`,
      conversation_id: currentConvId || 'default',
      role: 'user',
      content: userText,
      created_at: new Date().toISOString(),
      attachments: outgoingPreviews.length > 0 ? outgoingPreviews : undefined
    };

    const thinkingMsg: Message = {
      id: `msg-thinking-${Date.now()}`,
      conversation_id: currentConvId || 'default',
      role: 'assistant',
      content: 'Pensando...',
      created_at: new Date().toISOString(),
      isThinking: true
    };

    setMessages((prev) => [...prev, userMsg, thinkingMsg]);
    setIsStreaming(true);
    setTimeout(() => scrollToBottom(), 50);
    let finalAssistantText = '';

    try {
      const backendEndpoint = import.meta.env.PROD
        ? 'https://behavior-ai-production.up.railway.app/api/chat'
        : 'http://localhost:3000/api/chat';

      const res = await fetch(backendEndpoint, {
        method: 'POST',
        headers: { 
          'Content-Type': 'application/json',
          ...(session?.access_token ? { Authorization: `Bearer ${session.access_token}` } : {})
        },
        body: JSON.stringify({
          message: userText,
          conversationId: persistToCloud && currentConvId && !currentConvId.startsWith('conv-') ? currentConvId : undefined,
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

        setMessages((prev) => prev.filter((m) => !m.isThinking));

        const assistantMsgId = `msg-asst-${Date.now()}`;
        setMessages((prev) => [
          ...prev,
          {
            id: assistantMsgId,
            conversation_id: currentConvId || 'default',
            role: 'assistant',
            content: '',
            created_at: new Date().toISOString()
          }
        ]);

        while (true) {
          const { done, value } = await reader.read();
          if (done) break;

          const chunk = decoder.decode(value, { stream: true });
          const lines = chunk.split('\n');

          for (const line of lines) {
            if (line.startsWith('data: ')) {
              const dataStr = line.replace('data: ', '').trim();
              if (dataStr === '[DONE]') continue;
              try {
                const parsed = JSON.parse(dataStr);
                if (parsed.type === 'meta') {
                  // Paridad móvil: isDegraded marca el aviso de modo eco bajo el mensaje.
                  if (parsed.isDegraded) {
                    setMessages((prev) =>
                      prev.map((m) => (m.id === assistantMsgId ? { ...m, isDegraded: true } : m))
                    );
                  }
                } else if (parsed.type === 'notice') {
                  // Avisos del backend (login requerido para imágenes, límite diario, etc.)
                  const noticeText: Record<string, string> = {
                    image_login_required: 'Inicia sesión para generar imágenes.',
                    image_daily_limit_reached: 'Límite diario de imágenes alcanzado.',
                    image_generation_failed: 'No se pudo generar la imagen.',
                  };
                  setChatNotice(noticeText[parsed.code] || parsed.code || 'Aviso de Éxodo.');
                  setTimeout(() => setChatNotice(null), 5000);
                } else if (parsed.type === 'generating_image') {
                  setChatNotice('Sintetizando imagen...');
                } else if (parsed.type === 'done') {
                  // El evento done trae el texto FINAL y las fuentes extraídas por el backend.
                  // Se REEMPLAZA el contenido (no se concatena) para no duplicar la respuesta.
                  finalAssistantText = parsed.content || accumulatedText;
                  setMessages((prev) =>
                    prev.map((m) =>
                      m.id === assistantMsgId
                        ? {
                            ...m,
                            content: finalAssistantText,
                            sources: Array.isArray(parsed.sources) ? parsed.sources : []
                          }
                        : m
                    )
                  );
                  scrollToBottom();
                } else if (parsed.content) {
                  accumulatedText += parsed.content;
                  setMessages((prev) =>
                    prev.map((m) =>
                      m.id === assistantMsgId ? { ...m, content: accumulatedText } : m
                    )
                  );
                  scrollToBottom();
                }
              } catch (_) {}
            }
          }
        }
      } else {
        throw new Error('Fallback simulación instantánea');
      }
    } catch (err) {
      setMessages((prev) => prev.filter((m) => !m.isThinking));
      const simulatedResponse = `Recibido: "${userText}".\n\n*(Sincronizado con Éxodo sobre latencia 0 ms y conducta multinivel).*`;
      setMessages((prev) => [
        ...prev,
        {
          id: `msg-sim-${Date.now()}`,
          conversation_id: currentConvId || 'default',
          role: 'assistant',
          content: simulatedResponse,
          created_at: new Date().toISOString()
        }
      ]);
      scrollToBottom();
    } finally {
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

  const filteredConvs = conversations.filter((c) =>
    c.title.toLowerCase().includes(searchQuery.toLowerCase())
  );

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

  const voiceEndpoint = (path: string) => import.meta.env.PROD
    ? `https://behavior-ai-production.up.railway.app${path}`
    : `http://localhost:3000${path}`;

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
    try {
      const blob = new Blob(chunks, { type: 'audio/webm' });
      const form = new FormData();
      form.append('file', blob, 'nota.webm');
      const res = await fetch(voiceEndpoint('/api/voice/transcribe'), {
        method: 'POST',
        headers: { ...(session?.access_token ? { Authorization: `Bearer ${session.access_token}` } : {}) },
        body: form,
      });
      const data = await res.json().catch(() => ({}));
      const text = typeof data?.text === 'string' ? data.text.trim() : '';
      if (text) setInput((prev) => (prev ? `${prev} ${text}` : text));
      else {
        setChatNotice('No se entendió el audio. Intenta de nuevo.');
        setTimeout(() => setChatNotice(null), 3000);
      }
    } catch (_) {
      setChatNotice('No se pudo transcribir el audio.');
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
    // Paridad móvil (punto 6): incógnito E invitado tienen el modelo bloqueado.
    const isModelLocked = !session?.user || isIncognito || isGuestUser;
    const displayModelTitle = (!session?.user || isGuestUser) ? 'G1.1' : selectedModel.title;

    return (
    <div style={{ width: '100%', maxWidth: 820, margin: '0 auto', position: 'relative', display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
      {showUpgradeBanner && !isIncognito && (
        <div style={{
          width: 'min(92%, 360px)',
          padding: '4px 16px 24px 16px',
          position: 'absolute' as const,
          bottom: 'calc(100% - 18px)',
          left: '50%',
          transform: 'translateX(-50%)',
          zIndex: 1,
          background: 'var(--banner-bg, #252525)',
          border: '1px solid var(--banner-border, transparent)',
          borderBottom: 'none',
          borderRadius: '20px 20px 0 0',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          flexWrap: 'wrap',
          gap: '4px 10px',
          boxSizing: 'border-box' as const,
          textAlign: 'center'
        }}>
          <span style={{ fontFamily: 'AnthropicSans, sans-serif', fontSize: '12px', fontWeight: 600, color: 'var(--banner-text, #F5F2EB)', lineHeight: 1.2 }}>
            Más capacidad con XPi PRO
          </span>
          <button
            type="button"
            onClick={() => {
              // Paridad móvil (punto 6): invitado = no-op silencioso con
              // háptica suave; nunca abre el modal de compra.
              if (isGuestUser) { try { navigator.vibrate?.(10); } catch (_) {} return; }
              setShowPlansModal(true);
            }}
            style={{ background: 'none', border: 'none', cursor: 'pointer', padding: '4px', fontFamily: 'AnthropicSans, sans-serif', fontSize: '12px', fontWeight: 700, color: 'var(--amber-exodo)' }}
          >
            Actualizar
          </button>
          <button
            type="button"
            onClick={() => setShowUpgradeBanner(false)}
            style={{ background: 'none', border: 'none', cursor: 'pointer', padding: '4px 6px', display: 'flex', alignItems: 'center' }}
          >
            <X size={16} color="var(--banner-text, #F5F2EB)" />
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
              placeholder="Habla con Éxodo..."
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

              <div style={{ position: 'relative', display: 'flex', alignItems: 'center' }}>
                <button
                  type="button"
                  onClick={() => {
                    if (isModelLocked) return;
                    setShowModelSelector(!showModelSelector);
                  }}
                  style={{
                    padding: '6px 14px',
                    borderRadius: 16,
                    background: 'var(--model-chip-bg)',
                    border: '1px solid transparent',
                    display: 'flex',
                    alignItems: 'center',
                    gap: 6,
                    cursor: isModelLocked ? 'default' : 'pointer',
                    color: 'var(--chip-icon-color)'
                  }}
                  title={isModelLocked ? (!session?.user ? "En invitado no se puede elegir modelos, solo G1.1" : "Modelo bloqueado en Modo Incógnito") : "Seleccionar Modelo"}
                >
                  <span style={{ fontFamily: 'AnthropicSans, sans-serif', fontSize: '13px', fontWeight: 700 }}>
                    {displayModelTitle}
                  </span>
                  {isModelLocked ? (
                    <Lock size={13} color="var(--chip-icon-color)" />
                  ) : (
                    <ChevronRight size={15} color="var(--chip-icon-color)" style={{ transform: showModelSelector ? 'rotate(-90deg)' : 'rotate(90deg)', transition: 'transform 0.2s ease' }} />
                  )}
                </button>

                {showModelSelector && !isModelLocked && (
                  <>
                    <div 
                      style={{ position: 'fixed', top: 0, left: 0, right: 0, bottom: 0, zIndex: 100 }}
                      onClick={(e) => { e.stopPropagation(); setShowModelSelector(false); }}
                    />
                    <div
                      className="model-selector-popover"
                      onClick={(e) => e.stopPropagation()}
                    >
                      {[
                        {
                          id: 'origo',
                          title: 'G1.1',
                          subtitle: 'Origo',
                          plan: 'genesis',
                          description: 'Modelo rápido para uso general'
                        },
                        {
                          id: 'ehyeh',
                          title: 'XPi',
                          subtitle: 'Ehyeh',
                          plan: 'hazak',
                          description: 'Razonamiento avanzado'
                        }
                      ].map((m) => {
                        const active = selectedModel.id === m.id;
                        const isProModel = m.plan === 'hazak';
                        return (
                          <div
                            key={m.id}
                            onClick={() => {
                              setSelectedModel(m);
                              setShowModelSelector(false);
                            }}
                            style={{
                              padding: '10px 12px',
                              borderRadius: 10,
                              background: active ? 'var(--surface-input)' : 'transparent',
                              cursor: 'pointer',
                              display: 'flex',
                              flexDirection: 'column',
                              gap: '2px',
                              transition: 'background 0.15s ease'
                            }}
                          >
                            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                              <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                                <span style={{ fontFamily: 'AnthropicSans, sans-serif', fontWeight: active ? 700 : 500, fontSize: '13.5px', color: active ? 'var(--amber-exodo)' : 'var(--text-primary)' }}>
                                  {m.title}
                                </span>
                                {isProModel && (
                                  <span style={{ fontSize: '9px', padding: '1px 5px', borderRadius: 4, border: `1px solid ${active ? 'var(--amber-exodo)' : 'var(--border-color)'}`, color: active ? 'var(--amber-exodo)' : 'var(--text-secondary)', fontWeight: 700 }}>
                                    PRO
                                  </span>
                                )}
                              </div>
                              {active && <Check size={16} color="var(--amber-exodo)" />}
                            </div>
                            <span style={{ fontFamily: 'AnthropicSans, sans-serif', fontSize: '11.5px', color: 'var(--text-secondary)' }}>
                              {m.description}
                            </span>
                          </div>
                        );
                      })}
                      <div style={{ height: 1, background: 'var(--border-color)', margin: '4px 6px' }} />
                      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6, padding: '4px 6px 2px 6px' }}>
                        <PsychologyIcon size={15} color="rgba(201, 147, 58, 0.8)" />
                        <span style={{ fontFamily: 'AnthropicSans, sans-serif', fontSize: '11px', color: 'var(--text-secondary)', textAlign: 'center' }}>
                          modo thinking activado por defecto
                        </span>
                      </div>
                    </div>
                  </>
                )}
              </div>
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
          Exodo es IA y puede cometer errores. Por favor verifica las respuestas.
        </div>
      </div>
    </div>
  );
  };

  // ── Item de conversación (paridad _buildConvItem de drawer_menu.dart) ──
  const openConvMenu = (convId: string) => {
    setOpenMenuId(openMenuId === convId ? null : convId);
  };

  const renderConvMenuOptions = (conv: Conversation, isStarred: boolean) => (
    <>
      <button type="button" className="drawer-item" style={{ padding: '6px 12px', fontSize: '0.85rem' }} onClick={(e) => { e.stopPropagation(); setRenameDraft(conv.title); setRenamingId(conv.id); setOpenMenuId(null); }}>
        <Edit2 size={14} style={{ marginRight: 8 }} /> Renombrar
      </button>
      <button type="button" className="drawer-item" style={{ padding: '6px 12px', fontSize: '0.85rem' }} onClick={(e) => { e.stopPropagation(); toggleStarred(conv); setOpenMenuId(null); }}>
        <Pin size={14} style={{ marginRight: 8 }} /> {isStarred ? 'Desfijar' : 'Fijar'}
      </button>
      <button type="button" className="drawer-item" style={{ padding: '6px 12px', fontSize: '0.85rem', color: '#ff4d4f' }} onClick={(e) => { e.stopPropagation(); deleteConversation(conv.id); }}>
        <Trash2 size={14} color="#ff4d4f" style={{ marginRight: 8 }} /> Eliminar
      </button>
    </>
  );

  const renderConvItem = (conv: Conversation, isStarred: boolean) => {
    const active = activeConvId === conv.id;
    const isMobileView = typeof window !== 'undefined' && window.matchMedia('(max-width: 640px)').matches;
    return (
      <div
        key={conv.id}
        className={`conv-item ${active ? 'active' : ''}`}
        onMouseEnter={() => setHoveredConvId(conv.id)}
        onMouseLeave={() => setHoveredConvId(null)}
        onClick={() => {
          setActiveConvId(conv.id);
          localStorage.setItem('exodo_web_active_conv', conv.id);
          localStorage.removeItem('exodo_web_temp_conv');
          fetchMessages(conv.id);
          setDrawerOpen(false);
        }}
        style={{ padding: '11px 10px', justifyContent: 'space-between', position: 'relative', zIndex: openMenuId === conv.id ? 1000 : 1 }}
      >
        {active && <span className="conv-active-bar" />}
        {renamingId === conv.id ? (
          <input
            autoFocus
            className="search-input"
            style={{ flex: 1, minWidth: 0, background: 'var(--surface-input)', border: 'none', borderRadius: 6, padding: '4px 8px', fontSize: '0.92rem', color: 'var(--text-primary)' }}
            value={renameDraft}
            onChange={(e) => setRenameDraft(e.target.value)}
            onClick={(e) => e.stopPropagation()}
            onKeyDown={(e) => {
              if (e.key === 'Enter') commitRename(conv.id);
              if (e.key === 'Escape') setRenamingId(null);
            }}
            onBlur={() => commitRename(conv.id)}
          />
        ) : (
          <span style={{
            overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
            fontSize: '13.5px', fontFamily: 'AnthropicSans, sans-serif', letterSpacing: '-0.1px',
            fontWeight: active ? 700 : 400, flex: 1, minWidth: 0,
          }}>{conv.title}</span>
        )}
        {isStarred && renamingId !== conv.id && (
          <Pin size={14} color={active ? '#C9933A' : 'var(--text-secondary)'} style={{ flexShrink: 0 }} />
        )}
        {(hoveredConvId === conv.id || openMenuId === conv.id) && renamingId !== conv.id && (
          <button
            type="button"
            onClick={(e) => { e.stopPropagation(); openConvMenu(conv.id); }}
            style={{ background: 'none', border: 'none', cursor: 'pointer', padding: 2, display: 'flex', alignItems: 'center', flexShrink: 0 }}
            title="Opciones"
          >
            <MoreVertical size={16} color="var(--text-secondary)" />
          </button>
        )}
        {openMenuId === conv.id && !isMobileView && (
          <div style={{
            position: 'absolute', right: 32, top: 24, background: 'var(--surface-input)',
            border: 'none', borderRadius: 8, padding: '4px', zIndex: 100,
            display: 'flex', flexDirection: 'column', gap: 2,
            boxShadow: '0 4px 12px rgba(0,0,0,0.5)', minWidth: 120
          }}>
            {renderConvMenuOptions(conv, isStarred)}
          </div>
        )}
      </div>
    );
  };

  // Bottom sheet contextual móvil (paridad _showChatContextMenu).
  const renderConvContextSheet = () => {
    const conv = conversations.find((c) => c.id === openMenuId);
    if (!conv || !openMenuId) return null;
    if (typeof window !== 'undefined' && !window.matchMedia('(max-width: 640px)').matches) return null;
    const isStarred = !!conv.is_starred;
    return (
      <div style={{ position: 'fixed', inset: 0, zIndex: 1200 }}>
        <div style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.6)' }} onClick={() => setOpenMenuId(null)} />
        <div style={{
          position: 'absolute', left: 0, right: 0, bottom: 0,
          background: 'var(--surface-card)', borderRadius: '20px 20px 0 0',
          padding: '12px 16px calc(16px + env(safe-area-inset-bottom, 0px))',
        }}>
          <div style={{ width: 36, height: 4, borderRadius: 2, background: 'var(--text-secondary)', opacity: 0.4, margin: '0 auto 16px auto' }} />
          <button type="button" className="drawer-item" style={{ padding: '12px', fontSize: '15px', fontWeight: 500 }} onClick={() => { setRenameDraft(conv.title); setRenamingId(conv.id); setOpenMenuId(null); }}>
            <Edit2 size={18} style={{ marginRight: 12 }} /> Renombrar
          </button>
          <button type="button" className="drawer-item" style={{ padding: '12px', fontSize: '15px', fontWeight: 500 }} onClick={() => { toggleStarred(conv); setOpenMenuId(null); }}>
            <Pin size={18} style={{ marginRight: 12 }} /> {isStarred ? 'Desfijar' : 'Fijar'}
          </button>
          <button type="button" className="drawer-item" style={{ padding: '12px', fontSize: '15px', fontWeight: 500, color: '#ff4d4f' }} onClick={() => { deleteConversation(conv.id); }}>
            <Trash2 size={18} color="#ff4d4f" style={{ marginRight: 12 }} /> Eliminar
          </button>
          <div style={{ height: 12 }} />
        </div>
      </div>
    );
  };

  return (
    <div className="app-container">
      {/* Barra lateral vertical izquierda permanente con separador hasta abajo */}
      <aside className="sidebar-rail">
        <button 
          type="button" 
          className="icon-btn" 
          onClick={() => setDrawerOpen(true)}
          title="Menú"
          style={{ padding: '8px' }}
        >
          <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-start', gap: 5, padding: '4px 2px' }}>
            <div style={{ width: 20, height: 2, background: 'var(--text-primary)', borderRadius: 1 }} />
            <div style={{ width: 20, height: 2, background: 'var(--text-primary)', borderRadius: 1 }} />
            <div style={{ width: 12, height: 2, background: 'var(--text-primary)', borderRadius: 1 }} />
          </div>
        </button>
      </aside>

      {/* 2. Drawer Menu Deslizable (Exacto de drawer_menu.dart) */}
      {drawerOpen && (
        <div className="drawer-backdrop" onClick={() => setDrawerOpen(false)} />
      )}

      <aside className={`drawer-slide ${drawerOpen ? 'open' : ''}`}>
        <div className="drawer-header" style={{ padding: '16px 20px', display: 'flex', alignItems: 'center', justifyContent: 'space-between', borderBottom: 'none' }}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10, cursor: 'pointer' }} onClick={() => setShowWebVersion((v) => !v)} title="Versión">
              <img src="/Logo_behavior.png" alt="Éxodo Logo" style={{ width: 28, height: 28, objectFit: 'contain' }} />
              <div className="mask-text-yeso" style={{ width: 84, height: 24 }} />
            </div>
            {showWebVersion && (
              <div style={{
                alignSelf: 'flex-start',
                padding: '4px 10px',
                borderRadius: 6,
                border: '1px solid rgba(201, 147, 58, 0.3)',
                color: 'var(--amber-exodo)',
                fontSize: '10.5px',
                fontWeight: 600,
                fontFamily: 'AnthropicSans, sans-serif'
              }}>
                Éxodo Web
              </div>
            )}
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            <button type="button" className="icon-btn" onClick={() => setDrawerOpen(false)} style={{ width: 32, height: 32 }}>
              <PanelLeftClose size={18} color="var(--text-secondary)" />
            </button>
          </div>
        </div>

        <div style={{ padding: '8px 12px' }}>
          <button type="button" className="drawer-item" onClick={handleCreateNewChat} style={{ marginBottom: 4, padding: '10px 12px' }}>
            <MessageSquare size={20} color="var(--text-primary)" />
            <span style={{ fontSize: '0.94rem' }}>Nuevo chat</span>
          </button>

          <button 
            type="button" 
            className="drawer-item" 
            onClick={() => setTheme(theme === 'dark' ? 'light' : 'dark')}
            style={{ marginBottom: 4, padding: '10px 12px' }}
          >
            {theme === 'dark' ? <Sun size={20} color="var(--text-primary)" /> : <Moon size={20} color="var(--text-primary)" />}
            <span style={{ fontSize: '0.94rem' }}>{theme === 'dark' ? 'Modo claro' : 'Modo oscuro'}</span>
          </button>

          <button 
            type="button" 
            className="drawer-item" 
            onClick={() => { handleToggleIncognito(); setDrawerOpen(false); }}
            style={{ marginBottom: 4, padding: '10px 12px' }}
          >
            <div className="mask-icon-incognito" style={{ backgroundColor: isIncognito ? 'var(--amber-exodo)' : 'var(--text-primary)' }} />
            <span style={{ fontSize: '0.94rem', color: isIncognito ? 'var(--amber-exodo)' : undefined }}>Modo Incógnito</span>
          </button>

          <button
            type="button"
            className="drawer-item"
            onClick={() => setShowSearchBox(true)}
            style={{ marginBottom: 4, padding: '10px 12px' }}
          >
            <Search size={20} color="var(--text-primary)" />
            <span style={{ fontSize: '0.94rem' }}>Buscar chats</span>
          </button>
        </div>

        <div style={{ padding: '0 16px 12px 16px', position: 'relative' }}>
          <div
            className="header-token-bar"
            onClick={() => { fetchTodayUsage(); setShowTokenPopup(!showTokenPopup); }}
            title="Capacidad y tokens de Éxodo"
            style={{ width: '100%', justifyContent: 'space-between' }}
          >
            <span style={{ fontSize: '0.78rem', color: 'var(--text-secondary)', fontWeight: 600 }}>
              {tokensUsed}/{tokensLimit} tk
            </span>
            <div className="token-bar-progress" style={{ width: 100 }}>
              <div className="token-bar-fill" style={{ width: `${Math.min(100, (tokensUsed / tokensLimit) * 100)}%` }} />
            </div>
          </div>

          {showTokenPopup && (() => {
            // Reinicio a las 12:00 AM AST (America/Santo_Domingo), como la app.
            const nowAst = new Date(new Date().toLocaleString('en-US', { timeZone: 'America/Santo_Domingo' }));
            const reset = new Date(nowAst); reset.setHours(24, 0, 0, 0);
            const diffMs = reset.getTime() - nowAst.getTime();
            const hh = String(Math.floor(diffMs / 3600000)).padStart(2, '0');
            const mm = String(Math.floor((diffMs % 3600000) / 60000)).padStart(2, '0');
            const pct = tokensLimit > 0 ? ((tokensUsed / tokensLimit) * 100).toFixed(1) : '0';
            return (
              <div className="token-popup-card" style={{ top: 44, left: 16, transform: 'none', width: '258px', zIndex: 60, color: 'var(--text-primary)' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.8rem' }}>
                  <span>Consumido</span>
                  <span style={{ fontWeight: 700 }}>{tokensUsed} ({pct}%)</span>
                </div>
                <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.8rem' }}>
                  <span>Disponible</span>
                  <span style={{ fontWeight: 700 }}>{Math.max(0, tokensLimit - tokensUsed).toLocaleString()} tk</span>
                </div>
                <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.8rem' }}>
                  <span>Reinicio en</span>
                  <span style={{ fontWeight: 700 }}>{hh}h {mm}m</span>
                </div>
              </div>
            );
          })()}
        </div>

        {(showSearchBox || searchQuery.length > 0) && (
          <div className="search-box" style={{ margin: '4px 16px 12px 16px' }}>
            <Search size={16} color="var(--text-muted)" />
            <input
              type="text"
              className="search-input"
              placeholder="Escribe para buscar..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              autoFocus
            />
            {searchQuery && (
              <button type="button" onClick={() => { setSearchQuery(''); setShowSearchBox(false); }} style={{ background: 'none', border: 'none', cursor: 'pointer', padding: 0 }}>
                <X size={16} color="var(--text-muted)" />
              </button>
            )}
          </div>
        )}

        {/* Divisor tras opciones (paridad drawer móvil) */}
        <div style={{ height: 6 }} />
        <div style={{ height: 1, background: 'var(--border-color)', margin: '0 16px' }} />
        <div style={{ height: 8 }} />

        {/* Chats Historial (Fijados y Recientes) */}
        <div className="conv-list" style={{ flex: 1, overflowY: 'auto', paddingBottom: 130 }}>
          {filteredConvs.some((c) => c.is_starred) && (
            <div style={{ padding: '6px 20px 4px 20px', fontSize: '11.5px', fontWeight: 700, color: 'var(--text-secondary)', letterSpacing: '-0.1px', fontFamily: 'AnthropicSans, sans-serif' }}>
              Destacados
            </div>
          )}
          {filteredConvs.filter((c) => c.is_starred).map((conv) => renderConvItem(conv, true))}
          {filteredConvs.some((c) => c.is_starred) && <div style={{ height: 10 }} />}

          {/* Recientes (siempre visible, paridad móvil) */}
          <div style={{ padding: '6px 20px 4px 20px', fontSize: '11.5px', fontWeight: 700, color: 'var(--text-secondary)', letterSpacing: '-0.1px', fontFamily: 'AnthropicSans, sans-serif' }}>
            Recientes
          </div>
          {filteredConvs.filter((c) => !c.is_starred).map((conv) => renderConvItem(conv, false))}

          {filteredConvs.length === 0 && (
            <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', padding: '32px 24px' }}>
              <div style={{
                width: 56, height: 56, borderRadius: '50%',
                background: 'var(--surface-input)', border: '1px solid var(--border-color)',
                display: 'flex', alignItems: 'center', justifyContent: 'center', marginBottom: 16
              }}>
                <MessageSquare size={26} color="var(--amber-exodo)" />
              </div>
              <div style={{ fontSize: '13px', fontWeight: 600, color: 'var(--text-secondary)', letterSpacing: '-0.1px', fontFamily: 'AnthropicSans, sans-serif', textAlign: 'center' }}>
                {conversations.length === 0 ? 'Sin historial todavía' : 'Sin resultados'}
              </div>
              <div style={{ fontSize: '12px', color: 'var(--text-secondary)', opacity: 0.7, lineHeight: 1.4, fontFamily: 'Inter, sans-serif', textAlign: 'center', marginTop: 6 }}>
                {conversations.length === 0 ? 'Inicia una conversación para verla aquí.' : 'Prueba con otra búsqueda.'}
              </div>
            </div>
          )}
        </div>
        {renderConvContextSheet()}

        <div style={{ borderTop: '1px solid var(--border-color)', position: 'relative', background: 'var(--surface-card)' }}>
          {session?.user && !isGuestUser ? (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 10, padding: '12px 20px 14px 20px', cursor: 'pointer' }} onClick={() => setShowAccountMenu(true)}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 12, overflow: 'hidden' }}>
                {(session.user.user_metadata?.avatar_url || session.user.user_metadata?.picture) ? (
                  <img
                    src={session.user.user_metadata?.avatar_url || session.user.user_metadata?.picture}
                    alt="Avatar"
                    style={{ width: 38, height: 38, borderRadius: '50%', objectFit: 'cover', flexShrink: 0 }}
                  />
                ) : (
                  <div style={{
                    width: 38,
                    height: 38,
                    borderRadius: '50%',
                    background: 'var(--amber-exodo)',
                    color: '#000000',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    fontFamily: 'Syne, sans-serif',
                    fontWeight: 700,
                    fontSize: '19px',
                    flexShrink: 0
                  }}>
                    {((userProfile?.full_name || '').trim().charAt(0) || 'U').toUpperCase()}
                  </div>
                )}
                <span style={{ fontSize: '14px', fontWeight: 600, color: 'var(--text-primary)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', letterSpacing: '-0.2px', fontFamily: 'AnthropicSans, sans-serif' }}>
                  {(userProfile?.full_name || '').trim() || 'Usuario Éxodo'}
                </span>
              </div>
              <img src="/bybehavior_text.png" alt="by Behavior" style={{ height: 18, objectFit: 'contain', objectPosition: 'left', opacity: 0.75 }} />
            </div>
          ) : (
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '12px 16px' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 12, overflow: 'hidden' }}>
                <div style={{
                  width: 34,
                  height: 34,
                  borderRadius: '50%',
                  background: 'var(--text-primary)',
                  color: '#0E0C0A',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  fontWeight: 600,
                  fontSize: '1rem',
                  flexShrink: 0
                }}>
                  U
                </div>
                <div style={{ display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
                  <span style={{ fontSize: '0.92rem', fontWeight: 500, color: 'var(--text-primary)' }}>
                    Usuario Éxodo
                  </span>
                  <span style={{ fontSize: '0.78rem', color: '#9E9689' }}>
                    Invitado
                  </span>
                </div>
              </div>
              <button
                type="button"
                onClick={() => { setDrawerOpen(false); setShowAuthModal(true); }}
                style={{
                  padding: '6px 12px',
                  borderRadius: 8,
                  background: 'var(--amber-exodo)',
                  color: '#0E0C0A',
                  border: 'none',
                  fontWeight: 700,
                  fontSize: '0.8rem',
                  cursor: 'pointer',
                  flexShrink: 0
                }}
              >
                Acceder
              </button>
            </div>
          )}
        </div>
      </aside>

      {/* 3. Área Principal de Chat Exacta a Móvil / Claude Centrado */}
      <main className={`chat-main ${isIncognito ? 'incognito-mode' : ''}`}>
        {/* Barra superior responsiva al zoom (solo iconos derechos ya que menú está en la barra lateral) */}
        <header className="chat-header-bar">
          <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            <button 
              type="button" 
              className="icon-btn" 
              onClick={handleCreateNewChat}
              title="Nuevo chat"
            >
              <MessageSquare size={20} />
            </button>

            <button 
              type="button" 
              className="icon-btn" 
              onClick={() => setTheme(theme === 'dark' ? 'light' : 'dark')}
              title="Cambiar tema"
            >
              {theme === 'dark' ? <Sun size={20} /> : <Moon size={20} />}
            </button>

            <button 
              type="button" 
              className="icon-btn" 
              onClick={() => handleToggleIncognito()}
              title={isIncognito ? "Modo Incógnito activo" : "Modo Incógnito"}
              style={{ color: isIncognito ? 'var(--amber-exodo)' : undefined }}
            >
              <div 
                className="mask-icon-incognito" 
                style={{ 
                  backgroundColor: isIncognito ? 'var(--amber-exodo)' : undefined 
                }} 
              />
            </button>
          </div>
        </header>

        {isInitializing ? (
          <div style={{ flex: 1 }} />
        ) : !messages.some((m) => m.role === 'user') ? (
          <div className="welcome-center">
            {/* Paridad chat_stage móvil: saludo centrado 22px bold (2 líneas)
                + watermark debajo (40% ancho, aspecto 7.02, gap 16) */}
            <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', marginBottom: 36, padding: '0 24px' }}>
              {!isIncognito && (
                <>
                  <div className="greeting-text-exodo" style={{ textAlign: 'center', maxWidth: '100%', overflow: 'hidden', display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical' }}>
                    {getExodoGreeting()}
                  </div>
                  <img
                    src={(theme === 'dark' || isIncognito) ? '/watermark2.png' : '/watermark1.png'}
                    alt=""
                    draggable={false}
                    style={{ width: 'min(40vw, 340px)', aspectRatio: '7.0208', objectFit: 'fill', marginTop: 16, pointerEvents: 'none', userSelect: 'none' }}
                  />
                </>
              )}
              {isIncognito && (
                <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
                  <div className="greeting-text-exodo" style={{ textAlign: 'center' }}>
                    Incógnito
                  </div>
                  <div style={{ fontSize: '14px', color: 'var(--text-secondary)', textAlign: 'center', maxWidth: 480, lineHeight: 1.4, marginTop: 4 }}>
                    Los chats de incógnito no se guardan en el historial.
                  </div>
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
                {messages.map((msg) => (
                  <div key={msg.id} className={`msg-row ${msg.role}`}>
                    <div style={{ display: 'flex', flexDirection: 'column', alignItems: msg.role === 'user' ? 'flex-end' : 'flex-start', maxWidth: '100%', width: msg.role === 'assistant' ? '100%' : 'auto' }}>
                      {/* Paridad móvil: contenido vacío + adjuntos = solo adjuntos, sin marco */}
                      {!(msg.role === 'user' && !msg.content.trim() && msg.attachments && msg.attachments.length > 0) && (
                      <div className="msg-bubble markdown-body">
                        {msg.isThinking ? (
                          <ThinkingIndicator />
                        ) : msg.role === 'assistant' ? (
                          <ArtifactMessageBody
                            content={msg.content}
                            isStreaming={isStreaming && msg.id === messages[messages.length - 1]?.id}
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
                        <div style={{ display: 'flex', alignItems: 'center', gap: '6px', fontSize: '10px', color: 'var(--text-secondary)', marginTop: '3px', opacity: 0.7, paddingRight: '6px', fontFamily: 'Inter, sans-serif' }}>
                          <button style={{ background: 'transparent', border: 'none', cursor: 'pointer', padding: 0, display: 'flex', alignItems: 'center', color: 'inherit' }} onClick={() => editMessage(msg)} title="Editar">
                            <Edit2 size={14} />
                          </button>
                          <button style={{ background: 'transparent', border: 'none', cursor: 'pointer', padding: 0, display: 'flex', alignItems: 'center', color: 'inherit' }} onClick={() => navigator.clipboard.writeText(msg.content)} title="Copiar">
                            <div style={{ width: 14, height: 14, backgroundColor: 'currentColor', WebkitMaskImage: 'url(/copy-2-svgrepo-com.png)', WebkitMaskSize: 'contain', WebkitMaskRepeat: 'no-repeat', maskImage: 'url(/copy-2-svgrepo-com.png)', maskSize: 'contain', maskRepeat: 'no-repeat' }} />
                          </button>
                          <span>{new Date(msg.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</span>
                        </div>
                      )}

                      {msg.role === 'assistant' && !msg.isThinking && msg.id !== 'welcome-1' && (
                        <div className="ai-actions-bar" style={{ display: 'flex', gap: '8px', marginTop: '8px', paddingLeft: '4px', opacity: 0.7 }}>
                          <button className="action-btn" onClick={() => navigator.clipboard.writeText(msg.content)} title="Copiar">
                            <div style={{ width: 16, height: 16, backgroundColor: 'var(--text-secondary)', WebkitMaskImage: 'url(/copy-2-svgrepo-com.png)', WebkitMaskSize: 'contain', WebkitMaskRepeat: 'no-repeat', maskImage: 'url(/copy-2-svgrepo-com.png)', maskSize: 'contain', maskRepeat: 'no-repeat' }} />
                          </button>
                          <button className="action-btn" onClick={() => { setFeedbackComment(''); setFeedbackTarget({ msg, isLike: true }); }} title="Me gusta">
                            <div style={{ width: 16, height: 16, backgroundColor: 'var(--text-secondary)', WebkitMaskImage: 'url(/like-1-svgrepo-com.png)', WebkitMaskSize: 'contain', WebkitMaskRepeat: 'no-repeat', maskImage: 'url(/like-1-svgrepo-com.png)', maskSize: 'contain', maskRepeat: 'no-repeat' }} />
                          </button>
                          <button className="action-btn" onClick={() => { setFeedbackComment(''); setFeedbackTarget({ msg, isLike: false }); }} title="No me gusta">
                            <div style={{ width: 16, height: 16, backgroundColor: 'var(--text-secondary)', WebkitMaskImage: 'url(/like-1-svgrepo-com.png)', WebkitMaskSize: 'contain', WebkitMaskRepeat: 'no-repeat', maskImage: 'url(/like-1-svgrepo-com.png)', maskSize: 'contain', maskRepeat: 'no-repeat', transform: 'scaleY(-1)' }} />
                          </button>
                          <button className="action-btn" onClick={() => shareMessage(msg.content)} title="Compartir">
                            <div style={{ width: 16, height: 16, backgroundColor: 'var(--text-secondary)', WebkitMaskImage: 'url(/share-svgrepo-com.png)', WebkitMaskSize: 'contain', WebkitMaskRepeat: 'no-repeat', maskImage: 'url(/share-svgrepo-com.png)', maskSize: 'contain', maskRepeat: 'no-repeat' }} />
                          </button>
                        </div>
                      )}
                    </div>
                  </div>
                ))}
                <div ref={messagesEndRef} />
              </div>
            </div>

            {showScrollDown && (
              <button
                onClick={scrollToBottom}
                style={{
                  position: 'absolute',
                  bottom: '90px',
                  right: '24px',
                  width: '40px',
                  height: '40px',
                  borderRadius: '20px',
                  backgroundColor: theme === 'light' ? '#F5F2EB' : 'var(--surface-input)',
                  border: theme === 'light' ? '1px solid #EAE5D9' : 'none',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  cursor: 'pointer',
                  zIndex: 20,
                  boxShadow: theme === 'light' ? '0 2px 8px rgba(0,0,0,0.1)' : '0 2px 8px rgba(0,0,0,0.45)'
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

      {/* Hoja modal de Fuentes (paridad _SourcesSheet móvil) */}
      {openSourcesId && (() => {
        const openMsg = messages.find((m) => m.id === openSourcesId);
        const vs = openMsg ? validSourcesOf(openMsg) : [];
        if (vs.length === 0) return null;
        const labels = getSourceLabels(locale);
        return (
          <div className="sources-overlay" onClick={() => setOpenSourcesId(null)}>
            <div className="sources-sheet" onClick={(e) => e.stopPropagation()}>
              <div className="sources-sheet-header">
                <span className="sources-sheet-title">{labels.consulted}</span>
                <button
                  type="button"
                  className="sources-sheet-close"
                  onClick={() => setOpenSourcesId(null)}
                  aria-label="Cerrar"
                >
                  <X size={18} />
                </button>
              </div>
              <div className="sources-list">
                {vs.map((s, idx) => (
                  <button
                    key={`${s.url}-${idx}`}
                    type="button"
                    className="source-item"
                    onClick={() => s.url && openSourceUrl(s.url)}
                  >
                    <span
                      className="source-item-avatar"
                      style={{ background: SOURCE_CIRCLE_COLORS[idx % SOURCE_CIRCLE_COLORS.length] }}
                    >
                      {sourceInitials(s)}
                    </span>
                    <span className="source-item-text">
                      <span className="source-item-title">{s.title || s.url}</span>
                      {s.url ? <span className="source-item-url">{s.url}</span> : null}
                    </span>
                    {s.url ? <ExternalLink size={18} className="source-item-open" /> : null}
                  </button>
                ))}
              </div>
            </div>
          </div>
        );
      })()}

      {/* Settings bottom sheet (paridad _ClaudeAccountModal móvil) */}
      {showAccountMenu && (
        <div style={{ position: 'fixed', inset: 0, zIndex: 1000 }}>
          <div style={{ position: 'absolute', inset: 0, background: 'rgba(0, 0, 0, 0.6)', backdropFilter: 'blur(4px)' }} onClick={() => setShowAccountMenu(false)} />

          <div style={{
            position: 'absolute',
            left: 0,
            right: 0,
            bottom: 0,
            background: 'var(--surface-card)',
            borderRadius: '28px 28px 0 0',
            padding: '12px 20px calc(24px + env(safe-area-inset-bottom, 0px))',
            maxWidth: 640,
            margin: '0 auto',
            maxHeight: '88vh',
            overflowY: 'auto'
          }}>
            <div style={{ width: 36, height: 4, borderRadius: 2, background: 'var(--text-secondary)', opacity: 0.3, margin: '0 auto 16px auto' }} />
            <h2 style={{ textAlign: 'center', fontSize: '18px', fontWeight: 700, fontFamily: 'Syne, sans-serif', color: 'var(--text-primary)', margin: '0 0 20px 0' }}>Settings</h2>

            <div style={{ background: 'var(--surface-input)', borderRadius: 16, padding: '14px 16px', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
              <span style={{ fontSize: '14px', fontWeight: 600, color: 'var(--text-primary)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', letterSpacing: '-0.2px', fontFamily: 'AnthropicSans, sans-serif' }}>
                {session?.user?.email || 'Sin correo'}
              </span>
              <div style={{ background: 'var(--text-primary)', color: 'var(--surface-card)', padding: '4px 10px', borderRadius: 20, fontSize: '12px', fontWeight: 700, marginLeft: 12, flexShrink: 0 }}>
                {userProfile?.plan === 'hazak' ? 'Pro' : 'Free'}
              </div>
            </div>

            <div style={{ height: 16 }} />

            <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
              {!isGuestUser && (
              <div style={{ background: 'var(--surface-input)', borderRadius: 16, padding: '18px 20px', display: 'flex', alignItems: 'center', justifyContent: 'space-between', cursor: 'pointer' }} onClick={() => { setShowAccountMenu(false); setShowProfileMenu(true); }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
                  <MaterialProfileIcon size={22} color="var(--text-primary)" />
                  <span style={{ fontSize: '1.05rem', fontWeight: 600, color: 'var(--text-primary)' }}>Profile</span>
                </div>
                <ChevronRight size={20} color="var(--text-secondary)" />
              </div>
              )}

              <div style={{ background: 'var(--surface-input)', borderRadius: 16, padding: '14px 20px', display: 'flex', alignItems: 'center', justifyContent: 'space-between', cursor: 'pointer' }} onClick={() => { setShowAccountMenu(false); setShowLanguageMenu(true); }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
                  <Globe size={22} color="var(--text-primary)" />
                  <div style={{ display: 'flex', flexDirection: 'column' }}>
                    <span style={{ fontSize: '1.05rem', fontWeight: 600, color: 'var(--text-primary)' }}>Language</span>
                    <span style={{ fontSize: '0.85rem', color: 'var(--text-secondary)' }}>{localeDisplayName}</span>
                  </div>
                </div>
                <ChevronRight size={20} color="var(--text-secondary)" />
              </div>

              {!isGuestUser && (
              <div style={{ background: 'var(--surface-input)', borderRadius: 16, padding: '18px 20px', display: 'flex', alignItems: 'center', justifyContent: 'space-between', cursor: 'pointer' }} onClick={() => { setShowAccountMenu(false); setShowBillingMenu(true); }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
                  <MaterialBillingIcon size={22} color="var(--text-primary)" />
                  <span style={{ fontSize: '1.05rem', fontWeight: 600, color: 'var(--text-primary)' }}>Billing</span>
                </div>
                <ChevronRight size={20} color="var(--text-secondary)" />
              </div>
              )}

              <div style={{ background: 'var(--surface-input)', borderRadius: 16, padding: '18px 20px', display: 'flex', alignItems: 'center', justifyContent: 'space-between', cursor: 'pointer' }} onClick={() => { try { (window as any).open('https://play.google.com/store/apps/details?id=com.behavior.exodo', '_blank'); } catch (_) {} }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
                  <Smartphone size={22} color="var(--text-primary)" />
                  <span style={{ fontSize: '1.05rem', fontWeight: 600, color: 'var(--text-primary)' }}>Exodo App</span>
                </div>
                <ChevronRight size={20} color="var(--text-secondary)" />
              </div>
            </div>

            {/* Historial en la nube (paridad drawer móvil: switch con consentimiento) */}
            <div style={{ marginTop: 12, marginBottom: 12, background: 'var(--surface-input)', borderRadius: 16, padding: '14px 16px', display: 'flex', alignItems: 'center', gap: 16 }}>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: '13.5px', fontWeight: 600, color: cloudHistoryEnabled ? 'var(--text-primary)' : 'var(--amber-exodo)', fontFamily: 'AnthropicSans, sans-serif' }}>
                  Historial en la nube
                </div>
                <div style={{ fontSize: '10.5px', color: 'var(--text-secondary)', marginTop: 2, lineHeight: 1.3, fontFamily: 'AnthropicSans, sans-serif' }}>
                  {cloudHistoryEnabled
                    ? 'Tus chats se guardan y dan contexto a Éxodo.'
                    : 'Apagado: turnos efímeros, sin guardar ni contexto previo.'}
                </div>
              </div>
              <button
                type="button"
                role="switch"
                aria-checked={cloudHistoryEnabled}
                aria-label="Historial en la nube"
                onClick={() => toggleCloudHistory(!cloudHistoryEnabled)}
                style={{
                  width: 46, height: 26, borderRadius: 13, border: 'none', cursor: 'pointer',
                  background: cloudHistoryEnabled ? 'var(--amber-exodo)' : 'rgba(128,128,128,0.4)',
                  position: 'relative', flexShrink: 0, transition: 'background 0.15s'
                }}
              >
                <span style={{
                  position: 'absolute', top: 3, left: cloudHistoryEnabled ? 23 : 3,
                  width: 20, height: 20, borderRadius: '50%', background: '#fff',
                  transition: 'left 0.15s'
                }} />
              </button>
            </div>

            <div style={{ background: 'var(--surface-input)', borderRadius: 16, padding: '18px 20px', display: 'flex', alignItems: 'center', justifyContent: 'space-between', cursor: 'pointer' }} onClick={() => setShowTerms(true)}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
                <MaterialPrivacyIcon size={22} color="var(--text-primary)" />
                <span style={{ fontSize: '1.05rem', fontWeight: 600, color: 'var(--text-primary)' }}>Terms & Privacy</span>
              </div>
              <ChevronRight size={20} color="var(--text-secondary)" />
            </div>

            <div style={{ height: 16 }} />
            <div style={{ height: 1, background: 'var(--border-color)' }} />
            <div style={{ height: 8 }} />

            {/* Log out 100% plano (paridad móvil): sin caja, solo icono + texto rojo */}
            <div style={{ padding: '12px 8px', display: 'flex', alignItems: 'center', gap: 14, cursor: 'pointer' }} onClick={() => { setShowAccountMenu(false); supabase.auth.signOut(); }}>
              <LogOut size={22} color="#E05252" />
              <span style={{ fontSize: '15px', fontWeight: 600, color: '#E05252', letterSpacing: '-0.2px', fontFamily: 'AnthropicSans, sans-serif' }}>Log out</span>
            </div>

            <div style={{ height: 24 }} />
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, opacity: 0.6 }}>
              <img src="/Logo_behavior.png" alt="Éxodo" style={{ height: 16, objectFit: 'contain' }} />
              <span style={{ fontSize: '12px', color: 'var(--text-secondary)', fontFamily: 'AnthropicSans, sans-serif' }}>Éxodo Web</span>
            </div>
          </div>
        </div>
      )}

      {/* Profile pantalla completa (paridad ProfileScreen móvil) */}
      {showProfileMenu && (
        <div style={{ position: 'fixed', inset: 0, zIndex: 1000, background: 'var(--bg-color)', display: 'flex', flexDirection: 'column', overflowY: 'auto' }}>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '16px 12px', position: 'relative' }}>
            <button
              type="button"
              onClick={() => { setShowProfileMenu(false); setShowAccountMenu(true); }}
              style={{ background: 'none', border: 'none', cursor: 'pointer', padding: '8px', display: 'flex', position: 'absolute', left: 12 }}
            >
              <ArrowLeft size={24} color="var(--text-primary)" />
            </button>
            <h2 style={{ fontSize: '20px', fontWeight: 700, fontFamily: 'Syne, sans-serif', color: 'var(--text-primary)', margin: 0 }}>
              Profile
            </h2>
          </div>

          <div style={{ flex: 1, overflowY: 'auto', padding: '24px', maxWidth: 640, width: '100%', margin: '0 auto', boxSizing: 'border-box' }}>
              
              <div style={{ display: 'flex', justifyContent: 'center', marginBottom: 32 }}>
                <div style={{
                  width: 80,
                  height: 80,
                  borderRadius: '50%',
                  background: 'rgba(201, 147, 58, 0.2)', // ExodoColors.amber con alpha
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  overflow: 'hidden'
                }}>
                  {(session?.user?.user_metadata?.avatar_url || session?.user?.user_metadata?.picture) ? (
                    <img 
                      src={session.user.user_metadata?.avatar_url || session.user.user_metadata?.picture} 
                      alt="Avatar" 
                      style={{ width: '100%', height: '100%', objectFit: 'cover' }} 
                    />
                  ) : (
                    <span style={{ fontFamily: 'Syne, sans-serif', fontSize: '2rem', fontWeight: 700, color: 'var(--amber-exodo)' }}>
                      {(userProfile?.full_name || session?.user?.email || 'U').charAt(0).toUpperCase()}
                    </span>
                  )}
                </div>
              </div>

              <div style={{ display: 'flex', flexDirection: 'column', gap: 24 }}>
                
                <div>
                  <label style={{ display: 'block', fontSize: '0.9rem', fontWeight: 600, color: 'var(--text-primary)', marginBottom: 8, fontFamily: 'Inter, sans-serif' }}>
                    Full name
                  </label>
                  <input 
                    type="text" 
                    id="exodo-profile-fullname"
                    defaultValue={userProfile?.full_name || session?.user?.email?.split('@')[0] || ''}
                    placeholder="Enter your full name"
                    style={{ 
                      width: '100%', 
                      background: 'var(--surface-input)', 
                      border: 'none', 
                      borderRadius: 14, 
                      padding: '16px', 
                      color: 'var(--text-primary)', 
                      fontSize: '0.95rem',
                      fontFamily: 'Inter, sans-serif'
                    }} 
                  />
                </div>

                <div>
                  <label style={{ display: 'block', fontSize: '0.9rem', fontWeight: 600, color: 'var(--text-primary)', marginBottom: 8, fontFamily: 'Inter, sans-serif' }}>
                    What should we call you?
                  </label>
                  <input 
                    type="text" 
                    id="exodo-profile-nickname"
                    defaultValue={userProfile?.onboarding?.nickname || ''}
                    placeholder="Nickname"
                    style={{ 
                      width: '100%', 
                      background: 'var(--surface-input)', 
                      border: 'none', 
                      borderRadius: 14, 
                      padding: '16px', 
                      color: 'var(--text-primary)', 
                      fontSize: '0.95rem',
                      fontFamily: 'Inter, sans-serif'
                    }} 
                  />
                </div>

                <div style={{ marginTop: 12 }}>
                  <button type="button" onClick={async () => {
                    const fn = (document.getElementById('exodo-profile-fullname') as HTMLInputElement)?.value ?? '';
                    const nn = (document.getElementById('exodo-profile-nickname') as HTMLInputElement)?.value ?? '';
                    const ok = await saveProfile(fn, nn);
                    if (ok) { setShowProfileMenu(false); setShowAccountMenu(true); }
                    else alert('No se pudo guardar el perfil. Intenta de nuevo.');
                  }} style={{ 
                    width: '100%', 
                    background: 'var(--surface-input)', 
                    color: 'var(--text-primary)', 
                    border: 'none', 
                    borderRadius: 14, 
                    padding: '16px', 
                    fontSize: '1rem', 
                    fontWeight: 700,
                    fontFamily: 'Inter, sans-serif',
                    cursor: 'pointer'
                  }}>
                    Update profile
                  </button>
                </div>

                {/* Export Data (paridad ProfileScreen: outlined ámbar) */}
                <div style={{ marginTop: 16 }}>
                  <button type="button" onClick={exportMyData} style={{
                    width: '100%', height: 52,
                    display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
                    background: 'transparent', color: 'var(--amber-exodo)',
                    border: '1px solid var(--amber-exodo)', borderRadius: 14,
                    fontSize: '15px', fontWeight: 600, fontFamily: 'Inter, sans-serif', cursor: 'pointer'
                  }}>
                    <Download size={20} />
                    Export my data
                  </button>
                </div>

                <div style={{ display: 'flex', flexDirection: 'column', gap: 16, marginTop: 16 }}>
                  <button type="button" onClick={clearHistory} style={{ 
                    display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
                    width: '100%', background: 'transparent', color: 'var(--text-primary)', 
                    border: 'none', borderRadius: 14, padding: '14px', 
                    fontSize: '0.95rem', fontWeight: 500, fontFamily: 'Inter, sans-serif', cursor: 'pointer'
                  }}>
                    <Trash2 size={20} />
                    Clear History
                  </button>
                  
                  <button type="button" onClick={() => { setShowProfileMenu(false); deleteMyAccount(); }} style={{ 
                    display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
                    width: '100%', background: 'transparent', color: '#E57373', 
                    border: 'none', borderRadius: 14, padding: '16px', 
                    fontSize: '0.95rem', fontWeight: 600, fontFamily: 'Inter, sans-serif', cursor: 'pointer'
                  }}>
                    <Trash2 size={20} />
                    Delete account
                  </button>
                </div>

              </div>
          </div>
        </div>
      )}

      {/* Language bottom sheet (paridad _showLanguageSheet móvil) */}
      {showLanguageMenu && (
        <div style={{ position: 'fixed', inset: 0, zIndex: 1000 }}>
          <div style={{ position: 'absolute', inset: 0, background: 'rgba(0, 0, 0, 0.6)', backdropFilter: 'blur(4px)' }} onClick={() => setShowLanguageMenu(false)} />

          <div style={{
            position: 'absolute', left: 0, right: 0, bottom: 0,
            background: 'var(--surface-card)', borderRadius: '24px 24px 0 0',
            padding: '12px 0 calc(8px + env(safe-area-inset-bottom, 0px))',
            maxWidth: 640, margin: '0 auto', maxHeight: '75vh',
            display: 'flex', flexDirection: 'column', overflow: 'hidden'
          }}>
            <div style={{ width: 36, height: 4, borderRadius: 2, background: 'var(--text-secondary)', opacity: 0.3, margin: '0 auto 12px auto', flexShrink: 0 }} />
            <div style={{ padding: '4px 20px' }}>
              <h2 style={{ fontSize: '18px', fontWeight: 700, fontFamily: 'Syne, sans-serif', color: 'var(--text-primary)', margin: 0, textAlign: 'left' }}>
                App language
              </h2>
            </div>
            <div style={{ padding: '0 20px 12px 20px' }}>
              <span style={{ fontSize: '12.5px', color: 'var(--text-secondary)', fontFamily: 'Inter, sans-serif' }}>
                Select your preferred language
              </span>
            </div>

            <div style={{ overflowY: 'auto', paddingBottom: 8 }}>
              {[
                { flag: '🌐', title: 'System', subtitle: 'Auto-detect', code: null },
                { flag: '🇲🇽', title: 'Español (Latinoamérica)', subtitle: 'ES', code: 'es' },
                { flag: '🇺🇸', title: 'English (US)', subtitle: 'EN', code: 'en' },
                { flag: '🇬🇧', title: 'English (UK)', subtitle: 'EN_GB', code: 'en_GB' },
                { flag: '🇧🇷', title: 'Português (Brasil)', subtitle: 'PT_BR', code: 'pt_BR' },
                { flag: '🇵🇹', title: 'Português (Portugal)', subtitle: 'PT', code: 'pt' },
                { flag: '🇫🇷', title: 'Français', subtitle: 'FR', code: 'fr' },
                { flag: '🇭🇹', title: 'Kreyòl Ayisyen', subtitle: 'HT', code: 'ht' },
                { flag: '🇮🇹', title: 'Italiano', subtitle: 'IT', code: 'it' },
                { flag: '🇩🇪', title: 'Deutsch', subtitle: 'DE', code: 'de' },
                { flag: '🇷🇺', title: 'Русский', subtitle: 'RU', code: 'ru' },
                { flag: '🇨🇳', title: '中文', subtitle: 'ZH', code: 'zh' },
                { flag: '🇯🇵', title: '日本語', subtitle: 'JA', code: 'ja' },
                { flag: '🇸🇦', title: 'العربية', subtitle: 'AR', code: 'ar' },
                { flag: '🇰🇷', title: '한국어', subtitle: 'KO', code: 'ko' },
                { flag: '🇮🇳', title: 'हिन्दी', subtitle: 'HI', code: 'hi' }
              ].map((lang, idx) => (
                <div key={lang.title}>
                  {idx === 1 && <div style={{ height: 1, background: 'var(--border-color)', margin: '0 20px' }} />}
                  <div
                    style={{
                      padding: '12px 20px',
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'space-between',
                      cursor: 'pointer'
                    }}
                    onClick={() => {
                      const selectedCode = lang.code || 'es';
                      setLocale(selectedCode);
                      localStorage.setItem('exodo_web_locale', selectedCode);
                      setShowLanguageMenu(false);
                      setShowAccountMenu(true);
                    }}
                  >
                    <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
                      <span style={{ fontSize: '22px', width: 28, textAlign: 'center' }}>{lang.flag}</span>
                      <div style={{ display: 'flex', flexDirection: 'column' }}>
                        <span style={{
                          fontSize: '15px',
                          fontWeight: (locale === lang.code || (!lang.code && locale.startsWith('es'))) ? 700 : 500,
                          color: 'var(--text-primary)',
                          fontFamily: 'Inter, sans-serif'
                        }}>
                          {lang.title}
                        </span>
                        <span style={{ fontSize: '12px', color: 'var(--text-secondary)', fontFamily: 'Inter, sans-serif' }}>
                          {lang.subtitle}
                        </span>
                      </div>
                    </div>
                    {(locale === lang.code || (!lang.code && locale.startsWith('es'))) && (
                      <Check size={20} color="var(--amber-exodo)" />
                    )}
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>
      )}

      {/* Billing bottom sheet (paridad _showBillingModal móvil) */}
      {showBillingMenu && (
        <div style={{ position: 'fixed', inset: 0, zIndex: 1000 }}>
          <div style={{ position: 'absolute', inset: 0, background: 'rgba(0, 0, 0, 0.6)', backdropFilter: 'blur(4px)' }} onClick={() => setShowBillingMenu(false)} />

          <div style={{
            position: 'absolute', left: 0, right: 0, bottom: 0,
            background: 'var(--surface-card)', borderRadius: '24px 24px 0 0',
            padding: '12px 24px calc(24px + env(safe-area-inset-bottom, 0px))',
            maxWidth: 640, margin: '0 auto', maxHeight: '80vh', overflowY: 'auto'
          }}>
            <div style={{ width: 36, height: 4, borderRadius: 2, background: 'var(--text-secondary)', opacity: 0.3, margin: '0 auto 16px auto' }} />
            <h2 style={{ fontSize: '18px', fontWeight: 700, fontFamily: 'Inter, sans-serif', color: 'var(--text-primary)', margin: '0 0 16px 0' }}>
              Billing
            </h2>

            <div style={{
              background: 'var(--surface-input)',
              borderRadius: 16,
              padding: '20px',
              display: 'flex',
              flexDirection: 'column',
              gap: 16
            }}>
              <div>
                <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.8rem', marginBottom: 6 }}>
                  <span style={{ color: 'var(--text-secondary)' }}>Consumido</span>
                  <span style={{ fontWeight: 700, color: 'var(--text-primary)' }}>{tokensUsed} ({tokensLimit > 0 ? ((tokensUsed / tokensLimit) * 100).toFixed(1) : '0'}%)</span>
                </div>
                <div className="token-bar-progress" style={{ width: '100%' }}>
                  <div className="token-bar-fill" style={{ width: `${Math.min(100, (tokensUsed / tokensLimit) * 100)}%` }} />
                </div>
              </div>

              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <span style={{ fontSize: '0.95rem', color: 'var(--text-secondary)', fontFamily: 'Inter, sans-serif' }}>
                  Current plan
                </span>
                <span style={{ fontSize: '1rem', fontWeight: 700, color: 'var(--amber-exodo)', fontFamily: 'Inter, sans-serif' }}>
                  {userProfile?.plan === 'hazak' ? 'Pro' : 'Free'}
                </span>
              </div>

              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <span style={{ fontSize: '0.95rem', color: 'var(--text-secondary)', fontFamily: 'Inter, sans-serif' }}>
                  Gateway
                </span>
                <span style={{ fontSize: '1rem', color: 'var(--text-primary)', fontFamily: 'Inter, sans-serif' }}>
                  {userProfile?.plan === 'hazak' ? 'Stripe / Web Pay' : 'None'}
                </span>
              </div>
            </div>

            <div style={{ marginTop: 24 }}>
              {userProfile?.plan === 'hazak' ? (
                <button type="button" onClick={cancelProPlan} style={{
                  width: '100%',
                  background: 'transparent',
                  color: '#E57373',
                  border: '1px solid #E57373',
                  borderRadius: 14,
                  padding: '16px',
                  fontSize: '1rem',
                  fontWeight: 700,
                  fontFamily: 'Inter, sans-serif',
                  cursor: 'pointer'
                }}>
                  Cancel Subscription
                </button>
              ) : (
                <button type="button" onClick={() => { setShowBillingMenu(false); startCheckout(isAnnualPlan); }} style={{
                  width: '100%',
                  background: 'var(--amber-exodo)',
                  color: '#000000',
                  border: 'none',
                  borderRadius: 14,
                  padding: '16px',
                  fontSize: '1rem',
                  fontWeight: 700,
                  fontFamily: 'Inter, sans-serif',
                  cursor: 'pointer'
                }}>
                  Upgrade to Pro
                </button>
              )}
            </div>

          </div>
        </div>
      )}

      {/* Plans Page (Full Screen) */}
      {showPlansModal && (
        <div style={{ position: 'fixed', inset: 0, zIndex: 1000, background: 'var(--bg-color)', display: 'flex', flexDirection: 'column', overflowY: 'auto' }}>
          
          <div style={{ padding: '24px', display: 'flex', alignItems: 'center' }}>
            <button 
              type="button" 
              onClick={() => setShowPlansModal(false)}
              style={{ background: 'none', border: 'none', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center' }}
            >
              <ArrowLeft size={24} color="var(--text-primary)" />
            </button>
          </div>

          <div style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', padding: '0 24px 64px' }}>
            
            <h2 style={{ fontSize: '2.5rem', fontWeight: 700, fontFamily: 'Syne, sans-serif', color: 'var(--text-primary)', marginBottom: '32px', textAlign: 'center' }}>
              Planes que crecen contigo
            </h2>

            {/* Monthly / Annual Toggle */}
            <div style={{ 
              display: 'flex', 
              background: 'var(--surface-input)', 
              borderRadius: 24, 
              padding: 4, 
              marginBottom: 48,
              border: '1px solid var(--border-color)'
            }}>
              <button 
                type="button" 
                onClick={() => setIsAnnualPlan(false)}
                style={{ 
                  background: !isAnnualPlan ? 'var(--surface-card)' : 'transparent',
                  color: !isAnnualPlan ? 'var(--text-primary)' : 'var(--text-secondary)',
                  border: 'none',
                  borderRadius: 20,
                  padding: '10px 24px',
                  fontSize: '0.9rem',
                  fontWeight: 600,
                  fontFamily: 'Inter, sans-serif',
                  cursor: 'pointer',
                  transition: 'all 0.2s'
                }}
              >
                Mensual
              </button>
              <button 
                type="button" 
                onClick={() => setIsAnnualPlan(true)}
                style={{ 
                  background: isAnnualPlan ? 'var(--surface-card)' : 'transparent',
                  color: isAnnualPlan ? 'var(--text-primary)' : 'var(--text-secondary)',
                  border: 'none',
                  borderRadius: 20,
                  padding: '10px 24px',
                  fontSize: '0.9rem',
                  fontWeight: 600,
                  fontFamily: 'Inter, sans-serif',
                  cursor: 'pointer',
                  display: 'flex',
                  alignItems: 'center',
                  gap: 8,
                  transition: 'all 0.2s'
                }}
              >
                Anual
                <span style={{ color: 'var(--amber-exodo)', fontSize: '0.75rem', fontWeight: 700 }}>Ahorra 16%</span>
              </button>
            </div>

            {/* Cards Container */}
            <div style={{ display: 'flex', gap: 24, flexWrap: 'wrap', justifyContent: 'center', maxWidth: 1000, width: '100%' }}>
              
              {/* Free Card */}
              <div style={{ 
                flex: '1 1 320px',
                maxWidth: 360,
                background: 'var(--surface-card)',
                borderRadius: 24,
                border: '1px solid var(--border-color)',
                padding: '32px',
                display: 'flex',
                flexDirection: 'column'
              }}>
                <div style={{ marginBottom: 24 }}>
                  <Globe size={32} color="var(--text-primary)" style={{ marginBottom: 16 }} />
                  <h3 style={{ fontSize: '1.5rem', fontWeight: 700, fontFamily: 'Syne, sans-serif', color: 'var(--text-primary)', margin: '0 0 8px 0' }}>
                    Free
                  </h3>
                  <span style={{ fontSize: '0.9rem', color: 'var(--text-secondary)', fontFamily: 'Inter, sans-serif' }}>
                    Conoce a Exodo
                  </span>
                </div>

                <div style={{ marginBottom: 24 }}>
                  <span style={{ fontSize: '2.5rem', fontWeight: 700, fontFamily: 'AnthropicSans, sans-serif', color: 'var(--text-primary)' }}>
                    $0
                  </span>
                </div>

                <button type="button" style={{ 
                  width: '100%', 
                  background: 'transparent',
                  color: 'var(--text-primary)',
                  border: '1px solid var(--border-color)',
                  borderRadius: 12,
                  padding: '12px',
                  fontSize: '0.95rem',
                  fontWeight: 600,
                  fontFamily: 'Inter, sans-serif',
                  cursor: 'pointer',
                  marginBottom: 32
                }}>
                  Usa Exodo gratis
                </button>

                <div style={{ height: 1, background: 'var(--border-color)', marginBottom: 24 }} />

                <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
                  {[
                    'Chatea en web, iOS, Android',
                    'Generar código y visualizar datos',
                    'Modelos estándar de IA',
                    'Búsqueda web integrada'
                  ].map((feat, i) => (
                    <div key={i} style={{ display: 'flex', alignItems: 'flex-start', gap: 12 }}>
                      <Check size={18} color="var(--text-secondary)" style={{ marginTop: 2, flexShrink: 0 }} />
                      <span style={{ fontSize: '0.9rem', color: 'var(--text-primary)', fontFamily: 'Inter, sans-serif' }}>
                        {feat}
                      </span>
                    </div>
                  ))}
                </div>
              </div>

              {/* Pro Card */}
              <div style={{ 
                flex: '1 1 320px',
                maxWidth: 360,
                background: 'var(--surface-input)',
                borderRadius: 24,
                border: '1.5px solid var(--amber-exodo)',
                padding: '32px',
                display: 'flex',
                flexDirection: 'column',
                position: 'relative'
              }}>
                <div style={{ position: 'absolute', top: -12, left: '50%', transform: 'translateX(-50%)', background: 'var(--amber-exodo)', color: '#000', padding: '4px 12px', borderRadius: 12, fontSize: '0.75rem', fontWeight: 700, fontFamily: 'Inter, sans-serif' }}>
                  RECOMENDADO
                </div>

                <div style={{ marginBottom: 24 }}>
                  <Zap size={32} color="var(--amber-exodo)" style={{ marginBottom: 16 }} />
                  <h3 style={{ fontSize: '1.5rem', fontWeight: 700, fontFamily: 'Syne, sans-serif', color: 'var(--text-primary)', margin: '0 0 8px 0' }}>
                    XPi PRO
                  </h3>
                  <span style={{ fontSize: '0.9rem', color: 'var(--text-secondary)', fontFamily: 'Inter, sans-serif' }}>
                    Investiga, programa y organiza
                  </span>
                </div>

                <div style={{ marginBottom: 24, display: 'flex', alignItems: 'baseline', gap: 8 }}>
                  <span style={{ fontSize: '2.5rem', fontWeight: 700, fontFamily: 'AnthropicSans, sans-serif', color: 'var(--text-primary)' }}>
                    ${isAnnualPlan ? '49.99' : '4.99'}
                  </span>
                  <span style={{ fontSize: '0.85rem', color: 'var(--text-secondary)', fontFamily: 'Inter, sans-serif' }}>
                    / {isAnnualPlan ? 'año' : 'mes'}
                  </span>
                </div>

                <button type="button" onClick={() => startCheckout(isAnnualPlan)} disabled={isCheckingOut} style={{ 
                  width: '100%', 
                  background: 'var(--amber-exodo)',
                  color: '#000000',
                  border: 'none',
                  borderRadius: 12,
                  padding: '12px',
                  fontSize: '0.95rem',
                  fontWeight: 700,
                  fontFamily: 'Inter, sans-serif',
                  cursor: isCheckingOut ? 'wait' : 'pointer',
                  marginBottom: 8,
                  opacity: isCheckingOut ? 0.7 : 1
                }}>
                  {isCheckingOut ? 'Abriendo pago seguro...' : 'Obtener Plan Pro'}
                </button>
                <span style={{ textAlign: 'center', fontSize: '0.75rem', color: 'var(--text-secondary)', fontFamily: 'Inter, sans-serif', marginBottom: 32 }}>
                  Sin compromiso · Cancela cuando quieras
                </span>

                <div style={{ height: 1, background: 'var(--border-color)', marginBottom: 24 }} />

                <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
                  <span style={{ fontSize: '0.9rem', fontWeight: 700, color: 'var(--text-primary)', fontFamily: 'Inter, sans-serif' }}>
                    Todo lo de Free y:
                  </span>
                  {[
                    'Acceso a todos los modelos de IA avanzada',
                    'Límites de uso más altos (hasta 20x)',
                    'Acceso prioritario en momentos de alto tráfico',
                    'Generación de imágenes con IA en alta resolución',
                    'Memoria que se mantiene entre conversaciones',
                    'Avanza rápidamente en tus tareas con Cowork',
                    'Acceso anticipado a funciones avanzadas'
                  ].map((feat, i) => (
                    <div key={i} style={{ display: 'flex', alignItems: 'flex-start', gap: 12 }}>
                      <Check size={18} color="var(--amber-exodo)" style={{ marginTop: 2, flexShrink: 0 }} />
                      <span style={{ fontSize: '0.9rem', color: 'var(--text-primary)', fontFamily: 'Inter, sans-serif' }}>
                        {feat}
                      </span>
                    </div>
                  ))}
                </div>
              </div>

            </div>

            <div style={{ marginTop: 48, textAlign: 'center' }}>
              <span style={{ fontSize: '0.8rem', color: 'var(--text-secondary)', fontFamily: 'Inter, sans-serif' }}>
                *Se aplican límites de uso. Los precios y planes están sujetos a cambios.
              </span>
            </div>

          </div>
        </div>
      )}

      {/* Feedback Modal (paridad showFeedbackModal móvil) */}
      {feedbackTarget && (() => {
        const es = (locale || 'es').toLowerCase().startsWith('es');
        return (
          <div style={{ position: 'fixed', inset: 0, zIndex: 1000, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 20 }}>
            <div style={{ position: 'absolute', inset: 0, background: 'rgba(0, 0, 0, 0.6)', backdropFilter: 'blur(4px)' }} onClick={() => { setFeedbackTarget(null); setFeedbackComment(''); }} />
            <div style={{
              position: 'relative', background: 'var(--surface-card)',
              width: '100%', maxWidth: 420, borderRadius: 16, padding: '20px 20px 16px 20px',
            }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 12 }}>
                <span style={{ fontSize: '1rem', fontWeight: 600, color: 'var(--text-primary)', fontFamily: 'AnthropicSans, sans-serif' }}>
                  {feedbackTarget.isLike
                    ? (es ? 'Comentarios positivos' : 'Provide positive feedback')
                    : (es ? 'Comentarios de mejora' : 'Provide feedback')}
                </span>
              </div>
              <textarea
                autoFocus
                rows={3}
                value={feedbackComment}
                onChange={(e) => setFeedbackComment(e.target.value)}
                placeholder={es ? 'Cuéntanos qué te gustó o cómo podemos mejorar...' : 'Tell us what you liked or how we can improve...'}
                style={{
                  width: '100%', boxSizing: 'border-box', resize: 'vertical',
                  background: 'var(--surface-input)', border: '1px solid transparent',
                  borderRadius: 10, padding: '12px 14px', color: 'var(--text-primary)',
                  fontSize: '0.9rem', fontFamily: 'AnthropicSans, sans-serif', outline: 'none',
                }}
              />
              <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8, marginTop: 12 }}>
                <button
                  type="button"
                  onClick={() => { setFeedbackTarget(null); setFeedbackComment(''); }}
                  style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--text-secondary)', fontSize: '0.9rem', fontWeight: 500, padding: '8px 12px' }}
                >
                  {es ? 'Cancelar' : 'Cancel'}
                </button>
                <button
                  type="button"
                  onClick={submitFeedback}
                  style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--amber-exodo)', fontSize: '0.9rem', fontWeight: 700, padding: '8px 12px' }}
                >
                  {es ? 'Enviar' : 'Send'}
                </button>
              </div>
            </div>
          </div>
        );
      })()}

      {/* Consent gate (paridad _maybeShowConsentGate móvil, no descartable) */}
      {showConsentGate && (() => {
        const es = (locale || 'es').toLowerCase().startsWith('es');
        const row = (checked: boolean, onTap: () => void, label: string) => (
          <div onClick={onTap} style={{ display: 'flex', gap: 10, alignItems: 'flex-start', cursor: 'pointer', padding: '6px 0' }}>
            <div style={{
              width: 20, height: 20, borderRadius: 4, flexShrink: 0, marginTop: 1,
              border: `2px solid ${checked ? 'var(--amber-exodo)' : 'var(--text-secondary)'}`,
              background: checked ? 'var(--amber-exodo)' : 'transparent',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
            }}>
              {checked && <Check size={14} color="#000" />}
            </div>
            <span style={{ fontSize: '14px', color: 'var(--text-primary)', fontFamily: 'AnthropicSans, sans-serif', lineHeight: 1.45 }}>{label}</span>
          </div>
        );
        return (
          <div style={{ position: 'fixed', inset: 0, zIndex: 1100, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 20 }}>
            <div style={{ position: 'absolute', inset: 0, background: 'rgba(0, 0, 0, 0.7)' }} />
            <div style={{ position: 'relative', background: 'var(--surface-card)', width: '100%', maxWidth: 420, borderRadius: 16, padding: '24px 20px 16px 20px' }}>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
                {row(consentAge, () => setConsentAge((v) => !v), es ? 'Confirmo que tengo más de 13 años.' : "I confirm I'm over 13 years old.")}
                {row(consentCloud, () => setConsentCloud((v) => !v), es ? 'Acepto guardar mis chats en la nube. Behavior podrá leerlos únicamente para mejorar la herramienta.' : 'I agree to store my chats in the cloud. Behavior may read them only to improve the tool.')}
              </div>
              <div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: 16 }}>
                <button
                  type="button"
                  onClick={acceptConsent}
                  disabled={!consentAge}
                  style={{
                    background: 'none', border: 'none', cursor: consentAge ? 'pointer' : 'default',
                    color: consentAge ? 'var(--amber-exodo)' : 'var(--text-secondary)',
                    fontSize: '0.95rem', fontWeight: 700, padding: '8px 12px',
                    fontFamily: 'Inter, sans-serif', opacity: consentAge ? 1 : 0.5,
                  }}
                >
                  {es ? 'Continuar' : 'Continue'}
                </button>
              </div>
            </div>
          </div>
        );
      })()}

      {/* Terms & Privacy (paridad settings.legal_body) */}
      {showTerms && (() => {
        const es = (locale || 'es').toLowerCase().startsWith('es');
        return (
          <div style={{ position: 'fixed', inset: 0, zIndex: 1000, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 20 }}>
            <div style={{ position: 'absolute', inset: 0, background: 'rgba(0, 0, 0, 0.6)', backdropFilter: 'blur(4px)' }} onClick={() => setShowTerms(false)} />
            <div style={{ position: 'relative', background: 'var(--surface-card)', width: '100%', maxWidth: 420, borderRadius: 16, padding: '24px 20px 16px 20px' }}>
              <h2 style={{ fontSize: '18px', fontWeight: 700, fontFamily: 'Syne, sans-serif', color: 'var(--text-primary)', margin: '0 0 12px 0' }}>
                Terms & Privacy
              </h2>
              <p style={{ fontSize: '14px', color: 'var(--text-secondary)', fontFamily: 'Inter, sans-serif', lineHeight: 1.5, margin: 0 }}>
                {es
                  ? 'Éxodo AI opera bajo estricto cumplimiento de privacidad de datos e IA generativa.'
                  : 'Exodo AI operates under strict compliance with data privacy and generative AI.'}
              </p>
              <div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: 16 }}>
                <button
                  type="button"
                  onClick={() => setShowTerms(false)}
                  style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--amber-exodo)', fontSize: '0.9rem', fontWeight: 700, padding: '8px 12px' }}
                >
                  {es ? 'Cerrar' : 'Close'}
                </button>
              </div>
            </div>
          </div>
        );
      })()}
    </div>
  );
}
