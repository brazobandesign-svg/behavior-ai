import React, { useState, useEffect, useRef } from 'react';
import {
  MessageSquare,
  Search,
  X,
  ChevronRight,
  ChevronDown,
  Pin,
  MoreVertical,
  Edit2,
  Trash2,
  Folder,
  LogIn,
  AlertTriangle,
  Smartphone
} from 'lucide-react';
import type { Conversation } from '../lib/supabase';
import { openExodoApp } from '../lib/exodoLinks';

export interface DrawerMenuProps {
  isOpen: boolean;
  onClose: () => void;
  conversations: Conversation[];
  activeConvId: string | null;
  onSelectConversation: (id: string) => void;
  onCreateNewChat?: () => void;
  theme: 'dark' | 'light';
  onToggleTheme?: () => void;
  isIncognito?: boolean;
  onToggleIncognito?: () => void;
  isGuestUser: boolean;
  userProfile: any;
  userEmail?: string;
  onOpenAuth: () => void;
  onOpenSettings: () => void;
  onOpenExpedientes: () => void;
  onRenameConversation: (id: string, newTitle: string) => Promise<void> | void;
  onToggleStarConversation: (conv: Conversation) => Promise<void> | void;
  onDeleteConversation: (id: string) => Promise<void> | void;
  onSearchMessages?: (query: string) => Promise<string[]>;
  locale?: string;
}

// Traducciones del Drawer (paridad exacta con app_translations.dart)
const DRAWER_I18N: Record<string, Record<string, string>> = {
  es: {
    new_chat: 'Nuevo chat',
    light_mode: 'Modo claro',
    dark_mode: 'Modo oscuro',
    incognito: 'Modo Incógnito',
    shared_artifacts: 'Expedientes',
    settings: 'Ajustes',
    search_chats: 'Buscar chats',
    exodo_app: 'Exodo App',
    search_hint: 'Buscar conversaciones...',
    starred: 'Fijados',
    recents: 'Recientes',
    no_history: 'Sin historial todavía',
    start_conv: 'Inicia una conversación para verla aquí.',
    no_found: 'Sin resultados',
    try_search: 'Prueba con otra búsqueda.',
    user_default: 'Usuario Exodo',
    guest: 'Invitado',
    login: 'Acceder',
    rename: 'Renombrar',
    pin: 'Fijar',
    unpin: 'Desfijar',
    delete: 'Eliminar',
    cancel: 'Cancelar',
    save: 'Guardar',
    delete_confirm_title: 'Eliminar conversación',
    delete_confirm_body: '¿Seguro que deseas eliminar',
    rename_title: 'Renombrar conversación',
  },
  en: {
    new_chat: 'New chat',
    light_mode: 'Light mode',
    dark_mode: 'Dark mode',
    incognito: 'Incognito mode',
    shared_artifacts: 'Records',
    settings: 'Settings',
    search_chats: 'Search chats',
    exodo_app: 'Exodo App',
    search_hint: 'Search conversations...',
    starred: 'Pinned',
    recents: 'Recents',
    no_history: 'No history yet',
    start_conv: 'Start a conversation to see it here.',
    no_found: 'No results',
    try_search: 'Try another search.',
    user_default: 'Exodo User',
    guest: 'Guest',
    login: 'Sign in',
    rename: 'Rename',
    pin: 'Pin',
    unpin: 'Unpin',
    delete: 'Delete',
    cancel: 'Cancel',
    save: 'Save',
    delete_confirm_title: 'Delete conversation',
    delete_confirm_body: 'Are you sure you want to delete',
    rename_title: 'Rename conversation',
  }
};

