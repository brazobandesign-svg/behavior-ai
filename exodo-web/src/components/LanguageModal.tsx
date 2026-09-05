import React, { useState, useEffect } from 'react';
import { X, Check, Search, Globe } from 'lucide-react';
import { EXODO_LANGUAGES } from '../types/languages';

interface LanguageModalProps {
  isOpen: boolean;
  onClose: () => void;
  currentLocale: string;
  onSelectLocale: (code: string) => void;
  theme?: 'dark' | 'light';
}

export const LanguageModal: React.FC<LanguageModalProps> = ({
  isOpen,
  onClose,
  currentLocale,
  onSelectLocale,
  theme = 'dark',
}) => {
  const [searchQuery, setSearchQuery] = useState('');

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
  const isEn = currentLocale.toLowerCase().startsWith('en');

  const filteredLanguages = EXODO_LANGUAGES.filter((lang) => {
    const q = searchQuery.toLowerCase().trim();
    if (!q) return true;
    return (
      lang.title.toLowerCase().includes(q) ||
      lang.subtitle.toLowerCase().includes(q) ||
      (lang.code && lang.code.toLowerCase().includes(q))
    );
  });

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
        aria-labelledby="language-modal-title"
        className="modal-pop"
        style={{
          position: 'relative',
          width: '100%',
          maxWidth: 580,
          maxHeight: '85vh',
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
              <Globe size={18} color="var(--amber-exodo)" />
              <h2
                id="language-modal-title"
                style={{
                  margin: 0,
                  fontSize: '20px',
                  fontWeight: 700,
                  fontFamily: 'Syne, sans-serif',
                  color: 'var(--text-primary)',
                  letterSpacing: '-0.2px',
                }}
              >
                {isEn ? 'Interface Language' : 'Idioma de la Interfaz'}
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
              {isEn
                ? 'Select your preferred language for the application.'
                : 'Selecciona tu idioma preferido para la aplicación.'}
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
            title={isEn ? 'Close' : 'Cerrar'}
          >
            <X size={18} />
          </button>
        </div>

        {/* Buscador Rápido de Idiomas */}
        <div style={{ padding: '14px 24px 8px 24px' }}>
          <div
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: 10,
              background: isLight ? '#F7F6F2' : '#262626',
              border: `1px solid ${isLight ? '#E5E2DA' : 'rgba(255, 255, 255, 0.08)'}`,
              borderRadius: 12,
              padding: '10px 14px',
            }}
          >
            <Search size={16} color="var(--text-secondary)" />
            <input
              type="text"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              placeholder={isEn ? 'Search language...' : 'Buscar idioma...'}
              style={{
                background: 'transparent',
                border: 'none',
                outline: 'none',
                color: 'var(--text-primary)',
                fontSize: '13.5px',
                fontFamily: 'Inter, sans-serif',
                width: '100%',
              }}
            />
            {searchQuery && (
              <button
                type="button"
                onClick={() => setSearchQuery('')}
                style={{
                  background: 'none',
                  border: 'none',
                  cursor: 'pointer',
                  color: 'var(--text-secondary)',
                  padding: 2,
                }}
              >
                <X size={14} />
              </button>
            )}
          </div>
        </div>

        {/* Cuadrícula / Lista con Scroll */}
        <div
          style={{
            padding: '10px 24px 24px 24px',
            overflowY: 'auto',
            display: 'grid',
            gridTemplateColumns: 'repeat(auto-fill, minmax(240px, 1fr))',
            gap: 10,
          }}
        >
          {filteredLanguages.map((lang) => {
            const isSelected =
              lang.code === null
                ? currentLocale === 'system' || !currentLocale
                : currentLocale === lang.code;

            return (
              <div
                key={lang.code || 'system'}
                onClick={() => {
                  onSelectLocale(lang.code || 'system');
                  onClose();
                }}
                style={{
                  padding: '12px 14px',
                  borderRadius: 14,
                  background: isSelected
                    ? (isLight ? 'rgba(201, 147, 58, 0.12)' : 'rgba(201, 147, 58, 0.16)')
                    : (isLight ? '#F7F6F2' : '#242424'),
                  border: isSelected
                    ? '1.5px solid var(--amber-exodo)'
                    : `1px solid ${isLight ? '#E8E5DC' : 'rgba(255, 255, 255, 0.06)'}`,
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'space-between',
                  cursor: 'pointer',
                  transition: 'background 0.15s ease, border-color 0.15s ease, transform 0.1s ease',
                  userSelect: 'none',
                }}
                onMouseEnter={(e) => {
                  if (!isSelected) {
                    e.currentTarget.style.background = isLight ? '#EDEBE4' : '#2B2B2B';
                  }
                }}
                onMouseLeave={(e) => {
                  if (!isSelected) {
                    e.currentTarget.style.background = isLight ? '#F7F6F2' : '#242424';
                  }
                }}
              >
                <div style={{ display: 'flex', alignItems: 'center', gap: 12, minWidth: 0 }}>
                  <span style={{ fontSize: '22px', lineHeight: 1, flexShrink: 0 }}>
                    {lang.flag}
                  </span>
                  <div style={{ minWidth: 0 }}>
                    <div
                      style={{
                        fontSize: '13.5px',
                        fontWeight: isSelected ? 700 : 500,
                        color: isSelected ? 'var(--amber-exodo)' : 'var(--text-primary)',
                        fontFamily: 'Inter, sans-serif',
                        overflow: 'hidden',
                        textOverflow: 'ellipsis',
                        whiteSpace: 'nowrap',
                      }}
                    >
                      {lang.title}
                    </div>
                    <div
                      style={{
                        fontSize: '11px',
                        color: 'var(--text-secondary)',
                        fontFamily: 'Inter, sans-serif',
                      }}
                    >
                      {lang.subtitle}
                    </div>
                  </div>
                </div>

                {isSelected && (
                  <div
                    style={{
                      width: 22,
                      height: 22,
                      borderRadius: '50%',
                      background: 'var(--amber-exodo)',
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                      color: '#000000',
                      flexShrink: 0,
                    }}
                  >
                    <Check size={14} strokeWidth={3} />
                  </div>
                )}
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
};
