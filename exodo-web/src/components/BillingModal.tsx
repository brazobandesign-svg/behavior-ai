import React, { useEffect } from 'react';
import { X, CreditCard, Zap, CheckCircle2, ShieldCheck } from 'lucide-react';
import { TokenProgressBar } from './TokenProgressBar';

interface BillingModalProps {
  isOpen: boolean;
  onClose: () => void;
  userProfile: any;
  tokensUsed: number;
  tokensLimit: number;
  onOpenUpgrade: () => void;
  onCancelProPlan: () => Promise<void> | void;
  locale?: string;
  theme?: 'dark' | 'light';
}

const BILLING_I18N: Record<string, Record<string, string>> = {
  es: {
    title: 'Facturación y Suscripción',
    subtitle: 'Administra tu cuota de tokens diarios, plan activo y facturación.',
    current_plan: 'Plan actual',
    plan_pro: 'Plan XPi PRO',
    plan_free: 'Plan Gratuito G1.1',
    gateway: 'Pasarela de pago',
    gateway_free: 'Sin cobro',
    gateway_pro: 'Stripe / Web Checkout',
    daily_quota: 'Cuota diaria de tokens',
    quota_pro: '50,000 tokens / día',
    quota_free: '6,000 tokens / día',
    features_pro: 'Acceso ilimitado a modelo XPi · IA Prioritaria · Análisis de adjuntos',
    features_free: 'Acceso estándar a modelo G1.1 · Renovación diaria automática',
    upgrade_pro: 'Actualizar a Plan XPi PRO',
    cancel_sub: 'Cancelar suscripción',
    cancel_confirm: '¿Estás seguro de cancelar tu suscripción Pro?',
    close: 'Cerrar',
  },
  en: {
    title: 'Billing & Subscription',
    subtitle: 'Manage your daily token quota, active tier, and billing details.',
    current_plan: 'Current plan',
    plan_pro: 'XPi PRO Plan',
    plan_free: 'G1.1 Free Plan',
    gateway: 'Payment gateway',
    gateway_free: 'No charge',
    gateway_pro: 'Stripe / Web Checkout',
    daily_quota: 'Daily token quota',
    quota_pro: '50,000 tokens / day',
    quota_free: '6,000 tokens / day',
    features_pro: 'Unlimited access to XPi reasoning · Priority AI · Multimodal analysis',
    features_free: 'Standard access to G1.1 · Automatic daily reset',
    upgrade_pro: 'Upgrade to XPi PRO Plan',
    cancel_sub: 'Cancel subscription',
    cancel_confirm: 'Are you sure you want to cancel your Pro plan?',
    close: 'Close',
  },
};

