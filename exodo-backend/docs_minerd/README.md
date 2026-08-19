# Documentos Oficiales del MINERD (Corpus RAG Éxodo)

Coloca aquí los archivos PDF oficiales del Ministerio de Educación de la República Dominicana (MINERD) para ser procesados e indexados en el sistema vectorial de Supabase (`minerd_documents` y `minerd_chunks`).

---

## 📚 Listado Canónico de Documentos

El script de ingesta (`scripts/ingest_minerd.js`) mapea automáticamente los nombres de archivo a los siguientes códigos cortos oficiales:

| Código Corto | Documento Oficial | Tipo |
|---|---|---|
| **`LGE-66-97`** | Ley General de Educación No. 66-97 | Ley |
| **`ORD-1-2021`** | Ordenanza 1-2021 (Adecuación Curricular) | Ordenanza |
| **`DC-INIC-2021`** | Diseño Curricular Nivel Inicial (2021) | Diseño Curricular |
| **`DC-PRIM-1C-2021`** | Diseño Curricular Nivel Primario (1.er Ciclo: 1.° a 3.°) | Diseño Curricular |
| **`DC-PRIM-2C-2021`** | Diseño Curricular Nivel Primario (2.do Ciclo: 4.° a 6.°) | Diseño Curricular |
| **`DC-SEC-1C-2021`** | Diseño Curricular Nivel Secundario (1.er Ciclo: 1.° a 3.°) | Diseño Curricular |
| **`DC-SEC-2C-2021-A`** | Diseño Curricular Nivel Secundario (2.do Ciclo: Modalidad Académica) | Diseño Curricular |
| **`DC-SEC-2C-2021-T`** | Diseño Curricular Nivel Secundario (2.do Ciclo: Modalidad Técnico-Profesional) | Diseño Curricular |
| **`GEA-2018`** | Guía de Evaluación de los Aprendizajes | Guía Pedagógica |
| **`GPD-2021`** | Guía para la Planificación Didáctica | Guía Pedagógica |
| **`GAD-2019`** | Guía de Atención a la Diversidad y Adecuaciones Curriculares | Guía Pedagógica |
| **`PEI`** | Plan Estratégico Institucional MINERD | Plan |
| **`RI-2021`** | Reglamento Interno del Docente | Reglamento |
| **`PEI-GUIA`** | Guía para la Elaboración del Proyecto Educativo de Centro (PEC) | Guía |

---

## ⚙️ Ingesta Vectorial

Una vez colocados los archivos PDF en esta carpeta, ejecuta:

```bash
node scripts/ingest_minerd.js
```

El script:
1. Extrae el texto plano de cada PDF mediante `documentExtractor.js`.
2. Segmenta en chunks semánticos (~1000 caracteres con solapamiento de 200).
3. Genera embeddings de 1536 dimensiones con `text-embedding-3-small` (OpenAI).
4. Inserta los registros en `minerd_documents` y los chunks en `minerd_chunks` de Supabase por lotes de 25.
