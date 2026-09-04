import React, { useEffect } from 'react';
import { X, Keyboard } from 'lucide-react';

interface ShortcutsModalProps {
  isOpen: boolean;
  onClose: () => void;
  locale: string;
  theme?: 'dark' | 'light';
}

// ── i18n completo (16 idiomas, paridad con EXODO_LANGUAGES) ──
const SHORTCUTS_I18N: Record<string, Record<string, string>> = {
  es: {
    title: 'Atajos de teclado',
    subtitle: 'Navega más rápido con el teclado.',
    col_shortcut: 'Atajo',
    col_action: 'Acción',
    s_focus: 'Foco al compositor',
    s_close: 'Cerrar modal / panel activo',
    s_new: 'Nuevo chat',
    s_incog: 'Modo incógnito',
    s_theme: 'Cambiar tema (dark / light)',
    s_exped: 'Abrir expedientes',
    s_menu: 'Abrir / cerrar menú lateral',
    s_send: 'Enviar mensaje',
    s_search: 'Buscar chats',
    s_settings: 'Abrir configuración',
    s_shortcuts: 'Mostrar esta referencia',
    footer: 'Los atajos no se activan mientras escribes en el compositor.',
  },
  en: {
    title: 'Keyboard Shortcuts',
    subtitle: 'Navigate faster with the keyboard.',
    col_shortcut: 'Shortcut',
    col_action: 'Action',
    s_focus: 'Focus composer',
    s_close: 'Close active modal / panel',
    s_new: 'New chat',
    s_incog: 'Incognito mode',
    s_theme: 'Toggle theme (dark / light)',
    s_exped: 'Open shared artifacts',
    s_menu: 'Toggle sidebar menu',
    s_send: 'Send message',
    s_search: 'Search chats',
    s_settings: 'Open settings',
    s_shortcuts: 'Show this reference',
    footer: 'Shortcuts are disabled while typing in the composer.',
  },
  fr: {
    title: 'Raccourcis clavier',
    subtitle: 'Naviguez plus vite avec le clavier.',
    col_shortcut: 'Raccourci',
    col_action: 'Action',
    s_focus: 'Focus sur le compositeur',
    s_close: 'Fermer le modal / panneau actif',
    s_new: 'Nouvelle conversation',
    s_incog: 'Mode incognito',
    s_theme: 'Changer de thème (sombre / clair)',
    s_exped: 'Ouvrir les dossiers',
    s_menu: 'Ouvrir / fermer le menu latéral',
    s_send: 'Envoyer le message',
    s_search: 'Rechercher des conversations',
    s_settings: 'Ouvrir les paramètres',
    s_shortcuts: 'Afficher cette référence',
    footer: 'Les raccourcis sont désactivés pendant la saisie.',
  },
  pt: {
    title: 'Atalhos de teclado',
    subtitle: 'Navegue mais rápido com o teclado.',
    col_shortcut: 'Atalho',
    col_action: 'Ação',
    s_focus: 'Foco no compositor',
    s_close: 'Fechar modal / painel ativo',
    s_new: 'Nova conversa',
    s_incog: 'Modo incógnito',
    s_theme: 'Alternar tema (escuro / claro)',
    s_exped: 'Abrir expedientes',
    s_menu: 'Abrir / fechar menu lateral',
    s_send: 'Enviar mensagem',
    s_search: 'Pesquisar conversas',
    s_settings: 'Abrir configurações',
    s_shortcuts: 'Mostrar esta referência',
    footer: 'Os atalhos são desativados enquanto você digita.',
  },
  it: {
    title: 'Scorciatoie da tastiera',
    subtitle: 'Naviga più velocemente con la tastiera.',
    col_shortcut: 'Scorciatoia',
    col_action: 'Azione',
    s_focus: 'Focus sul compositore',
    s_close: 'Chiudi modale / pannello attivo',
    s_new: 'Nuova chat',
    s_incog: 'Modalità incognito',
    s_theme: 'Cambia tema (scuro / chiaro)',
    s_exped: 'Apri expedientes',
    s_menu: 'Apri / chiudi menu laterale',
    s_send: 'Invia messaggio',
    s_search: 'Cerca conversazioni',
    s_settings: 'Apri impostazioni',
    s_shortcuts: 'Mostra questo riferimento',
    footer: 'Le scorciatoie sono disattivate durante la digitazione.',
  },
  de: {
    title: 'Tastaturkürzel',
    subtitle: 'Navigieren Sie schneller mit der Tastatur.',
    col_shortcut: 'Kürzel',
    col_action: 'Aktion',
    s_focus: 'Fokus auf Eingabefeld',
    s_close: 'Aktives Modal / Panel schließen',
    s_new: 'Neuer Chat',
    s_incog: 'Inkognito-Modus',
    s_theme: 'Thema wechseln (dunkel / hell)',
    s_exped: 'Expedientes öffnen',
    s_menu: 'Seitenmenü öffnen / schließen',
    s_send: 'Nachricht senden',
    s_search: 'Chats suchen',
    s_settings: 'Einstellungen öffnen',
    s_shortcuts: 'Diese Referenz anzeigen',
    footer: 'Kürzel sind beim Tippen deaktiviert.',
  },
  ru: {
    title: 'Горячие клавиши',
    subtitle: 'Навигация быстрее с клавиатурой.',
    col_shortcut: 'Клавиша',
    col_action: 'Действие',
    s_focus: 'Фокус на поле ввода',
    s_close: 'Закрыть активное окно / панель',
    s_new: 'Новый чат',
    s_incog: 'Режим инкогнито',
    s_theme: 'Сменить тему (тёмная / светлая)',
    s_exped: 'Открыть экспедиенте',
    s_menu: 'Открыть / закрыть боковое меню',
    s_send: 'Отправить сообщение',
    s_search: 'Поиск чатов',
    s_settings: 'Открыть настройки',
    s_shortcuts: 'Показать справку',
    footer: 'Горячие клавиши отключены при вводе текста.',
  },
  zh: {
    title: '键盘快捷键',
    subtitle: '使用键盘更快速地导航。',
    col_shortcut: '快捷键',
    col_action: '操作',
    s_focus: '聚焦输入框',
    s_close: '关闭当前弹窗/面板',
    s_new: '新对话',
    s_incog: '隐身模式',
    s_theme: '切换主题（深色/浅色）',
    s_exped: '打开档案',
    s_menu: '打开/关闭侧边栏',
    s_send: '发送消息',
    s_search: '搜索对话',
    s_settings: '打开设置',
    s_shortcuts: '显示快捷键参考',
    footer: '在输入框中输入时快捷键不可用。',
  },
  ja: {
    title: 'キーボードショートカット',
    subtitle: 'キーボードでより速くナビゲート。',
    col_shortcut: 'ショートカット',
    col_action: 'アクション',
    s_focus: '入力欄にフォーカス',
    s_close: 'アクティブなモーダル/パネルを閉じる',
    s_new: '新しいチャット',
    s_incog: 'シークレットモード',
    s_theme: 'テーマ切替（ダーク/ライト）',
    s_exped: 'ファイルを開く',
    s_menu: 'サイドメニューの開閉',
    s_send: 'メッセージ送信',
    s_search: 'チャット検索',
    s_settings: '設定を開く',
    s_shortcuts: 'このリファレンスを表示',
    footer: '入力中はショートカットが無効になります。',
  },
  ar: {
    title: 'اختصارات لوحة المفاتيح',
    subtitle: 'تنقل أسرع باستخدام لوحة المفاتيح.',
    col_shortcut: 'اختصار',
    col_action: 'الإجراء',
    s_focus: 'التركيز على حقل الإدخال',
    s_close: 'إغلاق النافذة / اللوحة النشطة',
    s_new: 'محادثة جديدة',
    s_incog: 'وضع التصفح المتخفي',
    s_theme: 'تبديل السمة (داكن / فاتح)',
    s_exped: 'فتح الملفات',
    s_menu: 'فتح / إغلاق القائمة الجانبية',
    s_send: 'إرسال الرسالة',
    s_search: 'البحث في المحادثات',
    s_settings: 'فتح الإعدادات',
    s_shortcuts: 'عرض هذا المرجع',
    footer: 'الاختصارات معطلة أثناء الكتابة.',
  },
  ko: {
    title: '키보드 단축키',
    subtitle: '키보드로 더 빠르게 탐색하세요.',
    col_shortcut: '단축키',
    col_action: '동작',
    s_focus: '입력창에 포커스',
    s_close: '활성 모달/패널 닫기',
    s_new: '새 채팅',
    s_incog: '시크릿 모드',
    s_theme: '테마 전환 (다크/라이트)',
    s_exped: '파일 열기',
    s_menu: '사이드 메뉴 열기/닫기',
    s_send: '메시지 보내기',
    s_search: '채팅 검색',
    s_settings: '설정 열기',
    s_shortcuts: '이 참조 표시',
    footer: '입력 중에는 단축키가 비활성화됩니다.',
  },
  hi: {
    title: 'कीबोर्ड शॉर्टकट',
    subtitle: 'कीबोर्ड से तेज़ी से नेविगेट करें।',
    col_shortcut: 'शॉर्टकट',
    col_action: 'क्रिया',
    s_focus: 'कम्पोज़र पर फ़ोकस',
    s_close: 'सक्रिय मोडल / पैनल बंद करें',
    s_new: 'नई चैट',
    s_incog: 'गुप्त मोड',
    s_theme: 'थीम बदलें (डार्क / लाइट)',
    s_exped: 'एक्सपीडिएंट खोलें',
    s_menu: 'साइड मेनू खोलें / बंद करें',
    s_send: 'संदेश भेजें',
    s_search: 'चैट खोजें',
    s_settings: 'सेटिंग्स खोलें',
    s_shortcuts: 'यह संदर्भ दिखाएं',
    footer: 'टाइप करते समय शॉर्टकट अक्षम होते हैं।',
  },
  ht: {
    title: 'Rakousi klavye',
    subtitle: 'Navige pi vit ak klavye a.',
    col_shortcut: 'Rakousi',
    col_action: 'Aksyon',
    s_focus: 'Fòkis sou konpozitè a',
    s_close: 'Fèmen modal / pano aktif',
    s_new: 'Nouvo chat',
    s_incog: 'Mòd enkognito',
    s_theme: 'Chanje tèm (fonse / klè)',
    s_exped: 'Ouvri dosye',
    s_menu: 'Ouvri / fèmen meni lateral',
    s_send: 'Voye mesaj',
    s_search: 'Chèche chat',
    s_settings: 'Ouvri paramèt',
    s_shortcuts: 'Montre referans sa a',
    footer: 'Rakousi yo dezaktive pandan w ap tape.',
  },
};

