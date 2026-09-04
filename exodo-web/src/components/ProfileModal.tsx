import React, { useState, useEffect } from 'react';
import {
  X,
  User,
  Sparkles,
  Download,
  Trash2,
  AlertTriangle,
  CheckCircle2,
  ShieldCheck,
  Mail,
  Zap,
} from 'lucide-react';

interface ProfileModalProps {
  isOpen: boolean;
  onClose: () => void;
  userProfile: any;
  session: any;
  onSaveProfile: (fullName: string, nickname: string) => Promise<boolean>;
  onExportData: () => Promise<void> | void;
  onClearHistory: () => Promise<void> | void;
  onDeleteAccount: () => Promise<void> | void;
  locale?: string;
  theme?: 'dark' | 'light';
}

const PROFILE_I18N: Record<string, Record<string, string>> = {
  es: {
    title: 'Perfil de Usuario',
    subtitle: 'Administra tus datos personales, preferencias y privacidad de cuenta.',
    badge_pro: 'PLAN XPi PRO',
    badge_free: 'PLAN GRATUITO',
    personal_section: 'Información Personal',
    fullname: 'Nombre completo',
    fullname_hint: 'Ingresa tu nombre y apellido',
    nickname: '¿Cómo deberíamos llamarte?',
    nickname_hint: 'Tu apodo o nombre preferido',
    nickname_help: 'Exodo usará este nombre para saludarte y en las respuestas del chat.',
    update_btn: 'Guardar cambios',
    updating_btn: 'Guardando cambios...',
    data_section: 'Gestión de Datos y Privacidad',
    export_title: 'Exportar mis datos',
    export_desc: 'Descarga un archivo HTML interactivo con todo tu historial de conversaciones y expedientes.',
    export_btn: 'Exportar archivo HTML',
    clear_title_item: 'Borrar historial de chat',
    clear_desc: 'Elimina permanentemente todas tus conversaciones en la nube preservando tu cuenta.',
    clear_history_btn: 'Borrar historial',
    danger_section: 'Zona de Peligro',
    delete_title_item: 'Eliminar cuenta definitivamente',
    delete_desc: 'Esta acción borrará de forma irreversible tu cuenta, conversaciones, expedientes y todos tus datos.',
    delete_btn: 'Eliminar mi cuenta',
    save_success: 'Perfil actualizado con éxito',
    save_error: 'No se pudo guardar el perfil. Intenta de nuevo.',
    clear_dialog_title: '¿Borrar todo el historial?',
    clear_dialog_body: 'Se eliminarán todas tus conversaciones de la nube. Esta acción no se puede deshacer.',
    clear_confirm: 'Sí, borrar historial',
    delete_dialog_title: '¿Eliminar cuenta definitivamente?',
    delete_dialog_body: 'Esta acción borrará tu cuenta, conversaciones, expedientes y todos tus datos en Exodo para siempre.',
    delete_confirm: 'Eliminar cuenta permanentemente',
    cancel: 'Cancelar',
    close: 'Cerrar',
  },
  en: {
    title: 'User Profile',
    subtitle: 'Manage your personal details, preferences, and account privacy.',
    badge_pro: 'XPi PRO PLAN',
    badge_free: 'FREE PLAN',
    personal_section: 'Personal Details',
    fullname: 'Full name',
    fullname_hint: 'Enter your full name',
    nickname: 'What should we call you?',
    nickname_hint: 'Your nickname or preferred name',
    nickname_help: 'Exodo will use this name to greet you and in conversations.',
    update_btn: 'Save changes',
    updating_btn: 'Saving changes...',
    data_section: 'Data Management & Privacy',
    export_title: 'Export my data',
    export_desc: 'Download a complete interactive HTML file with all your chat history and records.',
    export_btn: 'Export HTML file',
    clear_title_item: 'Clear chat history',
    clear_desc: 'Permanently remove all cloud conversations while keeping your account.',
    clear_history_btn: 'Clear history',
    danger_section: 'Danger Zone',
    delete_title_item: 'Permanently delete account',
    delete_desc: 'This action will irreversibly wipe your account, conversations, records, and all data.',
    delete_btn: 'Delete my account',
    save_success: 'Profile updated successfully',
    save_error: 'Could not save profile. Try again.',
    clear_dialog_title: 'Clear all chat history?',
    clear_dialog_body: 'All your conversations will be deleted from the cloud. This action cannot be undone.',
    clear_confirm: 'Yes, clear history',
    delete_dialog_title: 'Permanently delete account?',
    delete_dialog_body: 'This will delete your account, conversations, records, and all personal data forever.',
    delete_confirm: 'Delete account permanently',
    cancel: 'Cancel',
    close: 'Close',
  },
};