export const BillingModal: React.FC<BillingModalProps> = ({
  isOpen,
  onClose,
  userProfile,
  tokensUsed,
  tokensLimit,
  onOpenUpgrade,
  onCancelProPlan,
  locale = 'es',
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
  const isPro = userProfile?.plan === 'hazak';
  const isEn = (locale || 'es').toLowerCase().startsWith('en');
  const langKey = isEn ? 'en' : 'es';
  const t = (key: string) => BILLING_I18N[langKey]?.[key] || BILLING_I18N.es[key] || key;

  return (
    <div
      className="modal-fade"
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
      {/* Backdrop con desenfoque de cristal */}
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
        aria-labelledby="billing-modal-title"
        className="modal-pop"
        style={{
          position: 'relative',
          width: '100%',
          maxWidth: 560,
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
            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              <CreditCard size={18} color="var(--amber-exodo)" />
              <h2
                id="billing-modal-title"
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
            </div>
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

        {/* Contenido con Scroll */}
        <div
          style={{
            padding: '20px 24px',
            overflowY: 'auto',
            display: 'flex',
            flexDirection: 'column',
            gap: 16,
          }}
        >
          {/* Contador interactivo TokenProgressBar (desplegable con cuenta regresiva en vivo) */}
          <TokenProgressBar
            used={tokensUsed}
            limit={tokensLimit}
            isPro={isPro}
            theme={theme}
            locale={locale}
          />

          {/* Tarjeta de Información de Plan */}
          <div
            style={{
              padding: '16px 18px',
              borderRadius: 18,
              background: isLight ? '#F7F6F2' : '#242424',
              border: `1px solid ${isLight ? '#E8E5DC' : 'rgba(255, 255, 255, 0.06)'}`,
              display: 'flex',
              flexDirection: 'column',
              gap: 12,
            }}
          >
            {/* Fila 1: Plan actual */}
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <span style={{ fontSize: '13.5px', color: 'var(--text-secondary)', fontFamily: 'Inter, sans-serif' }}>
                {t('current_plan')}
              </span>
              <span
                style={{
                  fontSize: '13.5px',
                  fontWeight: 700,
                  color: isPro ? 'var(--amber-exodo)' : 'var(--text-primary)',
                  fontFamily: 'Syne, sans-serif',
                  display: 'flex',
                  alignItems: 'center',
                  gap: 6,
                }}
              >
                {isPro ? <Zap size={14} fill="var(--amber-exodo)" color="var(--amber-exodo)" /> : <ShieldCheck size={14} />}
                {isPro ? t('plan_pro') : t('plan_free')}
              </span>
            </div>

            {/* Fila 2: Cuota Diaria */}
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <span style={{ fontSize: '13.5px', color: 'var(--text-secondary)', fontFamily: 'Inter, sans-serif' }}>
                {t('daily_quota')}
              </span>
              <span style={{ fontSize: '13.5px', fontWeight: 600, color: 'var(--text-primary)', fontFamily: 'Inter, sans-serif' }}>
                {isPro ? t('quota_pro') : t('quota_free')}
              </span>
            </div>

            {/* Fila 3: Pasarela */}
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <span style={{ fontSize: '13.5px', color: 'var(--text-secondary)', fontFamily: 'Inter, sans-serif' }}>
                {t('gateway')}
              </span>
              <span style={{ fontSize: '13px', color: 'var(--text-secondary)', fontFamily: 'Inter, sans-serif' }}>
                {isPro ? t('gateway_pro') : t('gateway_free')}
              </span>
            </div>

            {/* Descripción / Features */}
            <div
              style={{
                marginTop: 4,
                paddingTop: 12,
                borderTop: `1px solid ${isLight ? '#EFECE6' : 'rgba(255, 255, 255, 0.06)'}`,
                fontSize: '12px',
                color: 'var(--text-secondary)',
                lineHeight: 1.45,
                fontFamily: 'Inter, sans-serif',
                display: 'flex',
                alignItems: 'center',
                gap: 6,
              }}
            >
              <CheckCircle2 size={14} color="var(--amber-exodo)" style={{ flexShrink: 0 }} />
              <span>{isPro ? t('features_pro') : t('features_free')}</span>
            </div>
          </div>

          {/* Botón de Acción Principal */}
          <div style={{ marginTop: 4 }}>
            {isPro ? (
              <button
                type="button"
                onClick={async () => {
                  if (window.confirm(t('cancel_confirm'))) {
                    await onCancelProPlan();
                    onClose();
                  }
                }}
                style={{
                  width: '100%',
                  background: 'transparent',
                  color: '#E05252',
                  border: '1px solid rgba(224, 82, 82, 0.4)',
                  borderRadius: 14,
                  padding: '12px 18px',
                  fontSize: '13.5px',
                  fontWeight: 600,
                  fontFamily: 'Inter, sans-serif',
                  cursor: 'pointer',
                  transition: 'background 0.15s ease',
                }}
                onMouseEnter={(e) => (e.currentTarget.style.background = 'rgba(224, 82, 82, 0.08)')}
                onMouseLeave={(e) => (e.currentTarget.style.background = 'transparent')}
              >
                {t('cancel_sub')}
              </button>
            ) : (
              <button
                type="button"
                onClick={() => {
                  onClose();
                  onOpenUpgrade();
                }}
                style={{
                  width: '100%',
                  background: 'var(--amber-exodo)',
                  color: '#000000',
                  border: 'none',
                  borderRadius: 14,
                  padding: '14px 20px',
                  fontSize: '14.5px',
                  fontWeight: 700,
                  fontFamily: 'Inter, sans-serif',
                  cursor: 'pointer',
                  boxShadow: '0 4px 16px rgba(201, 147, 58, 0.35)',
                  transition: 'transform 0.15s ease, box-shadow 0.15s ease',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  gap: 8,
                }}
              >
                <Zap size={16} fill="#000000" />
                <span>{t('upgrade_pro')}</span>
              </button>
            )}
          </div>
        </div>
      </div>
    </div>
  );
};