// Mapa de atajos — la fuente de verdad compartida con el hook global
export const SHORTCUT_ENTRIES = [
  { keys: ['/'],                action: 's_focus' },
  { keys: ['Esc'],              action: 's_close' },
  { keys: ['Alt', 'N'],         action: 's_new' },
  { keys: ['Alt', 'I'],         action: 's_incog' },
  { keys: ['Alt', 'D'],         action: 's_theme' },
  { keys: ['Alt', 'E'],         action: 's_exped' },
  { keys: ['Alt', 'M'],         action: 's_menu' },
  { keys: ['Ctrl', 'Enter'],    action: 's_send' },
  { keys: ['Ctrl', 'Shift', 'S'], action: 's_search' },
  { keys: ['Alt', 'S'],         action: 's_settings' },
  { keys: ['Alt', '?'],         action: 's_shortcuts' },
] as const;

const KeyBadge: React.FC<{ label: string; isLight: boolean }> = ({ label, isLight }) => (
  <span
    style={{
      display: 'inline-flex',
      alignItems: 'center',
      justifyContent: 'center',
      minWidth: 28,
      height: 26,
      padding: '0 7px',
      borderRadius: 7,
      fontSize: '12px',
      fontWeight: 700,
      fontFamily: "'Inter', monospace",
      letterSpacing: '0.3px',
      color: isLight ? '#171615' : '#F5F2EB',
      background: isLight ? '#E8E5DE' : '#333333',
      border: `1px solid ${isLight ? '#D5D1C8' : '#444444'}`,
      boxShadow: isLight
        ? '0 1px 2px rgba(0,0,0,0.06), inset 0 -1px 0 rgba(0,0,0,0.08)'
        : '0 1px 2px rgba(0,0,0,0.3), inset 0 -1px 0 rgba(255,255,255,0.04)',
    }}
  >
    {label}
  </span>
);

