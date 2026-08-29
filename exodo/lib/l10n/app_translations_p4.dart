// P4 i18n (2026-08-28): límite de contexto de chat (banner urgente +
// exportar contexto HTML + reimporto) y privacidad (historial en la nube).
// Se fusionan sobre el mapa base en `translationsFor()` — mismo mecanismo
// que el parche P3. Español SÍ lleva parche aquí (claves nuevas para todos).
library;

const Map<String, String> kP4Es = <String, String>{
  'banner.context_limit_urgent':
      'Este chat casi alcanza su límite de mensajes y Éxodo ya no recordará el inicio. 1) Exporta el contexto (HTML) con lo esencial. 2) Inicia un chat nuevo. 3) Adjunta o pega el HTML ahí: Éxodo (o cualquier IA) retomará el hilo.',
  'banner.export_context': 'Exportar contexto',
  'banner.context_default_title': 'Conversación de Éxodo',
  'banner.context_transcript': 'Transcripción completa de la conversación',
  'banner.context_role_user': 'Tú',
  'banner.context_role_ai': 'Éxodo',
  'banner.context_reimport_hint':
      'Para continuar en un chat nuevo: adjunta o pega este archivo HTML y la IA retomará el contexto completo.',
  'settings.cloud_history': 'Guardar historial en la nube',
  'settings.cloud_history_desc':
      'Desactívalo para máxima privacidad: tus mensajes no se guardarán en ningún servidor ni en este dispositivo; al cerrar el chat desaparecen.',
};

const Map<String, String> kP4En = <String, String>{
  'banner.context_limit_urgent':
      'This chat is close to its message limit — Éxodo no longer recalls the beginning. 1) Export the context (HTML) with the essentials. 2) Start a new chat. 3) Attach or paste the HTML there: Éxodo (or any AI) will pick up the thread.',
  'banner.export_context': 'Export context',
  'banner.context_default_title': 'Éxodo conversation',
  'banner.context_transcript': 'Full conversation transcript',
  'banner.context_role_user': 'You',
  'banner.context_role_ai': 'Éxodo',
  'banner.context_reimport_hint':
      'To continue in a new chat: attach or paste this HTML file and the AI will pick up the full context.',
  'settings.cloud_history': 'Save history to cloud',
  'settings.cloud_history_desc':
      'Turn off for maximum privacy: your messages won\'t be stored on any server or on this device; they disappear when the chat closes.',
};

const Map<String, String> kP4Fr = <String, String>{
  'banner.context_limit_urgent':
      'Cette conversation approche sa limite de messages — Éxodo ne se souvient plus du début. 1) Exportez le contexte (HTML) avec l\'essentiel. 2) Ouvrez un nouveau chat. 3) Joignez ou collez le HTML là-bas : Éxodo (ou n\'importe quelle IA) reprendra le fil.',
  'banner.export_context': 'Exporter le contexte',
  'banner.context_default_title': 'Conversation Éxodo',
  'banner.context_transcript': 'Transcription complète de la conversation',
  'banner.context_role_user': 'Vous',
  'banner.context_role_ai': 'Éxodo',
  'banner.context_reimport_hint':
      'Pour continuer dans un nouveau chat : joignez ou collez ce fichier HTML et l\'IA reprendra tout le contexte.',
  'settings.cloud_history': 'Enregistrer l\'historique dans le cloud',
  'settings.cloud_history_desc':
      'Désactivez pour une confidentialité maximale : vos messages ne seront stockés sur aucun serveur ni sur cet appareil ; ils disparaissent à la fermeture du chat.',
};

const Map<String, String> kP4Ht = <String, String>{
  'banner.context_limit_urgent':
      'Diskisyon sa a pral rive limit mesaj li — Éxodo pa sonje kòmansman an kont. 1) Ekspòte kontèks la (HTML) ak bagay enpòtan yo. 2) Kòmanse yon nouvo chat. 3) Mete oswa kole HTML la la a: Éxodo (oswa nenpòt IA) pral kontinye fil la.',
  'banner.export_context': 'Ekspòte kontèks la',
  'banner.context_default_title': 'Konvèsasyon Éxodo',
  'banner.context_transcript': 'Transkripsyon konplè diskisyon an',
  'banner.context_role_user': 'Ou',
  'banner.context_role_ai': 'Éxodo',
  'banner.context_reimport_hint':
      'Pou kontinye nan yon nouvo chat: mete oswa kole fichye HTML sa a epi IA a pral pran tout kontèks la.',
  'settings.cloud_history': 'Kenbe istwa diskisyon an nan kloud la',
  'settings.cloud_history_desc':
      'Fèmen l pou privasite maksimòm: mesaj ou yo pa ap konsève nan okenn sèvè ni sou aparèy sa a; yo disparèt lè w fèmen chat la.',
};

