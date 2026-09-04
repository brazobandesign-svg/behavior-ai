import React, { useState } from 'react';
import { ThumbsUp, ThumbsDown } from 'lucide-react';
import { supabase, type Message } from '../lib/supabase';

interface FeedbackModalProps {
  isOpen: boolean;
  target: { msg: Message; isLike: boolean } | null;
  onClose: () => void;
  onSuccessNotice: (msg: string) => void;
  userId?: string;
  locale?: string;
  theme?: 'dark' | 'light';
}

const FEEDBACK_I18N: Record<string, Record<string, string>> = {
  es: {
    title_pos: 'Comentarios positivos',
    title_neg: 'Comentarios de mejora',
    hint: 'Cuéntanos qué te gustó o cómo podemos mejorar...',
    cancel: 'Cancelar',
    send: 'Enviar',
    success: 'Comentario enviado, ¡gracias!',
    error: 'No se pudo enviar el comentario. Intenta más tarde.',
  },
  en: {
    title_pos: 'Positive feedback',
    title_neg: 'Provide feedback',
    hint: 'Tell us what you liked or how we can improve...',
    cancel: 'Cancel',
    send: 'Send',
    success: 'Feedback sent, thank you!',
    error: 'Could not send feedback. Try again later.',
  },
};

export const FeedbackModal: React.FC<FeedbackModalProps> = ({
  isOpen,
  target,
  onClose,
  onSuccessNotice,
  userId,
  locale = 'es',
  theme = 'dark',
}) => {
  const [comment, setComment] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);

  if (!isOpen || !target) return null;

  const isLight = theme === 'light';
  const langKey = (locale || 'es').toLowerCase().startsWith('en') ? 'en' : 'es';
  const t = (key: string) => FEEDBACK_I18N[langKey]?.[key] || FEEDBACK_I18N.es[key] || key;

  const handleSubmit = async () => {
    setIsSubmitting(true);
    try {
      const { error } = await supabase.from('feedback').insert({
        user_id: userId || null,
        is_like: target.isLike,
        comment: comment.trim(),
        message_excerpt: (target.msg.content || '').slice(0, 500),
        conversation_id: target.msg.conversation_id && !target.msg.conversation_id.startsWith('conv-') ? target.msg.conversation_id : null,
        app_locale: langKey,
        app_version: 'web',
        created_at: new Date().toISOString(),
      });
      if (error) throw error;
      onSuccessNotice(t('success'));
      setComment('');
      onClose();
    } catch (_) {
      onSuccessNotice(t('error'));
      onClose();
    } finally {
      setIsSubmitting(false);
    }
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
          maxWidth: 420,
          borderRadius: 18,
          padding: '20px',
          boxShadow: '0 12px 36px rgba(0, 0, 0, 0.45)',
          border: `1px solid ${isLight ? '#E5E2DA' : 'rgba(255,255,255,0.08)'}`,
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 14 }}>
          {target.isLike ? (
            <ThumbsUp size={18} color="var(--amber-exodo)" />
          ) : (
            <ThumbsDown size={18} color="var(--amber-exodo)" />
          )}
          <span
            style={{
              fontSize: '15.5px',
              fontWeight: 700,
              color: 'var(--text-primary)',
              fontFamily: 'AnthropicSans, sans-serif',
            }}
          >
            {target.isLike ? t('title_pos') : t('title_neg')}
          </span>
        </div>

        <textarea
          autoFocus
          rows={3}
          value={comment}
          onChange={(e) => setComment(e.target.value)}
          placeholder={t('hint')}
          style={{
            width: '100%',
            boxSizing: 'border-box',
            resize: 'vertical',
            background: isLight ? '#F5F4EF' : '#191919',
            border: `1px solid ${isLight ? '#E0DDD4' : 'rgba(255,255,255,0.1)'}`,
            borderRadius: 12,
            padding: '12px 14px',
            color: 'var(--text-primary)',
            fontSize: '14px',
            fontFamily: 'AnthropicSans, sans-serif',
            outline: 'none',
          }}
        />

        <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 10, marginTop: 14 }}>
          <button
            type="button"
            onClick={onClose}
            style={{
              background: 'transparent',
              border: 'none',
              cursor: 'pointer',
              color: 'var(--text-secondary)',
              fontSize: '13.5px',
              fontWeight: 500,
              padding: '8px 14px',
            }}
          >
            {t('cancel')}
          </button>
          <button
            type="button"
            disabled={isSubmitting}
            onClick={handleSubmit}
            style={{
              background: 'transparent',
              border: 'none',
              cursor: isSubmitting ? 'wait' : 'pointer',
              color: 'var(--amber-exodo)',
              fontSize: '14px',
              fontWeight: 700,
              padding: '8px 14px',
            }}
          >
            {isSubmitting ? '...' : t('send')}
          </button>
        </div>
      </div>
    </div>
  );
};