export const ShortcutsModal: React.FC<ShortcutsModalProps> = ({
  isOpen,
  onClose,
  locale,
  theme = 'dark',
}) => {
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && isOpen) onClose();
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [isOpen, onClose]);

  if (!isOpen) return null;
  const isLight = theme === 'light';
  const langKey = (() => {
    const base = (locale || 'es').toLowerCase().split(/[-_]/)[0];
    return SHORTCUTS_I18N[base] ? base : 'es';
  })();
  const t = (key: string) => SHORTCUTS_I18N[langKey]?.[key] || SHORTCUTS_I18N.es[key] || key;

  return (
    <div style={{ position: 'fixed', inset: 0, zIndex: 1200 }}>
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

      {/* Sheet */}
      <div
        style={{
          position: 'absolute',
          left: 0,
          right: 0,
          bottom: 0,
          background: isLight ? '#FFFFFF' : '#1E1E1E',
          borderRadius: '28px 28px 0 0',
          padding: '12px 20px calc(28px + env(safe-area-inset-bottom, 0px))',
          maxWidth: 540,
          margin: '0 auto',
          maxHeight: '88vh',
          overflowY: 'auto',
          boxShadow: '0 -8px 32px rgba(0,0,0,0.4)',
          border: `1px solid ${isLight ? '#E5E5E5' : 'rgba(255,255,255,0.08)'}`,
          borderBottom: 'none',
        }}
      >
        {/* Handle */}
        <div
          style={{
            width: 36,
            height: 4,
            borderRadius: 2,
            background: 'var(--text-secondary)',
            opacity: 0.3,
            margin: '0 auto 16px auto',
          }}
        />

        {/* Header row */}
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            marginBottom: 6,
          }}
        >
          <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <Keyboard size={20} color="var(--amber-exodo)" />
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
            onClick={onClose}
            style={{
              background: 'none',
              border: 'none',
              cursor: 'pointer',
              padding: 6,
              borderRadius: 8,
              display: 'flex',
            }}
          >
            <X size={18} color="var(--text-secondary)" />
          </button>
        </div>

        <p
          style={{
            fontSize: '13px',
            color: 'var(--text-secondary)',
            fontFamily: 'Inter, sans-serif',
            margin: '0 0 18px 0',
          }}
        >
          {t('subtitle')}
        </p>

        {/* Table */}
        <div
          style={{
            background: isLight ? '#F5F4EF' : '#262626',
            borderRadius: 16,
            border: `1px solid ${isLight ? '#E6E4DD' : 'rgba(255,255,255,0.06)'}`,
            overflow: 'hidden',
          }}
        >
          {/* Header row */}
          <div
            style={{
              display: 'flex',
              padding: '10px 16px',
              borderBottom: `1px solid ${isLight ? '#E6E4DD' : 'rgba(255,255,255,0.06)'}`,
            }}
          >
            <span
              style={{
                flex: '0 0 180px',
                fontSize: '11px',
                fontWeight: 700,
                textTransform: 'uppercase',
                letterSpacing: '0.8px',
                color: 'var(--amber-exodo)',
                fontFamily: 'Inter, sans-serif',
              }}
            >
              {t('col_shortcut')}
            </span>
            <span
              style={{
                flex: 1,
                fontSize: '11px',
                fontWeight: 700,
                textTransform: 'uppercase',
                letterSpacing: '0.8px',
                color: 'var(--amber-exodo)',
                fontFamily: 'Inter, sans-serif',
              }}
            >
              {t('col_action')}
            </span>
          </div>

          {/* Rows */}
          {SHORTCUT_ENTRIES.map((entry, i) => (
            <div
              key={i}
              style={{
                display: 'flex',
                alignItems: 'center',
                padding: '10px 16px',
                borderBottom:
                  i < SHORTCUT_ENTRIES.length - 1
                    ? `1px solid ${isLight ? '#ECEAE3' : 'rgba(255,255,255,0.04)'}`
                    : 'none',
              }}
            >
              <div style={{ flex: '0 0 180px', display: 'flex', gap: 5, flexWrap: 'wrap' }}>
                {entry.keys.map((k, ki) => (
                  <React.Fragment key={ki}>
                    {ki > 0 && (
                      <span
                        style={{
                          color: 'var(--text-secondary)',
                          fontSize: '12px',
                          lineHeight: '26px',
                          opacity: 0.5,
                        }}
                      >
                        +
                      </span>
                    )}
                    <KeyBadge label={k} isLight={isLight} />
                  </React.Fragment>
                ))}
              </div>
              <span
                style={{
                  flex: 1,
                  fontSize: '13.5px',
                  fontWeight: 500,
                  color: 'var(--text-primary)',
                  fontFamily: 'Inter, sans-serif',
                }}
              >
                {t(entry.action)}
              </span>
            </div>
          ))}
        </div>

        {/* Footer note */}
        <p
          style={{
            fontSize: '11.5px',
            color: 'var(--text-secondary)',
            fontFamily: 'Inter, sans-serif',
            textAlign: 'center',
            margin: '14px 0 0 0',
            opacity: 0.7,
          }}
        >
          {t('footer')}
        </p>
      </div>
    </div>
  );
};
