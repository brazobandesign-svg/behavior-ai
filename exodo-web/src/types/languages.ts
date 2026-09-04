export interface LanguageOption {
  flag: string;
  title: string;
  subtitle: string;
  code: string | null;
}

export const EXODO_LANGUAGES: LanguageOption[] = [
  { flag: '🌐', title: 'System', subtitle: 'Auto-detect', code: null },
  { flag: '🇲🇽', title: 'Español (Latinoamérica)', subtitle: 'ES', code: 'es' },
  { flag: '🇺🇸', title: 'English (US)', subtitle: 'EN', code: 'en' },
  { flag: '🇬🇧', title: 'English (UK)', subtitle: 'EN_GB', code: 'en_GB' },
  { flag: '🇧🇷', title: 'Português (Brasil)', subtitle: 'PT_BR', code: 'pt_BR' },
  { flag: '🇵🇹', title: 'Português (Portugal)', subtitle: 'PT', code: 'pt' },
  { flag: '🇫🇷', title: 'Français', subtitle: 'FR', code: 'fr' },
  { flag: '🇭🇹', title: 'Kreyòl Ayisyen', subtitle: 'HT', code: 'ht' },
  { flag: '🇮🇹', title: 'Italiano', subtitle: 'IT', code: 'it' },
  { flag: '🇩🇪', title: 'Deutsch', subtitle: 'DE', code: 'de' },
  { flag: '🇷🇺', title: 'Русский', subtitle: 'RU', code: 'ru' },
  { flag: '🇨🇳', title: '中文', subtitle: 'ZH', code: 'zh' },
  { flag: '🇯🇵', title: '日本語', subtitle: 'JA', code: 'ja' },
  { flag: '🇸🇦', title: 'العربية', subtitle: 'AR', code: 'ar' },
  { flag: '🇰🇷', title: '한국어', subtitle: 'KO', code: 'ko' },
  { flag: '🇮🇳', title: 'हिन्दी', subtitle: 'HI', code: 'hi' },
];