const Map<String, String> kP4Pt = <String, String>{
  'banner.context_limit_urgent':
      'Esta conversa está perto do limite de mensagens — o Éxodo já não lembra o começo. 1) Exporte o contexto (HTML) com o essencial. 2) Inicie um novo chat. 3) Anexe ou cole o HTML lá: o Éxodo (ou qualquer IA) retomará o fio.',
  'banner.export_context': 'Exportar contexto',
  'banner.context_default_title': 'Conversa do Éxodo',
  'banner.context_transcript': 'Transcrição completa da conversa',
  'banner.context_role_user': 'Você',
  'banner.context_role_ai': 'Éxodo',
  'banner.context_reimport_hint':
      'Para continuar num novo chat: anexe ou cole este arquivo HTML e a IA retomará todo o contexto.',
  'settings.cloud_history': 'Salvar histórico na nuvem',
  'settings.cloud_history_desc':
      'Desative para privacidade máxima: suas mensagens não serão salvas em nenhum servidor nem neste aparelho; elas somem quando o chat fecha.',
};

const Map<String, String> kP4It = <String, String>{
  'banner.context_limit_urgent':
      'Questa chat sta per raggiungere il limite di messaggi — Éxodo non ricorda più l\'inizio. 1) Esporta il contesto (HTML) con l\'essenziale. 2) Avvia una nuova chat. 3) Allega o incolla lì il file HTML: Éxodo (o qualsiasi IA) riprenderà il filo.',
  'banner.export_context': 'Esporta contesto',
  'banner.context_default_title': 'Conversazione Éxodo',
  'banner.context_transcript': 'Trascrizione completa della conversazione',
  'banner.context_role_user': 'Tu',
  'banner.context_role_ai': 'Éxodo',
  'banner.context_reimport_hint':
      'Per continuare in una nuova chat: allega o incolla questo file HTML e l\'IA riprenderà tutto il contesto.',
  'settings.cloud_history': 'Salva cronologia nel cloud',
  'settings.cloud_history_desc':
      'Disattiva per la massima privacy: i tuoi messaggi non saranno salvati su alcun server né su questo dispositivo; scompaiono quando chiudi la chat.',
};

const Map<String, String> kP4De = <String, String>{
  'banner.context_limit_urgent':
      'Dieser Chat nähert sich dem Nachrichtenlimit — Éxodo erinnert sich nicht mehr an den Anfang. 1) Exportiere den Kontext (HTML) mit dem Wesentlichen. 2) Starte einen neuen Chat. 3) Hänge die HTML-Datei dort an: Éxodo (oder jede KI) nimmt den Faden wieder auf.',
  'banner.export_context': 'Kontext exportieren',
  'banner.context_default_title': 'Éxodo-Konversation',
  'banner.context_transcript': 'Vollständiges Gesprächsprotokoll',
  'banner.context_role_user': 'Du',
  'banner.context_role_ai': 'Éxodo',
  'banner.context_reimport_hint':
      'Um in einem neuen Chat fortzufahren: Hänge diese HTML-Datei an oder füge sie ein — die KI übernimmt den vollständigen Kontext.',
  'settings.cloud_history': 'Verlauf in der Cloud speichern',
  'settings.cloud_history_desc':
      'Für maximale Privatsphäre deaktivieren: Deine Nachrichten werden auf keinem Server und nicht auf diesem Gerät gespeichert; sie verschwinden, wenn der Chat geschlossen wird.',
};

const Map<String, String> kP4Ru = <String, String>{
  'banner.context_limit_urgent':
      'Этот чат приближается к лимиту сообщений — Éxodo уже не помнит начало. 1) Экспортируйте контекст (HTML) с главным. 2) Начните новый чат. 3) Прикрепите или вставьте HTML туда — Éxodo (или любой ИИ) продолжит нить разговора.',
  'banner.export_context': 'Экспортировать контекст',
  'banner.context_default_title': 'Диалог Éxodo',
  'banner.context_transcript': 'Полная транскрипция диалога',
  'banner.context_role_user': 'Вы',
  'banner.context_role_ai': 'Éxodo',
  'banner.context_reimport_hint':
      'Чтобы продолжить в новом чате: прикрепите или вставьте этот HTML-файл — ИИ подхватит весь контекст.',
  'settings.cloud_history': 'Сохранять историю в облаке',
  'settings.cloud_history_desc':
      'Отключите для максимальной конфиденциальности: ваши сообщения не сохраняются ни на сервере, ни на этом устройстве и исчезают при закрытии чата.',
};

const Map<String, String> kP4Zh = <String, String>{
  'banner.context_limit_urgent':
      '此对话即将达到消息上限 — Éxodo 已不再记得开头。1) 导出包含要点的上下文（HTML）。2) 开启新对话。3) 在新对话中附加或粘贴该 HTML：Éxodo（或任何 AI）将继续话题。',
  'banner.export_context': '导出上下文',
  'banner.context_default_title': 'Éxodo 对话',
  'banner.context_transcript': '完整对话记录',
  'banner.context_role_user': '用户',
  'banner.context_role_ai': 'Éxodo',
  'banner.context_reimport_hint': '要在新对话中继续：附加或粘贴此 HTML 文件，AI 将接管完整上下文。',
  'settings.cloud_history': '将历史记录保存到云端',
  'settings.cloud_history_desc':
      '关闭以获得最大隐私：您的消息不会保存在任何服务器或本设备上；关闭聊天后即消失。',
};

