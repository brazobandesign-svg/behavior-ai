'use strict';

/**
 * ============================================================================
 * ingest_minerd.js — Pipeline de Ingesta y Vectorización RAG MINERD
 * ============================================================================
 *
 * Procesa los archivos PDF oficiales en docs_minerd/:
 *  1. Extrae el texto plano con documentExtractor.js.
 *  2. Segmenta en chunks semánticos (~1000 chars con solapamiento de 200).
 *  3. Genera embeddings de 1536 dimensiones con text-embedding-3-small (OpenAI).
 *  4. Inserta/actualiza minerd_documents y minerd_chunks en Supabase por lotes de 25.
 *  5. Muestra barra de progreso y reporte de ingesta.
 */

require('dotenv').config({ override: true });
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const OpenAI = require('openai');
const supabase = require('../src/config/supabase');
const { extractText } = require('../src/services/documentExtractor');

const DOCS_DIR = path.join(__dirname, '..', 'docs_minerd');
const CHUNK_SIZE = 1000;
const CHUNK_OVERLAP = 200;
const BATCH_SIZE = 25;
const EMBEDDING_MODEL = 'text-embedding-3-small';

// Mapeo canónico de nombres de archivo a metadatos oficiales del MINERD
const CANONICAL_DOCS = {
  'lge-66-97': {
    short_name: 'LGE-66-97',
    title: 'Ley General de Educación No. 66-97',
    doc_type: 'ley',
    version: '1997',
  },
  'ord-1-2021': {
    short_name: 'ORD-1-2021',
    title: 'Ordenanza 1-2021: Actualización y Adecuación Curricular',
    doc_type: 'ordenanza',
    version: '2021',
  },
  'dc-inic-2021': {
    short_name: 'DC-INIC-2021',
    title: 'Diseño Curricular Nivel Inicial (2021)',
    doc_type: 'diseno',
    version: '2021',
  },
  'dc-prim-1c-2021': {
    short_name: 'DC-PRIM-1C-2021',
    title: 'Diseño Curricular Nivel Primario 1.er Ciclo (1.° a 3.°)',
    doc_type: 'diseno',
    version: '2021',
  },
  'dc-prim-2c-2021': {
    short_name: 'DC-PRIM-2C-2021',
    title: 'Diseño Curricular Nivel Primario 2.do Ciclo (4.° a 6.°)',
    doc_type: 'diseno',
    version: '2021',
  },
  'dc-sec-1c-2021': {
    short_name: 'DC-SEC-1C-2021',
    title: 'Diseño Curricular Nivel Secundario 1.er Ciclo (1.° a 3.°)',
    doc_type: 'diseno',
    version: '2021',
  },
  'dc-sec-2c-2021-a': {
    short_name: 'DC-SEC-2C-2021-A',
    title: 'Diseño Curricular Nivel Secundario 2.do Ciclo Modalidad Académica',
    doc_type: 'diseno',
    version: '2021',
  },
  'dc-sec-2c-2021-t': {
    short_name: 'DC-SEC-2C-2021-T',
    title: 'Diseño Curricular Nivel Secundario 2.do Ciclo Modalidad Técnico-Profesional',
    doc_type: 'diseno',
    version: '2021',
  },
  'gea-2018': {
    short_name: 'GEA-2018',
    title: 'Guía de Evaluación de los Aprendizajes',
    doc_type: 'guia',
    version: '2018',
  },
  'gpd-2021': {
    short_name: 'GPD-2021',
    title: 'Guía para la Planificación Didáctica',
    doc_type: 'guia',
    version: '2021',
  },
  'gad-2019': {
    short_name: 'GAD-2019',
    title: 'Guía de Atención a la Diversidad y Adecuaciones Curriculares',
    doc_type: 'guia',
    version: '2019',
  },
  'pei': {
    short_name: 'PEI',
    title: 'Plan Estratégico Institucional MINERD',
    doc_type: 'plan',
    version: '2021',
  },
  'ri-2021': {
    short_name: 'RI-2021',
    title: 'Reglamento Interno del Docente',
    doc_type: 'reglamento',
    version: '2021',
  },
  'pei-guia': {
    short_name: 'PEI-GUIA',
    title: 'Guía para la Elaboración del Proyecto Educativo de Centro (PEC)',
    doc_type: 'guia',
    version: '2021',
  },
};

