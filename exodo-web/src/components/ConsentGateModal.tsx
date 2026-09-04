import React, { useState } from 'react';
import { Check } from 'lucide-react';

interface ConsentGateModalProps {
  isOpen: boolean;
  onAccept: (cloudConsent: boolean) => Promise<void> | void;
  locale?: string;
  theme?: 'dark' | 'light';
}

const CONSENT_I18N: Record<string, Record<string, string>> = {
  es: {
    age: 'Confirmo que tengo más de 13 años.',
    cloud: 'Acepto guardar mis chats en la nube. Behavior podrá leerlos únicamente para mejorar la herramienta.',
    continue: 'Continuar',
  },
  en: {
    age: "I confirm I'm over 13 years old.",
    cloud: 'I agree to store my chats in the cloud. Behavior may read them only to improve the tool.',
    continue: 'Continue',
  },
};

export const ConsentGateModal: React.FC<ConsentGateModalProps> = ({
  isOpen,
  onAccept,
  locale = 'es',
  theme = 'dark',
}) => {
  const [consentAge, setConsentAge] = useState(false);
  const [consentCloud, setConsentCloud] = useState(true);
  const [isSubmitting, setIsSubmitting] = useState(false);

  if (!isOpen) return null;

  const isLight = theme === 'light';
  const langKey = (locale || 'es').toLowerCase().startsWith('en') ? 'en' : 'es';
  const t = (key: string) => CONSENT_I18N[langKey]?.[key] || CONSENT_I18N.es[key] || key;

  const handleContinue = async () => {
    if (!consentAge || isSubmitting) return;
    setIsSubmitting(true);
    await onAccept(consentCloud);
    setIsSubmitting(false);
  };

  const renderCheckboxRow = (checked: boolean, onToggle: () => void, label: string) => (
    <div
      onClick={onToggle}
      style={{
        display: 'flex',
        gap: 12,
        alignItems: 'flex-start',
        cursor: 'pointer',
        padding: '8px 0',
      }}
    >
      <div
        style={{
          width: 20,
          height: 20,
          borderRadius: 5,
          flexShrink: 0,
          marginTop: 1,
          border: `2px solid ${checked ? 'var(--amber-exodo)' : 'var(--text-secondary)'}`,
          background: checked ? 'var(--amber-exodo)' : 'transparent',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          transition: 'all 0.15s ease',
        }}
      >
        {checked && <Check size={14} color="#000000" strokeWidth={3} />}
      </div>
      <span
        style={{
          fontSize: '13.5px',
          color: 'var(--text-primary)',
          fontFamily: 'AnthropicSans, sans-serif',
          lineHeight: 1.45,
          userSelect: 'none',
        }}
      >
        {label}
      </span>
    </div>
  );

  return (
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
      {/* Backdrop no cancelable */}
      <div
        style={{
          position: 'absolute',
          inset: 0,
          background: 'rgba(0, 0, 0, 0.75)',
          backdropFilter: 'blur(5px)',
        }}
      />

      {/* Modal Container */}
      <div
        style={{
          position: 'relative',
          background: isLight ? '#FFFFFF' : '#222222',
          width: '100%',
          maxWidth: 440,
          borderRadius: 20,
          padding: '24px 20px 20px 20px',
          boxShadow: '0 16px 40px rgba(0, 0, 0, 0.5)',
          border: `1px solid ${isLight ? '#E5E2DA' : 'rgba(255,255,255,0.08)'}`,
        }}
      >
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          {renderCheckboxRow(consentAge, () => setConsentAge(!consentAge), t('age'))}
          {renderCheckboxRow(consentCloud, () => setConsentCloud(!consentCloud), t('cloud'))}
        </div>

        <div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: 20 }}>
          <button
            type="button"
            disabled={!consentAge || isSubmitting}
            onClick={handleContinue}
            style={{
              background: consentAge ? 'var(--amber-exodo)' : (isLight ? '#E5E2DA' : '#333333'),
              color: consentAge ? '#000000' : 'var(--text-secondary)',
              border: 'none',
              borderRadius: 12,
              cursor: consentAge ? 'pointer' : 'not-allowed',
              fontSize: '14px',
              fontWeight: 700,
              padding: '10px 20px',
              fontFamily: 'Inter, sans-serif',
              transition: 'all 0.15s ease',
            }}
          >
            {isSubmitting ? '...' : t('continue')}
          </button>
        </div>
      </div>
    </div>
  );
};
