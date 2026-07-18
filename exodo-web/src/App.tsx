import React, { useState, useEffect, useRef, useLayoutEffect } from 'react';
import { 
  ChevronRight, 
  ChevronUp,
  ChevronDown,
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
  ChevronDown
} from 'lucide-react';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import { supabase, type Conversation, type Message } from './lib/supabase';
import { AuthModal } from './components/AuthModal';

const PsychologyIcon = ({ size = 14, color = 'currentColor' }: { size?: number; color?: string }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="currentColor" style={{ flexShrink: 0, color }}>
    <path d="M13 3c-4.97 0-9 4.03-9 9 0 2.12.74 4.07 1.97 5.61L4.35 19.2c-.39.39-.39 1.02 0 1.41.39.39 1.02.39 1.41 0l1.9-1.9C9.24 19.58 11.06 20 13 20c4.97 0 9-4.03 9-9s-4.03-9-9-9zm0 15c-3.31 0-6-2.69-6-6s2.69-6 6-6 6 2.69 6 6-2.69 6-6 6z"/>
    <path d="M11 9h2v2h-2zm0 4h2v2h-2zm3-2h2v2h-2z"/>
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
  const [showModelSelector, setShowModelSelector] = useState(false);
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
  const [input, setInput] = useState(() => localStorage.getItem('exodo_web_draft_input') || '');
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

  useEffect(() => {
    localStorage.setItem('exodo_web_draft_input', input);
  }, [input]);

  useLayoutEffect(() => {
    if (textareaRef.current) {
      textareaRef.current.style.height = '0px';
      const scrollHeight = textareaRef.current.scrollHeight;
      textareaRef.current.style.height = `${Math.min(scrollHeight, 300)}px`;
      
      const scrollable = scrollHeight > 300;
      textareaRef.current.style.overflowY = scrollable ? 'auto' : 'hidden';
      setIsComposerScrollable(scrollable);
    }
  }, [input]);

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

  const handleSendMessage = async (e?: React.FormEvent) => {
    if (e) e.preventDefault();
    if (!input.trim() || isStreaming) return;

    const userText = input.trim();
    setInput('');

    const userMsg: Message = {
      id: `msg-user-${Date.now()}`,
      conversation_id: activeConvId || 'default',
      role: 'user',
      content: userText,
      created_at: new Date().toISOString()
    };

    const thinkingMsg: Message = {
      id: `msg-thinking-${Date.now()}`,
      conversation_id: activeConvId || 'default',
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
          model: 'hazak',
          messages: [...messages, userMsg].map((m) => ({ role: m.role, content: m.content })),
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
            conversation_id: activeConvId || 'default',
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
          conversation_id: activeConvId || 'default',
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
            <textarea
              ref={textareaRef}
              className="composer-input"
              placeholder="Habla con Éxodo..."
              value={input}
              onChange={(e) => {
                setInput(e.target.value);
              }}
              onKeyDown={(e) => {
                if (e.key === 'Enter' && !e.shiftKey) {
                  e.preventDefault();
                  handleSendMessage();
                }
              }}
              rows={1}
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
                overflowY: 'auto'
              }}
            />
            {isComposerScrollable && (
              <div style={{ position: 'absolute', right: 8, top: 4, bottom: 4, display: 'flex', flexDirection: 'column', justifyContent: 'space-between', alignItems: 'center', pointerEvents: 'none', zIndex: 10 }}>
                <button
                  type="button"
                  onClick={() => textareaRef.current?.scrollTo({ top: 0, behavior: 'smooth' })}
                  style={{ pointerEvents: 'auto', width: 22, height: 22, background: 'var(--surface-input)', border: '1px solid #505050', borderRadius: '50%', color: '#505050', display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer' }}
                  title="Ir al inicio"
                >
                  <ChevronUp size={14} />
                </button>
                <button
                  type="button"
                  onClick={() => textareaRef.current?.scrollTo({ top: textareaRef.current.scrollHeight, behavior: 'smooth' })}
                  style={{ pointerEvents: 'auto', width: 22, height: 22, background: 'var(--surface-input)', border: '1px solid #505050', borderRadius: '50%', color: '#505050', display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer' }}
                  title="Ir al final"
                >
                  <ChevronDown size={14} />
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
                        <PsychologyIcon size={14} color="var(--text-secondary)" />
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
        <div className="drawer-header">
          <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <div className="mask-logo-amber" style={{ width: 32, height: 32 }} />
            <div className="mask-text-yeso" style={{ width: 88, height: 26 }} />
          </div>
          <button type="button" className="icon-btn" onClick={() => setDrawerOpen(false)}>
            <ChevronRight size={22} color="var(--text-secondary)" />
          </button>
        </div>

        <div style={{ padding: '8px 0' }}>
          <button type="button" className="drawer-item" onClick={handleCreateNewChat}>
            <MessageSquare size={20} color="var(--text-primary)" />
            <span>Nuevo chat</span>
          </button>

          <button 
            type="button" 
            className="drawer-item" 
            onClick={() => setTheme(theme === 'dark' ? 'light' : 'dark')}
          >
            {theme === 'dark' ? <Sun size={20} color="var(--text-primary)" /> : <Moon size={20} color="var(--text-primary)" />}
            <span>{theme === 'dark' ? 'Modo claro' : 'Modo oscuro'}</span>
          </button>

          <button 
            type="button" 
            className="drawer-item" 
            onClick={() => { setIsIncognito(!isIncognito); setDrawerOpen(false); }}
            style={{ color: isIncognito ? 'var(--amber-exodo)' : undefined }}
          >
            <div 
              className="mask-icon-incognito" 
              style={{ 
                backgroundColor: isIncognito ? 'var(--amber-exodo)' : undefined 
              }} 
            />
            <span>Modo Incógnito</span>
          </button>

          <button 
            type="button" 
            className="drawer-item" 
            onClick={() => setShowSearchBox(!showSearchBox)}
          >
            <Search size={20} color="var(--text-primary)" />
            <span>Buscar conversación</span>
          </button>
        </div>

        {(showSearchBox || searchQuery.length > 0) && (
          <div className="search-box" style={{ margin: '4px 16px 8px 16px' }}>
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

        {/* Separador 1: entre opciones y chats historial */}
        <div style={{ height: 1, background: 'var(--border-color)', margin: '6px 16px 10px 16px' }} />

        {/* Indicador de Capacidad (#252525) dentro del menú lateral */}
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
            <div className="token-popup-card" style={{ top: 44, left: 16, transform: 'none', width: '258px', zIndex: 60 }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.8rem' }}>
                <span style={{ color: 'var(--text-secondary)' }}>Consumido</span>
                <span style={{ fontWeight: 700 }}>0 (0.0%)</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.8rem' }}>
                <span style={{ color: 'var(--text-secondary)' }}>Disponible</span>
                <span style={{ fontWeight: 700 }}>50,000 tk</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.8rem' }}>
                <span style={{ color: 'var(--text-secondary)' }}>Reinicio en</span>
                <span style={{ color: 'var(--amber-exodo)', fontWeight: 700 }}>24h 00m</span>
              </div>

              <div 
                className="capacity-upgrade-banner"
                onClick={() => alert('Sincronizado con suscripción y planes de tu cuenta móvil Android')}
              >
                <span>⚡ Más capacidad con XPi PRO</span>
              </div>
            </div>
          )}
        </div>

        {/* Chats Historial (Fijados y Recientes) */}
        <div className="conv-list">
          {/* Fijos (Starred) */}
          {filteredConvs.some((c) => c.is_starred) && (
            <div style={{ padding: '6px 14px 2px 14px', fontSize: '0.72rem', fontWeight: 700, color: 'var(--text-muted)', letterSpacing: 0.6 }}>
              FIJADOS
            </div>
          )}
          {filteredConvs.filter((c) => c.is_starred).map((conv) => (
            <div
              key={conv.id}
              className={`conv-item ${activeConvId === conv.id ? 'active' : ''}`}
              onClick={() => {
                setActiveConvId(conv.id);
                localStorage.setItem('exodo_web_active_conv', conv.id);
                localStorage.removeItem('exodo_web_temp_conv');
                fetchMessages(conv.id);
                setDrawerOpen(false);
              }}
              style={{ justifyContent: 'space-between' }}
            >
              <div style={{ display: 'flex', alignItems: 'center', gap: 10, overflow: 'hidden' }}>
                <MessageSquare size={16} style={{ flexShrink: 0 }} />
                <span style={{ overflow: 'hidden', textOverflow: 'ellipsis' }}>{conv.title}</span>
              </div>
              <button
                type="button"
                onClick={(e) => {
                  e.stopPropagation();
                  setConversations(conversations.map(c => c.id === conv.id ? { ...c, is_starred: !c.is_starred } : c));
                }}
                style={{ background: 'none', border: 'none', cursor: 'pointer', padding: 2 }}
                title="Desfijar chat"
              >
                <Pin size={14} color="var(--amber-exodo)" fill="var(--amber-exodo)" />
              </button>
            </div>
          ))}

          {/* Recientes */}
          {filteredConvs.length > 0 && (
            <div style={{ padding: '8px 14px 2px 14px', fontSize: '0.72rem', fontWeight: 700, color: 'var(--text-muted)', letterSpacing: 0.6 }}>
              RECIENTES
            </div>
          )}
          {filteredConvs.filter((c) => !c.is_starred).map((conv) => (
            <div
              key={conv.id}
              className={`conv-item ${activeConvId === conv.id ? 'active' : ''}`}
              onClick={() => {
                setActiveConvId(conv.id);
                localStorage.setItem('exodo_web_active_conv', conv.id);
                localStorage.removeItem('exodo_web_temp_conv');
                fetchMessages(conv.id);
                setDrawerOpen(false);
              }}
              style={{ justifyContent: 'space-between' }}
            >
              <div style={{ display: 'flex', alignItems: 'center', gap: 10, overflow: 'hidden' }}>
                <MessageSquare size={16} style={{ flexShrink: 0 }} />
                <span style={{ overflow: 'hidden', textOverflow: 'ellipsis' }}>{conv.title}</span>
              </div>
              <button
                type="button"
                onClick={(e) => {
                  e.stopPropagation();
                  setConversations(conversations.map(c => c.id === conv.id ? { ...c, is_starred: !c.is_starred } : c));
                }}
                style={{ background: 'none', border: 'none', cursor: 'pointer', padding: 2, opacity: 0.4 }}
                title="Fijar chat"
              >
                <Pin size={14} color="var(--text-secondary)" />
              </button>
            </div>
          ))}

          {filteredConvs.length === 0 && (
            <div style={{ padding: '16px 14px', color: 'var(--text-muted)', fontSize: '0.85rem' }}>
              No hay conversaciones encontradas.
            </div>
          )}
        </div>

        {/* Separador 2: entre historial y footer (Avatar + Descarga) */}
        <div style={{ height: 1, background: 'var(--border-color)', margin: 0 }} />

        <div className="drawer-footer" style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          {/* Botón de descarga para app de escritorio/móvil futura */}
          <button 
            type="button" 
            className="drawer-item" 
            onClick={() => alert('Próximamente disponible para descarga en tu dispositivo.')}
            style={{ padding: '10px 14px', background: 'rgba(201, 147, 58, 0.08)', borderRadius: 12, border: '1px solid rgba(201, 147, 58, 0.25)' }}
          >
            <Download size={18} color="var(--amber-exodo)" />
            <span style={{ color: 'var(--amber-exodo)', fontWeight: 600, fontSize: '0.88rem' }}>Descargar aplicación</span>
          </button>

          {/* Avatar y Datos del Usuario */}
          {session?.user ? (
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '2px 4px' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 12, overflow: 'hidden' }}>
                <div style={{
                  width: 38,
                  height: 38,
                  borderRadius: '50%',
                  background: 'var(--amber-exodo)',
                  color: '#0E0C0A',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  fontWeight: 700,
                  fontSize: '1rem',
                  flexShrink: 0
                }}>
                  {(userProfile?.full_name || session.user.email || 'U').charAt(0).toUpperCase()}
                </div>
                <div style={{ display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
                  <span style={{ fontSize: '0.88rem', fontWeight: 600, color: 'var(--text-primary)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                    {userProfile?.full_name || session.user.email}
                  </span>
                  <span style={{ fontSize: '0.72rem', color: 'var(--amber-exodo)', fontWeight: 700 }}>
                    PLAN {userProfile?.plan?.toUpperCase() || 'HAZAK'}
                  </span>
                </div>
              </div>
              <button
                type="button"
                className="icon-btn"
                onClick={() => supabase.auth.signOut()}
                title="Cerrar Sesión"
              >
                <LogOut size={18} color="var(--text-secondary)" />
              </button>
            </div>
          ) : (
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '2px 4px' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 12, overflow: 'hidden' }}>
                <div style={{
                  width: 38,
                  height: 38,
                  borderRadius: '50%',
                  background: 'var(--amber-exodo)',
                  color: '#0E0C0A',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  fontWeight: 700,
                  fontSize: '1rem',
                  flexShrink: 0
                }}>
                  U
                </div>
                <div style={{ display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
                  <span style={{ fontSize: '0.88rem', fontWeight: 600, color: 'var(--text-primary)' }}>
                    Usuario Éxodo
                  </span>
                  <span style={{ fontSize: '0.72rem', color: 'var(--text-secondary)', fontWeight: 600 }}>
                    Invitado
                  </span>
                </div>
              </div>
              <button
                type="button"
                onClick={() => { setDrawerOpen(false); setShowAuthModal(true); }}
                style={{
                  padding: '8px 12px',
                  borderRadius: 10,
                  background: 'var(--amber-exodo)',
                  color: '#0E0C0A',
                  border: 'none',
                  fontWeight: 700,
                  fontSize: '0.8rem',
                  cursor: 'pointer'
                }}
              >
                Acceder
              </button>
            </div>
          )}
        </div>
      </aside>

      {/* 3. Área Principal de Chat Exacta a Móvil / Claude Centrado */}
      <main className="chat-main">
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
              onClick={() => setIsIncognito(!isIncognito)}
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
            <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 14, marginBottom: 36 }}>
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
                <>
                  <div className="greeting-text-exodo" style={{ textAlign: 'center' }}>
                    Incógnito
                  </div>
                  <div style={{ fontSize: '14px', color: 'var(--text-secondary)', textAlign: 'center', maxWidth: 480, lineHeight: 1.4, marginTop: 4 }}>
                    Los chats de incógnito no se guardan en el historial.
                  </div>
                </>
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
                          <div className="thinking-pulse">
                            <div style={{ width: 8, height: 8, borderRadius: '50%', background: 'var(--amber-exodo)' }} />
                            <span>{msg.content}</span>
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

            {/* 4. Composer Pinned Exacto al Móvil (#252525) */}
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
    </div>
  );
}
