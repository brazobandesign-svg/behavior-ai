import React, { useState, useEffect, useMemo } from 'react';
import { 
  X, 
  Search, 
  FileText, 
  Table as TableIcon, 
  Code2, 
  Download, 
  Copy, 
  Trash2, 
  Check, 
  FolderLock,
  FolderArchive,
} from 'lucide-react';
import { supabase } from '../lib/supabase';

export interface ExpedienteItem {
  id: string;
  chat_id?: string;
  title: string;
  category: string; // 'documento' | 'tabla' | 'interactivo'
  file_format: string; // 'docx' | 'xlsx' | 'pdf' | 'html' | 'svg' | 'md'
  content_payload?: string;
  metadata?: Record<string, any>;
  created_at: string;
  updated_at?: string;
}

interface ExpedientesModalProps {
  isOpen: boolean;
  onClose: () => void;
  isGuestUser?: boolean;
  locale?: string;
  theme?: 'dark' | 'light';
}

type FilterCategory = 'all' | 'documento' | 'tabla' | 'interactivo';

const EXPEDIENTES_I18N: Record<string, Record<string, string>> = {
  es: {
    title: 'Expedientes y Archivos',
    subtitle: 'Tus documentos, tablas y artefactos generados en conversaciones.',
    search_hint: 'Buscar por título, formato o contenido...',
    filter_all: 'Todos',
    filter_docs: 'Documentos',
    filter_tables: 'Tablas',
    filter_interactive: 'Interactivos',
    empty_title: 'Sin expedientes todavía',
    empty_body: 'Los artefactos interactivos, documentos y tablas que generes con Exodo se archivarán aquí automáticamente.',
    guest_locked_title: 'Módulo de Expedientes',
    guest_locked_body: 'Inicia sesión con tu cuenta de Google para acceder a tus documentos, tablas y artefactos guardados en la nube.',
    copied: 'Copiado al portapapeles',
    downloaded: 'Descarga iniciada',
    delete_confirm: '¿Eliminar este expediente?',
    preview_title: 'Vista previa de expediente',
    code_view: 'Código',
    preview_view: 'Vista previa',
    close: 'Cerrar',
  },
  en: {
    title: 'Records & Files',
    subtitle: 'Your documents, tables, and artifacts generated in conversations.',
    search_hint: 'Search by title, format, or content...',
    filter_all: 'All',
    filter_docs: 'Documents',
    filter_tables: 'Tables',
    filter_interactive: 'Interactive',
    empty_title: 'No records yet',
    empty_body: 'Interactive artifacts, documents, and tables generated with Exodo will be automatically archived here.',
    guest_locked_title: 'Records Module',
    guest_locked_body: 'Sign in with your Google account to access your saved documents, tables, and cloud artifacts.',
    copied: 'Copied to clipboard',
    downloaded: 'Download started',
    delete_confirm: 'Delete this record?',
    preview_title: 'Record Preview',
    code_view: 'Code',
    preview_view: 'Preview',
    close: 'Close',
  },
};

