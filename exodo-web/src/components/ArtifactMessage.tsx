import React, { useMemo, useState } from 'react';
import { createPortal } from 'react-dom';

/**
 * Paridad web de _AssistantContentWithArtifacts (móvil): divide el markdown
 * del assistant en segmentos de texto, bloques ```html y bloques
 * ```exodo-options; cada uno se renderiza como tarjeta de artefacto vivo o
 * como tarjeta de opciones seleccionables (estilo aclaración guiada).
 */
export const ArtifactMessageBody: React.FC<{
  content: string;
  renderMarkdown: (text: string) => React.ReactNode;
  isStreaming?: boolean;
  onPickOption?: (label: string) => void;
}> = ({ content, renderMarkdown, isStreaming }) => {
  const parts = useMemo(() => {
    const segs: Array<
      | { kind: 'text'; text: string }
      | { kind: 'artifact'; code: string }
      | { kind: 'options'; raw: string }
    > = [];
    const re = /```(html|exodo-options)\r?\n?([\s\S]*?)(?:```|$)/g;
    let last = 0;
    let m: RegExpExecArray | null;
    while ((m = re.exec(content)) !== null) {
      if (m.index > last) segs.push({ kind: 'text', text: content.slice(last, m.index) });
      if (m[1] === 'exodo-options') {
        // El cuestionario guiado vive en el COMPOSER (formulario paso a paso),
        // no en el chat: los segmentos de opciones no se pintan como burbuja.
        segs.push({ kind: 'options', raw: m[2] || '' });
      } else {
        segs.push({ kind: 'artifact', code: m[2] || '' });
      }
      last = m.index + m[0].length;
    }
    if (last < content.length) segs.push({ kind: 'text', text: content.slice(last) });
    return segs;
  }, [content]);

  return (
    <>
      {parts.map((p, i) =>
        p.kind === 'text' ? (
          <React.Fragment key={i}>{p.text.trim() ? renderMarkdown(p.text) : null}</React.Fragment>
        ) : p.kind === 'options' ? null : (
          <ArtifactCard key={i} code={p.code} isStreaming={isStreaming} />
        )
      )}
    </>
  );
};

/**
 * Extrae la tarjeta de aclaración guiada del contenido de un mensaje:
 * busca el ÚLTIMO bloque ```exodo-options (tolerante a fence sin cerrar) y
 * normaliza a {question, options, recommend|null}. null si no hay bloque o
 * el JSON aún está incompleto (streaming).
 */
export function extractOptionsForm(content: string): {
  question: string;
  options: string[];
  recommend: number | null;
} | null {
  if (!content) return null;
  // Tolerante a fence sin cerrar: los modelos a veces olvidan el ```
  // final; si el JSON parsea, el bloque es válido. En streaming el JSON
  // incompleto no parsea y devuelve null (nada se monta a medias).
  const re = /```exodo-options\r?\n?([\s\S]*?)(?:```|$)/g;
  let m: RegExpExecArray | null;
  let lastRaw: string | null = null;
  while ((m = re.exec(content)) !== null) lastRaw = m[1] || '';
  if (lastRaw == null) return null;
  try {
    const parsed = JSON.parse(lastRaw.trim()) as {
      question?: unknown;
      options?: unknown;
      recommend?: unknown;
      title?: unknown;
      questions?: unknown;
    };
    // Esquema nuevo: una pregunta por tarjeta + índice recomendado
    if (typeof parsed?.question === 'string' && Array.isArray(parsed?.options)) {
      const options = (parsed.options as unknown[])
        .filter((o): o is string => typeof o === 'string' && o.trim().length > 0)
        .slice(0, 6)
        .map((o) => o.trim());
      if (!parsed.question.trim() || options.length < 2) return null;
      const rec = typeof parsed.recommend === 'number' && parsed.recommend >= 0 && parsed.recommend < options.length
        ? parsed.recommend
        : null;
      return { question: parsed.question.trim(), options, recommend: rec };
    }
    // Legacy tolerado: esquema multi-pregunta viejo → primera pregunta
    if (Array.isArray(parsed?.questions)) {
      const first = (parsed.questions as unknown[])[0] as { question?: unknown; options?: unknown } | undefined;
      if (first && typeof first.question === 'string' && Array.isArray(first.options)) {
        const options = (first.options as unknown[])
          .filter((o): o is string => typeof o === 'string' && o.trim().length > 0)
          .slice(0, 6)
          .map((o) => o.trim());
        if (first.question.trim() && options.length >= 2) {
          return { question: first.question.trim(), options, recommend: null };
        }
      }
    }
    return null;
  } catch (_) {
    return null;
  }
}

