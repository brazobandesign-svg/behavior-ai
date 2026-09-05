import React, { useState } from 'react';
import { Headphones, Mail, Copy, Check, Send, X } from 'lucide-react';

interface SupportModalProps {
  isOpen: boolean;
  onClose: () => void;
  locale?: string;
  theme?: 'dark' | 'light';
}

const SUPPORT_EMAIL = 'exodobybehavior@gmail.com';

const SUPPORT_I18N: Record<
  string,
  {
    title: string;
    desc: string;
    copy: string;
    copied: string;
    send: string;
    close: string;
  }
> = {
  es: {
    title: 'Soporte',
    desc: '¿Tienes dudas, quejas, mensajes o sugerencias? Escríbenos directamente a nuestro correo y te responderemos lo antes posible:',
    copy: 'Copiar correo',
    copied: '¡Copiado!',
    send: 'Enviar correo',
    close: 'Cerrar',
  },
  en: {
    title: 'Support',
    desc: 'Have questions, complaints, feedback, or suggestions? Write directly to our email and we will reply as soon as possible:',
    copy: 'Copy email',
    copied: 'Copied!',
    send: 'Send email',
    close: 'Close',
  },
  fr: {
    title: 'Support',
    desc: 'Vous avez des questions, des réclamations, des messages ou des suggestions ? Écrivez-nous directement par e-mail et nous vous répondrons dès que possible :',
    copy: "Copier l'e-mail",
    copied: 'Copié !',
    send: 'Envoyer un e-mail',
    close: 'Fermer',
  },
  pt: {
    title: 'Suporte',
    desc: 'Tem dúvidas, reclamações, mensagens ou sugestões? Escreva diretamente para o nosso e-mail e responderemos o mais breve possível:',
    copy: 'Copiar e-mail',
    copied: 'Copiado!',
    send: 'Enviar e-mail',
    close: 'Fechar',
  },
  it: {
    title: 'Supporto',
    desc: 'Hai domande, reclami, messaggi o suggerimenti? Scrivici directamente via email e ti risponderemo il prima possibile:',
    copy: 'Copia email',
    copied: 'Copiato!',
    send: 'Invia email',
    close: 'Chiudi',
  },
  de: {
    title: 'Support',
    desc: 'Haben Sie Fragen, Beschwerden, Nachrichten oder Anregungen? Schreiben Sie uns direkt per E-Mail und wir antworten so schnell wie möglich:',
    copy: 'E-Mail kopieren',
    copied: 'Kopiert!',
    send: 'E-Mail senden',
    close: 'Schließen',
  },
  ru: {
    title: 'Поддержка',
    desc: 'У вас есть вопросы, жалобы, сообщения или предложения? Напишите нам на почту, и мы ответим как можно скорее:',
    copy: 'Скопировать email',
    copied: 'Скопировано!',
    send: 'Написать письмо',
    close: 'Закрыть',
  },
  zh: {
    title: '支持',
    desc: '您有任何疑问、投诉、留言或建议吗？请直接发送邮件至我们的邮箱，我们将尽快回复：',
    copy: '复制邮箱',
    copied: '已复制！',
    send: '发送邮件',
    close: '关闭',
  },
  ja: {
    title: 'サポート',
    desc: 'ご質問、苦情、メッセージ、ご要望などがございましたら、直接メールでお問い合わせください。できる限り迅速にご返信いたします：',
    copy: 'メールをコピー',
    copied: 'コピーしました！',
    send: 'メールを送信',
    close: '閉じる',
  },
  ar: {
    title: 'الدعم',
    desc: 'هل لديك أي أسئلة أو شكاوى أو رسائل أو اقتراحات؟ راسلنا مباشرة عبر البريد الإلكتروني وسنرد عليك في أقرب وقت:',
    copy: 'نسخ البريد',
    copied: 'تم النسخ!',
    send: 'إرسال بريد',
    close: 'إغلاق',
  },
  ko: {
    title: '고객 지원',
    desc: '질문, 불만 사항, 메시지 또는 제안이 있으신가요? 이메일로 직접 문의해 주시면 최대한 빨리 답변해 드리겠습니다:',
    copy: '이메일 복사',
    copied: '복사 완료!',
    send: '이메일 보내기',
    close: '닫기',
  },
  hi: {
    title: 'सहायता',
    desc: 'क्या आपके पास कोई प्रश्न, शिकायत, संदेश या सुझाव है? हमें सीधे ईमेल करें और हम जल्द से जल्द उत्तर देंगे:',
    copy: 'ईमेल कॉपी करें',
    copied: 'कॉपी किया गया!',
    send: 'ईमेल भेजें',
    close: 'बंद करें',
  },
  ht: {
    title: 'Sipò',
    desc: 'Ou gen kesyon, plent, mesaj oswa sijesyon? Ekri nou dirèkteman nan imèl nou epi n ap reponn ou pi vit posib:',
    copy: 'Kopye imèl',
    copied: 'Kopye!',
    send: 'Voye imèl',
    close: 'Fèmen',
  },
};