/**
 * Divide el texto en fragmentos semánticos respetando párrafos y solapamiento.
 */
function createSemanticChunks(text, targetSize = CHUNK_SIZE, overlap = CHUNK_OVERLAP) {
  if (!text || text.trim().length === 0) return [];

  const paragraphs = text.split(/\n\s*\n/).map((p) => p.trim()).filter(Boolean);
  const chunks = [];
  let current = '';

  for (const para of paragraphs) {
    if ((current.length + para.length + 2) <= targetSize) {
      current = current ? `${current}\n\n${para}` : para;
    } else {
      if (current) {
        chunks.push(current.trim());
        // Solapamiento: tomar los últimos 'overlap' caracteres para contexto
        const overlapStart = Math.max(0, current.length - overlap);
        const overlapText = current.substring(overlapStart);
        current = `${overlapText}\n\n${para}`;
      } else {
        // Párrafo muy largo: cortar por frases
        const sentences = para.split(/(?<=[.?!])\s+/);
        for (const s of sentences) {
          if ((current.length + s.length + 1) <= targetSize) {
            current = current ? `${current} ${s}` : s;
          } else {
            if (current) chunks.push(current.trim());
            current = s;
          }
        }
      }
    }
  }

  if (current.trim()) {
    chunks.push(current.trim());
  }

  return chunks;
}

/**
 * Heurística de extracción de metadatos pedagógicos a partir del texto del chunk.
 */
function extractGrado(text) {
  let m = text.match(/grado\s+(\d{1,2})\b/i);
  if (m) return m[1];
  m = text.match(/(\d{1,2})\s*[.°]?\s*(?:er|do|ro|to|avo)\s+grado\b/i);
  if (m) return m[1];
  m = text.match(/(\d{1,2})\s*[.°]\s+grado\b/i);
  if (m) return m[1];
  return null;
}

function extractSection(text) {
  const lines = text.split('\n').map((l) => l.trim()).filter(Boolean);
  for (const line of lines) {
    if (/^(cap[ií]tulo|art[ií]culo|t[ií]tulo|secci[oó]n|unidad|bloque|eje tem[aá]tico|competencia espec[ií]fica|indicadores? de logro|anexo)\b/i.test(line)) {
      return line.slice(0, 120);
    }
  }
  return null;
}

function extractChunkMetadata(text, docShortName) {
  const t = text.toLowerCase();
  const meta = {
    nivel: null,
    ciclo: null,
    grado: extractGrado(text),
    area_curricular: null,
    competencia_fundamental: [],
    confidence_label: 'medium',
    section: extractSection(text),
  };

  // Nivel
  if (docShortName.includes('INIC') || t.includes('nivel inicial') || t.includes('educación inicial')) {
    meta.nivel = 'inicial';
  } else if (docShortName.includes('PRIM') || t.includes('nivel primario') || t.includes('educación primaria')) {
    meta.nivel = 'primario';
  } else if (docShortName.includes('SEC') || t.includes('nivel secundario') || t.includes('educación secundaria')) {
    meta.nivel = 'secundario';
  } else {
    meta.nivel = 'transversal';
  }

  // Ciclo
  if (docShortName.includes('1C') || t.includes('primer ciclo') || t.includes('1.er ciclo') || t.includes('1er ciclo')) {
    meta.ciclo = '1er_ciclo';
  } else if (docShortName.includes('2C') || t.includes('segundo ciclo') || t.includes('2.do ciclo') || t.includes('2do ciclo')) {
    meta.ciclo = '2do_ciclo';
  } else {
    meta.ciclo = 'N/A';
  }

  // Competencias fundamentales
  const cfList = [
    'Comunicación',
    'Pensamiento Lógico, Creativo y Crítico',
    'Resolución de Problemas',
    'Científica y Tecnológica',
    'Ciudadana',
    'Cultural y Artística',
    'Emocional y Afectiva',
  ];
  for (const cf of cfList) {
    if (t.includes(cf.toLowerCase())) {
      meta.competencia_fundamental.push(cf);
    }
  }

  // Áreas curriculares
  const areas = ['Matemáticas', 'Lengua Española', 'Ciencias de la Naturaleza', 'Ciencias Sociales', 'Educación Artística', 'Educación Física', 'Formación Integral Humana y Religiosa', 'Lenguas Extranjeras'];
  for (const a of areas) {
    if (t.includes(a.toLowerCase())) {
      meta.area_curricular = a;
      break;
    }
  }

  if (t.includes('artículo') || t.includes('definición') || t.includes('ordenanza') || meta.competencia_fundamental.length > 0) {
    meta.confidence_label = 'high';
  }

  return meta;
}

