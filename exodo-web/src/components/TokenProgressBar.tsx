import React, { useState, useEffect } from 'react';
import { ChevronDown } from 'lucide-react';

interface TokenProgressBarProps {
  used: number;
  limit: number;
  resetTime?: Date | null;
  isPro: boolean;
  theme?: 'dark' | 'light';
  locale?: string;
}

const TOKEN_I18N: Record<string, Record<string, string>> = {
  es: {
    used: 'Consumido',
    available: 'Disponible',
    reset_in: 'Se reinicia en',
  },
  en: {
    used: 'Used',
    available: 'Available',
    reset_in: 'Resets in',
  },
};

export const TokenProgressBar: React.FC<TokenProgressBarProps> = ({
  used,
  limit,
  resetTime,
  isPro,
  theme = 'dark',
  locale = 'es',
}) => {
  const [isExpanded, setIsExpanded] = useState(false);
  const [countdown, setCountdown] = useState('24h 00m 00s');

  const isLight = theme === 'light';
  const effectiveLimit = limit > 0 ? limit : (isPro ? 50000 : 6000);
  const progress = Math.min(Math.max(used / effectiveLimit, 0), 1);
  const remaining = Math.max(effectiveLimit - used, 0);
  const pct = (progress * 100).toFixed(1);

  const langKey = (locale || 'es').toLowerCase().startsWith('en') ? 'en' : 'es';
  const t = (key: string) => TOKEN_I18N[langKey]?.[key] || TOKEN_I18N.es[key] || key;

  // Actualización del cronómetro segundo a segundo SOLO mientras está expandido (paridad P3 batería de Flutter)
  useEffect(() => {
    if (!isExpanded) return;

    const calcCountdown = () => {
      const now = new Date();
      // Medianoche UTC-4 (AST) o resetTime
      let target: Date;
      if (resetTime) {
        target = resetTime;
      } else {
        target = new Date();
        target.setUTCHours(4, 0, 0, 0);
        if (target.getTime() <= now.getTime()) {
          target = new Date(target.getTime() + 24 * 3600 * 1000);
        }
      }

      const diff = target.getTime() - now.getTime();
      if (diff <= 0) {
        setCountdown('00h 00m 00s');
        return;
      }

      const h = String(Math.floor(diff / (3600 * 1000))).padStart(2, '0');
      const m = String(Math.floor((diff % (3600 * 1000)) / (60 * 1000))).padStart(2, '0');
      const s = String(Math.floor((diff % (60 * 1000)) / 1000)).padStart(2, '0');
      setCountdown(`${h}h ${m}m ${s}s`);
    };

    calcCountdown();
    const interval = setInterval(calcCountdown, 1000);
    return () => clearInterval(interval);
  }, [isExpanded, resetTime]);

  const bgColor = isLight ? '#F7F7F7' : '#1D1D1D';
  const trackColor = isLight ? 'rgba(0, 0, 0, 0.08)' : '#141414';
  const fillColor = isLight ? '#191919' : 'var(--exodo-text-primary, #F5F2EB)';
  const textColor = isLight ? '#171615' : 'var(--text-primary)';

  return (
    <div
      onClick={() => setIsExpanded(!isExpanded)}
      style={{
        background: bgColor,
        borderRadius: 16,
        padding: '12px 14px',
        border: `1px solid ${
          isExpanded
            ? 'var(--amber-exodo)'
            : isLight
            ? 'rgba(0,0,0,0.08)'
            : '#2C2C2C'
        }`,
        cursor: 'pointer',
        transition: 'border-color 0.25s ease, box-shadow 0.25s ease',
        boxShadow: isExpanded ? '0 0 14px rgba(201, 147, 58, 0.2)' : 'none',
        userSelect: 'none',
      }}
    >
      {/* Fila principal colapsada */}
      <div style={{ display: 'flex', alignItems: 'center' }}>
        <span
          style={{
            fontFamily: 'AnthropicSans, sans-serif',
            fontSize: '11.5px',
            color: textColor,
            fontWeight: 600,
            whiteSpace: 'nowrap',
          }}
        >
          {used}/{effectiveLimit}
        </span>

        <div style={{ flex: 1, margin: '0 10px' }}>
          <div
            style={{
              height: 6,
              borderRadius: 4,
              background: trackColor,
              overflow: 'hidden',
              width: '100%',
            }}
          >
            <div
              style={{
                width: `${progress * 100}%`,
                height: '100%',
                background: fillColor,
                borderRadius: 4,
                transition: 'width 0.3s ease',
              }}
            />
          </div>
        </div>

        <div
          style={{
            transform: isExpanded ? 'rotate(180deg)' : 'rotate(0deg)',
            transition: 'transform 0.2s ease',
            display: 'flex',
            alignItems: 'center',
          }}
        >
          <ChevronDown
            size={18}
            color={isExpanded ? 'var(--amber-exodo)' : 'var(--text-secondary)'}
          />
        </div>
      </div>

      {/* Contenido expandible con estadísticas y cronómetro en vivo */}
      {isExpanded && (
        <div
          style={{
            marginTop: 12,
            padding: '10px 12px',
            background: isLight ? '#FFFFFF' : '#131313',
            borderRadius: 12,
            border: `1px solid ${isLight ? 'rgba(0,0,0,0.06)' : '#242424'}`,
            display: 'flex',
            justifyContent: 'space-around',
            alignItems: 'center',
          }}
          onClick={(e) => e.stopPropagation()}
        >
          {/* Píldora 1: Consumido */}
          <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
            <span
              style={{
                fontSize: '9.5px',
                color: isLight ? 'rgba(0,0,0,0.54)' : 'var(--text-secondary)',
                fontWeight: 500,
                fontFamily: 'Inter, sans-serif',
              }}
            >
              {t('used')}
            </span>
            <span
              style={{
                fontFamily: 'AnthropicSans, sans-serif',
                fontSize: '12px',
                fontWeight: 700,
                color: isLight ? '#191919' : '#FFFFFF',
                marginTop: 3,
              }}
            >
              {used} ({pct}%)
            </span>
          </div>

          {/* Píldora 2: Disponible (si es Pro) */}
          {isPro && (
            <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
              <span
                style={{
                  fontSize: '9.5px',
                  color: isLight ? 'rgba(0,0,0,0.54)' : 'var(--text-secondary)',
                  fontWeight: 500,
                  fontFamily: 'Inter, sans-serif',
                }}
              >
                {t('available')}
              </span>
              <span
                style={{
                  fontFamily: 'AnthropicSans, sans-serif',
                  fontSize: '12px',
                  fontWeight: 700,
                  color: isLight ? '#191919' : '#FFFFFF',
                  marginTop: 3,
                }}
              >
                {remaining} tk
              </span>
            </div>
          )}

          {/* Píldora 3: Se reinicia en (en vivo y en color ámbar) */}
          <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
            <span
              style={{
                fontSize: '9.5px',
                color: isLight ? 'rgba(0,0,0,0.54)' : 'var(--text-secondary)',
                fontWeight: 500,
                fontFamily: 'Inter, sans-serif',
              }}
            >
              {t('reset_in')}
            </span>
            <span
              style={{
                fontFamily: 'AnthropicSans, sans-serif',
                fontSize: '12px',
                fontWeight: 700,
                color: 'var(--amber-exodo)',
                marginTop: 3,
                fontVariantNumeric: 'tabular-nums',
              }}
            >
              {countdown}
            </span>
          </div>
        </div>
      )}
    </div>
  );
};
