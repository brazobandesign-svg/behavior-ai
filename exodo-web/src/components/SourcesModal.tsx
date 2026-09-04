import React from 'react';
import { X, ExternalLink } from 'lucide-react';
import type { Source } from '../lib/supabase';

interface SourcesModalProps {
  isOpen: boolean;
  sources: Source[];
  onClose: () => void;
  locale?: string;
  theme?: 'dark' | 'light';
}

const SOURCE_CIRCLE_COLORS = [
  '#C9933A',
  '#5C9CE6',
  '#6DBA82',
  '#9B7BD8',
  '#D96B6B',
  '#E69555',
];

const sourceInitials = (s: Source): string => {
  const t = (s.title || '').trim();
  if (t) {
    const w = t.split(/\s+/).filter(Boolean);
    if (w.length >= 2) return (w[0][0] + w[1][0]).toUpperCase();
    return t.slice(0, 2).toUpperCase();
  }
  if (s.url) {
    try {
      const h = new URL(s.url).hostname.replace(/^www\./, '');
      return h.slice(0, 2).toUpperCase();
    } catch (_) {}
  }
  return 'WEB';
};

const getFaviconUrl = (url?: string): string | null => {
  if (!url) return null;
  try {
    const host = new URL(url).hostname;
    return host ? `https://www.google.com/s2/favicons?domain=${host}&sz=32` : null;
  } catch (_) {
    return null;
  }
};

export const SourcesModal: React.FC<SourcesModalProps> = ({
  isOpen,
  sources,
  onClose,
  locale = 'es',
  theme = 'dark',
}) => {
  if (!isOpen || sources.length === 0) return null;

  const isLight = theme === 'light';
  const es = (locale || 'es').toLowerCase().startsWith('es');
  const title = es ? 'Fuentes consultadas' : 'Sources consulted';

  const handleOpenUrl = (url?: string) => {
    if (!url) return;
    try {
      window.open(url, '_blank', 'noopener,noreferrer');
    } catch (_) {}
  };

  return (
    <div
      style={{
        position: 'fixed',
        inset: 0,
        zIndex: 1200,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        padding: 16,
      }}
      onClick={onClose}
    >
      {/* Backdrop */}
      <div
        style={{
          position: 'absolute',
          inset: 0,
          background: 'rgba(0, 0, 0, 0.65)',
          backdropFilter: 'blur(4px)',
        }}
      />

      {/* Sheet Container */}
      <div
        style={{
          position: 'relative',
          background: isLight ? '#FFFFFF' : '#222222',
          width: '100%',
          maxWidth: 460,
          borderRadius: 20,
          padding: '20px',
          boxShadow: '0 16px 40px rgba(0,0,0,0.4)',
          border: `1px solid ${isLight ? '#E5E2DA' : 'rgba(255,255,255,0.08)'}`,
          display: 'flex',
          flexDirection: 'column',
          maxHeight: '80vh',
        }}
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            marginBottom: 16,
            paddingBottom: 10,
            borderBottom: `1px solid ${isLight ? '#F0EFEA' : 'rgba(255,255,255,0.06)'}`,
          }}
        >
          <span
            style={{
              fontFamily: 'Syne, sans-serif',
              fontSize: '16px',
              fontWeight: 700,
              color: 'var(--text-primary)',
            }}
          >
            {title} ({sources.length})
          </span>
          <button
            type="button"
            onClick={onClose}
            style={{
              background: 'none',
              border: 'none',
              cursor: 'pointer',
              color: 'var(--text-secondary)',
              padding: 4,
              display: 'flex',
            }}
            aria-label="Cerrar"
          >
            <X size={18} />
          </button>
        </div>

        {/* List of sources */}
        <div
          style={{
            overflowY: 'auto',
            display: 'flex',
            flexDirection: 'column',
            gap: 8,
            paddingRight: 4,
          }}
        >
          {sources.map((s, idx) => {
            const favicon = getFaviconUrl(s.url);
            return (
              <button
                key={`${s.url}-${idx}`}
                type="button"
                onClick={() => handleOpenUrl(s.url)}
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  gap: 12,
                  padding: '12px 14px',
                  borderRadius: 14,
                  background: isLight ? '#F7F6F2' : '#1C1C1C',
                  border: `1px solid ${isLight ? '#EAE8E1' : 'rgba(255,255,255,0.04)'}`,
                  cursor: 'pointer',
                  textAlign: 'left',
                  width: '100%',
                  transition: 'background 0.15s ease',
                }}
              >
                {/* Favicon or Circle Initials */}
                <div
                  style={{
                    width: 32,
                    height: 32,
                    borderRadius: 8,
                    background: favicon ? (isLight ? '#FFFFFF' : '#2A2A2A') : SOURCE_CIRCLE_COLORS[idx % SOURCE_CIRCLE_COLORS.length],
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    flexShrink: 0,
                    overflow: 'hidden',
                  }}
                >
                  {favicon ? (
                    <img
                      src={favicon}
                      alt=""
                      width={18}
                      height={18}
                      style={{ objectFit: 'contain' }}
                      onError={(e) => {
                        e.currentTarget.style.display = 'none';
                        const parent = e.currentTarget.parentElement;
                        if (parent) {
                          parent.style.background = SOURCE_CIRCLE_COLORS[idx % SOURCE_CIRCLE_COLORS.length];
                          parent.innerText = sourceInitials(s);
                          parent.style.color = '#FFFFFF';
                          parent.style.fontSize = '10px';
                          parent.style.fontWeight = 'bold';
                        }
                      }}
                    />
                  ) : (
                    <span style={{ fontSize: '10px', fontWeight: 'bold', color: '#FFFFFF' }}>
                      {sourceInitials(s)}
                    </span>
                  )}
                </div>

                {/* Info */}
                <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 2 }}>
                  <span
                    style={{
                      fontSize: '13.5px',
                      fontWeight: 600,
                      color: 'var(--text-primary)',
                      overflow: 'hidden',
                      textOverflow: 'ellipsis',
                      whiteSpace: 'nowrap',
                      fontFamily: 'AnthropicSans, sans-serif',
                    }}
                  >
                    {s.title || s.url}
                  </span>
                  {s.url && (
                    <span
                      style={{
                        fontSize: '11.5px',
                        color: 'var(--text-secondary)',
                        overflow: 'hidden',
                        textOverflow: 'ellipsis',
                        whiteSpace: 'nowrap',
                        fontFamily: 'Inter, sans-serif',
                      }}
                    >
                      {s.url}
                    </span>
                  )}
                </div>

                <ExternalLink size={16} color="var(--text-secondary)" style={{ flexShrink: 0 }} />
              </button>
            );
          })}
        </div>
      </div>
    </div>
  );
};