const ArtifactCard: React.FC<{ code: string; isStreaming?: boolean }> = ({ code, isStreaming }) => {
  const [showCode, setShowCode] = useState(false);
  const [fullscreen, setFullscreen] = useState(false);
  const [copied, setCopied] = useState(false);
  const srcDoc = useMemo(
    () =>
      `<!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"><style>html,body{margin:0;padding:8px;font-family:'AnthropicSans',sans-serif;background:#FFFFFF;color:#171615;}</style></head><body>${code}</body></html>`,
    [code]
  );

  const copyCode = async () => {
    try {
      await navigator.clipboard.writeText(code);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch (_) {}
  };

  // Esc cierra pantalla completa (paridad visores nativos)
  React.useEffect(() => {
    if (!fullscreen) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setFullscreen(false);
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [fullscreen]);

  return (
    <div className="artifact-card" style={{ margin: '14px 0' }}>
      {/* El contenido inline se OCULTA mientras está ampliado: evita el doble
          render detrás del overlay y libera GPU (un solo iframe vivo). */}
      <div style={fullscreen ? { visibility: 'hidden' } : undefined}>
        <div className="artifact-card-header">
          <span className="artifact-card-title">Artefacto</span>
          <span style={{ display: 'flex', gap: 8 }}>
            {!isStreaming && code.trim() && (
              <button type="button" className="artifact-card-toggle" onClick={() => setFullscreen(true)}>
                Ampliar
              </button>
            )}
            <button type="button" className="artifact-card-toggle" onClick={() => setShowCode((v) => !v)}>
              {showCode ? 'Vista' : 'Código'}
            </button>
          </span>
        </div>
        {showCode ? (
          <pre className="artifact-code">
            <code>{code}</code>
          </pre>
        ) : isStreaming ? (
          <div className="artifact-generating">Construyendo visualización…</div>
        ) : (
          <iframe
            title="Artefacto Exodo"
            sandbox="allow-scripts"
            srcDoc={srcDoc}
            style={{ width: '100%', height: 340, border: 'none', borderRadius: '0 0 12px 12px', background: '#FFFFFF', display: 'block' }}
          />
        )}
      </div>
      {fullscreen &&
        // PORTAL a document.body: .msg-row anima transform (slideUpFade con
        // fill forwards) y un ancestro con transform vuelve position:fixed
        // relativo a la fila — el stage salía desplazado/cortado dentro del
        // bubble. El portal escapa del contexto y ancla al viewport real.
        createPortal(
          <div className="artifact-stage-backdrop" onClick={() => setFullscreen(false)}>
            <div
              className="artifact-stage-header"
              onClick={(e) => e.stopPropagation()}
            >
              <span className="artifact-stage-title">Artefacto</span>
              <span style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
                <button type="button" className="artifact-card-toggle" onClick={() => setShowCode((v) => !v)}>
                  {showCode ? 'Vista' : 'Código'}
                </button>
                <button type="button" className="artifact-card-toggle" onClick={copyCode}>
                  {copied ? '¡Copiado!' : 'Copiar'}
                </button>
                <button type="button" className="artifact-card-toggle" onClick={() => setFullscreen(false)}>
                  Cerrar
                </button>
              </span>
            </div>
            <div className="artifact-stage" onClick={(e) => e.stopPropagation()}>
              {showCode ? (
                <pre className="artifact-code" style={{ height: '100%', margin: 0, overflow: 'auto', borderRadius: 14 }}>
                  <code>{code}</code>
                </pre>
              ) : (
                <iframe
                  title="Artefacto Exodo (pantalla completa)"
                  sandbox="allow-scripts"
                  srcDoc={srcDoc}
                  style={{ width: '100%', height: '100%', border: 'none', borderRadius: 14, background: '#FFFFFF', display: 'block' }}
                />
              )}
            </div>
          </div>,
          document.body
        )}
    </div>
  );
};
