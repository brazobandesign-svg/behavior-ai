import React, { useMemo, useState } from 'react';

/**
 * Paridad web de _AssistantContentWithArtifacts (móvil): divide el markdown
 * del assistant en segmentos de texto y bloques ```html; cada bloque se
 * renderiza como tarjeta de artefacto con vista viva (iframe sandbox) y
 * toggle Vista/Código, igual que ArtifactCard en la app.
 */
export const ArtifactMessageBody: React.FC<{
  content: string;
  renderMarkdown: (text: string) => React.ReactNode;
  isStreaming?: boolean;
}> = ({ content, renderMarkdown, isStreaming }) => {
  const parts = useMemo(() => {
    const segs: Array<{ kind: 'text'; text: string } | { kind: 'artifact'; code: string }> = [];
    const re = /```html\r?\n?([\s\S]*?)(?:```|$)/g;
    let last = 0;
    let m: RegExpExecArray | null;
    while ((m = re.exec(content)) !== null) {
      if (m.index > last) segs.push({ kind: 'text', text: content.slice(last, m.index) });
      segs.push({ kind: 'artifact', code: m[1] || '' });
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
        ) : (
          <ArtifactCard key={i} code={p.code} isStreaming={isStreaming} />
        )
      )}
    </>
  );
};

const ArtifactCard: React.FC<{ code: string; isStreaming?: boolean }> = ({ code, isStreaming }) => {
  const [showCode, setShowCode] = useState(false);
  const srcDoc = useMemo(
    () =>
      `<!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"><style>html,body{margin:0;padding:8px;font-family:'AnthropicSans',sans-serif;background:#FFFFFF;color:#171615;}</style></head><body>${code}</body></html>`,
    [code]
  );

  return (
    <div className="artifact-card" style={{ margin: '14px 0' }}>
      <div className="artifact-card-header">
        <span className="artifact-card-title">Artefacto</span>
        <button type="button" className="artifact-card-toggle" onClick={() => setShowCode((v) => !v)}>
          {showCode ? 'Vista' : 'Código'}
        </button>
      </div>
      {showCode ? (
        <pre className="artifact-code">
          <code>{code}</code>
        </pre>
      ) : isStreaming ? (
        <div className="artifact-generating">Construyendo visualización…</div>
      ) : (
        <iframe
          title="Artefacto Éxodo"
          sandbox="allow-scripts"
          srcDoc={srcDoc}
          style={{ width: '100%', height: 340, border: 'none', borderRadius: '0 0 12px 12px', background: '#FFFFFF', display: 'block' }}
        />
      )}
    </div>
  );
};