export const SupportModal: React.FC<SupportModalProps> = ({
  isOpen,
  onClose,
  locale = 'es',
  theme = 'dark',
}) => {
  const [copied, setCopied] = useState(false);

  if (!isOpen) return null;

  const isLight = theme === 'light';
  const baseLang = (locale || 'es').toLowerCase().split(/[-_]/)[0];
  const t = SUPPORT_I18N[baseLang] || SUPPORT_I18N.es;

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(SUPPORT_EMAIL);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      const textarea = document.createElement('textarea');
      textarea.value = SUPPORT_EMAIL;
      document.body.appendChild(textarea);
      textarea.select();
      document.execCommand('copy');
      document.body.removeChild(textarea);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    }
  };

  const handleSendEmail = () => {
    window.location.href = `mailto:${SUPPORT_EMAIL}?subject=Soporte%20Exodo`;
  };

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
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            marginBottom: 16,
          }}
        >
          <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <div
              style={{
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                width: 36,
                height: 36,
                borderRadius: 10,
                background: 'rgba(201, 147, 58, 0.15)',
              }}
            >
              <Headphones size={20} color="var(--amber-exodo)" />
            </div>
            <h2
              style={{
                fontSize: '18px',
                fontWeight: 700,
                fontFamily: 'Syne, sans-serif',
                color: 'var(--text-primary)',
                margin: 0,
              }}
            >
              {t.title}
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

        <p
          style={{
            fontSize: '13.5px',
            color: 'var(--text-secondary)',
            fontFamily: 'Inter, sans-serif',
            lineHeight: 1.5,
            margin: '0 0 16px 0',
          }}
        >
          {t.desc}
        </p>

        {/* Email Box */}
        <div
          style={{
            background: isLight ? '#F5F4EF' : '#2A2A2A',
            borderRadius: 14,
            padding: '12px 14px',
            display: 'flex',
            alignItems: 'center',
            gap: 10,
            marginBottom: 20,
            border: `1px solid ${isLight ? '#E5E2DA' : 'rgba(255,255,255,0.06)'}`,
          }}
        >
          <Mail size={18} color="var(--amber-exodo)" />
          <span
            style={{
              fontSize: '14px',
              fontWeight: 600,
              fontFamily: 'Inter, sans-serif',
              color: 'var(--text-primary)',
              letterSpacing: '-0.2px',
              userSelect: 'all',
              flex: 1,
            }}
          >
            {SUPPORT_EMAIL}
          </span>
        </div>

        {/* Actions */}
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: 10,
          }}
        >
          <button
            type="button"
            onClick={handleCopy}
            style={{
              flex: 1,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              gap: 8,
              background: isLight ? '#F0EFEA' : '#333333',
              color: 'var(--text-primary)',
              border: `1px solid ${isLight ? '#DCD9CF' : 'rgba(255,255,255,0.1)'}`,
              borderRadius: 12,
              cursor: 'pointer',
              fontSize: '13px',
              fontWeight: 600,
              padding: '10px 14px',
              fontFamily: 'Inter, sans-serif',
              transition: 'background 0.15s ease',
            }}
          >
            {copied ? (
              <>
                <Check size={16} color="var(--amber-exodo)" />
                <span style={{ color: 'var(--amber-exodo)' }}>{t.copied}</span>
              </>
            ) : (
              <>
                <Copy size={16} color="var(--text-secondary)" />
                <span>{t.copy}</span>
              </>
            )}
          </button>

          <button
            type="button"
            onClick={handleSendEmail}
            style={{
              flex: 1,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              gap: 8,
              background: 'var(--amber-exodo)',
              color: '#000000',
              border: 'none',
              borderRadius: 12,
              cursor: 'pointer',
              fontSize: '13px',
              fontWeight: 700,
              padding: '10px 14px',
              fontFamily: 'Inter, sans-serif',
            }}
          >
            <Send size={16} color="#000000" />
            <span>{t.send}</span>
          </button>
        </div>
      </div>
    </div>
  );
};