const Map<String, String> kP4Ja = <String, String>{
  'banner.context_limit_urgent':
      'このチャットはメッセージ上限に近づいています — Éxodo はもう冒頭を覚えていません。1) 要点をまとめたコンテキストをHTMLで書き出す。2) 新しいチャットを開始。3) そこにHTMLを添付・貼り付け：Éxodo（どんなAIでも）話を引き継ぎます。',
  'banner.export_context': 'コンテキストを書き出す',
  'banner.context_default_title': 'Éxodoの会話',
  'banner.context_transcript': '会話の完全な記録',
  'banner.context_role_user': 'あなた',
  'banner.context_role_ai': 'Éxodo',
  'banner.context_reimport_hint':
      '新しいチャットで続けるには：このHTMLファイルを添付・貼り付けすると、AIが完全な文脈を引き継ぎます。',
  'settings.cloud_history': '履歴をクラウドに保存',
  'settings.cloud_history_desc':
      'オフにすると最大限のプライバシーが得られます：メッセージはサーバーにもこの端末にも保存されず、チャットを閉じると消えます。',
};

const Map<String, String> kP4Ar = <String, String>{
  'banner.context_limit_urgent':
      'هذه المحادثة تقترب من حد الرسائل — لم يعد Éxodo يتذكر البداية. 1) صدّر السياق (HTML) مع النقاط المهمة. 2) ابدأ محادثة جديدة. 3) أرفق ملف HTML أو الصقه هناك — سيكمل Éxodo (أي ذكاء اصطناعي) السياق.',
  'banner.export_context': 'تصدير السياق',
  'banner.context_default_title': 'محادثة Éxodo',
  'banner.context_transcript': 'النص الكامل للمحادثة',
  'banner.context_role_user': 'أنت',
  'banner.context_role_ai': 'Éxodo',
  'banner.context_reimport_hint': 'للمتابعة في محادثة جديدة: أرفق ملف HTML هذا أو الصقه وسيكمل الذكاء الاصطناعي السياق كاملاً.',
  'settings.cloud_history': 'حفظ السجل في السحابة',
  'settings.cloud_history_desc':
      'أوقفه لأقصى خصوصية: لن تُحفظ رسائلك على أي خادم أو على هذا الجهاز، وتختفي عند إغلاق المحادثة.',
};

const Map<String, String> kP4Ko = <String, String>{
  'banner.context_limit_urgent':
      '이 채팅이 메시지 한도에 가까워지고 있습니다 — Éxodo가 더 이상 처음 부분을 기억하지 못합니다. 1) 핵심 내용을 HTML로 내보내세요. 2) 새 채팅을 시작하세요. 3) 그곳에 HTML을 첨부·붙여넣기 하세요: Éxodo(모든 AI)가 맥락을 이어갑니다.',
  'banner.export_context': '컨텍스트 내보내기',
  'banner.context_default_title': 'Éxodo 대화',
  'banner.context_transcript': '전체 대화 기록',
  'banner.context_role_user': '사용자',
  'banner.context_role_ai': 'Éxodo',
  'banner.context_reimport_hint': '새 채팅에서 계속하려면: 이 HTML 파일을 첨부하거나 붙여넣으면 AI가 전체 맥락을 이어받습니다.',
  'settings.cloud_history': '기록을 클라우드에 저장',
  'settings.cloud_history_desc':
      '끄면 최대한의 프라이버시를 제공합니다: 메시지는 어떤 서버나 이 기기에도 저장되지 않으며 채팅을 닫으면 사라집니다.',
};

const Map<String, String> kP4Hi = <String, String>{
  'banner.context_limit_urgent':
      'यह चैट संदेश सीमा के पास है — Éxodo अब शुरुआत याद नहीं रखता। 1) मुख्य बातें सहित संदर्भ (HTML) निर्यात करें। 2) नया चैट शुरू करें। 3) वहाँ HTML संलग्न या पेस्ट करें: Éxodo (कोई भी AI) संदर्भ जारी रखेगा।',
  'banner.export_context': 'संदर्भ निर्यात करें',
  'banner.context_default_title': 'Éxodo बातचीत',
  'banner.context_transcript': 'पूरी बातचीत का लिखित अंश',
  'banner.context_role_user': 'आप',
  'banner.context_role_ai': 'Éxodo',
  'banner.context_reimport_hint': 'नए चैट में जारी रखने के लिए: यह HTML फ़ाइल संलग्न या पेस्ट करें — AI पूरा संदर्भ ले लेगा।',
  'settings.cloud_history': 'इतिहास क्लाउड में सहेजें',
  'settings.cloud_history_desc':
      'अधिकतम गोपनीयता के लिए बंद करें: आपके संदेश किसी सर्वर या इस डिवाइस पर सहेजे नहीं जाएंगे; चैट बंद करने पर वे गायब हो जाएंगे।',
};
