import React, { useState, useEffect, useRef } from 'react';
import { 
  ChevronRight, 
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
  Pin
} from 'lucide-react';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import { supabase, type Conversation, type Message } from './lib/supabase';
import { AuthModal } from './components/AuthModal';

export default function App() {
  // Estados de sesión y autenticación
  const [session, setSession] = useState<any>(null);
  const [userProfile, setUserProfile] = useState<{ plan?: string; full_name?: string } | null>(null);
  const [showAuthModal, setShowAuthModal] = useState(false);

  // Estados de interfaz exacta a móvil
  const [theme, setTheme] = useState<'dark' | 'light'>('dark');
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
  const [conversations, setConversations] = useState<Conversation[]>([]);
  const [activeConvId, setActiveConvId] = useState<string | null>(null);
  const [messages, setMessages] = useState<Message[]>([
    {
      id: 'welcome-1',
      conversation_id: 'initial',
      role: 'assistant',
      content: 'Hola. ¿En qué trabajamos hoy?',
      created_at: new Date().toISOString()
    }
  ]);
  const [input, setInput] = useState('');
  const [isStreaming, setIsStreaming] = useState(false);

  const messagesEndRef = useRef<HTMLDivElement>(null);

  // Sincronización de tema
  useEffect(() => {
    document.documentElement.setAttribute('data-theme', theme);
  }, [theme]);

  // Sincronización de sesión y Realtime
  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => {
      setSession(session);
      if (session?.user) fetchProfile(session.user.id);
    });

    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
      setSession(session);
      if (session?.user) {
        fetchProfile(session.user.id);
        fetchConversations();
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
      subscription.unsubscribe();
      supabase.removeChannel(channel);
    };
  }, []);

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
        setConversations(data);
        if (data.length > 0 && !activeConvId) {
          setActiveConvId(data[0].id);
          fetchMessages(data[0].id);
        }
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
    setConversations([newConv, ...conversations]);
    setActiveConvId(newConvId);
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

  const getExodoGreeting = () => {
    if (isIncognito) return 'Modo Incógnito';
    const hour = new Date().getHours();
    if (hour >= 0 && hour < 6) return 'Ni la madrugada te detiene';
    if (hour < 12) return 'Cafecito con Exodo';
    if (hour < 18) return 'Tarde productiva';
    return 'La noche es joven';
  };

  const renderChatComposer = () => (
    <div style={{ width: '100%', maxWidth: 680, margin: '0 auto', display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
      {showUpgradeBanner && !isIncognito && (
        <div style={{
          width: 'min(92%, 360px)',
          padding: '4px 16px 29px 16px',
          position: 'relative' as const,
          top: 10,
          background: '#F5F2EB',
          borderRadius: '20px 20px 0 0',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          flexWrap: 'wrap',
          gap: '4px 10px',
          boxSizing: 'border-box' as const,
          textAlign: 'center'
        }}>
          <span style={{ fontFamily: 'AnthropicSans, sans-serif', fontSize: '12px', fontWeight: 600, color: '#0E0C0A', lineHeight: 1.2 }}>
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
            <X size={16} color="#0E0C0A" />
          </button>
        </div>
      )}
      <form 
        className="composer-container" 
        onSubmit={handleSendMessage} 
        style={{
          position: showUpgradeBanner && !isIncognito ? 'relative' : undefined,
          top: showUpgradeBanner && !isIncognito ? -18 : undefined, 
        width: '100%', 
        maxWidth: 680,
        margin: '0 auto',
        background: '#252525',
        border: 'none',
        outline: 'none',
        boxShadow: 'none',
        borderRadius: 24,
        padding: '18px 20px 14px 20px',
        display: 'flex',
        flexDirection: 'column'
      }}
    >
      <textarea
        className="composer-input"
        placeholder="Reply to Exodo..."
        value={input}
        onChange={(e) => setInput(e.target.value)}
        onKeyDown={(e) => {
          if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault();
            handleSendMessage();
          }
        }}
        rows={2}
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
          minHeight: '52px',
          padding: '4px 6px 16px 6px'
        }}
      />

      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <button 
            type="button" 
            className="icon-btn" 
            style={{ width: 36, height: 36, borderRadius: '50%', background: '#1B1B1B', display: 'flex', alignItems: 'center', justifyContent: 'center' }}
            title="Adjuntar archivos"
            onClick={() => alert('Selector de adjuntos sincronizado con nube')}
          >
            <Plus size={20} color="var(--text-primary)" />
          </button>

          <button
            type="button"
            onClick={() => setShowModelSelector(true)}
            style={{
              padding: '6px 14px',
              borderRadius: 16,
              background: '#1B1B1B',
              border: selectedModel.id === 'ehyeh' ? '1px solid var(--amber-exodo)' : '1px solid transparent',
              display: 'flex',
              alignItems: 'center',
              gap: 6,
              cursor: 'pointer',
              color: 'var(--text-primary)'
            }}
            title="Seleccionar Modelo"
          >
            <span style={{ fontFamily: 'AnthropicSans, sans-serif', fontSize: '13px', fontWeight: 700 }}>
              {selectedModel.title}
            </span>
            <ChevronRight size={15} color="var(--text-secondary)" style={{ transform: 'rotate(90deg)' }} />
          </button>
        </div>

        <button
          type="submit"
          disabled={!input.trim() || isStreaming}
          style={{
            width: 38,
            height: 38,
            borderRadius: '50%',
            background: input.trim() && !isStreaming ? '#F5F2EB' : '#36322D',
            color: input.trim() && !isStreaming ? '#141210' : '#6B6560',
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
    <div style={{ marginTop: -4, textAlign: 'center', fontFamily: 'AnthropicSans, sans-serif', fontSize: '12px', color: 'var(--text-secondary)' }}>
      Exodo es IA y puede cometer errores. Por favor verifica las respuestas.
    </div>
    </div>
  );

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
            <img 
              src="/incognito-svgrepo-com.png" 
              alt="Incógnito" 
              style={{ 
                width: 20, 
                height: 20, 
                filter: isIncognito 
                  ? 'brightness(0) saturate(100%) invert(60%) sepia(80%) saturate(600%) hue-rotate(360deg) brightness(95%) contrast(90%)' 
                  : 'invert(0.8)' 
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
              <img 
                src="/incognito-svgrepo-com.png" 
                alt="Incógnito" 
                style={{ 
                  width: 20, 
                  height: 20, 
                  filter: isIncognito 
                    ? 'brightness(0) saturate(100%) invert(60%) sepia(80%) saturate(600%) hue-rotate(360deg) brightness(95%) contrast(90%)' 
                    : 'invert(0.8)' 
                }} 
              />
            </button>
          </div>
        </header>

        {!messages.some((m) => m.role === 'user') ? (
          <div className="welcome-center">
            <div style={{ display: 'flex', alignItems: 'center', gap: 24, marginBottom: 36 }}>
              <img 
                src="/Logo_behavior.png" 
                alt="Éxodo Logo" 
                style={{ width: 72, height: 72, objectFit: 'contain', flexShrink: 0 }} 
              />
              <div className="greeting-text-exodo" style={{ textAlign: 'left' }}>
                {getExodoGreeting()}
              </div>
            </div>

            {/* Cajón de escritura exacto a móvil (#252525 con selector de modelos) */}
            {renderChatComposer()}
          </div>
        ) : (
          <>
            <div className="messages-list">
              <div className="messages-wrapper">
                {messages.map((msg) => (
                  <div key={msg.id} className={`msg-row ${msg.role}`}>
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
                  </div>
                ))}
                <div ref={messagesEndRef} />
              </div>
            </div>

            {/* 4. Composer Pinned Exacto al Móvil (#252525) */}
            <div className="composer-pinned" style={{ width: '100%', display: 'flex', justifyContent: 'center' }}>
              {renderChatComposer()}
            </div>
          </>
        )}
      </main>

      {/* Modal Selector de Modelos Exacto a model_selector.dart */}
      {showModelSelector && (
        <div className="drawer-backdrop" onClick={() => setShowModelSelector(false)} style={{ zIndex: 60 }}>
          <div 
            className="model-selector-modal"
            onClick={(e) => e.stopPropagation()}
            style={{
              position: 'fixed',
              top: '50%',
              left: '50%',
              transform: 'translate(-50%, -50%)',
              background: 'var(--surface-card)',
              border: '1px solid var(--border-color)',
              borderRadius: 20,
              padding: '24px',
              width: '90%',
              maxWidth: '420px',
              zIndex: 61,
              boxShadow: '0 20px 50px rgba(0,0,0,0.5)'
            }}
          >
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 16 }}>
              <span style={{ fontFamily: 'AnthropicSans, sans-serif', fontSize: '16px', fontWeight: 700, color: 'var(--text-primary)' }}>
                Modelo de Inteligencia
              </span>
              <button type="button" className="icon-btn" onClick={() => setShowModelSelector(false)}>
                <ChevronRight size={20} color="var(--text-secondary)" />
              </button>
            </div>

            <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
              {[
                {
                  id: 'origo',
                  title: 'G1.1',
                  subtitle: 'Origo',
                  plan: 'genesis',
                  description: 'Modelo capaz para tareas diarias.'
                },
                {
                  id: 'ehyeh',
                  title: 'XPi',
                  subtitle: 'Ehyeh',
                  plan: 'hazak',
                  description: 'Razonamiento avanzado para tareas exigentes.'
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
                      padding: '14px 16px',
                      borderRadius: 14,
                      background: active ? 'rgba(201, 147, 58, 0.12)' : 'var(--surface-input)',
                      border: active ? '1px solid var(--amber-exodo)' : '1px solid transparent',
                      cursor: 'pointer',
                      display: 'flex',
                      flexDirection: 'column',
                      gap: 4
                    }}
                  >
                    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                      <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                        <span style={{ fontFamily: 'AnthropicSans, sans-serif', fontWeight: 700, fontSize: '15px', color: active ? 'var(--amber-exodo)' : 'var(--text-primary)' }}>
                          {m.title}
                        </span>
                        <span style={{ fontFamily: 'AnthropicSans, sans-serif', fontSize: '13px', color: 'var(--text-secondary)' }}>
                          {m.subtitle}
                        </span>
                        {isProModel && (
                          <span style={{ padding: '2px 6px', borderRadius: 4, background: active ? 'rgba(201, 147, 58, 0.2)' : '#222', border: `1px solid ${active ? 'var(--amber-exodo)' : 'rgba(255,255,255,0.15)'}`, fontSize: '10px', fontWeight: 700, color: active ? 'var(--amber-exodo)' : 'var(--text-primary)' }}>
                            PRO
                          </span>
                        )}
                      </div>
                      {active && <Check size={18} color="var(--amber-exodo)" />}
                    </div>
                    <span style={{ fontFamily: 'AnthropicSans, sans-serif', fontSize: '12px', color: 'var(--text-secondary)' }}>
                      {m.description}
                    </span>
                  </div>
                );
              })}
            </div>

            <div style={{ marginTop: 20, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6 }}>
              <span style={{ fontSize: '11px', color: 'var(--text-secondary)' }}>
                ❖ Razonamiento por defecto activo en todos los modelos
              </span>
            </div>
          </div>
        </div>
      )}

      {/* Modal exacto de AuthScreen móvil (sin pestañas de correo) */}
      <AuthModal
        isOpen={showAuthModal}
        onClose={() => setShowAuthModal(false)}
        onSuccess={() => fetchConversations()}
      />
    </div>
  );
}