/**
 * Genera embeddings por lotes usando OpenAI text-embedding-3-small.
 */
async function generateEmbeddingsBatch(texts, openaiClient) {
  if (!openaiClient) {
    throw new Error('OPENAI_API_KEY no está configurada en .env');
  }

  const response = await openaiClient.embeddings.create({
    model: EMBEDDING_MODEL,
    input: texts.map((t) => t.replace(/\n+/g, ' ').trim()),
  });

  return response.data.map((item) => item.embedding);
}

/**
 * Procesa un archivo PDF individual.
 */
async function processPdfFile(filePath, openaiClient) {
  const fileName = path.basename(filePath);
  const baseKey = path.parse(fileName).name.toLowerCase();
  const canonical = CANONICAL_DOCS[baseKey] || {
    short_name: baseKey.toUpperCase(),
    title: fileName.replace(/\.[^/.]+$/, ''),
    doc_type: 'guia',
    version: '2021',
  };

  console.log(`\n📄 Procesando: ${fileName} -> [${canonical.short_name}]`);
  const buffer = fs.readFileSync(filePath);
  const fileHash = crypto.createHash('sha256').update(buffer).digest('hex');

  // 1. Extraer texto
  const extractResult = await extractText(buffer, {
    mimeType: 'application/pdf',
    filename: fileName,
  });

  if (!extractResult.ok || !extractResult.text) {
    console.error(`  ❌ Error extrayendo texto de ${fileName}:`, extractResult.error?.message || 'Texto vacío');
    return { success: false, fileName, error: extractResult.error?.message };
  }

  console.log(`  ✓ Texto extraído: ${extractResult.stats.chars} caracteres (${extractResult.stats.durationMs} ms)`);

  // 2. Insertar / Actualizar documento canónico en minerd_documents
  if (!supabase) {
    throw new Error('Cliente Supabase no inicializado. Verifica SUPABASE_URL y SUPABASE_SERVICE_KEY.');
  }

  const { data: docData, error: docError } = await supabase
    .from('minerd_documents')
    .upsert(
      {
        short_name: canonical.short_name,
        title: canonical.title,
        doc_type: canonical.doc_type,
        version: canonical.version,
        file_hash: fileHash,
        status: 'active',
        language: 'es-DO',
        updated_at: new Date().toISOString(),
      },
      { onConflict: 'short_name' }
    )
    .select('id')
    .single();

  if (docError || !docData) {
    console.error(`  ❌ Error guardando minerd_documents:`, docError?.message);
    return { success: false, fileName, error: docError?.message };
  }

  const docId = docData.id;
  console.log(`  ✓ Documento registrado en BD: ID ${docId}`);

  // 3. Crear chunks semánticos
  const textChunks = createSemanticChunks(extractResult.text);
  console.log(`  ✓ Fragmentado en ${textChunks.length} chunks semánticos`);

  // Limpiar chunks previos de este documento para evitar duplicidad en re-ingesta
  await supabase.from('minerd_chunks').delete().eq('document_id', docId);

  // 4. Generar embeddings y subir en lotes de BATCH_SIZE
  let processed = 0;
  for (let i = 0; i < textChunks.length; i += BATCH_SIZE) {
    const batchTexts = textChunks.slice(i, i + BATCH_SIZE);
    const embeddings = await generateEmbeddingsBatch(batchTexts, openaiClient);

    const chunkRows = batchTexts.map((chunkContent, batchIdx) => {
      const globalIdx = i + batchIdx;
      const meta = extractChunkMetadata(chunkContent, canonical.short_name);
      return {
        document_id: docId,
        chunk_index: globalIdx,
        content: chunkContent,
        content_tokens: Math.ceil(chunkContent.length / 4),
        embedding: JSON.stringify(embeddings[batchIdx]),
        nivel: meta.nivel,
        ciclo: meta.ciclo,
        grado: meta.grado,
        section: meta.section,
        area_curricular: meta.area_curricular,
        competencia_fundamental: meta.competencia_fundamental,
        confidence_label: meta.confidence_label,
      };
    });

    const { error: insertErr } = await supabase.from('minerd_chunks').insert(chunkRows);
    if (insertErr) {
      console.error(`  ❌ Error insertando lote ${i} a ${i + batchTexts.length}:`, insertErr.message);
      throw insertErr;
    }

    processed += batchTexts.length;
    const pct = Math.round((processed / textChunks.length) * 100);
    process.stdout.write(`  ⏳ Vectorizando y subiendo: ${processed}/${textChunks.length} (${pct}%)\r`);
  }

  console.log(`\n  ✅ ${textChunks.length} chunks insertados exitosamente en minerd_chunks.`);
  return { success: true, fileName, shortName: canonical.short_name, chunksCount: textChunks.length };
}

