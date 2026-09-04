import React from 'react';
import { Shield, X } from 'lucide-react';

interface TermsModalProps {
  isOpen: boolean;
  onClose: () => void;
  locale?: string;
  theme?: 'dark' | 'light';
}

const TERMS_I18N: Record<string, Record<string, string>> = {
  es: {
    title: 'Términos y Privacidad',
    body_1: 'Exodo AI opera bajo estricto cumplimiento de privacidad de datos, seguridad criptográfica y mejores prácticas de inteligencia artificial generativa.',
    body_2: 'Todos los derechos reservados. Tus datos y conversaciones pertenecen exclusivamente a ti. Exodo no vende ni transfiere información personal a intermediarios.',
    body_3: 'El modo incógnito garantiza turnos completamente efímeros que no se persisten en almacenamiento permanente ni alimentan modelos base.',
    close: 'Cerrar',
  },
  en: {
    title: 'Terms & Privacy',
    body_1: 'Exodo AI operates under strict data privacy compliance, cryptographic security, and responsible generative AI standards.',
    body_2: 'All rights reserved. Your data and conversations belong exclusively to you. Exodo does not sell or transfer personal data to third parties.',
    body_3: 'Incognito mode guarantees completely ephemeral sessions that are neither stored in persistent databases nor used to train base models.',
    close: 'Close',
  },
};

export const TermsModal: React.FC<TermsModalProps> = ({
  isOpen,
  onClose,
  locale = 'es',
  theme = 'dark',
}) => {
  if (!isOpen) return null;

  const isLight = theme === 'light';
  const langKey = (locale || 'es').toLowerCase().startsWith('en') ? 'en' : 'es';
  const t = (key: string) => TERMS_I18N[langKey]?.[key] || TERMS_I18N.es[key] || key;

  return (
    <div
      style={{
        position: 'fixed',
        inset: 0,
        zIndex: 1250,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        padding: 16,
      }}
    >
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

      {/* Modal Container */}
      <div
        style={{
          position: 'relative',
          background: isLight ? '#FFFFFF' : '#222222',
          width: '100%',
          maxWidth: 440,
          borderRadius: 20,
          padding: '24px',
          boxShadow: '0 12px 36px rgba(0, 0, 0, 0.45)',
          border: `1px solid ${isLight ? '#E5E2DA' : 'rgba(255,255,255,0.08)'}`,
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 14 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <Shield size={22} color="var(--amber-exodo)" />
            <h2
              style={{
                fontSize: '18px',
                fontWeight: 700,
                fontFamily: 'Syne, sans-serif',
                color: 'var(--text-primary)',
                margin: 0,
              }}
            >
              {t('title')}
            </h2>
          </div>
          <button
            type="button"
            onClick={onClose}
            style={{
              background: 'none',
              border: 'none',
              cursor: 'pointer',
              color: 'var(--text-secondary)',
              padding: 4,
            }}
          >
            <X size={18} />
          </button>
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 12, margin: '14px 0 20px 0' }}>
          <p
            style={{
              fontSize: '13.5px',
              color: 'var(--text-secondary)',
              fontFamily: 'Inter, sans-serif',
              lineHeight: 1.5,
              margin: 0,
            }}
          >
            {t('body_1')}
          </p>
          <p
            style={{
              fontSize: '13.5px',
              color: 'var(--text-secondary)',
              fontFamily: 'Inter, sans-serif',
              lineHeight: 1.5,
              margin: 0,
            }}
          >
            {t('body_2')}
          </p>
          <p
            style={{
              fontSize: '13.5px',
              color: 'var(--text-secondary)',
              fontFamily: 'Inter, sans-serif',
              lineHeight: 1.5,
              margin: 0,
            }}
          >
            {t('body_3')}
          </p>
        </div>

        <div style={{ display: 'flex', justifyContent: 'flex-end' }}>
          <button
            type="button"
            onClick={onClose}
            style={{
              background: 'var(--amber-exodo)',
              color: '#000000',
              border: 'none',
              borderRadius: 10,
              cursor: 'pointer',
              fontSize: '13.5px',
              fontWeight: 700,
              padding: '8px 18px',
              fontFamily: 'Inter, sans-serif',
            }}
          >
            {t('close')}
          </button>
        </div>
      </div>
    </div>
  );
};
