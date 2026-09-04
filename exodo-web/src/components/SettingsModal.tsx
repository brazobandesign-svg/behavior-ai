import React, { useEffect } from 'react';
import { ChevronRight, Globe, Shield, LogOut, LogIn, User, CreditCard } from 'lucide-react';

interface SettingsModalProps {
  isOpen: boolean;
  onClose: () => void;
  session: any;
  userProfile: any;
  isGuestUser: boolean;
  locale: string;
  localeDisplayName: string;
  cloudHistoryEnabled: boolean;
  onToggleCloudHistory: (enabled: boolean) => void;
  onOpenProfile: () => void;
  onOpenLanguage: () => void;
  onOpenBilling: () => void;
  onOpenTerms: () => void;
  onSignOut: () => void;
  theme?: 'dark' | 'light';
}

export const SettingsModal: React.FC<SettingsModalProps> = ({
  isOpen,
  onClose,
  session,
  userProfile,
  isGuestUser,
  locale,
  localeDisplayName,
  cloudHistoryEnabled,
  onToggleCloudHistory,
  onOpenProfile,
  onOpenLanguage,
  onOpenBilling,
  onOpenTerms,
  onSignOut,
  theme = 'dark',
}) => {
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && isOpen) {
        onClose();
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [isOpen, onClose]);

  if (!isOpen) return null;
  const isLight = theme === 'light';
  const isEn = (locale || 'es').toLowerCase().startsWith('en');
  const isPro = userProfile?.plan === 'hazak';

  return (
    <div style={{ position: 'fixed', inset: 0, zIndex: 1150 }}>
      {/* Backdrop */}
      <div
        style={{
          position: 'absolute',
          inset: 0,
          background: 'rgba(0, 0, 0, 0.65)',
          backdropFilter: 'blur(4px)',
        }}
        onClick={onClose}
      />

      {/* Sheet Container */}
      <div
        style={{
          position: 'absolute',
          left: 0,
          right: 0,
          bottom: 0,
          background: isLight ? '#FFFFFF' : '#1E1E1E',
          borderRadius: '28px 28px 0 0',
          padding: '12px 20px calc(24px + env(safe-area-inset-bottom, 0px))',
          maxWidth: 600,
          margin: '0 auto',
          maxHeight: '88vh',
          overflowY: 'auto',
          boxShadow: '0 -8px 32px rgba(0,0,0,0.4)',
          border: `1px solid ${isLight ? '#E5E5E5' : 'rgba(255,255,255,0.08)'}`,
          borderBottom: 'none',
        }}
      >
        {/* Handle */}
        <div
          style={{
            width: 36,
            height: 4,
            borderRadius: 2,
            background: 'var(--text-secondary)',
            opacity: 0.3,
            margin: '0 auto 16px auto',
          }}
        />

        <h2
          style={{
            textAlign: 'center',
            fontSize: '18px',
            fontWeight: 700,
            fontFamily: 'Syne, sans-serif',
            color: 'var(--text-primary)',
            margin: '0 0 20px 0',
          }}
        >
          {isEn ? 'Settings' : 'Configuración'}
        </h2>

        {/* Tarjeta de usuario */}
        <div
          style={{
            background: isLight ? '#F5F4EF' : '#262626',
            borderRadius: 16,
            padding: '14px 16px',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            marginBottom: 16,
            border: `1px solid ${isLight ? '#E6E4DD' : 'rgba(255,255,255,0.06)'}`,
          }}
        >
          <span
            style={{
              fontSize: '14px',
              fontWeight: 600,
              color: 'var(--text-primary)',
              overflow: 'hidden',
              textOverflow: 'ellipsis',
              whiteSpace: 'nowrap',
              letterSpacing: '-0.2px',
              fontFamily: 'AnthropicSans, sans-serif',
            }}
          >
            {isGuestUser
              ? (isEn ? 'Guest Mode' : 'Modo Invitado')
              : (session?.user?.email || (isEn ? 'No email' : 'Sin correo'))}
          </span>
          <div
            style={{
              background: isPro ? 'var(--amber-exodo)' : 'var(--text-primary)',
              color: isPro ? '#000000' : (isLight ? '#FFFFFF' : '#000000'),
              padding: '4px 10px',
              borderRadius: 20,
              fontSize: '11px',
              fontWeight: 700,
              marginLeft: 12,
              flexShrink: 0,
              fontFamily: 'AnthropicSans, sans-serif',
            }}
          >
            {isPro ? 'PRO' : 'FREE'}
          </div>
        </div>

        {/* Lista de navegación */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
          {/* 1. Perfil */}
          <div
            style={{
              background: isLight ? '#F5F4EF' : '#262626',
              borderRadius: 16,
              padding: '16px 18px',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'space-between',
              cursor: 'pointer',
              transition: 'background 0.15s ease',
            }}
            onClick={() => {
              onClose();
              onOpenProfile();
            }}
          >
            <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
              <User size={20} color="var(--text-primary)" />
              <span style={{ fontSize: '15px', fontWeight: 600, color: 'var(--text-primary)', fontFamily: 'Inter, sans-serif' }}>
                {isEn ? 'Profile' : 'Perfil'}
              </span>
            </div>
            <ChevronRight size={18} color="var(--text-secondary)" />
          </div>

          {/* 2. Idioma */}
          <div
            style={{
              background: isLight ? '#F5F4EF' : '#262626',
              borderRadius: 16,
              padding: '14px 18px',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'space-between',
              cursor: 'pointer',
              transition: 'background 0.15s ease',
            }}
            onClick={() => {
              onClose();
              onOpenLanguage();
            }}
          >
            <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
              <Globe size={20} color="var(--text-primary)" />
              <div style={{ display: 'flex', flexDirection: 'column' }}>
                <span style={{ fontSize: '15px', fontWeight: 600, color: 'var(--text-primary)', fontFamily: 'Inter, sans-serif' }}>
                  {isEn ? 'Language' : 'Idioma'}
                </span>
                <span style={{ fontSize: '12px', color: 'var(--text-secondary)', fontFamily: 'Inter, sans-serif' }}>
                  {localeDisplayName}
                </span>
              </div>
            </div>
            <ChevronRight size={18} color="var(--text-secondary)" />
          </div>

          {/* 3. Facturación y Suscripción */}
          <div
            style={{
              background: isLight ? '#F5F4EF' : '#262626',
              borderRadius: 16,
              padding: '16px 18px',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'space-between',
              cursor: 'pointer',
              transition: 'background 0.15s ease',
            }}
            onClick={() => {
              onClose();
              onOpenBilling();
            }}
          >
            <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
              <CreditCard size={20} color="var(--text-primary)" />
              <span style={{ fontSize: '15px', fontWeight: 600, color: 'var(--text-primary)', fontFamily: 'Inter, sans-serif' }}>
                {isEn ? 'Billing & Subscription' : 'Facturación y Suscripción'}
              </span>
            </div>
            <ChevronRight size={18} color="var(--text-secondary)" />
          </div>

          {/* 4. Términos y Privacidad */}
          <div
            style={{
              background: isLight ? '#F5F4EF' : '#262626',
              borderRadius: 16,
              padding: '16px 18px',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'space-between',
              cursor: 'pointer',
              transition: 'background 0.15s ease',
            }}
            onClick={() => {
              onClose();
              onOpenTerms();
            }}
          >
            <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
              <Shield size={20} color="var(--text-primary)" />
              <span style={{ fontSize: '15px', fontWeight: 600, color: 'var(--text-primary)', fontFamily: 'Inter, sans-serif' }}>
                {isEn ? 'Terms & Privacy' : 'Términos y Privacidad'}
              </span>
            </div>
            <ChevronRight size={18} color="var(--text-secondary)" />
          </div>
        </div>

        {/* Switch Historial en la nube */}
        <div
          style={{
            marginTop: 14,
            marginBottom: 14,
            background: isLight ? '#F5F4EF' : '#262626',
            borderRadius: 16,
            padding: '14px 16px',
            display: 'flex',
            alignItems: 'center',
            gap: 16,
            border: `1px solid ${isLight ? '#E6E4DD' : 'rgba(255,255,255,0.06)'}`,
          }}
        >
          <div style={{ flex: 1 }}>
            <div
              style={{
                fontSize: '13.5px',
                fontWeight: 600,
                color: cloudHistoryEnabled ? 'var(--text-primary)' : 'var(--amber-exodo)',
                fontFamily: 'AnthropicSans, sans-serif',
              }}
            >
              {isEn ? 'Cloud History' : 'Historial en la nube'}
            </div>
            <div
              style={{
                fontSize: '11px',
                color: 'var(--text-secondary)',
                marginTop: 2,
                lineHeight: 1.3,
                fontFamily: 'AnthropicSans, sans-serif',
              }}
            >
              {cloudHistoryEnabled
                ? (isEn ? 'Your chats are saved and provide context to Exodo.' : 'Tus chats se guardan y dan contexto a Exodo.')
                : (isEn ? 'Off: Ephemeral turns, no history saved or prior context.' : 'Apagado: turnos efímeros, sin guardar ni contexto previo.')}
            </div>
          </div>
          <button
            type="button"
            role="switch"
            aria-checked={cloudHistoryEnabled}
            onClick={() => onToggleCloudHistory(!cloudHistoryEnabled)}
            style={{
              width: 52,
              height: 32,
              borderRadius: 16,
              boxSizing: 'border-box',
              border: cloudHistoryEnabled
                ? '2px solid var(--amber-exodo)'
                : `2px solid ${isLight ? '#C5C2BA' : '#525252'}`,
              cursor: 'pointer',
              background: cloudHistoryEnabled
                ? 'var(--amber-exodo)'
                : (isLight ? '#E5E2DA' : '#363636'),
              position: 'relative',
              flexShrink: 0,
              padding: 0,
              outline: 'none',
              transition: 'background-color 0.25s cubic-bezier(0.2, 0, 0, 1), border-color 0.25s cubic-bezier(0.2, 0, 0, 1)',
            }}
          >
            <span
              style={{
                position: 'absolute',
                top: cloudHistoryEnabled ? 2 : 6,
                left: cloudHistoryEnabled ? 'calc(100% - 26px)' : 6,
                width: cloudHistoryEnabled ? 24 : 16,
                height: cloudHistoryEnabled ? 24 : 16,
                borderRadius: '50%',
                background: cloudHistoryEnabled
                  ? '#000000'
                  : (isLight ? '#75736E' : '#A8A6A0'),
                transition: 'all 0.28s cubic-bezier(0.34, 1.35, 0.64, 1)',
                boxShadow: cloudHistoryEnabled
                  ? '0 2px 6px rgba(0, 0, 0, 0.35)'
                  : 'none',
              }}
            />
          </button>
        </div>

        <div style={{ height: 1, background: isLight ? '#E6E4DD' : 'rgba(255,255,255,0.08)', margin: '8px 0' }} />

        {/* Log out / Sign in plano */}
        <div
          style={{
            padding: '14px 8px',
            display: 'flex',
            alignItems: 'center',
            gap: 14,
            cursor: 'pointer',
          }}
          onClick={() => {
            onClose();
            onSignOut();
          }}
        >
          {isGuestUser ? (
            <>
              <LogIn size={20} color="var(--amber-exodo)" />
              <span
                style={{
                  fontSize: '14.5px',
                  fontWeight: 600,
                  color: 'var(--amber-exodo)',
                  letterSpacing: '-0.2px',
                  fontFamily: 'AnthropicSans, sans-serif',
                }}
              >
                {isEn ? 'Sign in' : 'Iniciar sesión'}
              </span>
            </>
          ) : (
            <>
              <LogOut size={20} color="#E05252" />
              <span
                style={{
                  fontSize: '14.5px',
                  fontWeight: 600,
                  color: '#E05252',
                  letterSpacing: '-0.2px',
                  fontFamily: 'AnthropicSans, sans-serif',
                }}
              >
                {isEn ? 'Log out' : 'Cerrar sesión'}
              </span>
            </>
          )}
        </div>

        <div style={{ height: 16 }} />
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, opacity: 0.6 }}>
          <img src="/Logo_behavior.png" alt="Exodo" style={{ height: 15, objectFit: 'contain' }} />
          <span style={{ fontSize: '11.5px', color: 'var(--text-secondary)', fontFamily: 'AnthropicSans, sans-serif' }}>
            Exodo Web
          </span>
        </div>
      </div>
    </div>
  );
};