async function main() {
  console.log('\n╔════════════════════════════════════════════════════════════════╗');
  console.log('║       ÉXODO AI — PIPELINE DE INGESTA VECTORIAL MINERD          ║');
  console.log('╚════════════════════════════════════════════════════════════════╝\n');

  if (!fs.existsSync(DOCS_DIR)) {
    fs.mkdirSync(DOCS_DIR, { recursive: true });
  }

  const pdfFiles = fs
    .readdirSync(DOCS_DIR)
    .filter((f) => f.toLowerCase().endsWith('.pdf'))
    .map((f) => path.join(DOCS_DIR, f));

  if (pdfFiles.length === 0) {
    console.log(`⚠️  No se encontraron archivos PDF en: ${DOCS_DIR}`);
    console.log('Coloca los archivos PDF del currículo MINERD en esa carpeta y vuelve a ejecutar.\n');
    console.log('Consulta docs_minerd/README.md para ver los 14 nombres canónicos esperados.\n');
    return;
  }

  console.log(`Encontrados ${pdfFiles.length} archivo(s) PDF para procesar.\n`);

  const openaiKey = process.env.OPENAI_API_KEY;
  if (!openaiKey) {
    console.error('❌ Error: OPENAI_API_KEY no está configurada en .env.');
    console.error('Se requiere para generar embeddings de 1536 dimensiones (text-embedding-3-small).\n');
    process.exit(1);
  }

  const openaiClient = new OpenAI({ apiKey: openaiKey });
  const results = [];

  for (const pdfPath of pdfFiles) {
    try {
      const res = await processPdfFile(pdfPath, openaiClient);
      results.push(res);
    } catch (e) {
      console.error(`\n❌ Error fatal procesando ${path.basename(pdfPath)}:`, e.message);
      results.push({ success: false, fileName: path.basename(pdfPath), error: e.message });
    }
  }

  console.log('\n' + '═'.repeat(64));
  console.log('📊 RESUMEN FINAL DE INGESTA RAG:');
  console.log('═'.repeat(64));
  for (const r of results) {
    if (r.success) {
      console.log(`  ✅ [${r.shortName}] ${r.fileName} -> ${r.chunksCount} chunks`);
    } else {
      console.log(`  ❌ ${r.fileName} -> ERROR: ${r.error}`);
    }
  }
  console.log('═'.repeat(64) + '\n');
}

main().catch((err) => {
  console.error('[FATAL]', err);
  process.exit(1);
});
