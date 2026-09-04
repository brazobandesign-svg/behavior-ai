import React from 'react';
import {
  Search,
  Folder,
  Smartphone
} from 'lucide-react';
import { openExodoApp } from '../lib/exodoLinks';

export interface SidebarRailProps {
  onToggleDrawer: () => void;
  isDrawerOpen: boolean;
  isGuestUser: boolean;
  userProfile: any;
  userEmail?: string;
  onOpenAuth: () => void;
  onOpenSettings: () => void;
  onOpenExpedientes: () => void;
  onStartSearch: () => void;
  locale?: string;
}

export const SidebarRail: React.FC<SidebarRailProps> = ({
  onToggleDrawer,
  isDrawerOpen,
  isGuestUser,
  userProfile,
  userEmail,
  onOpenAuth,
  onOpenSettings,
  onOpenExpedientes,
  onStartSearch,
  locale = 'es'
}) => {
  const isEn = locale?.toLowerCase().startsWith('en');

  return (
    <aside className="sidebar-rail" aria-label={isEn ? 'Sidebar menu' : 'Menú lateral'}>
      {/* 1. Botón de Menú Normal (Hamburguesa) para desplegar opciones completas con nombres */}
      <button
        type="button"
        className={`icon-btn rail-btn ${isDrawerOpen ? 'active' : ''}`}
        onClick={onToggleDrawer}
        title={isEn ? (isDrawerOpen ? 'Close menu' : 'Main menu') : (isDrawerOpen ? 'Cerrar menú' : 'Menú principal')}
        aria-label="Menú"
        style={{ marginBottom: 14 }}
      >
        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-start', gap: 4, padding: '4px 2px' }}>
          <div style={{ width: 18, height: 2, background: 'var(--text-primary)', borderRadius: 1 }} />
          <div style={{ width: 18, height: 2, background: 'var(--text-primary)', borderRadius: 1 }} />
          <div style={{ width: 12, height: 2, background: 'var(--text-primary)', borderRadius: 1 }} />
        </div>
      </button>

      {/* 2. Buscar Chats */}
      <button
        type="button"
        className="icon-btn rail-btn"
        onClick={onStartSearch}
        title={isEn ? 'Search chats' : 'Buscar chats'}
        aria-label="Buscar chats"
        style={{ marginBottom: 8 }}
      >
        <Search size={19} color="var(--text-primary)" />
      </button>

      {/* 3. Expedientes (si no es invitado) */}
      {!isGuestUser && (
        <button
          type="button"
          className="icon-btn rail-btn"
          onClick={onOpenExpedientes}
          title={isEn ? 'Shared artifacts' : 'Expedientes'}
          aria-label="Expedientes"
          style={{ marginBottom: 8 }}
        >
          <Folder size={19} color="var(--text-primary)" />
        </button>
      )}

      {/* 4. Exodo App — enlace directo a la Play Store */}
      <button
        type="button"
        className="icon-btn rail-btn"
        onClick={openExodoApp}
        title="Exodo App"
        aria-label="Exodo App"
        style={{ marginBottom: 8 }}
      >
        <Smartphone size={19} color="var(--text-primary)" />
      </button>

      {/* Espaciador vertical flexible */}
      <div style={{ flex: 1 }} />

      {/* 5. Perfil / Usuario / Acceder */}
      <button
        type="button"
        className="icon-btn rail-btn rail-avatar-btn"
        onClick={isGuestUser ? onOpenAuth : onOpenSettings}
        title={isGuestUser ? (isEn ? 'Sign in' : 'Acceder') : (userProfile?.name || userEmail || (isEn ? 'Account' : 'Cuenta'))}
        aria-label="Cuenta de usuario"
      >
        {isGuestUser ? (
          <div
            style={{
              width: 28,
              height: 28,
              borderRadius: '50%',
              background: 'var(--surface-input)',
              border: '1px solid var(--border-color)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              fontSize: '11px',
              fontWeight: 700,
              color: 'var(--text-primary)',
              fontFamily: 'AnthropicSans, sans-serif',
            }}
          >
            G
          </div>
        ) : (
          <div
            style={{
              width: 28,
              height: 28,
              borderRadius: '50%',
              background: 'var(--amber-exodo)',
              color: '#0E0C0A',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              fontSize: '12px',
              fontWeight: 700,
              fontFamily: 'AnthropicSans, sans-serif',
            }}
          >
            {(userProfile?.name || userEmail || 'U').charAt(0).toUpperCase()}
          </div>
        )}
      </button>
    </aside>
  );
};
