import React, { useState } from 'react';
import { X, Check } from 'lucide-react';

export interface UpgradeModalProps {
  isOpen: boolean;
  onClose: () => void;
  onStartCheckout: (isAnnual: boolean) => Promise<void> | void;
  isCheckingOut: boolean;
  isGuestUser?: boolean;
  locale?: string;
  theme?: 'dark' | 'light';
}

const UPGRADE_I18N: Record<string, Record<string, string>> = {
  es: {
    title: 'Más capacidad en Exodo',
    header_sub: 'Elige el plan ideal para ti',
    plan_title: 'XPi PRO',
    subtitle: 'Para productividad diaria',
    up_to_80_off: 'Hasta 80% off',
    billed_monthly: 'Facturado mensualmente',
    out_of_service: 'Fuera de servicio',
    billed_annually: 'Facturado anualmente',
    get_pro: 'Obtener plan Pro',
    processing: 'Conectando con Stripe...',
    no_commitments: 'Sin compromisos - Cancela cuando quieras',
    pro_features: 'Todo lo de Gratis, más:',
    feat1: 'Todo lo incluido en Gratis',
    feat2: 'Límites de uso más altos',
    feat3: 'Chatea en web, iOS y Android',
    feat4: 'Generar código y visualizar datos',
    feat5: 'Razonamiento extendido para trabajos complejos',
    feat6: 'Soporte prioritario y acceso anticipado',
    feat7: 'Generación de imágenes ampliada: más imágenes que en el plan Gratis',
  },
  en: {
    title: 'Get more Exodo',
    header_sub: 'Choose the plan right for you',
    plan_title: 'XPi PRO',
    subtitle: 'For everyday productivity',
    up_to_80_off: 'Up to 80% off',
    billed_monthly: 'Billed monthly',
    out_of_service: 'Unavailable',
    billed_annually: 'Billed annually',
    get_pro: 'Get Pro plan',
    processing: 'Connecting to Stripe...',
    no_commitments: 'No commitments - Cancel anytime',
    pro_features: 'Everything in Free, plus:',
    feat1: 'Everything included in Free',
    feat2: 'Higher usage limits',
    feat3: 'Chat across web, iOS, and Android',
    feat4: 'Generate code and visualize data',
    feat5: 'Extended reasoning for complex workflows',
    feat6: 'Priority support & early access',
    feat7: 'Extended image generation: more images than the Free plan',
  },
  pt: {
    title: 'Mais capacidade no Exodo',
    header_sub: 'Escolha o plano ideal para você',
    plan_title: 'XPi PRO',
    subtitle: 'Para produtividade diária',
    up_to_80_off: 'Até 80% off',
    billed_monthly: 'Faturado mensalmente',
    out_of_service: 'Fora de serviço',
    billed_annually: 'Faturado anualmente',
    get_pro: 'Obter plano Pro',
    processing: 'Conectando ao Stripe...',
    no_commitments: 'Sem compromissos - Cancele quando quiser',
    pro_features: 'Tudo do Grátis, mais:',
    feat1: 'Tudo incluído no Grátis',
    feat2: 'Limites de uso mais altos',
    feat3: 'Converse na web, iOS e Android',
    feat4: 'Gerar código e visualizar dados',
    feat5: 'Raciocínio estendido para tarefas complexas',
    feat6: 'Suporte prioritário e acesso antecipado',
    feat7: 'Geração de imágenes ampliada: mais imagens que no plano Grátis',
  },
  fr: {
    title: 'Plus de capacité sur Exodo',
    header_sub: 'Choisissez le forfait qui vous convient',
    plan_title: 'XPi PRO',
    subtitle: 'Pour la productivité quotidienne',
    up_to_80_off: 'Jusqu\'à 80% de réduction',
    billed_monthly: 'Facturé mensuellement',
    out_of_service: 'Indisponible',
    billed_annually: 'Facturé annuellement',
    get_pro: 'Obtenir le plan Pro',
    processing: 'Connexion à Stripe...',
    no_commitments: 'Sans engagement - Annulez à tout moment',
    pro_features: 'Tout ce qui est dans Gratuit, plus :',
    feat1: 'Tout ce qui est inclus dans Gratuit',
    feat2: 'Limites d\'utilisation plus élevées',
    feat3: 'Discutez sur le web, iOS et Android',
    feat4: 'Générer du code et visualiser des données',
    feat5: 'Raisonnement étendu pour les flux de travail complexes',
    feat6: 'Support prioritaire et accès anticipé',
    feat7: 'Génération d\'images étendue : plus d\'images que le forfait Gratuit',
  },
};