export const DrawerMenu: React.FC<DrawerMenuProps> = ({
  isOpen,
  onClose,
  conversations,
  activeConvId,
  onSelectConversation,
  theme,
  isGuestUser,
  userProfile,
  onOpenAuth,
  onOpenSettings,
  onOpenExpedientes,
  onRenameConversation,
  onToggleStarConversation,
  onDeleteConversation,
  onSearchMessages,
  locale = 'es',
}) => {
  const [searchQuery, setSearchQuery] = useState('');
  const [isSearching, setIsSearching] = useState(false);
  const [matchingIds, setMatchingIds] = useState<Set<string>>(new Set());
  const [showVersion, setShowVersion] = useState(false);
  const [hoveredConvId, setHoveredConvId] = useState<string | null>(null);
  const [openMenuId, setOpenMenuId] = useState<string | null>(null);
  const [renamingId, setRenamingId] = useState<string | null>(null);
  const [renameDraft, setRenameDraft] = useState('');
  const [deleteConfirmConv, setDeleteConfirmConv] = useState<Conversation | null>(null);
  const [renameDialogConv, setRenameDialogConv] = useState<Conversation | null>(null);
  const [renameDialogText, setRenameDialogText] = useState('');
  const [isRecentsCollapsed, setIsRecentsCollapsed] = useState(false);
  const [isPinnedCollapsed, setIsPinnedCollapsed] = useState(false);

  const searchInputRef = useRef<HTMLInputElement>(null);
  const langKey = locale.toLowerCase().startsWith('es') ? 'es' : 'en';
  const t = (key: string) => DRAWER_I18N[langKey]?.[key] || DRAWER_I18N.es[key] || key;

  // Auto-focus al activar búsqueda
  useEffect(() => {
    if (isSearching) {
      setTimeout(() => searchInputRef.current?.focus(), 50);
    }
  }, [isSearching]);

  // Búsqueda con debounce por título y contenido
  useEffect(() => {
    const q = searchQuery.trim();
    if (q.length < 2) {
      setMatchingIds(new Set());
      return;
    }
    const timer = setTimeout(async () => {
      if (onSearchMessages) {
        try {
          const ids = await onSearchMessages(q);
          setMatchingIds(new Set(ids));
        } catch (_) {
          // Fallback a coincidencia por título
        }
      }
    }, 280);
    return () => clearTimeout(timer);
  }, [searchQuery, onSearchMessages]);

  // Filtrado de conversaciones
  const filteredConvs = conversations.filter((c) => {
    if (!searchQuery.trim()) return true;
    const lower = searchQuery.toLowerCase();
    return c.title.toLowerCase().includes(lower) || matchingIds.has(c.id);
  });

  const starredConvs = filteredConvs.filter((c) => c.is_starred);
  const recentConvs = filteredConvs.filter((c) => !c.is_starred);

  const isLight = theme === 'light';

  // Ejecutar renombrado inline
  const handleCommitRename = (convId: string) => {
    const trimmed = renameDraft.trim();
    if (trimmed && trimmed !== conversations.find((c) => c.id === convId)?.title) {
      onRenameConversation(convId, trimmed);
    }
    setRenamingId(null);
  };

  // Click fuera para cerrar menús contextuales
  useEffect(() => {
    const handleClickOutside = () => setOpenMenuId(null);
    if (openMenuId) {
      window.addEventListener('click', handleClickOutside);
      return () => window.removeEventListener('click', handleClickOutside);
    }
  }, [openMenuId]);

  return (
    <>
      {/* 1. Backdrop con transición suave para evitar destellos */}
      <div
        className={`drawer-backdrop ${isOpen ? 'open' : ''}`}
        onClick={onClose}
        style={{ cursor: 'pointer' }}
      />

      {/* 2. Drawer Panel */}
      <aside
        className={`drawer-slide ${isOpen ? 'open' : ''}`}
        style={{
          width: 'min(310px, 86vw)',
          boxShadow: isOpen ? '4px 0 24px rgba(0,0,0,0.3)' : 'none',
        }}
      >
        {/* Header fijo: Logo_behavior + exodo_text + versión + cerrar */}
        <div
          className="drawer-header"
          style={{
            padding: '24px 20px 14px 20px',
            borderBottom: 'none',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
          }}
        >
          <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
            <div
              style={{ display: 'flex', alignItems: 'center', gap: 10, cursor: 'pointer' }}
              onClick={() => setShowVersion((v) => !v)}
              title="Versión"
            >
              <img
                src="/Logo_behavior.png"
                alt="Logo"
                style={{
                  height: 38,
                  width: 'auto',
                  objectFit: 'contain',
                  filter: 'drop-shadow(0 2px 6px rgba(201, 147, 58, 0.25))'
                }}
              />
              <div
                className="mask-text-yeso"
                style={{
                  width: 78,
                  height: 24,
                  backgroundColor: isLight ? '#171615' : '#F5F2EB',
                }}
              />
            </div>

            {/* Badge de versión (paridad toggle tap logo_behavior) */}
            {showVersion && (
              <div
                style={{
                  alignSelf: 'flex-start',
                  padding: '3px 9px',
                  borderRadius: 6,
                  border: '0.8px solid rgba(201, 147, 58, 0.4)',
                  backgroundColor: isLight ? '#F5F2EB' : '#131313',
                  color: 'var(--amber-exodo)',
                  fontSize: '10.5px',
                  fontWeight: 600,
                  fontFamily: 'AnthropicSans, sans-serif',
                  letterSpacing: '0.2px',
                }}
              >
                AVI 1.1.86-web.01
              </div>
            )}
          </div>

          <button
            type="button"
            className="icon-btn"
            onClick={onClose}
            style={{ width: 32, height: 32, display: 'flex', alignItems: 'center', justifyContent: 'center' }}
            title="Cerrar menú"
          >
            <ChevronRight size={22} color="var(--text-secondary)" />
          </button>
        </div>

        {/* Acciones del menú (Expedientes y Buscar chats) */}
        <div style={{ padding: '4px 10px 8px 10px' }}>

          {/* Artefactos compartidos (Expedientes) — exclusivo para cuentas */}
          {!isGuestUser && (
            <button
              type="button"
              className="drawer-item"
              onClick={() => {
                onClose();
                onOpenExpedientes();
              }}
              style={{ borderRadius: 10, padding: '10px 14px', marginBottom: 2 }}
            >
              <Folder size={19} color="var(--text-primary)" />
              <span style={{ fontSize: '14px', fontWeight: 600, letterSpacing: '-0.2px' }}>
                {t('shared_artifacts')}
              </span>
            </button>
          )}

          {/* Buscar chats */}
          {!isSearching && (
            <button
              type="button"
              className="drawer-item"
              onClick={() => setIsSearching(true)}
              style={{ borderRadius: 10, padding: '10px 14px', marginBottom: 2 }}
            >
              <Search size={19} color="var(--text-primary)" />
              <span style={{ fontSize: '14px', fontWeight: 600, letterSpacing: '-0.2px' }}>
                {t('search_chats')}
              </span>
            </button>
          )}

          {/* Exodo App — enlace directo a la Play Store (movido desde Settings) */}
          <button
            type="button"
            className="drawer-item"
            onClick={openExodoApp}
            style={{ borderRadius: 10, padding: '10px 14px', marginBottom: 2 }}
          >
            <Smartphone size={19} color="var(--text-primary)" />
            <span style={{ fontSize: '14px', fontWeight: 600, letterSpacing: '-0.2px' }}>
              {t('exodo_app')}
            </span>
          </button>
        </div>

        {/* Input de búsqueda interactivo desplegado */}
        {isSearching && (
          <div
            style={{
              margin: '2px 14px 10px 14px',
              padding: '7px 12px',
              background: isLight ? '#FFFFFF' : '#252525',
              borderRadius: 10,
              display: 'flex',
              alignItems: 'center',
              gap: 8,
              border: `1px solid ${isLight ? '#E0E0E0' : 'rgba(255,255,255,0.08)'}`,
            }}
          >
            <Search size={16} color="var(--text-secondary)" />
            <input
              ref={searchInputRef}
              type="text"
              placeholder={t('search_hint')}
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              style={{
                flex: 1,
                border: 'none',
                background: 'transparent',
                color: 'var(--text-primary)',
                fontSize: '13px',
                outline: 'none',
                fontFamily: 'AnthropicSans, sans-serif',
              }}
            />
            <button
              type="button"
              onClick={() => {
                setSearchQuery('');
                setIsSearching(false);
              }}
              style={{ background: 'none', border: 'none', cursor: 'pointer', padding: 2, display: 'flex', alignItems: 'center' }}
            >
              <X size={15} color="var(--text-secondary)" />
            </button>
          </div>
        )}

        {/* Divisor */}
        <div style={{ height: 1, background: isLight ? '#E0E0E0' : '#212121', margin: '2px 16px 8px 16px' }} />

        {/* Historial de conversaciones (Fijados y Recientes) */}
        <div
          className="conv-list"
          style={{
            flex: 1,
            overflowY: 'auto',
            padding: '0 8px 120px 8px',
          }}
        >
          {/* Vacío */}
          {filteredConvs.length === 0 && (
            <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', padding: '32px 20px', textAlign: 'center' }}>
              <div
                style={{
                  width: 52,
                  height: 52,
                  borderRadius: '50%',
                  background: isLight ? '#F0F0F0' : '#252525',
                  border: `1px solid ${isLight ? '#E0E0E0' : '#333333'}`,
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  marginBottom: 14,
                }}
              >
                <MessageSquare size={22} color="var(--amber-exodo)" />
              </div>
              <div
                style={{
                  fontSize: '13px',
                  fontWeight: 600,
                  color: 'var(--text-secondary)',
                  letterSpacing: '-0.1px',
                  fontFamily: 'AnthropicSans, sans-serif',
                }}
              >
                {conversations.length === 0 ? t('no_history') : t('no_found')}
              </div>
              <div
                style={{
                  fontSize: '12px',
                  color: 'var(--text-secondary)',
                  opacity: 0.75,
                  marginTop: 4,
                  lineHeight: 1.4,
                  fontFamily: 'Inter, sans-serif',
                }}
              >
                {conversations.length === 0 ? t('start_conv') : t('try_search')}
              </div>
            </div>
          )}

          {/* Sección: Fijados (Acoplable con indicador en forma de "V") */}
          {starredConvs.length > 0 && (
            <div style={{ marginBottom: 12 }}>
              <div
                onClick={() => setIsPinnedCollapsed((prev) => !prev)}
                style={{
                  position: 'sticky',
                  top: 0,
                  zIndex: 4,
                  backgroundColor: isLight ? '#FFFFFF' : '#191919',
                  padding: '8px 12px 6px 12px',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'space-between',
                  cursor: 'pointer',
                  userSelect: 'none',
                  borderRadius: 6,
                }}
                role="button"
                aria-expanded={!isPinnedCollapsed}
                title={isPinnedCollapsed ? (langKey === 'es' ? 'Desacoplar fijados' : 'Expand pinned') : (langKey === 'es' ? 'Acoplar fijados' : 'Collapse pinned')}
              >
                <span
                  style={{
                    fontSize: '11.5px',
                    fontWeight: 700,
                    color: 'var(--text-secondary)',
                    letterSpacing: '-0.1px',
                    fontFamily: 'AnthropicSans, sans-serif',
                    textTransform: 'uppercase',
                  }}
                >
                  {t('starred')}
                </span>
                <div
                  style={{
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    transform: isPinnedCollapsed ? 'rotate(-90deg)' : 'rotate(0deg)',
                    transition: 'transform 0.22s cubic-bezier(0.16, 1, 0.3, 1)',
                  }}
                >
                  <ChevronDown size={14} color="var(--text-secondary)" />
                </div>
              </div>
              {!isPinnedCollapsed && (
                <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
                  {starredConvs.map((conv) => renderConversationTile(conv, true))}
                </div>
              )}
            </div>
          )}

          {/* Sección: Recientes (Acoplable con indicador en forma de "V") */}
          {recentConvs.length > 0 && (
            <div>
              <div
                onClick={() => setIsRecentsCollapsed((prev) => !prev)}
                style={{
                  position: 'sticky',
                  top: 0,
                  zIndex: 3,
                  backgroundColor: isLight ? '#FFFFFF' : '#191919',
                  padding: '8px 12px 6px 12px',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'space-between',
                  cursor: 'pointer',
                  userSelect: 'none',
                  borderRadius: 6,
                }}
                role="button"
                aria-expanded={!isRecentsCollapsed}
                title={isRecentsCollapsed ? (langKey === 'es' ? 'Desacoplar recientes' : 'Expand recents') : (langKey === 'es' ? 'Acoplar recientes' : 'Collapse recents')}
              >
                <span
                  style={{
                    fontSize: '11.5px',
                    fontWeight: 700,
                    color: 'var(--text-secondary)',
                    letterSpacing: '-0.1px',
                    fontFamily: 'AnthropicSans, sans-serif',
                    textTransform: 'uppercase',
                  }}
                >
                  {t('recents')}
                </span>
                <div
                  style={{
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    transform: isRecentsCollapsed ? 'rotate(-90deg)' : 'rotate(0deg)',
                    transition: 'transform 0.22s cubic-bezier(0.16, 1, 0.3, 1)',
                  }}
                >
                  <ChevronDown size={14} color="var(--text-secondary)" />
                </div>
              </div>
              {!isRecentsCollapsed && (
                <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
                  {recentConvs.map((conv) => renderConversationTile(conv, false))}
                </div>
              )}
            </div>
          )}
        </div>

        {/* Footer fijo (Stack bottom): Usuario + by Behavior */}
        <div
          style={{
            borderTop: `1px solid ${isLight ? '#E0E0E0' : '#212121'}`,
            backgroundColor: isLight ? '#FFFFFF' : '#191919',
            padding: '12px 18px 14px 18px',
            position: 'absolute',
            bottom: 0,
            left: 0,
            right: 0,
          }}
        >
          {userProfile && !isGuestUser ? (
            <div
              onClick={onOpenSettings}
              style={{
                display: 'flex',
                flexDirection: 'column',
                gap: 8,
                cursor: 'pointer',
              }}
              title="Ajustes de cuenta"
            >
              <div style={{ display: 'flex', alignItems: 'center', gap: 12, overflow: 'hidden' }}>
                {userProfile.avatar_url ? (
                  <img
                    src={userProfile.avatar_url}
                    alt="Avatar"
                    style={{ width: 36, height: 36, borderRadius: '50%', objectFit: 'cover', flexShrink: 0 }}
                  />
                ) : (
                  <div
                    style={{
                      width: 36,
                      height: 36,
                      borderRadius: '50%',
                      background: 'var(--amber-exodo)',
                      color: '#000000',
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                      fontFamily: 'Syne, sans-serif',
                      fontWeight: 700,
                      fontSize: '17px',
                      flexShrink: 0,
                    }}
                  >
                    {((userProfile.full_name || '').trim().charAt(0) || 'U').toUpperCase()}
                  </div>
                )}
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div
                    style={{
                      fontSize: '13.5px',
                      fontWeight: 600,
                      color: 'var(--text-primary)',
                      whiteSpace: 'nowrap',
                      overflow: 'hidden',
                      textOverflow: 'ellipsis',
                      letterSpacing: '-0.2px',
                      fontFamily: 'AnthropicSans, sans-serif',
                    }}
                  >
                    {userProfile.full_name || t('user_default')}
                  </div>
                </div>
              </div>

              {/* Logo by Behavior */}
              <div
                className="mask-bybehavior"
                style={{
                  height: 20,
                  backgroundColor: isLight ? '#757575' : 'var(--text-secondary)',
                }}
              />
            </div>
          ) : (
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
              <div
                onClick={onOpenSettings}
                style={{ display: 'flex', alignItems: 'center', gap: 10, cursor: 'pointer', flex: 1 }}
                title="Ajustes de cuenta"
              >
                <div
                  style={{
                    width: 34,
                    height: 34,
                    borderRadius: '50%',
                    background: isLight ? '#F0F0F0' : '#252525',
                    color: isLight ? '#171615' : '#F5F2EB',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    fontWeight: 700,
                    fontSize: '13px',
                    fontFamily: 'AnthropicSans, sans-serif',
                  }}
                >
                  G
                </div>
                <span style={{ fontSize: '13.5px', fontWeight: 600, color: 'var(--text-primary)' }}>
                  {t('guest')}
                </span>
              </div>
              <button
                type="button"
                onClick={onOpenAuth}
                style={{
                  border: '1px solid var(--amber-exodo)',
                  background: 'transparent',
                  color: 'var(--amber-exodo)',
                  padding: '5px 12px',
                  borderRadius: 8,
                  fontSize: '12px',
                  fontWeight: 600,
                  cursor: 'pointer',
                  display: 'flex',
                  alignItems: 'center',
                  gap: 6,
                }}
              >
                <LogIn size={13} />
                {t('login')}
              </button>
            </div>
          )}
        </div>
      </aside>

      {/* 3. Modal de Confirmación de Eliminación */}
      {deleteConfirmConv && (
        <div style={{ position: 'fixed', inset: 0, zIndex: 1200, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 20 }}>
          <div
            style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.6)', backdropFilter: 'blur(3px)' }}
            onClick={() => setDeleteConfirmConv(null)}
          />
          <div
            style={{
              position: 'relative',
              background: isLight ? '#FFFFFF' : '#1E1E1E',
              width: '100%',
              maxWidth: 380,
              borderRadius: 16,
              padding: '20px',
              border: `1px solid ${isLight ? '#E0E0E0' : '#333333'}`,
              boxShadow: '0 8px 30px rgba(0,0,0,0.4)',
            }}
          >
            <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 12 }}>
              <AlertTriangle size={22} color="#ff4d4f" />
              <h3 style={{ margin: 0, fontSize: '16px', fontWeight: 700, fontFamily: 'Inter, sans-serif', color: 'var(--text-primary)' }}>
                {t('delete_confirm_title')}
              </h3>
            </div>
            <p style={{ margin: '0 0 20px 0', fontSize: '14px', color: 'var(--text-secondary)', lineHeight: 1.45 }}>
              {t('delete_confirm_body')} "{deleteConfirmConv.title}"?
            </p>
            <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 10 }}>
              <button
                type="button"
                onClick={() => setDeleteConfirmConv(null)}
                style={{
                  background: 'transparent',
                  border: 'none',
                  padding: '8px 14px',
                  borderRadius: 8,
                  fontSize: '13px',
                  fontWeight: 600,
                  color: 'var(--text-secondary)',
                  cursor: 'pointer',
                }}
              >
                {t('cancel')}
              </button>
              <button
                type="button"
                onClick={() => {
                  onDeleteConversation(deleteConfirmConv.id);
                  setDeleteConfirmConv(null);
                }}
                style={{
                  background: '#ff4d4f',
                  border: 'none',
                  padding: '8px 16px',
                  borderRadius: 8,
                  fontSize: '13px',
                  fontWeight: 600,
                  color: '#FFFFFF',
                  cursor: 'pointer',
                }}
              >
                {t('delete')}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* 4. Modal de Renombrar Conversación */}
      {renameDialogConv && (
        <div style={{ position: 'fixed', inset: 0, zIndex: 1200, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 20 }}>
          <div
            style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.6)', backdropFilter: 'blur(3px)' }}
            onClick={() => setRenameDialogConv(null)}
          />
          <div
            style={{
              position: 'relative',
              background: isLight ? '#FFFFFF' : '#1E1E1E',
              width: '100%',
              maxWidth: 380,
              borderRadius: 16,
              padding: '20px',
              border: `1px solid ${isLight ? '#E0E0E0' : '#333333'}`,
              boxShadow: '0 8px 30px rgba(0,0,0,0.4)',
            }}
          >
            <h3 style={{ margin: '0 0 14px 0', fontSize: '16px', fontWeight: 700, fontFamily: 'Inter, sans-serif', color: 'var(--text-primary)' }}>
              {t('rename_title')}
            </h3>
            <input
              type="text"
              autoFocus
              value={renameDialogText}
              onChange={(e) => setRenameDialogText(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') {
                  const trimmed = renameDialogText.trim();
                  if (trimmed) onRenameConversation(renameDialogConv.id, trimmed);
                  setRenameDialogConv(null);
                }
              }}
              style={{
                width: '100%',
                padding: '10px 12px',
                borderRadius: 8,
                border: `1px solid ${isLight ? '#D0D0D0' : '#444444'}`,
                background: isLight ? '#F9F9F9' : '#282828',
                color: 'var(--text-primary)',
                fontSize: '14px',
                outline: 'none',
                boxSizing: 'border-box',
                marginBottom: 16,
              }}
            />
            <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 10 }}>
              <button
                type="button"
                onClick={() => setRenameDialogConv(null)}
                style={{
                  background: 'transparent',
                  border: 'none',
                  padding: '8px 14px',
                  borderRadius: 8,
                  fontSize: '13px',
                  fontWeight: 600,
                  color: 'var(--text-secondary)',
                  cursor: 'pointer',
                }}
              >
                {t('cancel')}
              </button>
              <button
                type="button"
                onClick={() => {
                  const trimmed = renameDialogText.trim();
                  if (trimmed) onRenameConversation(renameDialogConv.id, trimmed);
                  setRenameDialogConv(null);
                }}
                style={{
                  background: 'var(--amber-exodo)',
                  border: 'none',
                  padding: '8px 16px',
                  borderRadius: 8,
                  fontSize: '13px',
                  fontWeight: 700,
                  color: '#000000',
                  cursor: 'pointer',
                }}
              >
                {t('save')}
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  );

  // Renderizador de un ítem de conversación (paridad `_buildConvItem`)
  function renderConversationTile(conv: Conversation, isStarred: boolean) {
    const active = activeConvId === conv.id;
    const isEditing = renamingId === conv.id;

    return (
      <div
        key={conv.id}
        className={`conv-item ${active ? 'active' : ''}`}
        onMouseEnter={() => setHoveredConvId(conv.id)}
        onMouseLeave={() => setHoveredConvId(null)}
        onClick={() => {
          onSelectConversation(conv.id);
          onClose();
        }}
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: 8,
          height: 40,
          minHeight: 40,
          boxSizing: 'border-box',
          padding: '0 10px',
          margin: '2px 4px',
          borderRadius: 12,
          position: 'relative',
          cursor: 'pointer',
          background: active
            ? (isLight ? '#E6E6EB' : '#2C2C30')
            : (hoveredConvId === conv.id ? (isLight ? '#F0EFEA' : '#232323') : 'transparent'),
          border: active
            ? `1.2px solid ${isLight ? '#D0D0D5' : 'rgba(201, 147, 58, 0.4)'}`
            : '1.2px solid transparent',
          boxShadow: active ? '0 2px 6px rgba(0,0,0,0.15)' : 'none',
          transition: 'background 0.15s ease, border-color 0.15s ease',
        }}
      >
        {/* Barra vertical ámbar del chat activo */}
        {active && (
          <span
            style={{
              width: 4,
              height: 20,
              borderRadius: 2,
              backgroundColor: 'var(--amber-exodo)',
              flexShrink: 0,
            }}
          />
        )}

        {/* Título o Input de renombrado */}
        {isEditing ? (
          <input
            autoFocus
            className="search-input"
            value={renameDraft}
            onChange={(e) => setRenameDraft(e.target.value)}
            onClick={(e) => e.stopPropagation()}
            onKeyDown={(e) => {
              if (e.key === 'Enter') handleCommitRename(conv.id);
              if (e.key === 'Escape') setRenamingId(null);
            }}
            onBlur={() => handleCommitRename(conv.id)}
            style={{
              flex: 1,
              minWidth: 0,
              background: isLight ? '#FFFFFF' : '#1E1E1E',
              border: `1px solid ${isLight ? '#CCCCCC' : '#444444'}`,
              borderRadius: 6,
              padding: '3px 8px',
              fontSize: '13px',
              color: 'var(--text-primary)',
            }}
          />
        ) : (
          <span
            style={{
              flex: 1,
              minWidth: 0,
              overflow: 'hidden',
              textOverflow: 'ellipsis',
              whiteSpace: 'nowrap',
              fontSize: '13.5px',
              fontFamily: 'AnthropicSans, sans-serif',
              fontWeight: active ? 700 : 400,
              color: active
                ? (isLight ? '#000000' : '#FFFFFF')
                : (isLight ? '#444444' : '#B0B0B0'),
              letterSpacing: '-0.1px',
            }}
          >
            {conv.title}
          </span>
        )}

        {/* Pin indicador para fijados */}
        {isStarred && !isEditing && (
          <Pin
            size={13}
            color={active ? 'var(--amber-exodo)' : (isLight ? '#666666' : '#888888')}
            style={{ flexShrink: 0 }}
          />
        )}

        {/* Botón de 3 puntos (Opciones) — siempre en DOM con opacidad para NO alterar las dimensiones ni mover nada en hover */}
        {!isEditing && (
          <button
            type="button"
            onClick={(e) => {
              e.stopPropagation();
              setOpenMenuId(openMenuId === conv.id ? null : conv.id);
            }}
            style={{
              background: 'none',
              border: 'none',
              cursor: 'pointer',
              padding: 2,
              width: 20,
              height: 20,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              flexShrink: 0,
              opacity: hoveredConvId === conv.id || openMenuId === conv.id ? 1 : 0,
              pointerEvents: hoveredConvId === conv.id || openMenuId === conv.id ? 'auto' : 'none',
              transition: 'opacity 0.12s ease',
            }}
            title="Opciones"
          >
            <MoreVertical size={16} color="var(--text-secondary)" />
          </button>
        )}

        {/* Menú contextual flotante */}
        {openMenuId === conv.id && (
          <div
            onClick={(e) => e.stopPropagation()}
            style={{
              position: 'absolute',
              right: 8,
              top: 36,
              background: isLight ? '#FFFFFF' : '#222222',
              border: `1px solid ${isLight ? '#E0E0E0' : '#333333'}`,
              borderRadius: 10,
              padding: '4px',
              zIndex: 100,
              display: 'flex',
              flexDirection: 'column',
              gap: 2,
              boxShadow: '0 6px 18px rgba(0,0,0,0.35)',
              minWidth: 130,
            }}
          >
            <button
              type="button"
              className="drawer-item"
              onClick={() => {
                setRenameDialogText(conv.title);
                setRenameDialogConv(conv);
                setOpenMenuId(null);
              }}
              style={{
                padding: '7px 10px',
                fontSize: '13px',
                fontWeight: 500,
                borderRadius: 6,
                gap: 8,
              }}
            >
              <Edit2 size={14} color="var(--text-secondary)" />
              {t('rename')}
            </button>

            <button
              type="button"
              className="drawer-item"
              onClick={() => {
                onToggleStarConversation(conv);
                setOpenMenuId(null);
              }}
              style={{
                padding: '7px 10px',
                fontSize: '13px',
                fontWeight: 500,
                borderRadius: 6,
                gap: 8,
              }}
            >
              <Pin size={14} color="var(--text-secondary)" />
              {isStarred ? t('unpin') : t('pin')}
            </button>

            <button
              type="button"
              className="drawer-item"
              onClick={() => {
                setDeleteConfirmConv(conv);
                setOpenMenuId(null);
              }}
              style={{
                padding: '7px 10px',
                fontSize: '13px',
                fontWeight: 500,
                color: '#ff4d4f',
                borderRadius: 6,
                gap: 8,
              }}
            >
              <Trash2 size={14} color="#ff4d4f" />
              {t('delete')}
            </button>
          </div>
        )}
      </div>
    );
  }
};
