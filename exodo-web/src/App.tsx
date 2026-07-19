import React, { useState, useEffect, useRef, useLayoutEffect } from 'react';
import { 
  ChevronRight, 
  ChevronUp,
  ChevronLeft,
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
  SlidersHorizontal,
  ChevronsUpDown,
  Database,
  MoreVertical,
  Edit2,
  Trash2,
  UserRound,
  Globe,
  CircleDollarSign,
  Smartphone,
  Zap
} from 'lucide-react';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import TextareaAutosize from 'react-textarea-autosize';
import { supabase, type Conversation, type Message } from './lib/supabase';
import { AuthModal } from './components/AuthModal';

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
  const [userProfile, setUserProfile] = useState<{ plan?: string; full_name?: string } | null>(null);
  const [showAuthModal, setShowAuthModal] = useState(false);

  // Estados de interfaz exacta a móvil
  const [theme, setTheme] = useState<'dark' | 'light'>(() => (localStorage.getItem('exodo_theme') as 'dark' | 'light') || 'dark');
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [isIncognito, setIsIncognito] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [showSearchBox, setShowSearchBox] = useState(false);
  const [showTokenPopup, setShowTokenPopup] = useState(false);
  const [showAccountMenu, setShowAccountMenu] = useState(false);
  const [showProfileMenu, setShowProfileMenu] = useState(false);
  const [showLanguageMenu, setShowLanguageMenu] = useState(false);
  const [showBillingMenu, setShowBillingMenu] = useState(false);
  const [showPlansModal, setShowPlansModal] = useState(false);
  const [showModelSelector, setShowModelSelector] = useState(false);
  const [isAnnualPlan, setIsAnnualPlan] = useState(false);
  const [openMenuId, setOpenMenuId] = useState<string | null>(null);
  const [hoveredConvId, setHoveredConvId] = useState<string | null>(null);
  const [selectedModel, setSelectedModel] = useState({
    id: 'origo',
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
  const setInput = (val: string) => {
    setDrafts(prev => {
      const newDrafts = { ...prev, [currentConvKey]: val };
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
          fetchProfile(session.user.id);
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
        fetchProfile(session.user.id);
        fetchConversations();
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
        .select('plan, full_name')
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
    if (!input.trim() || isStreaming) return;

    const userText = input.trim();
    setInput('');

    let currentConvId = activeConvId;

    // Si es un chat temporal y el usuario está logueado, crear la conversación real en DB primero
    if (currentConvId && currentConvId.startsWith('conv-') && session?.user && !isIncognito) {
      const { data, error } = await supabase.from('conversations').insert({
        user_id: session.user.id,
        title: userText.length > 35 ? userText.substring(0, 35) + '...' : userText,
        model_plan: selectedModel.plan || 'genesis',
        is_incognito: isIncognito
      }).select().single();

      if (!error && data) {
        currentConvId = data.id;
        setActiveConvId(currentConvId);
        localStorage.setItem('exodo_web_active_conv', currentConvId);
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
      created_at: new Date().toISOString()
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

    try {
      const res = await fetch('http://localhost:3000/chat', {
        method: 'POST',
        headers: { 
          'Content-Type': 'application/json',
          ...(session?.access_token ? { Authorization: `Bearer ${session.access_token}` } : {})
        },
        body: JSON.stringify({
          message: userText,
          conversationId: currentConvId && currentConvId.startsWith('conv-') ? undefined : currentConvId,
          model_override: selectedModel.id,
          isIncognito
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
                if (parsed.content) {
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
    }
  };

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

  const renderChatComposer = (isPinned: boolean = false) => {
    const isModelLocked = !session?.user || isIncognito;
    const displayModelTitle = !session?.user ? 'G1.1' : selectedModel.title;

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
            onClick={() => alert('Upgrade modal')}
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
                onClick={() => alert('Selector de adjuntos sincronizado con nube')}
              >
                <Plus size={20} color="var(--chip-icon-color)" />
              </button>

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

            <button
              type="submit"
              disabled={!input.trim() || isStreaming}
              style={{
                width: 38,
                height: 38,
                borderRadius: '50%',
                background: input.trim() && !isStreaming ? 'var(--send-btn-bg)' : 'var(--send-btn-disabled)',
                color: input.trim() && !isStreaming ? 'var(--send-btn-color)' : 'var(--text-muted)',
                border: 'none',
                outline: 'none',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                cursor: input.trim() && !isStreaming ? 'pointer' : 'default',
                transition: 'background 0.2s ease, color 0.2s ease'
              }}
              title="Enviar"
            >
              <ArrowUp size={19} strokeWidth={2.5} />
            </button>
          </div>
        </form>
        <div style={{ marginTop: isPinned ? 4 : 10, marginBottom: isPinned ? 2 : 0, textAlign: 'center', fontFamily: 'AnthropicSans, sans-serif', fontSize: '12px', color: 'var(--text-secondary)' }}>
          Exodo es IA y puede cometer errores. Por favor verifica las respuestas.
        </div>
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
          <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <img src="/Logo_behavior.png" alt="Éxodo Logo" style={{ width: 28, height: 28, objectFit: 'contain' }} />
            <div className="mask-text-yeso" style={{ width: 84, height: 24 }} />
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
            <div className="mask-icon-incognito" style={{ backgroundColor: 'var(--text-primary)' }} />
            <span style={{ fontSize: '0.94rem' }}>Modo Incógnito</span>
          </button>
        </div>

        <div style={{ padding: '0 16px 12px 16px', position: 'relative' }}>
          <div 
            className="header-token-bar" 
            onClick={() => setShowTokenPopup(!showTokenPopup)}
            title="Capacidad y tokens de Éxodo"
            style={{ width: '100%', justifyContent: 'space-between' }}
          >
            <span style={{ fontSize: '0.78rem', color: 'var(--text-secondary)', fontWeight: 600 }}>
              0/50000 tk
            </span>
            <div className="token-bar-progress" style={{ width: 100 }}>
              <div className="token-bar-fill" style={{ width: '2%' }} />
            </div>
          </div>

          {showTokenPopup && (
            <div className="token-popup-card" style={{ top: 44, left: 16, transform: 'none', width: '258px', zIndex: 60, color: 'var(--text-primary)' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.8rem' }}>
                <span>Consumido</span>
                <span style={{ fontWeight: 700 }}>0 (0.0%)</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.8rem' }}>
                <span>Disponible</span>
                <span style={{ fontWeight: 700 }}>50,000 tk</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.8rem' }}>
                <span>Reinicio en</span>
                <span style={{ fontWeight: 700 }}>24h 00m</span>
              </div>

            </div>
          )}
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
              <button type="button" onClick={() => setSearchQuery('')} style={{ background: 'none', border: 'none', cursor: 'pointer', padding: 0 }}>
                <X size={16} color="var(--text-muted)" />
              </button>
            )}
          </div>
        )}

        {/* Chats Historial (Fijados y Recientes) */}
        <div className="conv-list" style={{ flex: 1, overflowY: 'auto' }}>
          {/* Fijos (Starred) */}
          {filteredConvs.some((c) => c.is_starred) && (
            <div style={{ padding: '16px 20px 8px 20px', fontSize: '0.75rem', fontWeight: 500, color: '#9E9689' }}>
              Destacados
            </div>
          )}
          {filteredConvs.filter((c) => c.is_starred).map((conv) => (
            <div
              key={conv.id}
              className={`conv-item ${activeConvId === conv.id ? 'active' : ''}`}
              onMouseEnter={() => setHoveredConvId(conv.id)}
              onMouseLeave={() => setHoveredConvId(null)}
              onClick={() => {
                setActiveConvId(conv.id);
                localStorage.setItem('exodo_web_active_conv', conv.id);
                localStorage.removeItem('exodo_web_temp_conv');
                fetchMessages(conv.id);
                setDrawerOpen(false);
              }}
              style={{ padding: '12px 20px', justifyContent: 'space-between', position: 'relative', zIndex: openMenuId === conv.id ? 1000 : 1 }}
            >
              <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', fontSize: '0.92rem' }}>{conv.title}</span>
              {(hoveredConvId === conv.id || openMenuId === conv.id) && (
                <button
                  type="button"
                  onClick={(e) => {
                    e.stopPropagation();
                    setOpenMenuId(openMenuId === conv.id ? null : conv.id);
                  }}
                  style={{ background: 'none', border: 'none', cursor: 'pointer', padding: 2, display: 'flex', alignItems: 'center' }}
                  title="Opciones"
                >
                  <MoreVertical size={16} color="var(--text-secondary)" />
                </button>
              )}
              {openMenuId === conv.id && (
                <div style={{
                  position: 'absolute',
                  right: 32,
                  top: 24,
                  background: 'var(--surface-input)',
                  border: 'none',
                  borderRadius: 8,
                  padding: '4px',
                  zIndex: 100,
                  display: 'flex',
                  flexDirection: 'column',
                  gap: 2,
                  boxShadow: '0 4px 12px rgba(0,0,0,0.5)',
                  minWidth: 120
                }}>
                  <button type="button" className="drawer-item" style={{ padding: '6px 12px', fontSize: '0.85rem' }} onClick={(e) => { e.stopPropagation(); /* TODO rename */ setOpenMenuId(null); }}>
                    <Edit2 size={14} style={{ marginRight: 8 }} /> Renombrar
                  </button>
                  <button type="button" className="drawer-item" style={{ padding: '6px 12px', fontSize: '0.85rem' }} onClick={(e) => { e.stopPropagation(); setConversations(conversations.map(c => c.id === conv.id ? { ...c, is_starred: false } : c)); setOpenMenuId(null); }}>
                    <Pin size={14} style={{ marginRight: 8 }} /> Desfijar
                  </button>
                  <button type="button" className="drawer-item" style={{ padding: '6px 12px', fontSize: '0.85rem', color: '#ff4d4f' }} onClick={(e) => { e.stopPropagation(); /* TODO delete */ setOpenMenuId(null); }}>
                    <Trash2 size={14} color="#ff4d4f" style={{ marginRight: 8 }} /> Eliminar
                  </button>
                </div>
              )}
            </div>
          ))}

          {/* Recientes */}
          {filteredConvs.length > 0 && (
            <div style={{ padding: '16px 20px 8px 20px', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <span style={{ fontSize: '0.75rem', fontWeight: 500, color: '#9E9689' }}>Recientes</span>
            </div>
          )}
          {filteredConvs.filter((c) => !c.is_starred).map((conv) => (
            <div
              key={conv.id}
              className={`conv-item ${activeConvId === conv.id ? 'active' : ''}`}
              onMouseEnter={() => setHoveredConvId(conv.id)}
              onMouseLeave={() => setHoveredConvId(null)}
              onClick={() => {
                setActiveConvId(conv.id);
                localStorage.setItem('exodo_web_active_conv', conv.id);
                localStorage.removeItem('exodo_web_temp_conv');
                fetchMessages(conv.id);
                setDrawerOpen(false);
              }}
              style={{ padding: '12px 20px', justifyContent: 'space-between', position: 'relative', zIndex: openMenuId === conv.id ? 1000 : 1 }}
            >
              <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', fontSize: '0.92rem' }}>{conv.title}</span>
              {(hoveredConvId === conv.id || openMenuId === conv.id) && (
                <button
                  type="button"
                  onClick={(e) => {
                    e.stopPropagation();
                    setOpenMenuId(openMenuId === conv.id ? null : conv.id);
                  }}
                  style={{ background: 'none', border: 'none', cursor: 'pointer', padding: 2, display: 'flex', alignItems: 'center' }}
                  title="Opciones"
                >
                  <MoreVertical size={16} color="var(--text-secondary)" />
                </button>
              )}
              {openMenuId === conv.id && (
                <div style={{
                  position: 'absolute',
                  right: 32,
                  top: 24,
                  background: 'var(--surface-input)',
                  border: 'none',
                  borderRadius: 8,
                  padding: '4px',
                  zIndex: 100,
                  display: 'flex',
                  flexDirection: 'column',
                  gap: 2,
                  boxShadow: '0 4px 12px rgba(0,0,0,0.5)',
                  minWidth: 120
                }}>
                  <button type="button" className="drawer-item" style={{ padding: '6px 12px', fontSize: '0.85rem' }} onClick={(e) => { e.stopPropagation(); /* TODO rename */ setOpenMenuId(null); }}>
                    <Edit2 size={14} style={{ marginRight: 8 }} /> Renombrar
                  </button>
                  <button type="button" className="drawer-item" style={{ padding: '6px 12px', fontSize: '0.85rem' }} onClick={(e) => { e.stopPropagation(); setConversations(conversations.map(c => c.id === conv.id ? { ...c, is_starred: true } : c)); setOpenMenuId(null); }}>
                    <Pin size={14} style={{ marginRight: 8 }} /> Fijar
                  </button>
                  <button type="button" className="drawer-item" style={{ padding: '6px 12px', fontSize: '0.85rem', color: '#ff4d4f' }} onClick={(e) => { e.stopPropagation(); /* TODO delete */ setOpenMenuId(null); }}>
                    <Trash2 size={14} color="#ff4d4f" style={{ marginRight: 8 }} /> Eliminar
                  </button>
                </div>
              )}
            </div>
          ))}

          {filteredConvs.length === 0 && (
            <div style={{ padding: '16px 20px', color: 'var(--text-muted)', fontSize: '0.85rem' }}>
              No hay conversaciones.
            </div>
          )}
        </div>

        <div style={{ borderTop: '1px solid var(--border-color)', position: 'relative' }}>
          {session?.user ? (
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '12px 16px', cursor: 'pointer' }} onClick={() => setShowAccountMenu(true)}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 12, overflow: 'hidden' }}>
                {(session.user.user_metadata?.avatar_url || session.user.user_metadata?.picture) ? (
                  <img 
                    src={session.user.user_metadata?.avatar_url || session.user.user_metadata?.picture} 
                    alt="Avatar" 
                    style={{ width: 34, height: 34, borderRadius: '50%', objectFit: 'cover', flexShrink: 0 }} 
                  />
                ) : (
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
                    {(userProfile?.full_name || session.user.email || 'U').charAt(0).toUpperCase()}
                  </div>
                )}
                <div style={{ display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
                  <span style={{ fontSize: '0.92rem', fontWeight: 500, color: 'var(--text-primary)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                    {userProfile?.full_name || session.user.email}
                  </span>
                  <span style={{ fontSize: '0.78rem', color: '#9E9689' }}>
                    Plan {userProfile?.plan || 'gratuito'}
                  </span>
                </div>
              </div>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexShrink: 0 }}>
                <div style={{ position: 'relative' }}>
                  <Download size={16} color="var(--text-secondary)" />
                  <div style={{ position: 'absolute', top: -2, right: -2, width: 6, height: 6, borderRadius: '50%', background: '#4D90FE' }} />
                </div>
              </div>
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
            <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', height: 100, marginBottom: 36 }}>
              {!isIncognito && (
                <div style={{ display: 'flex', alignItems: 'center', gap: 24 }}>
                  <img 
                    src="/Logo_behavior.png" 
                    alt="Éxodo Logo" 
                    style={{ width: 72, height: 72, objectFit: 'contain', flexShrink: 0 }} 
                  />
                  <div className="greeting-text-exodo" style={{ textAlign: 'left' }}>
                    {getExodoGreeting()}
                  </div>
                </div>
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
                      <div className="msg-bubble markdown-body">
                        {msg.isThinking ? (
                          <div className="thinking-row">
                            <div className="thinking-logo-mask" />
                            <span className="thinking-label">Pensando</span>
                          </div>
                        ) : (
                          <ReactMarkdown remarkPlugins={[remarkGfm]}>
                            {msg.content}
                          </ReactMarkdown>
                        )}
                      </div>
                      
                      {msg.role === 'user' && (
                        <div style={{ display: 'flex', alignItems: 'center', gap: '6px', fontSize: '11px', color: 'var(--text-secondary)', marginTop: '4px', opacity: 0.7, paddingRight: '6px', fontFamily: 'Inter, sans-serif' }}>
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
                          <button className="action-btn" title="Me gusta">
                            <div style={{ width: 16, height: 16, backgroundColor: 'var(--text-secondary)', WebkitMaskImage: 'url(/like-1-svgrepo-com.png)', WebkitMaskSize: 'contain', WebkitMaskRepeat: 'no-repeat', maskImage: 'url(/like-1-svgrepo-com.png)', maskSize: 'contain', maskRepeat: 'no-repeat' }} />
                          </button>
                          <button className="action-btn" title="No me gusta">
                            <div style={{ width: 16, height: 16, backgroundColor: 'var(--text-secondary)', WebkitMaskImage: 'url(/like-1-svgrepo-com.png)', WebkitMaskSize: 'contain', WebkitMaskRepeat: 'no-repeat', maskImage: 'url(/like-1-svgrepo-com.png)', maskSize: 'contain', maskRepeat: 'no-repeat', transform: 'scaleY(-1)' }} />
                          </button>
                          <button className="action-btn" title="Compartir">
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

      {/* Settings Modal */}
      {showAccountMenu && (
        <div style={{ position: 'fixed', inset: 0, zIndex: 1000, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <div style={{ position: 'absolute', inset: 0, background: 'rgba(0, 0, 0, 0.6)', backdropFilter: 'blur(4px)' }} onClick={() => setShowAccountMenu(false)} />
          
          <div style={{ 
            position: 'relative', 
            background: 'var(--surface-card)', 
            width: '90%', 
            maxWidth: 500, 
            borderRadius: 24, 
            padding: '24px 20px', 
            display: 'flex', 
            flexDirection: 'column', 
            gap: 16,
            maxHeight: '90vh',
            overflowY: 'auto'
          }}>
            
            <h2 style={{ textAlign: 'center', fontSize: '1.2rem', fontWeight: 600, fontFamily: 'Syne, sans-serif', color: 'var(--text-primary)', marginBottom: 8, marginTop: 4 }}>Settings</h2>
            
            <div style={{ background: 'var(--surface-input)', borderRadius: 16, padding: '16px 20px', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
              <span style={{ fontSize: '1.05rem', fontWeight: 500, color: 'var(--text-primary)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                {session?.user?.email || 'usuario@exodo.ai'}
              </span>
              <div style={{ background: 'var(--text-primary)', color: 'var(--surface-card)', padding: '4px 12px', borderRadius: 20, fontSize: '0.85rem', fontWeight: 700 }}>
                {userProfile?.plan === 'pro' ? 'Pro' : 'Pro'}
              </div>
            </div>

            <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
              <div style={{ background: 'var(--surface-input)', borderRadius: 16, padding: '18px 20px', display: 'flex', alignItems: 'center', justifyContent: 'space-between', cursor: 'pointer' }} onClick={() => { setShowAccountMenu(false); setShowProfileMenu(true); }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
                  <MaterialProfileIcon size={22} color="var(--text-primary)" />
                  <span style={{ fontSize: '1.05rem', fontWeight: 600, color: 'var(--text-primary)' }}>Profile</span>
                </div>
                <ChevronRight size={20} color="var(--text-secondary)" />
              </div>

              <div style={{ background: 'var(--surface-input)', borderRadius: 16, padding: '14px 20px', display: 'flex', alignItems: 'center', justifyContent: 'space-between', cursor: 'pointer' }} onClick={() => { setShowAccountMenu(false); setShowLanguageMenu(true); }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
                  <Globe size={22} color="var(--text-primary)" />
                  <div style={{ display: 'flex', flexDirection: 'column' }}>
                    <span style={{ fontSize: '1.05rem', fontWeight: 600, color: 'var(--text-primary)' }}>Language</span>
                    <span style={{ fontSize: '0.85rem', color: 'var(--text-secondary)' }}>English (US) 🇺🇸</span>
                  </div>
                </div>
                <ChevronRight size={20} color="var(--text-secondary)" />
              </div>

              <div style={{ background: 'var(--surface-input)', borderRadius: 16, padding: '18px 20px', display: 'flex', alignItems: 'center', justifyContent: 'space-between', cursor: 'pointer' }} onClick={() => { setShowAccountMenu(false); setShowBillingMenu(true); }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
                  <MaterialBillingIcon size={22} color="var(--text-primary)" />
                  <span style={{ fontSize: '1.05rem', fontWeight: 600, color: 'var(--text-primary)' }}>Billing</span>
                </div>
                <ChevronRight size={20} color="var(--text-secondary)" />
              </div>

              <div style={{ background: 'var(--surface-input)', borderRadius: 16, padding: '18px 20px', display: 'flex', alignItems: 'center', justifyContent: 'space-between', cursor: 'pointer' }} onClick={() => setShowAccountMenu(false)}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
                  <Smartphone size={22} color="var(--text-primary)" />
                  <span style={{ fontSize: '1.05rem', fontWeight: 600, color: 'var(--text-primary)' }}>Exodo App</span>
                </div>
                <ChevronRight size={20} color="var(--text-secondary)" />
              </div>

              <div style={{ background: 'var(--surface-input)', borderRadius: 16, padding: '18px 20px', display: 'flex', alignItems: 'center', justifyContent: 'space-between', cursor: 'pointer' }} onClick={() => setShowAccountMenu(false)}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
                  <MaterialPrivacyIcon size={22} color="var(--text-primary)" />
                  <span style={{ fontSize: '1.05rem', fontWeight: 600, color: 'var(--text-primary)' }}>Terms & Privacy</span>
                </div>
                <ChevronRight size={20} color="var(--text-secondary)" />
              </div>
            </div>

            <div style={{ marginTop: 24, marginBottom: 8 }}>
              <div style={{ padding: '12px 8px', display: 'flex', alignItems: 'center', gap: 16, cursor: 'pointer' }} onClick={() => { setShowAccountMenu(false); supabase.auth.signOut(); }}>
                <LogOut size={22} color="#E57373" />
                <span style={{ fontSize: '1.05rem', fontWeight: 600, color: '#E57373' }}>Log out</span>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Profile Modal */}
      {showProfileMenu && (
        <div style={{ position: 'fixed', inset: 0, zIndex: 1000, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <div style={{ position: 'absolute', inset: 0, background: 'rgba(0, 0, 0, 0.6)', backdropFilter: 'blur(4px)' }} onClick={() => setShowProfileMenu(false)} />
          
          <div style={{ 
            position: 'relative', 
            background: 'var(--surface-card)', 
            width: '100%', 
            maxWidth: 500, 
            height: '100%',
            maxHeight: '90vh',
            borderRadius: 24, 
            display: 'flex', 
            flexDirection: 'column',
            overflow: 'hidden'
          }}>
            {/* Header */}
            <div style={{ display: 'flex', alignItems: 'center', padding: '20px', position: 'relative' }}>
              <button 
                type="button" 
                onClick={() => { setShowProfileMenu(false); setShowAccountMenu(true); }}
                style={{ background: 'none', border: 'none', cursor: 'pointer', padding: '8px', display: 'flex', alignItems: 'center', justifyContent: 'center' }}
              >
                <ArrowLeft size={24} color="var(--text-primary)" />
              </button>
              <h2 style={{ flex: 1, textAlign: 'center', fontSize: '1.25rem', fontWeight: 700, fontFamily: 'Syne, sans-serif', color: 'var(--text-primary)', margin: 0, paddingRight: 40 }}>
                Profile
              </h2>
            </div>

            {/* Body */}
            <div style={{ flex: 1, overflowY: 'auto', padding: '24px' }}>
              
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
                    defaultValue={userProfile?.full_name || ''}
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
                  <button type="button" style={{ 
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

                <div style={{ display: 'flex', flexDirection: 'column', gap: 16, marginTop: 16 }}>
                  <button type="button" style={{ 
                    display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
                    width: '100%', background: 'transparent', color: 'var(--text-primary)', 
                    border: 'none', borderRadius: 14, padding: '14px', 
                    fontSize: '0.95rem', fontWeight: 500, fontFamily: 'Inter, sans-serif', cursor: 'pointer'
                  }}>
                    <Trash2 size={20} />
                    Clear History
                  </button>
                  
                  <button type="button" style={{ 
                    display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
                    width: '100%', background: 'transparent', color: '#E57373', 
                    border: 'none', borderRadius: 14, padding: '16px', 
                    fontSize: '0.95rem', fontWeight: 600, fontFamily: 'Inter, sans-serif', cursor: 'pointer'
                  }}>
                    <LogOut size={20} /> {/* Use appropriate delete icon here, LogOut is a placeholder for delete_forever */}
                    Delete account
                  </button>
                </div>

              </div>
            </div>
          </div>
        </div>
      )}

      {/* Language Modal */}
      {showLanguageMenu && (
        <div style={{ position: 'fixed', inset: 0, zIndex: 1000, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <div style={{ position: 'absolute', inset: 0, background: 'rgba(0, 0, 0, 0.6)', backdropFilter: 'blur(4px)' }} onClick={() => setShowLanguageMenu(false)} />
          
          <div style={{ 
            position: 'relative', 
            background: 'var(--surface-card)', 
            width: '100%', 
            maxWidth: 500, 
            height: '100%',
            maxHeight: '90vh',
            borderRadius: 24, 
            display: 'flex', 
            flexDirection: 'column',
            overflow: 'hidden'
          }}>
            {/* Header */}
            <div style={{ display: 'flex', alignItems: 'center', padding: '20px', position: 'relative' }}>
              <button 
                type="button" 
                onClick={() => { setShowLanguageMenu(false); setShowAccountMenu(true); }}
                style={{ background: 'none', border: 'none', cursor: 'pointer', padding: '8px', display: 'flex', alignItems: 'center', justifyContent: 'center' }}
              >
                <ArrowLeft size={24} color="var(--text-primary)" />
              </button>
              <div style={{ flex: 1, textAlign: 'center', paddingRight: 40 }}>
                <h2 style={{ fontSize: '1.25rem', fontWeight: 700, fontFamily: 'Syne, sans-serif', color: 'var(--text-primary)', margin: 0 }}>
                  App language
                </h2>
                <span style={{ fontSize: '0.85rem', color: 'var(--text-secondary)', fontFamily: 'Inter, sans-serif' }}>
                  Select your preferred language
                </span>
              </div>
            </div>

            {/* Body */}
            <div style={{ flex: 1, overflowY: 'auto', padding: '12px 24px 24px' }}>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
                
                {[
                  { flag: null, title: 'System', subtitle: 'Auto-detect', code: null },
                  { flag: 'mx', title: 'Español (Latinoamérica)', subtitle: 'ES', code: 'es' },
                  { flag: 'us', title: 'English (US)', subtitle: 'EN', code: 'en' },
                  { flag: 'gb', title: 'English (UK)', subtitle: 'EN_GB', code: 'en_GB' },
                  { flag: 'br', title: 'Português (Brasil)', subtitle: 'PT_BR', code: 'pt_BR' },
                  { flag: 'pt', title: 'Português (Portugal)', subtitle: 'PT', code: 'pt' },
                  { flag: 'fr', title: 'Français', subtitle: 'FR', code: 'fr' },
                  { flag: 'ht', title: 'Kreyòl Ayisyen', subtitle: 'HT', code: 'ht' },
                  { flag: 'it', title: 'Italiano', subtitle: 'IT', code: 'it' },
                  { flag: 'de', title: 'Deutsch', subtitle: 'DE', code: 'de' },
                  { flag: 'ru', title: 'Русский', subtitle: 'RU', code: 'ru' },
                  { flag: 'cn', title: '中文', subtitle: 'ZH', code: 'zh' },
                  { flag: 'jp', title: '日本語', subtitle: 'JA', code: 'ja' },
                  { flag: 'sa', title: 'العربية', subtitle: 'AR', code: 'ar' },
                  { flag: 'kr', title: '한국어', subtitle: 'KO', code: 'ko' },
                  { flag: 'in', title: 'हिन्दी', subtitle: 'HI', code: 'hi' }
                ].map((lang) => (
                  <div 
                    key={lang.title}
                    style={{ 
                      background: 'var(--surface-input)', 
                      borderRadius: 16, 
                      padding: '14px 20px', 
                      display: 'flex', 
                      alignItems: 'center', 
                      justifyContent: 'space-between', 
                      cursor: 'pointer' 
                    }} 
                    onClick={() => { setShowLanguageMenu(false); setShowAccountMenu(true); }}
                  >
                    <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
                      <div style={{ width: 28, height: 28, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                        {lang.flag ? (
                          <img src={`https://flagcdn.com/w40/${lang.flag}.png`} alt={lang.title} style={{ width: '100%', borderRadius: 2 }} />
                        ) : (
                          <Globe size={22} color="var(--text-primary)" />
                        )}
                      </div>
                      <div style={{ display: 'flex', flexDirection: 'column' }}>
                        <span style={{ 
                          fontSize: '1.05rem', 
                          fontWeight: lang.code === 'en' ? 700 : 500, 
                          color: 'var(--text-primary)',
                          fontFamily: 'Inter, sans-serif'
                        }}>
                          {lang.title}
                        </span>
                        <span style={{ fontSize: '0.75rem', color: 'var(--text-secondary)', fontFamily: 'Inter, sans-serif' }}>
                          {lang.subtitle}
                        </span>
                      </div>
                    </div>
                    {lang.code === 'en' && (
                      <Check size={20} color="var(--amber-exodo)" />
                    )}
                  </div>
                ))}

              </div>
            </div>
          </div>
        </div>
      )}

      {/* Billing Modal */}
      {showBillingMenu && (
        <div style={{ position: 'fixed', inset: 0, zIndex: 1000, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <div style={{ position: 'absolute', inset: 0, background: 'rgba(0, 0, 0, 0.6)', backdropFilter: 'blur(4px)' }} onClick={() => setShowBillingMenu(false)} />
          
          <div style={{ 
            position: 'relative', 
            background: 'var(--surface-card)', 
            width: '100%', 
            maxWidth: 500, 
            borderRadius: 24, 
            display: 'flex', 
            flexDirection: 'column',
            overflow: 'hidden'
          }}>
            {/* Header */}
            <div style={{ display: 'flex', alignItems: 'center', padding: '20px', position: 'relative' }}>
              <button 
                type="button" 
                onClick={() => { setShowBillingMenu(false); setShowAccountMenu(true); }}
                style={{ background: 'none', border: 'none', cursor: 'pointer', padding: '8px', display: 'flex', alignItems: 'center', justifyContent: 'center' }}
              >
                <ArrowLeft size={24} color="var(--text-primary)" />
              </button>
              <h2 style={{ flex: 1, textAlign: 'center', fontSize: '1.25rem', fontWeight: 700, fontFamily: 'Syne, sans-serif', color: 'var(--text-primary)', margin: 0, paddingRight: 40 }}>
                Billing
              </h2>
            </div>

            {/* Body */}
            <div style={{ padding: '8px 24px 24px' }}>
              
              <div style={{ 
                background: 'var(--surface-input)', 
                borderRadius: 16, 
                padding: '20px', 
                display: 'flex', 
                flexDirection: 'column',
                gap: 16
              }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                  <span style={{ fontSize: '0.95rem', color: 'var(--text-secondary)', fontFamily: 'Inter, sans-serif' }}>
                    Current plan
                  </span>
                  <span style={{ fontSize: '1rem', fontWeight: 700, color: 'var(--amber-exodo)', fontFamily: 'Inter, sans-serif' }}>
                    {userProfile?.plan === 'pro' ? 'Pro' : 'Free'}
                  </span>
                </div>
                
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                  <span style={{ fontSize: '0.95rem', color: 'var(--text-secondary)', fontFamily: 'Inter, sans-serif' }}>
                    Gateway
                  </span>
                  <span style={{ fontSize: '1rem', color: 'var(--text-primary)', fontFamily: 'Inter, sans-serif' }}>
                    {userProfile?.plan === 'pro' ? 'Stripe / Web Pay' : 'None'}
                  </span>
                </div>
              </div>

              <div style={{ marginTop: 24 }}>
                {userProfile?.plan === 'pro' ? (
                  <button type="button" style={{ 
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
                  <button type="button" onClick={() => { setShowBillingMenu(false); setShowPlansModal(true); }} style={{ 
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

                <button type="button" style={{ 
                  width: '100%', 
                  background: 'var(--amber-exodo)',
                  color: '#000000',
                  border: 'none',
                  borderRadius: 12,
                  padding: '12px',
                  fontSize: '0.95rem',
                  fontWeight: 700,
                  fontFamily: 'Inter, sans-serif',
                  cursor: 'pointer',
                  marginBottom: 8
                }}>
                  Obtener Plan Pro
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
                    'Acceso a todos los modelos de Claude e IA avanzada',
                    'Límites de uso más altos (hasta 20x)',
                    'Acceso prioritario en momentos de alto tráfico',
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
    </div>
  );
}
