'use strict';

/**
 * ============================================================================
 * apply_migrations.js — Ejecutor automatizado de migraciones SQL
 * ============================================================================
 *
 * Lee y ejecuta en orden secuencial:
 *   1. src/data/migrations/001_stripe_idempotency.sql
 *   2. src/data/migrations/002_minerd_schema.sql
 *
 * Utiliza 'pg' (Pool) con DATABASE_URL o credenciales directas de PostgreSQL.
 * Cada archivo se ejecuta en una transacción atómica segura.
 */

require('dotenv').config({ override: true });
const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');

const MIGRATIONS = [
  {
    name: '001_stripe_idempotency.sql',
    path: path.join(__dirname, '..', 'src', 'data', 'migrations', '001_stripe_idempotency.sql'),
    description: 'Idempotencia Stripe (webhook_events) + transición atómica de suscripciones',
    expectedTables: ['webhook_events'],
    expectedFunctions: ['transition_subscription'],
  },
  {
    name: '002_minerd_schema.sql',
    path: path.join(__dirname, '..', 'src', 'data', 'migrations', '002_minerd_schema.sql'),
    description: 'Grounding RAG MINERD (minerd_documents, minerd_chunks, match_chunks, hybrid_search)',
    expectedTables: ['minerd_documents', 'minerd_chunks', 'minerd_query_log'],
    expectedFunctions: ['match_chunks', 'hybrid_search', 'minerd_chunks_update_tsv'],
  },
  {
    name: '003_published_artifacts.sql',
    path: path.join(__dirname, '..', 'src', 'data', 'migrations', '003_published_artifacts.sql'),
    description: 'Cloud Artifacts (published_artifacts, increment_views, RLS público/privado)',
    expectedTables: ['published_artifacts'],
    expectedFunctions: ['increment_views'],
  },
  {
    name: '004_expedientes.sql',
    path: path.join(__dirname, '..', 'src', 'data', 'migrations', '004_expedientes.sql'),
    description: 'Modulo Expedientes (expedientes, RLS auth.uid() = user_id)',
    expectedTables: ['expedientes'],
    expectedFunctions: [],
  },
];

async function main() {
  console.log('\n╔════════════════════════════════════════════════════════════════╗');
  console.log('║   ÉXODO AI — EJECUTOR DE MIGRACIONES POSTGRESQL / SUPABASE    ║');
  console.log('╚════════════════════════════════════════════════════════════════╝\n');

  const databaseUrl = process.env.DATABASE_URL;

  if (!databaseUrl) {
    console.log('⚠️  [ADVERTENCIA] Variable DATABASE_URL no encontrada en .env\n');
    console.log('Para ejecutar las migraciones automáticamente desde Node.js:');
    console.log('  1. Obtén la Connection String de tu proyecto Supabase:');
    console.log('     Settings -> Database -> Connection string -> URI');
    console.log('     Ejemplo: postgresql://postgres:[TU_PASSWORD]@db.[PROJECT_REF].supabase.co:5432/postgres');
    console.log('  2. Agrega DATABASE_URL a tu archivo .env');
    console.log('  3. Vuelve a ejecutar: node scripts/apply_migrations.js\n');
    console.log('─'.repeat(64));
    console.log('Archivos de migración listos para aplicar manualmente en Supabase SQL Editor:');
    for (const m of MIGRATIONS) {
      const exists = fs.existsSync(m.path);
      const size = exists ? fs.statSync(m.path).size : 0;
      console.log(`  • ${m.name} (${size} bytes) - [${exists ? 'DISPONIBLE' : 'NO ENCONTRADO'}]`);
      console.log(`    ${m.description}`);
    }
    console.log('─'.repeat(64) + '\n');
    return;
  }

  const pool = new Pool({
    connectionString: databaseUrl,
    ssl: databaseUrl.includes('localhost') || databaseUrl.includes('127.0.0.1')
      ? false
      : { rejectUnauthorized: false },
  });

  const client = await pool.connect();
  console.log('🔌 Conexión establecida con la base de datos PostgreSQL.\n');

  try {
    for (let i = 0; i < MIGRATIONS.length; i++) {
      const m = MIGRATIONS[i];
      console.log(`[${i + 1}/${MIGRATIONS.length}] Aplicando migración: ${m.name}...`);
      console.log(`    Descripción: ${m.description}`);

      if (!fs.existsSync(m.path)) {
        throw new Error(`Archivo no encontrado: ${m.path}`);
      }

      const sql = fs.readFileSync(m.path, 'utf8');
      const startTime = Date.now();

      await client.query('BEGIN');
      try {
        await client.query(sql);
        await client.query('COMMIT');
        const elapsed = Date.now() - startTime;
        console.log(`    ✅ Migración ${m.name} aplicada con éxito (${elapsed} ms)\n`);
      } catch (sqlErr) {
        await client.query('ROLLBACK');
        console.error(`    ❌ Error ejecutando ${m.name}:`, sqlErr.message);
        throw sqlErr;
      }
    }

    console.log('═'.repeat(64));
    console.log('✨ TODAS LAS MIGRACIONES FUERON APLICADAS EXITOSAMENTE');
    console.log('═'.repeat(64) + '\n');

    // Verificación de tablas y funciones creadas
    console.log('🔍 Verificando objetos creados en la base de datos:');
    
    // Tablas
    const allTables = MIGRATIONS.flatMap((m) => m.expectedTables);
    const tablesRes = await client.query(
      `SELECT table_name FROM information_schema.tables 
       WHERE table_schema = 'public' AND table_name = ANY($1::text[])`,
      [allTables]
    );
    const foundTables = new Set(tablesRes.rows.map((r) => r.table_name));
    for (const t of allTables) {
      console.log(`  • Tabla public.${t}: ${foundTables.has(t) ? '✅ EXISTE' : '⚠️ NO ENCONTRADA'}`);
    }

    // Funciones
    const allFuncs = MIGRATIONS.flatMap((m) => m.expectedFunctions);
    const funcsRes = await client.query(
      `SELECT routine_name FROM information_schema.routines 
       WHERE routine_schema = 'public' AND routine_name = ANY($1::text[])`,
      [allFuncs]
    );
    const foundFuncs = new Set(funcsRes.rows.map((r) => r.routine_name));
    for (const f of allFuncs) {
      console.log(`  • Función public.${f}(): ${foundFuncs.has(f) ? '✅ EXISTE' : '⚠️ NO ENCONTRADA'}`);
    }

    // Extensiones
    const extRes = await client.query(
      `SELECT extname FROM pg_extension WHERE extname IN ('vector', 'pg_trgm', 'pgcrypto')`
    );
    const foundExts = new Set(extRes.rows.map((r) => r.extname));
    console.log(`  • Extensión pgvector: ${foundExts.has('vector') ? '✅ ACTIVA' : '⚠️ NO INSTALADA'}`);
    console.log(`  • Extensión pg_trgm:  ${foundExts.has('pg_trgm') ? '✅ ACTIVA' : '⚠️ NO INSTALADA'}`);
    console.log(`  • Extensión pgcrypto: ${foundExts.has('pgcrypto') ? '✅ ACTIVA' : '⚠️ NO INSTALADA'}`);

    console.log('\n🎉 Base de datos lista para operar con RAG MINERD e Idempotencia Stripe.\n');
  } catch (err) {
    console.error('\n❌ ERROR DURANTE LA MIGRACIÓN:', err.message);
    process.exitCode = 1;
  } finally {
    client.release();
    await pool.end();
  }
}

main().catch((e) => {
  console.error('[FATAL]', e);
  process.exit(1);
});