export const ProfileModal: React.FC<ProfileModalProps> = ({
  isOpen,
  onClose,
  userProfile,
  session,
  onSaveProfile,
  onExportData,
  onClearHistory,
  onDeleteAccount,
  locale = 'es',
  theme = 'dark',
}) => {
  const [fullName, setFullName] = useState('');
  const [nickname, setNickname] = useState('');
  const [isSaving, setIsSaving] = useState(false);
  const [showClearConfirm, setShowClearConfirm] = useState(false);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const [toastMessage, setToastMessage] = useState<string | null>(null);

  useEffect(() => {
    if (isOpen) {
      const currentName = userProfile?.full_name || session?.user?.email?.split('@')[0] || '';
      const currentNick = userProfile?.onboarding?.nickname || '';
      setFullName(currentName);
      setNickname(currentNick);
    }
  }, [isOpen, userProfile, session]);

  // Manejo de tecla Escape para cerrar en escritorio
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && isOpen) {
        if (showClearConfirm) {
          setShowClearConfirm(false);
        } else if (showDeleteConfirm) {
          setShowDeleteConfirm(false);
        } else {
          onClose();
        }
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [isOpen, showClearConfirm, showDeleteConfirm, onClose]);

  if (!isOpen) return null;

  const isLight = theme === 'light';
  const isPro = userProfile?.plan === 'hazak';
  const langKey = (locale || 'es').toLowerCase().startsWith('en') ? 'en' : 'es';
  const t = (key: string) => PROFILE_I18N[langKey]?.[key] || PROFILE_I18N.es[key] || key;

  const handleSave = async (e?: React.FormEvent) => {
    if (e) e.preventDefault();
    setIsSaving(true);
    const ok = await onSaveProfile(fullName, nickname);
    setIsSaving(false);
    if (ok) {
      setToastMessage(t('save_success'));
      setTimeout(() => setToastMessage(null), 2500);
    } else {
      setToastMessage(t('save_error'));
      setTimeout(() => setToastMessage(null), 3000);
    }
  };

  const initialLetter = (fullName || session?.user?.email || 'E').trim().charAt(0).toUpperCase() || 'E';
  const avatarUrl = session?.user?.user_metadata?.avatar_url || session?.user?.user_metadata?.picture;
  const userEmail = session?.user?.email || '';

  return (
    <div
      style={{
        position: 'fixed',
        inset: 0,
        zIndex: 1200,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        padding: '24px 16px',
        boxSizing: 'border-box',
      }}
    >
      {/* Backdrop con desenfoque moderno web */}
      <div
        style={{
          position: 'absolute',
          inset: 0,
          background: 'rgba(0, 0, 0, 0.70)',
          backdropFilter: 'blur(8px)',
          WebkitBackdropFilter: 'blur(8px)',
        }}
        onClick={onClose}
      />

      {/* Ventana de Diálogo Web Centrada */}
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="profile-modal-title"
        style={{
          position: 'relative',
          width: '100%',
          maxWidth: 620,
          maxHeight: '90vh',
          background: isLight ? '#FFFFFF' : '#1C1C1C',
          borderRadius: 24,
          boxShadow: '0 24px 64px rgba(0, 0, 0, 0.45)',
          border: `1px solid ${isLight ? '#E5E2DA' : 'rgba(255, 255, 255, 0.09)'}`,
          display: 'flex',
          flexDirection: 'column',
          overflow: 'hidden',
          zIndex: 1210,
        }}
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header Superior Web */}
        <div
          style={{
            padding: '20px 24px 16px 24px',
            display: 'flex',
            alignItems: 'flex-start',
            justifyContent: 'space-between',
            borderBottom: `1px solid ${isLight ? '#EFECE6' : 'rgba(255, 255, 255, 0.07)'}`,
            gap: 16,
          }}
        >
          <div>
            <h2
              id="profile-modal-title"
              style={{
                margin: 0,
                fontSize: '20px',
                fontWeight: 700,
                fontFamily: 'Syne, sans-serif',
                color: 'var(--text-primary)',
                letterSpacing: '-0.2px',
              }}
            >
              {t('title')}
            </h2>
            <p
              style={{
                margin: '4px 0 0 0',
                fontSize: '13px',
                color: 'var(--text-secondary)',
                fontFamily: 'Inter, sans-serif',
                lineHeight: 1.4,
              }}
            >
              {t('subtitle')}
            </p>
          </div>

          <button
            type="button"
            onClick={onClose}
            style={{
              background: isLight ? '#F0EDE6' : 'rgba(255, 255, 255, 0.08)',
              border: 'none',
              borderRadius: 12,
              width: 34,
              height: 34,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              cursor: 'pointer',
              color: 'var(--text-secondary)',
              flexShrink: 0,
              transition: 'background 0.15s ease, color 0.15s ease',
            }}
            title={t('close')}
          >
            <X size={18} />
          </button>
        </div>

        {/* Cuerpo del Perfil con Scroll */}
        <div
          style={{
            padding: '22px 24px',
            overflowY: 'auto',
            display: 'flex',
            flexDirection: 'column',
            gap: 24,
          }}
        >
          {/* Tarjeta de Identidad de Cuenta (Banner Web) */}
          <div
            style={{
              padding: '16px 18px',
              borderRadius: 18,
              background: isLight ? '#F7F6F2' : '#242424',
              border: `1px solid ${isLight ? '#E8E5DC' : 'rgba(255, 255, 255, 0.06)'}`,
              display: 'flex',
              alignItems: 'center',
              gap: 16,
            }}
          >
            {/* Avatar circular con badge */}
            <div
              style={{
                width: 68,
                height: 68,
                borderRadius: '50%',
                background: 'rgba(201, 147, 58, 0.18)',
                border: '2px solid var(--amber-exodo)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                overflow: 'hidden',
                flexShrink: 0,
                boxShadow: '0 4px 14px rgba(201, 147, 58, 0.25)',
              }}
            >
              {avatarUrl ? (
                <img
                  src={avatarUrl}
                  alt="Avatar"
                  style={{ width: '100%', height: '100%', objectFit: 'cover' }}
                />
              ) : (
                <span
                  style={{
                    fontFamily: 'Syne, sans-serif',
                    fontSize: '1.9rem',
                    fontWeight: 800,
                    color: 'var(--amber-exodo)',
                  }}
                >
                  {initialLetter}
                </span>
              )}
            </div>

            {/* Metadatos y Plan */}
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
                <span
                  style={{
                    fontSize: '16px',
                    fontWeight: 700,
                    fontFamily: 'Syne, sans-serif',
                    color: 'var(--text-primary)',
                    whiteSpace: 'nowrap',
                    overflow: 'hidden',
                    textOverflow: 'ellipsis',
                  }}
                >
                  {fullName || t('nickname_hint')}
                </span>
                <span
                  style={{
                    fontSize: '10.5px',
                    fontWeight: 700,
                    fontFamily: 'Inter, sans-serif',
                    padding: '3px 8px',
                    borderRadius: 12,
                    background: isPro ? 'var(--amber-exodo)' : (isLight ? '#E2DFD6' : '#333333'),
                    color: isPro ? '#000000' : 'var(--text-secondary)',
                    display: 'inline-flex',
                    alignItems: 'center',
                    gap: 4,
                  }}
                >
                  {isPro ? <Zap size={11} fill="#000000" /> : <ShieldCheck size={11} />}
                  {isPro ? t('badge_pro') : t('badge_free')}
                </span>
              </div>

              {userEmail && (
                <div
                  style={{
                    marginTop: 4,
                    display: 'flex',
                    alignItems: 'center',
                    gap: 6,
                    fontSize: '13px',
                    color: 'var(--text-secondary)',
                    fontFamily: 'Inter, sans-serif',
                  }}
                >
                  <Mail size={13} />
                  <span style={{ overflow: 'hidden', textOverflow: 'ellipsis' }}>{userEmail}</span>
                </div>
              )}
            </div>
          </div>

          {/* Sección 1: Formulario de Información Personal */}
          <div>
            <div
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: 8,
                marginBottom: 14,
                fontSize: '13.5px',
                fontWeight: 700,
                fontFamily: 'Syne, sans-serif',
                color: 'var(--text-primary)',
                letterSpacing: '-0.1px',
              }}
            >
              <User size={16} color="var(--amber-exodo)" />
              <span>{t('personal_section')}</span>
            </div>

            <form onSubmit={handleSave} style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
              {/* Campo Nombre Completo */}
              <div>
                <label
                  htmlFor="profile-fullname"
                  style={{
                    display: 'block',
                    fontSize: '12.5px',
                    fontWeight: 600,
                    color: 'var(--text-secondary)',
                    marginBottom: 6,
                    fontFamily: 'Inter, sans-serif',
                  }}
                >
                  {t('fullname')}
                </label>
                <input
                  id="profile-fullname"
                  type="text"
                  value={fullName}
                  onChange={(e) => setFullName(e.target.value)}
                  placeholder={t('fullname_hint')}
                  style={{
                    width: '100%',
                    background: isLight ? '#FFFFFF' : '#262626',
                    border: `1px solid ${isLight ? '#DCD8CE' : 'rgba(255, 255, 255, 0.12)'}`,
                    borderRadius: 12,
                    padding: '12px 14px',
                    color: 'var(--text-primary)',
                    fontSize: '14px',
                    fontFamily: 'Inter, sans-serif',
                    boxSizing: 'border-box',
                    outline: 'none',
                    transition: 'border-color 0.2s ease, box-shadow 0.2s ease',
                  }}
                  onFocus={(e) => {
                    e.currentTarget.style.borderColor = 'var(--amber-exodo)';
                    e.currentTarget.style.boxShadow = '0 0 0 3px rgba(201, 147, 58, 0.2)';
                  }}
                  onBlur={(e) => {
                    e.currentTarget.style.borderColor = isLight ? '#DCD8CE' : 'rgba(255, 255, 255, 0.12)';
                    e.currentTarget.style.boxShadow = 'none';
                  }}
                />
              </div>

              {/* Campo Nickname */}
              <div>
                <label
                  htmlFor="profile-nickname"
                  style={{
                    display: 'block',
                    fontSize: '12.5px',
                    fontWeight: 600,
                    color: 'var(--text-secondary)',
                    marginBottom: 6,
                    fontFamily: 'Inter, sans-serif',
                  }}
                >
                  {t('nickname')}
                </label>
                <input
                  id="profile-nickname"
                  type="text"
                  value={nickname}
                  onChange={(e) => setNickname(e.target.value)}
                  placeholder={t('nickname_hint')}
                  style={{
                    width: '100%',
                    background: isLight ? '#FFFFFF' : '#262626',
                    border: `1px solid ${isLight ? '#DCD8CE' : 'rgba(255, 255, 255, 0.12)'}`,
                    borderRadius: 12,
                    padding: '12px 14px',
                    color: 'var(--text-primary)',
                    fontSize: '14px',
                    fontFamily: 'Inter, sans-serif',
                    boxSizing: 'border-box',
                    outline: 'none',
                    transition: 'border-color 0.2s ease, box-shadow 0.2s ease',
                  }}
                  onFocus={(e) => {
                    e.currentTarget.style.borderColor = 'var(--amber-exodo)';
                    e.currentTarget.style.boxShadow = '0 0 0 3px rgba(201, 147, 58, 0.2)';
                  }}
                  onBlur={(e) => {
                    e.currentTarget.style.borderColor = isLight ? '#DCD8CE' : 'rgba(255, 255, 255, 0.12)';
                    e.currentTarget.style.boxShadow = 'none';
                  }}
                />
                <span
                  style={{
                    display: 'inline-flex',
                    alignItems: 'center',
                    gap: 4,
                    fontSize: '11.5px',
                    color: 'var(--text-secondary)',
                    marginTop: 5,
                    fontFamily: 'Inter, sans-serif',
                  }}
                >
                  <Sparkles size={12} color="var(--amber-exodo)" />
                  {t('nickname_help')}
                </span>
              </div>

              {/* Botón de Guardar */}
              <div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: 4 }}>
                <button
                  type="submit"
                  disabled={isSaving}
                  style={{
                    background: 'var(--amber-exodo)',
                    color: '#000000',
                    border: 'none',
                    borderRadius: 12,
                    padding: '11px 22px',
                    fontSize: '13.5px',
                    fontWeight: 700,
                    fontFamily: 'Inter, sans-serif',
                    cursor: isSaving ? 'wait' : 'pointer',
                    boxShadow: '0 3px 12px rgba(201, 147, 58, 0.3)',
                    transition: 'transform 0.15s ease, opacity 0.15s ease',
                    opacity: isSaving ? 0.7 : 1,
                  }}
                >
                  {isSaving ? t('updating_btn') : t('update_btn')}
                </button>
              </div>
            </form>
          </div>

          {/* Sección 2: Datos y Privacidad */}
          <div>
            <div
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: 8,
                marginBottom: 14,
                fontSize: '13.5px',
                fontWeight: 700,
                fontFamily: 'Syne, sans-serif',
                color: 'var(--text-primary)',
                letterSpacing: '-0.1px',
              }}
            >
              <Download size={16} color="var(--amber-exodo)" />
              <span>{t('data_section')}</span>
            </div>

            <div
              style={{
                background: isLight ? '#F7F6F2' : '#242424',
                borderRadius: 16,
                border: `1px solid ${isLight ? '#E8E5DC' : 'rgba(255, 255, 255, 0.06)'}`,
                overflow: 'hidden',
              }}
            >
              {/* Opción Exportar datos */}
              <div
                style={{
                  padding: '16px 18px',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'space-between',
                  gap: 16,
                  borderBottom: `1px solid ${isLight ? '#EFECE6' : 'rgba(255, 255, 255, 0.06)'}`,
                }}
              >
                <div>
                  <div
                    style={{
                      fontSize: '14px',
                      fontWeight: 600,
                      fontFamily: 'Inter, sans-serif',
                      color: 'var(--text-primary)',
                    }}
                  >
                    {t('export_title')}
                  </div>
                  <div
                    style={{
                      fontSize: '12px',
                      color: 'var(--text-secondary)',
                      marginTop: 2,
                      fontFamily: 'Inter, sans-serif',
                    }}
                  >
                    {t('export_desc')}
                  </div>
                </div>

                <button
                  type="button"
                  onClick={onExportData}
                  style={{
                    background: 'transparent',
                    border: '1.5px solid var(--amber-exodo)',
                    color: 'var(--amber-exodo)',
                    padding: '8px 14px',
                    borderRadius: 10,
                    fontSize: '12.5px',
                    fontWeight: 600,
                    fontFamily: 'Inter, sans-serif',
                    cursor: 'pointer',
                    whiteSpace: 'nowrap',
                    display: 'flex',
                    alignItems: 'center',
                    gap: 6,
                    flexShrink: 0,
                  }}
                >
                  <Download size={14} />
                  {t('export_btn')}
                </button>
              </div>

              {/* Opción Borrar historial */}
              <div
                style={{
                  padding: '16px 18px',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'space-between',
                  gap: 16,
                }}
              >
                <div>
                  <div
                    style={{
                      fontSize: '14px',
                      fontWeight: 600,
                      fontFamily: 'Inter, sans-serif',
                      color: 'var(--text-primary)',
                    }}
                  >
                    {t('clear_title_item')}
                  </div>
                  <div
                    style={{
                      fontSize: '12px',
                      color: 'var(--text-secondary)',
                      marginTop: 2,
                      fontFamily: 'Inter, sans-serif',
                    }}
                  >
                    {t('clear_desc')}
                  </div>
                </div>

                <button
                  type="button"
                  onClick={() => setShowClearConfirm(true)}
                  style={{
                    background: isLight ? '#EDEBE4' : '#2F2F2F',
                    border: 'none',
                    color: 'var(--text-secondary)',
                    padding: '8px 14px',
                    borderRadius: 10,
                    fontSize: '12.5px',
                    fontWeight: 600,
                    fontFamily: 'Inter, sans-serif',
                    cursor: 'pointer',
                    whiteSpace: 'nowrap',
                    display: 'flex',
                    alignItems: 'center',
                    gap: 6,
                    flexShrink: 0,
                  }}
                >
                  <Trash2 size={14} />
                  {t('clear_history_btn')}
                </button>
              </div>
            </div>
          </div>

          {/* Sección 3: Zona de Peligro */}
          <div>
            <div
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: 8,
                marginBottom: 14,
                fontSize: '13.5px',
                fontWeight: 700,
                fontFamily: 'Syne, sans-serif',
                color: '#E05252',
                letterSpacing: '-0.1px',
              }}
            >
              <AlertTriangle size={16} color="#E05252" />
              <span>{t('danger_section')}</span>
            </div>

            <div
              style={{
                padding: '16px 18px',
                borderRadius: 16,
                background: isLight ? '#FFF8F8' : 'rgba(224, 82, 82, 0.05)',
                border: `1px solid ${isLight ? '#F5D8D8' : 'rgba(224, 82, 82, 0.22)'}`,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'space-between',
                gap: 16,
              }}
            >
              <div>
                <div
                  style={{
                    fontSize: '14px',
                    fontWeight: 600,
                    fontFamily: 'Inter, sans-serif',
                    color: '#E05252',
                  }}
                >
                  {t('delete_title_item')}
                </div>
                <div
                  style={{
                    fontSize: '12px',
                    color: 'var(--text-secondary)',
                    marginTop: 2,
                    fontFamily: 'Inter, sans-serif',
                    lineHeight: 1.35,
                  }}
                >
                  {t('delete_desc')}
                </div>
              </div>

              <button
                type="button"
                onClick={() => setShowDeleteConfirm(true)}
                style={{
                  background: '#E05252',
                  color: '#FFFFFF',
                  border: 'none',
                  borderRadius: 10,
                  padding: '9px 14px',
                  fontSize: '12.5px',
                  fontWeight: 700,
                  fontFamily: 'Inter, sans-serif',
                  cursor: 'pointer',
                  whiteSpace: 'nowrap',
                  flexShrink: 0,
                  boxShadow: '0 2px 8px rgba(224, 82, 82, 0.25)',
                }}
              >
                {t('delete_btn')}
              </button>
            </div>
          </div>
        </div>
      </div>

      {/* Toast Feedback */}
      {toastMessage && (
        <div
          style={{
            position: 'fixed',
            bottom: 24,
            left: '50%',
            transform: 'translateX(-50%)',
            background: '#1D1D1D',
            color: '#FFFFFF',
            padding: '10px 18px',
            borderRadius: 12,
            fontSize: '13px',
            fontWeight: 600,
            fontFamily: 'Inter, sans-serif',
            display: 'flex',
            alignItems: 'center',
            gap: 8,
            boxShadow: '0 8px 24px rgba(0,0,0,0.5)',
            border: '1px solid var(--amber-exodo)',
            zIndex: 1400,
          }}
        >
          <CheckCircle2 size={16} color="var(--amber-exodo)" />
          <span>{toastMessage}</span>
        </div>
      )}

      {/* Modal de Confirmación: Borrar Historial */}
      {showClearConfirm && (
        <div
          style={{
            position: 'fixed',
            inset: 0,
            zIndex: 1300,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            padding: 16,
          }}
        >
          <div
            style={{
              position: 'absolute',
              inset: 0,
              background: 'rgba(0, 0, 0, 0.75)',
              backdropFilter: 'blur(4px)',
            }}
            onClick={() => setShowClearConfirm(false)}
          />
          <div
            style={{
              position: 'relative',
              background: isLight ? '#FFFFFF' : '#222222',
              borderRadius: 20,
              padding: '24px',
              maxWidth: 420,
              width: '100%',
              boxShadow: '0 16px 40px rgba(0,0,0,0.5)',
              border: `1px solid ${isLight ? '#E5E2DA' : 'rgba(255,255,255,0.1)'}`,
            }}
          >
            <h3
              style={{
                margin: '0 0 8px 0',
                fontSize: '17px',
                fontWeight: 700,
                fontFamily: 'Syne, sans-serif',
                color: 'var(--text-primary)',
              }}
            >
              {t('clear_dialog_title')}
            </h3>
            <p
              style={{
                margin: '0 0 20px 0',
                fontSize: '13.5px',
                color: 'var(--text-secondary)',
                lineHeight: 1.45,
                fontFamily: 'Inter, sans-serif',
              }}
            >
              {t('clear_dialog_body')}
            </p>
            <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 10 }}>
              <button
                type="button"
                onClick={() => setShowClearConfirm(false)}
                style={{
                  padding: '9px 16px',
                  background: 'transparent',
                  border: `1px solid ${isLight ? '#DCD8CE' : 'rgba(255,255,255,0.15)'}`,
                  color: 'var(--text-primary)',
                  borderRadius: 10,
                  cursor: 'pointer',
                  fontWeight: 600,
                  fontSize: '13px',
                  fontFamily: 'Inter, sans-serif',
                }}
              >
                {t('cancel')}
              </button>
              <button
                type="button"
                onClick={async () => {
                  setShowClearConfirm(false);
                  await onClearHistory();
                  onClose();
                }}
                style={{
                  padding: '9px 18px',
                  background: 'var(--amber-exodo)',
                  color: '#000000',
                  border: 'none',
                  borderRadius: 10,
                  cursor: 'pointer',
                  fontWeight: 700,
                  fontSize: '13px',
                  fontFamily: 'Inter, sans-serif',
                }}
              >
                {t('clear_confirm')}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Modal de Confirmación: Eliminar Cuenta */}
      {showDeleteConfirm && (
        <div
          style={{
            position: 'fixed',
            inset: 0,
            zIndex: 1300,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            padding: 16,
          }}
        >
          <div
            style={{
              position: 'absolute',
              inset: 0,
              background: 'rgba(0, 0, 0, 0.75)',
              backdropFilter: 'blur(4px)',
            }}
            onClick={() => setShowDeleteConfirm(false)}
          />
          <div
            style={{
              position: 'relative',
              background: isLight ? '#FFFFFF' : '#222222',
              borderRadius: 20,
              padding: '24px',
              maxWidth: 440,
              width: '100%',
              boxShadow: '0 16px 40px rgba(0,0,0,0.5)',
              border: '1px solid rgba(224, 82, 82, 0.4)',
            }}
          >
            <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 12 }}>
              <AlertTriangle size={22} color="#E05252" />
              <h3
                style={{
                  margin: 0,
                  fontSize: '17px',
                  fontWeight: 700,
                  fontFamily: 'Syne, sans-serif',
                  color: '#E05252',
                }}
              >
                {t('delete_dialog_title')}
              </h3>
            </div>
            <p
              style={{
                margin: '0 0 20px 0',
                fontSize: '13.5px',
                color: 'var(--text-secondary)',
                lineHeight: 1.45,
                fontFamily: 'Inter, sans-serif',
              }}
            >
              {t('delete_dialog_body')}
            </p>
            <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 10 }}>
              <button
                type="button"
                onClick={() => setShowDeleteConfirm(false)}
                style={{
                  padding: '9px 16px',
                  background: 'transparent',
                  border: `1px solid ${isLight ? '#DCD8CE' : 'rgba(255,255,255,0.15)'}`,
                  color: 'var(--text-primary)',
                  borderRadius: 10,
                  cursor: 'pointer',
                  fontWeight: 600,
                  fontSize: '13px',
                  fontFamily: 'Inter, sans-serif',
                }}
              >
                {t('cancel')}
              </button>
              <button
                type="button"
                onClick={async () => {
                  setShowDeleteConfirm(false);
                  await onDeleteAccount();
                }}
                style={{
                  padding: '9px 18px',
                  background: '#E05252',
                  color: '#FFFFFF',
                  border: 'none',
                  borderRadius: 10,
                  cursor: 'pointer',
                  fontWeight: 700,
                  fontSize: '13px',
                  fontFamily: 'Inter, sans-serif',
                }}
              >
                {t('delete_confirm')}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
