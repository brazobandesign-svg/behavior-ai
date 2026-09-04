import React from 'react';
import { Check, Lock, ChevronDown } from 'lucide-react';

import { EXODO_MODELS, type ModelOption } from '../types/models';

interface ModelSelectorProps {
  selectedModel: ModelOption;
  onSelectModel: (model: ModelOption) => void;
  isOpen: boolean;
  onToggleOpen: () => void;
  onClose: () => void;
  userPlan?: string;
  isIncognito?: boolean;
  isGuestUser?: boolean;
  onRequireUpgrade: () => void;
  locale?: string;
  theme?: 'dark' | 'light';
}

export const ModelSelector: React.FC<ModelSelectorProps> = ({
  selectedModel,
  onSelectModel,
  isOpen,
  onToggleOpen,
  onClose,
  userPlan = 'genesis',
  isIncognito = false,
  isGuestUser = false,
  onRequireUpgrade,
  locale = 'es',
  theme = 'dark',
}) => {
  const isLight = theme === 'light';
  const isEn = (locale || 'es').toLowerCase().startsWith('en');
  const isModelLocked = isIncognito || isGuestUser;

  const displayTitle = isIncognito ? 'G1.1' : selectedModel.title;

  return (
    <div style={{ position: 'relative' }}>
      {/* Chip disparador en el composer */}
      <button
        type="button"
        onClick={() => {
          if (isModelLocked) return;
          onToggleOpen();
        }}
        style={{
          padding: '6px 12px',
          borderRadius: 16,
          background: isLight ? '#FFFFFF' : '#141414',
          border: selectedModel.id === 'xpi' && userPlan === 'hazak'
            ? '1px solid var(--amber-exodo)'
            : `1px solid ${isLight ? 'rgba(0,0,0,0.08)' : 'rgba(255,255,255,0.08)'}`,
          boxShadow: selectedModel.id === 'xpi' && userPlan === 'hazak'
            ? '0 0 12px rgba(201, 147, 58, 0.25)'
            : 'none',
          display: 'flex',
          alignItems: 'center',
          gap: 5,
          cursor: isModelLocked ? 'default' : 'pointer',
          color: 'var(--text-primary)',
          transition: 'all 0.15s ease',
        }}
        title={
          isModelLocked
            ? isGuestUser
              ? 'En modo invitado solo se permite G1.1'
              : 'Modelo bloqueado en Modo Incógnito'
            : 'Seleccionar modelo de IA'
        }
      >
        <span style={{ fontFamily: 'AnthropicSans, sans-serif', fontSize: '13px', fontWeight: 700 }}>
          {displayTitle}
        </span>
        {isModelLocked ? (
          <Lock size={13} color="var(--text-secondary)" />
        ) : (
          <ChevronDown
            size={16}
            color="var(--text-secondary)"
            style={{
              transform: isOpen ? 'rotate(180deg)' : 'rotate(0deg)',
              transition: 'transform 0.2s ease',
            }}
          />
        )}
      </button>

      {/* Popover desplegable */}
      {isOpen && !isModelLocked && (
        <>
          <div
            style={{ position: 'fixed', inset: 0, zIndex: 110 }}
            onClick={onClose}
          />
          <div
            className="model-selector-popover"
            style={{
              position: 'absolute',
              bottom: 'calc(100% + 8px)',
              left: 0,
              background: isLight ? '#FFFFFF' : '#222222',
              border: `1px solid ${isLight ? '#E0E0E0' : '#333333'}`,
              borderRadius: 16,
              padding: '8px',
              zIndex: 120,
              width: 270,
              boxShadow: '0 8px 24px rgba(0,0,0,0.3)',
            }}
            onClick={(e) => e.stopPropagation()}
          >
            <div
              style={{
                width: 36,
                height: 4,
                borderRadius: 2,
                background: isLight ? '#E5E2DA' : '#444444',
                margin: '2px auto 10px auto',
              }}
            />
            {EXODO_MODELS.map((m) => {
              const active = selectedModel.id === m.id;
              const isProModel = m.plan === 'hazak';
              const isUserFree = userPlan !== 'hazak';

              return (
                <div
                  key={m.id}
                  onClick={() => {
                    if (isProModel && isUserFree) {
                      onClose();
                      onRequireUpgrade();
                    } else {
                      onSelectModel(m);
                      onClose();
                    }
                  }}
                  style={{
                    padding: '10px 12px',
                    borderRadius: 10,
                    background: active
                      ? (isLight ? '#F0EFEA' : '#2C2C30')
                      : 'transparent',
                    cursor: 'pointer',
                    display: 'flex',
                    flexDirection: 'column',
                    gap: 3,
                    transition: 'background 0.15s ease',
                  }}
                >
                  <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                      <span
                        style={{
                          fontFamily: 'AnthropicSans, sans-serif',
                          fontWeight: active ? 700 : 600,
                          fontSize: '14px',
                          color: active ? 'var(--amber-exodo)' : 'var(--text-primary)',
                        }}
                      >
                        {m.title}
                      </span>
                      {!isProModel && m.subtitle && (
                        <span
                          style={{
                            fontFamily: 'AnthropicSans, sans-serif',
                            fontSize: '12px',
                            color: 'var(--text-secondary)',
                          }}
                        >
                          {m.subtitle}
                        </span>
                      )}
                      {isProModel && (
                        <span
                          style={{
                            fontSize: '9.5px',
                            padding: '1.5px 5px',
                            borderRadius: 4,
                            border: `1px solid ${active ? 'var(--amber-exodo)' : 'rgba(255,255,255,0.2)'}`,
                            backgroundColor: active ? 'rgba(201, 147, 58, 0.18)' : 'transparent',
                            color: active ? 'var(--amber-exodo)' : 'var(--text-secondary)',
                            fontWeight: 700,
                            fontFamily: 'AnthropicSans, sans-serif',
                          }}
                        >
                          PRO
                        </span>
                      )}
                    </div>
                    {active && <Check size={16} color="var(--amber-exodo)" />}
                  </div>
                  <span
                    style={{
                      fontFamily: 'AnthropicSans, sans-serif',
                      fontSize: '11.5px',
                      color: 'var(--text-secondary)',
                      lineHeight: 1.35,
                    }}
                  >
                    {isEn ? m.descriptionEn : m.description}
                  </span>
                </div>
              );
            })}


          </div>
        </>
      )}
    </div>
  );
};