export const UpgradeModal: React.FC<UpgradeModalProps> = ({
  isOpen,
  onClose,
  onStartCheckout,
  isCheckingOut,
  isGuestUser: _isGuestUser = false,
  locale = 'es',
  theme = 'dark',
}) => {
  const [isAnnual, setIsAnnual] = useState(false);

  if (!isOpen) return null;

  const isLight = theme === 'light';
  const langKey = (locale || 'es').toLowerCase().startsWith('en')
    ? 'en'
    : (locale || 'es').toLowerCase().startsWith('pt')
    ? 'pt'
    : (locale || 'es').toLowerCase().startsWith('fr')
    ? 'fr'
    : 'es';
  const t = (key: string) => UPGRADE_I18N[langKey]?.[key] || UPGRADE_I18N.es[key] || key;

  // Paleta exacta de model_selector.dart (UpgradeModal)
  const bgColor = isLight ? '#FFFFFF' : '#191919';
  const composerBg = isLight ? '#F5F2EB' : '#252525';
  const planSelectedBg = isLight ? '#FFFFFF' : '#191919';
  const planUnselectedBg = isLight ? '#F5F2EB' : '#252525';
  const borderColor = isLight ? '#D1D1D6' : 'transparent';
  const textPrimary = isLight ? '#191919' : '#FFFFFF';
  const textSecondary = isLight ? '#191919' : '#F5F2EB';
  const radioOff = isLight ? '#191919' : 'rgba(255, 255, 255, 0.24)';
  const buttonBg = isLight ? '#191919' : '#FFFFFF';
  const buttonFg = isLight ? '#FFFFFF' : '#000000';
  const amber = 'var(--amber-exodo, #C9933A)';

  const features = [
    t('feat1'),
    t('feat2'),
    t('feat3'),
    t('feat4'),
    t('feat5'),
    t('feat6'),
    t('feat7'),
  ];

  return (
    <div
      style={{
        position: 'fixed',
        inset: 0,
        zIndex: 1100,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        padding: '16px',
      }}
    >
      {/* Backdrop */}
      <div
        style={{
          position: 'absolute',
          inset: 0,
          background: 'rgba(0, 0, 0, 0.65)',
          backdropFilter: 'blur(6px)',
        }}
        onClick={onClose}
      />

      {/* Modal Container (Paridad exacta UpgradeModal de model_selector.dart) */}
      <div
        style={{
          position: 'relative',
          background: bgColor,
          borderRadius: 28,
          padding: '20px 20px 24px 20px',
          width: '100%',
          maxWidth: 440,
          border: `1px solid ${isLight ? '#D1D1D6' : 'rgba(255, 255, 255, 0.08)'}`,
          boxShadow: '0 16px 48px rgba(0, 0, 0, 0.5)',
          maxHeight: '90vh',
          overflowY: 'auto',
          boxSizing: 'border-box',
        }}
      >
        {/* Botón cerrar */}
        <div style={{ display: 'flex', justifyContent: 'flex-start', marginBottom: 4 }}>
          <button
            type="button"
            onClick={onClose}
            style={{
              background: 'none',
              border: 'none',
              cursor: 'pointer',
              padding: 4,
              display: 'flex',
              alignItems: 'center',
              color: textSecondary,
            }}
            title="Cerrar"
          >
            <X size={20} />
          </button>
        </div>

        {/* Encabezado centrado */}
        <div style={{ textAlign: 'center', marginBottom: 24 }}>
          <h2
            style={{
              margin: 0,
              fontFamily: 'Syne, sans-serif',
              fontSize: '24px',
              fontWeight: 700,
              color: textPrimary,
            }}
          >
            {t('title')}
          </h2>
          <p
            style={{
              margin: '6px 0 0 0',
              fontSize: '14px',
              fontFamily: 'Inter, sans-serif',
              color: textSecondary,
            }}
          >
            {t('header_sub')}
          </p>
        </div>

        {/* Contenedor principal de la tarjeta XPi PRO (composerBg con borderRadius: 22) */}
        <div
          style={{
            background: composerBg,
            borderRadius: 22,
            padding: 20,
            border: `1px solid ${borderColor}`,
            boxSizing: 'border-box',
          }}
        >
          {/* Título de la tarjeta */}
          <div
            style={{
              fontFamily: 'Syne, sans-serif',
              fontSize: '20px',
              fontWeight: 700,
              color: textPrimary,
            }}
          >
            {t('plan_title')}
          </div>
          <div
            style={{
              marginTop: 4,
              fontSize: '13px',
              fontFamily: 'Inter, sans-serif',
              color: textSecondary,
            }}
          >
            {t('subtitle')}
          </div>

          {/* Opciones de facturación (Mensual $0.99 vs Anual Fuera de servicio) */}
          <div style={{ display: 'flex', gap: 10, marginTop: 16 }}>
            {/* Mensual (Seleccionado) */}
            <div
              onClick={() => setIsAnnual(false)}
              style={{
                flex: 1,
                padding: '12px 10px',
                borderRadius: 14,
                cursor: 'pointer',
                background: !isAnnual ? planSelectedBg : planUnselectedBg,
                border: !isAnnual
                  ? `1.5px solid ${amber}`
                  : `1px solid ${borderColor}`,
                boxSizing: 'border-box',
                display: 'flex',
                flexDirection: 'column',
                transition: 'all 0.15s ease',
              }}
            >
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                <div
                  style={{
                    width: 18,
                    height: 18,
                    borderRadius: '50%',
                    border: `2px solid ${!isAnnual ? amber : radioOff}`,
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    boxSizing: 'border-box',
                  }}
                >
                  {!isAnnual && (
                    <div
                      style={{
                        width: 8,
                        height: 8,
                        borderRadius: '50%',
                        background: amber,
                      }}
                    />
                  )}
                </div>
                <div
                  style={{
                    background: 'rgba(201, 147, 58, 0.2)',
                    color: amber,
                    padding: '2px 5px',
                    borderRadius: 6,
                    fontSize: '9px',
                    fontWeight: 700,
                    fontFamily: 'Inter, sans-serif',
                    whiteSpace: 'nowrap',
                  }}
                >
                  {t('up_to_80_off')}
                </div>
              </div>

              <div
                style={{
                  fontFamily: 'AnthropicSans, sans-serif',
                  fontSize: '18px',
                  fontWeight: 700,
                  color: textPrimary,
                  marginTop: 10,
                }}
              >
                $0.99
              </div>
              <div
                style={{
                  fontSize: '11px',
                  fontFamily: 'Inter, sans-serif',
                  color: textSecondary,
                  whiteSpace: 'nowrap',
                  overflow: 'hidden',
                  textOverflow: 'ellipsis',
                }}
              >
                {t('billed_monthly')}
              </div>
            </div>

            {/* Anual (Fuera de servicio - Opacidad 0.42 fija de Flutter) */}
            <div
              style={{
                flex: 1,
                padding: '12px 10px',
                borderRadius: 14,
                background: planUnselectedBg,
                border: `1px solid ${borderColor}`,
                opacity: 0.42,
                cursor: 'not-allowed',
                boxSizing: 'border-box',
                display: 'flex',
                flexDirection: 'column',
              }}
            >
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                <div
                  style={{
                    width: 18,
                    height: 18,
                    borderRadius: '50%',
                    border: `2px solid ${radioOff}`,
                    boxSizing: 'border-box',
                  }}
                />
                <div
                  style={{
                    background: isLight ? 'rgba(0, 0, 0, 0.08)' : 'rgba(255, 255, 255, 0.15)',
                    color: textSecondary,
                    padding: '2px 5px',
                    borderRadius: 6,
                    fontSize: '9px',
                    fontWeight: 700,
                    fontFamily: 'Inter, sans-serif',
                    whiteSpace: 'nowrap',
                  }}
                >
                  {t('out_of_service')}
                </div>
              </div>

              <div
                style={{
                  fontFamily: 'AnthropicSans, sans-serif',
                  fontSize: '18px',
                  fontWeight: 700,
                  color: textSecondary,
                  textDecoration: 'line-through',
                  marginTop: 10,
                }}
              >
                $49.99
              </div>
              <div
                style={{
                  fontSize: '11px',
                  fontFamily: 'Inter, sans-serif',
                  color: textSecondary,
                  whiteSpace: 'nowrap',
                  overflow: 'hidden',
                  textOverflow: 'ellipsis',
                }}
              >
                {t('billed_annually')}
              </div>
            </div>
          </div>

          {/* Botón CTA principal: Obtener plan Pro */}
          <button
            type="button"
            disabled={isCheckingOut}
            onClick={() => onStartCheckout(isAnnual)}
            style={{
              width: '100%',
              height: 48,
              borderRadius: 14,
              background: buttonBg,
              color: buttonFg,
              border: 'none',
              fontSize: '15px',
              fontWeight: 700,
              fontFamily: 'Inter, sans-serif',
              cursor: isCheckingOut ? 'wait' : 'pointer',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              marginTop: 18,
              boxShadow: isLight ? '0 2px 8px rgba(0,0,0,0.1)' : '0 4px 14px rgba(0,0,0,0.3)',
              transition: 'opacity 0.15s ease',
            }}
          >
            {isCheckingOut ? (
              <div
                style={{
                  width: 22,
                  height: 22,
                  borderRadius: '50%',
                  border: `2.5px solid ${buttonFg}`,
                  borderTopColor: 'transparent',
                  animation: 'spin 0.8s linear infinite',
                }}
              />
            ) : (
              t('get_pro')
            )}
          </button>

          {/* Subtítulo bajo el botón: Sin compromisos - Cancela cuando quieras */}
          <div
            style={{
              marginTop: 8,
              textAlign: 'center',
              fontSize: '11.5px',
              fontFamily: 'Inter, sans-serif',
              color: isLight ? 'rgba(25, 25, 25, 0.85)' : 'rgba(245, 242, 235, 0.85)',
            }}
          >
            {t('no_commitments')}
          </div>

          {/* Sección de características: Todo lo de Gratis, más: */}
          <div
            style={{
              marginTop: 18,
              fontSize: '12px',
              fontWeight: 700,
              fontFamily: 'Inter, sans-serif',
              color: textPrimary,
            }}
          >
            {t('pro_features')}
          </div>

          {/* 7 características oficiales de billing.feat1 a billing.feat7 */}
          <div style={{ display: 'flex', flexDirection: 'column', gap: 6, marginTop: 8 }}>
            {features.map((feat, i) => (
              <div key={i} style={{ display: 'flex', alignItems: 'flex-start', gap: 8 }}>
                <div style={{ marginTop: 2, flexShrink: 0 }}>
                  <Check size={15} color={textSecondary} strokeWidth={2.5} />
                </div>
                <div
                  style={{
                    fontSize: '12.5px',
                    fontFamily: 'Inter, sans-serif',
                    color: textSecondary,
                    lineHeight: 1.35,
                  }}
                >
                  {feat}
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
};