export const ExpedientesModal: React.FC<ExpedientesModalProps> = ({
  isOpen,
  onClose,
  isGuestUser = false,
  locale = 'es',
  theme = 'dark',
}) => {
  const [items, setItems] = useState<ExpedienteItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [activeFilter, setActiveFilter] = useState<FilterCategory>('all');
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedPreview, setSelectedPreview] = useState<ExpedienteItem | null>(null);
  const [previewMode, setPreviewMode] = useState<'preview' | 'code'>('preview');
  const [toastMessage, setToastMessage] = useState<string | null>(null);

  const isLight = theme === 'light';
  const langKey = (locale || 'es').toLowerCase().startsWith('en') ? 'en' : 'es';
  const t = (key: string) => EXPEDIENTES_I18N[langKey]?.[key] || EXPEDIENTES_I18N.es[key] || key;

  const showToast = (msg: string) => {
    setToastMessage(msg);
    setTimeout(() => setToastMessage(null), 2500);
  };

  // Tecla Escape
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && isOpen) {
        if (selectedPreview) {
          setSelectedPreview(null);
        } else {
          onClose();
        }
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [isOpen, selectedPreview, onClose]);

  // Carga de expedientes desde Supabase
  useEffect(() => {
    if (!isOpen || isGuestUser) return;
    let isCancelled = false;

    const fetchExpedientes = async () => {
      setLoading(true);
      try {
        const { data, error } = await supabase
          .from('expedientes')
          .select('*')
          .order('created_at', { ascending: false });

        if (error) throw error;
        if (!isCancelled) {
          setItems(data || []);
        }
      } catch (err) {
        console.warn('Error fetching expedientes:', err);
      } finally {
        if (!isCancelled) setLoading(false);
      }
    };

    fetchExpedientes();
    return () => {
      isCancelled = true;
    };
  }, [isOpen, isGuestUser]);

  // Filtrado y búsqueda
  const filteredItems = useMemo(() => {
    return items.filter((item) => {
      const matchesFilter =
        activeFilter === 'all' || item.category?.toLowerCase() === activeFilter;
      if (!matchesFilter) return false;

      if (!searchQuery.trim()) return true;
      const q = searchQuery.toLowerCase().trim();
      const matchTitle = item.title?.toLowerCase().includes(q);
      const matchFormat = item.file_format?.toLowerCase().includes(q);
      const matchCategory = item.category?.toLowerCase().includes(q);
      const matchContent = item.content_payload?.toLowerCase().includes(q);

      return matchTitle || matchFormat || matchCategory || matchContent;
    });
  }, [items, activeFilter, searchQuery]);

  // Acciones sobre un expediente
  const handleCopy = (payload: string, e?: React.MouseEvent) => {
    if (e) e.stopPropagation();
    navigator.clipboard.writeText(payload);
    showToast(t('copied'));
  };

  const handleDownload = (item: ExpedienteItem, e?: React.MouseEvent) => {
    if (e) e.stopPropagation();
    const format = (item.file_format || 'txt').toLowerCase();
    const mimeMap: Record<string, string> = {
      html: 'text/html',
      svg: 'image/svg+xml',
      md: 'text/markdown',
      csv: 'text/csv',
      pdf: 'application/pdf',
      docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      xlsx: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    };

    const mime = mimeMap[format] || 'text/plain';
    const blob = new Blob([item.content_payload || ''], { type: mime });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `${item.title.replace(/\s+/g, '_')}.${format}`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
    showToast(t('downloaded'));
  };

  const handleDelete = async (id: string, e?: React.MouseEvent) => {
    if (e) e.stopPropagation();
    if (!window.confirm(t('delete_confirm'))) return;

    try {
      const { error } = await supabase.from('expedientes').delete().eq('id', id);
      if (error) throw error;
      setItems((prev) => prev.filter((i) => i.id !== id));
      if (selectedPreview?.id === id) {
        setSelectedPreview(null);
      }
    } catch (err) {
      console.error('Error eliminando expediente:', err);
    }
  };

  const getCategoryIcon = (cat: string) => {
    switch (cat?.toLowerCase()) {
      case 'documento':
        return <FileText size={18} color="#5C9CE6" />;
      case 'tabla':
        return <TableIcon size={18} color="#4CAF50" />;
      case 'interactivo':
      default:
        return <Code2 size={18} color="var(--amber-exodo)" />;
    }
  };

  if (!isOpen) return null;

  return (
    <div
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
          background: 'rgba(0, 0, 0, 0.72)',
          backdropFilter: 'blur(8px)',
          WebkitBackdropFilter: 'blur(8px)',
        }}
        onClick={onClose}
      />

      {/* Ventana de Trabajo Web Centrada */}
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="expedientes-modal-title"
        style={{
          position: 'relative',
          width: '100%',
          maxWidth: 960,
          height: '88vh',
          maxHeight: 820,
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
            padding: '18px 24px',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            borderBottom: `1px solid ${isLight ? '#EFECE6' : 'rgba(255, 255, 255, 0.07)'}`,
            gap: 16,
            flexWrap: 'wrap',
          }}
        >
          <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
            <div
              style={{
                width: 40,
                height: 40,
                borderRadius: 12,
                background: 'rgba(201, 147, 58, 0.15)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                color: 'var(--amber-exodo)',
              }}
            >
              <FolderArchive size={20} />
            </div>
            <div>
              <h2
                id="expedientes-modal-title"
                style={{
                  margin: 0,
                  fontSize: '19px',
                  fontWeight: 700,
                  fontFamily: 'Syne, sans-serif',
                  color: 'var(--text-primary)',
                  letterSpacing: '-0.2px',
                }}
              >
                {t('title')}
              </h2>
              <p
                style={{
                  margin: '2px 0 0 0',
                  fontSize: '12.5px',
                  color: 'var(--text-secondary)',
                  fontFamily: 'Inter, sans-serif',
                }}
              >
                {t('subtitle')}
              </p>
            </div>
          </div>

          <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
            {/* Buscador Integrado */}
            <div
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: 8,
                background: isLight ? '#F7F6F2' : '#262626',
                border: `1px solid ${isLight ? '#E5E2DA' : 'rgba(255, 255, 255, 0.08)'}`,
                borderRadius: 12,
                padding: '8px 14px',
                width: 240,
              }}
            >
              <Search size={15} color="var(--text-secondary)" />
              <input
                type="text"
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                placeholder={t('search_hint')}
                style={{
                  background: 'transparent',
                  border: 'none',
                  outline: 'none',
                  color: 'var(--text-primary)',
                  fontSize: '13px',
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
                    padding: 0,
                  }}
                >
                  <X size={14} />
                </button>
              )}
            </div>

            {/* Botón Cerrar */}
            <button
              type="button"
              onClick={onClose}
              style={{
                background: isLight ? '#F0EDE6' : 'rgba(255, 255, 255, 0.08)',
                border: 'none',
                borderRadius: 12,
                width: 36,
                height: 36,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                cursor: 'pointer',
                color: 'var(--text-secondary)',
                flexShrink: 0,
                transition: 'background 0.15s ease, color 0.15s ease',
              }}
              title={t('close')}
            >
              <X size={18} />
            </button>
          </div>
        </div>

        {/* Barra de Filtros por Categoría */}
        <div
          style={{
            padding: '12px 24px',
            display: 'flex',
            alignItems: 'center',
            gap: 8,
            borderBottom: `1px solid ${isLight ? '#EFECE6' : 'rgba(255, 255, 255, 0.06)'}`,
            background: isLight ? '#FCFBF8' : '#181818',
            overflowX: 'auto',
          }}
        >
          {(
            [
              { key: 'all', label: t('filter_all') },
              { key: 'documento', label: t('filter_docs') },
              { key: 'tabla', label: t('filter_tables') },
              { key: 'interactivo', label: t('filter_interactive') },
            ] as const
          ).map((filter) => {
            const isActive = activeFilter === filter.key;
            return (
              <button
                key={filter.key}
                type="button"
                onClick={() => setActiveFilter(filter.key)}
                style={{
                  background: isActive
                    ? 'var(--amber-exodo)'
                    : isLight
                    ? '#EFECE6'
                    : '#262626',
                  color: isActive ? '#000000' : 'var(--text-secondary)',
                  border: 'none',
                  borderRadius: 20,
                  padding: '6px 14px',
                  fontSize: '12.5px',
                  fontWeight: isActive ? 700 : 500,
                  fontFamily: 'Inter, sans-serif',
                  cursor: 'pointer',
                  transition: 'all 0.15s ease',
                  whiteSpace: 'nowrap',
                }}
              >
                {filter.label}
              </button>
            );
          })}

          <div style={{ marginLeft: 'auto', fontSize: '12px', color: 'var(--text-secondary)', fontFamily: 'Inter, sans-serif' }}>
            {filteredItems.length} {filteredItems.length === 1 ? 'archivo' : 'archivos'}
          </div>
        </div>

        {/* Estado Bloqueado para Invitados */}
        {isGuestUser ? (
          <div
            style={{
              flex: 1,
              display: 'flex',
              flexDirection: 'column',
              alignItems: 'center',
              justifyContent: 'center',
              padding: '40px 24px',
              textAlign: 'center',
            }}
          >
            <div
              style={{
                width: 64,
                height: 64,
                borderRadius: '50%',
                background: 'rgba(201, 147, 58, 0.15)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                marginBottom: 16,
              }}
            >
              <FolderLock size={32} color="var(--amber-exodo)" />
            </div>
            <h3
              style={{
                fontSize: '18px',
                fontWeight: 700,
                fontFamily: 'Syne, sans-serif',
                color: 'var(--text-primary)',
                margin: '0 0 8px 0',
              }}
            >
              {t('guest_locked_title')}
            </h3>
            <p
              style={{
                fontSize: '13.5px',
                color: 'var(--text-secondary)',
                fontFamily: 'Inter, sans-serif',
                maxWidth: 420,
                lineHeight: 1.45,
                margin: 0,
              }}
            >
              {t('guest_locked_body')}
            </p>
          </div>
        ) : loading ? (
          <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <span style={{ fontSize: '14px', color: 'var(--text-secondary)', fontFamily: 'Inter, sans-serif' }}>
              Cargando expedientes...
            </span>
          </div>
        ) : filteredItems.length === 0 ? (
          /* Estado Vacío */
          <div
            style={{
              flex: 1,
              display: 'flex',
              flexDirection: 'column',
              alignItems: 'center',
              justifyContent: 'center',
              padding: '40px 24px',
              textAlign: 'center',
            }}
          >
            <div
              style={{
                width: 64,
                height: 64,
                borderRadius: '50%',
                background: isLight ? '#F0EDE6' : '#262626',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                marginBottom: 16,
                color: 'var(--text-secondary)',
              }}
            >
              <FolderArchive size={30} />
            </div>
            <h3
              style={{
                fontSize: '18px',
                fontWeight: 700,
                fontFamily: 'Syne, sans-serif',
                color: 'var(--text-primary)',
                margin: '0 0 8px 0',
              }}
            >
              {t('empty_title')}
            </h3>
            <p
              style={{
                fontSize: '13.5px',
                color: 'var(--text-secondary)',
                fontFamily: 'Inter, sans-serif',
                maxWidth: 460,
                lineHeight: 1.45,
                margin: 0,
              }}
            >
              {t('empty_body')}
            </p>
          </div>
        ) : (
          /* Cuadrícula de Archivos / Expedientes */
          <div
            style={{
              flex: 1,
              overflowY: 'auto',
              padding: '20px 24px',
              display: 'grid',
              gridTemplateColumns: 'repeat(auto-fill, minmax(260px, 1fr))',
              gap: 14,
              alignContent: 'start',
            }}
          >
            {filteredItems.map((item) => (
              <div
                key={item.id}
                onClick={() => {
                  setSelectedPreview(item);
                  setPreviewMode('preview');
                }}
                style={{
                  background: isLight ? '#F7F6F2' : '#242424',
                  border: `1px solid ${isLight ? '#E8E5DC' : 'rgba(255, 255, 255, 0.06)'}`,
                  borderRadius: 16,
                  padding: '16px',
                  display: 'flex',
                  flexDirection: 'column',
                  gap: 12,
                  cursor: 'pointer',
                  transition: 'transform 0.15s ease, border-color 0.15s ease, box-shadow 0.15s ease',
                  userSelect: 'none',
                }}
                onMouseEnter={(e) => {
                  e.currentTarget.style.transform = 'translateY(-2px)';
                  e.currentTarget.style.borderColor = 'var(--amber-exodo)';
                  e.currentTarget.style.boxShadow = '0 6px 18px rgba(0,0,0,0.15)';
                }}
                onMouseLeave={(e) => {
                  e.currentTarget.style.transform = 'none';
                  e.currentTarget.style.borderColor = isLight ? '#E8E5DC' : 'rgba(255, 255, 255, 0.06)';
                  e.currentTarget.style.boxShadow = 'none';
                }}
              >
                {/* Header de la tarjeta */}
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                    <div
                      style={{
                        width: 32,
                        height: 32,
                        borderRadius: 8,
                        background: isLight ? '#FFFFFF' : '#1D1D1D',
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                      }}
                    >
                      {getCategoryIcon(item.category)}
                    </div>
                    <span
                      style={{
                        fontSize: '10px',
                        fontWeight: 700,
                        padding: '2px 6px',
                        borderRadius: 6,
                        background: isLight ? '#E2DFD6' : '#333333',
                        color: 'var(--text-secondary)',
                        textTransform: 'uppercase',
                        fontFamily: 'Inter, sans-serif',
                      }}
                    >
                      .{item.file_format || 'TXT'}
                    </span>
                  </div>

                  <span style={{ fontSize: '11px', color: 'var(--text-secondary)', fontFamily: 'Inter, sans-serif' }}>
                    {new Date(item.created_at).toLocaleDateString()}
                  </span>
                </div>

                {/* Título */}
                <h4
                  style={{
                    margin: 0,
                    fontSize: '14px',
                    fontWeight: 700,
                    fontFamily: 'Syne, sans-serif',
                    color: 'var(--text-primary)',
                    overflow: 'hidden',
                    textOverflow: 'ellipsis',
                    whiteSpace: 'nowrap',
                  }}
                >
                  {item.title}
                </h4>

                {/* Acciones de la Tarjeta */}
                <div
                  style={{
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'space-between',
                    paddingTop: 10,
                    borderTop: `1px solid ${isLight ? '#EFECE6' : 'rgba(255, 255, 255, 0.06)'}`,
                    marginTop: 'auto',
                  }}
                >
                  <div style={{ display: 'flex', gap: 6 }}>
                    <button
                      type="button"
                      onClick={(e) => handleCopy(item.content_payload || '', e)}
                      title={t('copied')}
                      style={{
                        background: 'none',
                        border: 'none',
                        cursor: 'pointer',
                        color: 'var(--text-secondary)',
                        padding: 4,
                      }}
                    >
                      <Copy size={15} />
                    </button>
                    <button
                      type="button"
                      onClick={(e) => handleDownload(item, e)}
                      title="Descargar archivo"
                      style={{
                        background: 'none',
                        border: 'none',
                        cursor: 'pointer',
                        color: 'var(--text-secondary)',
                        padding: 4,
                      }}
                    >
                      <Download size={15} />
                    </button>
                  </div>

                  <button
                    type="button"
                    onClick={(e) => handleDelete(item.id, e)}
                    title="Eliminar expediente"
                    style={{
                      background: 'none',
                      border: 'none',
                      cursor: 'pointer',
                      color: 'var(--text-secondary)',
                      padding: 4,
                    }}
                    onMouseEnter={(e) => (e.currentTarget.style.color = '#E05252')}
                    onMouseLeave={(e) => (e.currentTarget.style.color = 'var(--text-secondary)')}
                  >
                    <Trash2 size={15} />
                  </button>
                </div>
              </div>
            ))}
          </div>
        )}

        {/* Visor de Expediente Flotante (Lightbox) */}
        {selectedPreview && (
          <div
            style={{
              position: 'absolute',
              inset: 0,
              background: isLight ? '#FFFFFF' : '#181818',
              zIndex: 10,
              display: 'flex',
              flexDirection: 'column',
            }}
          >
            {/* Header del Visor */}
            <div
              style={{
                padding: '14px 20px',
                borderBottom: `1px solid ${isLight ? '#E5E2DA' : 'rgba(255, 255, 255, 0.08)'}`,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'space-between',
              }}
            >
              <div style={{ display: 'flex', alignItems: 'center', gap: 10, minWidth: 0 }}>
                {getCategoryIcon(selectedPreview.category)}
                <h3
                  style={{
                    margin: 0,
                    fontSize: '16px',
                    fontWeight: 700,
                    fontFamily: 'Syne, sans-serif',
                    color: 'var(--text-primary)',
                    overflow: 'hidden',
                    textOverflow: 'ellipsis',
                    whiteSpace: 'nowrap',
                  }}
                >
                  {selectedPreview.title}
                </h3>
              </div>

              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                {/* Selector de modo (Preview vs Code) */}
                <div
                  style={{
                    display: 'flex',
                    background: isLight ? '#EFECE6' : '#2A2A2A',
                    borderRadius: 10,
                    padding: 3,
                  }}
                >
                  <button
                    type="button"
                    onClick={() => setPreviewMode('preview')}
                    style={{
                      padding: '5px 12px',
                      borderRadius: 8,
                      border: 'none',
                      fontSize: '12px',
                      fontWeight: 600,
                      cursor: 'pointer',
                      background: previewMode === 'preview' ? 'var(--amber-exodo)' : 'transparent',
                      color: previewMode === 'preview' ? '#000000' : 'var(--text-secondary)',
                    }}
                  >
                    {t('preview_view')}
                  </button>
                  <button
                    type="button"
                    onClick={() => setPreviewMode('code')}
                    style={{
                      padding: '5px 12px',
                      borderRadius: 8,
                      border: 'none',
                      fontSize: '12px',
                      fontWeight: 600,
                      cursor: 'pointer',
                      background: previewMode === 'code' ? 'var(--amber-exodo)' : 'transparent',
                      color: previewMode === 'code' ? '#000000' : 'var(--text-secondary)',
                    }}
                  >
                    {t('code_view')}
                  </button>
                </div>

                <button
                  type="button"
                  onClick={() => handleCopy(selectedPreview.content_payload || '')}
                  style={{
                    padding: '6px 12px',
                    borderRadius: 10,
                    background: 'transparent',
                    border: `1px solid ${isLight ? '#DCD8CE' : 'rgba(255, 255, 255, 0.12)'}`,
                    color: 'var(--text-primary)',
                    cursor: 'pointer',
                    display: 'flex',
                    alignItems: 'center',
                    gap: 6,
                    fontSize: '12px',
                    fontWeight: 600,
                  }}
                >
                  <Copy size={13} />
                  <span>Copiar</span>
                </button>

                <button
                  type="button"
                  onClick={() => handleDownload(selectedPreview)}
                  style={{
                    padding: '6px 12px',
                    borderRadius: 10,
                    background: 'var(--amber-exodo)',
                    border: 'none',
                    color: '#000000',
                    cursor: 'pointer',
                    display: 'flex',
                    alignItems: 'center',
                    gap: 6,
                    fontSize: '12px',
                    fontWeight: 700,
                  }}
                >
                  <Download size={13} />
                  <span>Descargar</span>
                </button>

                <button
                  type="button"
                  onClick={() => setSelectedPreview(null)}
                  style={{
                    background: 'none',
                    border: 'none',
                    color: 'var(--text-secondary)',
                    cursor: 'pointer',
                    padding: 6,
                    display: 'flex',
                  }}
                  title={t('close')}
                >
                  <X size={20} />
                </button>
              </div>
            </div>

            {/* Contenedor del Preview */}
            <div style={{ flex: 1, overflow: 'hidden', position: 'relative' }}>
              {previewMode === 'preview' ? (
                selectedPreview.file_format === 'html' || selectedPreview.file_format === 'svg' ? (
                  <iframe
                    title="Live Artifact Preview"
                    srcDoc={selectedPreview.content_payload}
                    sandbox="allow-scripts allow-same-origin allow-modals"
                    style={{ width: '100%', height: '100%', border: 'none', background: '#FFFFFF' }}
                  />
                ) : (
                  <div
                    style={{
                      padding: 24,
                      overflowY: 'auto',
                      height: '100%',
                      fontFamily: 'Inter, sans-serif',
                      fontSize: '14px',
                      lineHeight: 1.6,
                      color: 'var(--text-primary)',
                      whiteSpace: 'pre-wrap',
                    }}
                  >
                    {selectedPreview.content_payload}
                  </div>
                )
              ) : (
                <textarea
                  readOnly
                  value={selectedPreview.content_payload}
                  style={{
                    width: '100%',
                    height: '100%',
                    background: isLight ? '#F9F8F5' : '#121212',
                    color: isLight ? '#191919' : '#00FF66',
                    fontFamily: 'monospace',
                    fontSize: '13px',
                    padding: 20,
                    border: 'none',
                    outline: 'none',
                    resize: 'none',
                    boxSizing: 'border-box',
                  }}
                />
              )}
            </div>
          </div>
        )}
      </div>

      {/* Toast Feedback */}
      {toastMessage && (
        <div
          style={{
            position: 'fixed',
            bottom: 24,
            left: '50%',
            transform: 'translateX(-50%)',
            background: '#1D1D1D',
            color: '#FFFFFF',
            padding: '10px 18px',
            borderRadius: 12,
            fontSize: '13px',
            fontWeight: 600,
            fontFamily: 'Inter, sans-serif',
            display: 'flex',
            alignItems: 'center',
            gap: 8,
            boxShadow: '0 8px 24px rgba(0,0,0,0.5)',
            border: '1px solid var(--amber-exodo)',
            zIndex: 1400,
          }}
        >
          <Check size={16} color="var(--amber-exodo)" />
          <span>{toastMessage}</span>
        </div>
      )}
    </div>
  );
};
