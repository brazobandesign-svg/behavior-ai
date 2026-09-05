import React, { useMemo, useState } from 'react';

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
}> = ({ content, renderMarkdown, isStreaming, onPickOption }) => {
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
        ) : p.kind === 'options' ? (
          <OptionsCard key={i} raw={p.raw} isStreaming={isStreaming} onPick={onPickOption} />
        ) : (
          <ArtifactCard key={i} code={p.code} isStreaming={isStreaming} />
        )
      )}
    </>
  );
};

/**
 * Tarjeta de opciones seleccionables (estilo aclaración guiada): el backend
 * emite un bloque ```exodo-options con JSON {"question","options"}; el
 * usuario toca una opción y se envía como su mensaje. Si el JSON aún está
 * incompleto (streaming), no renderiza nada hasta que el fence cierre.
 */
const OptionsCard: React.FC<{
  raw: string;
  isStreaming?: boolean;
  onPick?: (label: string) => void;
}> = ({ raw, isStreaming, onPick }) => {
  const [picked, setPicked] = useState<string | null>(null);
  const data = useMemo<{ question: string; options: string[] } | null>(() => {
    try {
      const parsed = JSON.parse(raw.trim()) as { question?: unknown; options?: unknown };
      const question = typeof parsed?.question === 'string' ? parsed.question.trim() : '';
      const options = Array.isArray(parsed?.options)
        ? (parsed.options as unknown[])
            .filter((o): o is string => typeof o === 'string' && o.trim().length > 0)
            .slice(0, 6)
            .map((o) => o.trim())
        : [];
      if (!question || options.length === 0) return null;
      return { question, options };
    } catch (_) {
      return null;
    }
  }, [raw]);

  if (!data) return null;

  return (
    <div className="options-card" style={{ margin: '14px 0' }}>
      <div className="options-card-question">{data.question}</div>
      <div className="options-card-list">
        {data.options.map((opt) => {
          const isPicked = picked === opt;
          const disabled = Boolean(picked) || isStreaming;
          return (
            <button
              key={opt}
              type="button"
              disabled={disabled}
              className={`options-card-btn${isPicked ? ' picked' : ''}`}
              onClick={() => {
                if (disabled) return;
                setPicked(opt);
                onPick?.(opt);
              }}
            >
              <span className="options-card-label">{opt}</span>
              {isPicked && <span className="options-card-check">✓</span>}
            </button>
          );
        })}
      </div>
    </div>
  );
};

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

  return (
    <div className="artifact-card" style={{ margin: '14px 0' }}>
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
      {fullscreen && (
        <div
          style={{
            position: 'fixed', inset: 0, zIndex: 1000, background: 'rgba(0,0,0,0.75)',
            display: 'flex', flexDirection: 'column', padding: 16,
          }}
          onClick={() => setFullscreen(false)}
        >
          <div
            style={{
              display: 'flex', alignItems: 'center', gap: 8, marginBottom: 12,
              maxWidth: 960, width: '100%', marginLeft: 'auto', marginRight: 'auto',
            }}
            onClick={(e) => e.stopPropagation()}
          >
            <span style={{ color: '#F5F2EB', fontWeight: 700, flex: 1 }}>Artefacto</span>
            <button type="button" className="artifact-card-toggle" onClick={() => setShowCode((v) => !v)}>
              {showCode ? 'Vista' : 'Código'}
            </button>
            <button type="button" className="artifact-card-toggle" onClick={copyCode}>
              {copied ? '¡Copiado!' : 'Copiar'}
            </button>
            <button type="button" className="artifact-card-toggle" onClick={() => setFullscreen(false)}>
              Cerrar
            </button>
          </div>
          <div
            style={{ flex: 1, maxWidth: 960, width: '100%', marginLeft: 'auto', marginRight: 'auto', overflow: 'hidden', borderRadius: 12 }}
            onClick={(e) => e.stopPropagation()}
          >
            {showCode ? (
              <pre className="artifact-code" style={{ height: '100%', margin: 0, overflow: 'auto' }}>
                <code>{code}</code>
              </pre>
            ) : (
              <iframe
                title="Artefacto Exodo (pantalla completa)"
                sandbox="allow-scripts"
                srcDoc={srcDoc}
                style={{ width: '100%', height: '100%', minHeight: 400, border: 'none', borderRadius: 12, background: '#FFFFFF', display: 'block' }}
              />
            )}
          </div>
        </div>
      )}
    </div>
  );
};
