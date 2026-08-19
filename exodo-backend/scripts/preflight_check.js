'use strict';

/**
 * ============================================================================
 * preflight_check.js — Diagnóstico de Infraestructura y Conectividad
 * ============================================================================
 *
 * 1. Verifica la presencia de variables esenciales en .env.
 * 2. Prueba la conexión con Supabase (SELECT count(*) FROM profiles, user_usage, etc.).
 * 3. Prueba la disponibilidad de tablas de RAG MINERD y Stripe.
 * 4. Prueba extensiones PostgreSQL si DATABASE_URL está disponible.
 * 5. Reporta un semáforo visual en consola (OK / PENDIENTE / ERROR).
 */

require('dotenv').config({ override: true });
const { createClient } = require('@supabase/supabase-js');

const COLORS = {
  reset: '\x1b[0m',
  bright: '\x1b[1m',
  dim: '\x1b[2m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  red: '\x1b[31m',
  cyan: '\x1b[36m',
  gold: '\x1b[38;2;201;147;58m',
};

const SYMBOLS = {
  ok: `${COLORS.green}🟢 [OK]${COLORS.reset}`,
  pending: `${COLORS.yellow}🟡 [PENDIENTE]${COLORS.reset}`,
  error: `${COLORS.red}🔴 [ERROR]${COLORS.reset}`,
  info: `${COLORS.cyan}ℹ️ [INFO]${COLORS.reset}`,
};

async function main() {
  console.log('\n╔════════════════════════════════════════════════════════════════╗');
  console.log(`║   ${COLORS.gold}ÉXODO AI — PREFLIGHT CHECK & DIAGNÓSTICO DE INFRAESTRUCTURA${COLORS.reset}  ║`);
  console.log('╚════════════════════════════════════════════════════════════════╝\n');

  let hasErrors = false;
  let hasPending = false;

  // ───────────────────────────────────────────────────────────────────────────
  // 1. VARIABLES DE ENTORNO
  // ───────────────────────────────────────────────────────────────────────────
  console.log(`${COLORS.bright}1. VARIABLES DE ENTORNO (.env):${COLORS.reset}`);

  const requiredVars = [
    { key: 'SUPABASE_URL', label: 'URL de Proyecto Supabase', critical: true },
    { key: 'SUPABASE_SERVICE_KEY', label: 'Service Role Key (Supabase)', critical: true },
    { key: 'DEEPSEEK_API_KEY', label: 'DeepSeek API Key (Texto/Razonamiento)', critical: true },
    { key: 'GEMINI_API_KEY', alias: 'GOOGLE_API_KEY', label: 'Google Gemini API Key (Visión/Fallback)', critical: true },
    { key: 'STRIPE_SECRET_KEY', label: 'Stripe Secret Key (Pagos)', critical: false },
    { key: 'STRIPE_WEBHOOK_SECRET', label: 'Stripe Webhook Secret (whsec_...)', critical: false },
    { key: 'DATABASE_URL', label: 'PostgreSQL Direct URL (Migraciones)', critical: false },
  ];

  for (const v of requiredVars) {
    const val = process.env[v.key] || (v.alias ? process.env[v.alias] : null);
    if (val && val.trim().length > 0) {
      const masked = val.length > 8
        ? `${val.substring(0, 4)}...${val.substring(val.length - 4)}`
        : '••••••••';
      console.log(`  ${SYMBOLS.ok} ${v.key.padEnd(24)} ${COLORS.dim}(${v.label}: ${masked})${COLORS.reset}`);
    } else if (v.critical) {
      console.log(`  ${SYMBOLS.error} ${v.key.padEnd(24)} ${COLORS.red}FALTA VARIABLE CRÍTICA${COLORS.reset} (${v.label})`);
      hasErrors = true;
    } else {
      console.log(`  ${SYMBOLS.pending} ${v.key.padEnd(24)} ${COLORS.yellow}No configurada (Opcional/Pendiente)${COLORS.reset} (${v.label})`);
      hasPending = true;
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 2. CONECTIVIDAD SUPABASE & TABLAS
  // ───────────────────────────────────────────────────────────────────────────
  console.log(`\n${COLORS.bright}2. CONECTIVIDAD CON SUPABASE REST API:${COLORS.reset}`);

  const supabaseUrl = process.env.SUPABASE_URL;
  const supabaseKey = process.env.SUPABASE_SERVICE_KEY;

  if (!supabaseUrl || !supabaseKey) {
    console.log(`  ${SYMBOLS.error} No se puede conectar a Supabase sin SUPABASE_URL y SUPABASE_SERVICE_KEY`);
  } else {
    try {
      const supabase = createClient(supabaseUrl, supabaseKey);
      const startTime = Date.now();

      // Test 1: Profiles (Tabla base de usuarios)
      const { count: profileCount, error: profileErr } = await supabase
        .from('profiles')
        .select('*', { count: 'exact', head: true });

      const latency = Date.now() - startTime;

      if (profileErr) {
        console.log(`  ${SYMBOLS.error} Conexión a Supabase falló: ${profileErr.message}`);
        hasErrors = true;
      } else {
        console.log(`  ${SYMBOLS.ok} Conexión a Supabase activa (Latencia: ${latency} ms)`);
        console.log(`  ${SYMBOLS.ok} Tabla 'profiles' accesible (${profileCount ?? 0} registros)`);
      }

      // Test 2: user_usage
      const { count: usageCount, error: usageErr } = await supabase
        .from('user_usage')
        .select('*', { count: 'exact', head: true });

      if (usageErr) {
        console.log(`  ${SYMBOLS.pending} Tabla 'user_usage': ${usageErr.message}`);
        hasPending = true;
      } else {
        console.log(`  ${SYMBOLS.ok} Tabla 'user_usage' accesible (${usageCount ?? 0} registros)`);
      }

      // Test 3: conversations
      const { count: convCount, error: convErr } = await supabase
        .from('conversations')
        .select('*', { count: 'exact', head: true });

      if (convErr) {
        console.log(`  ${SYMBOLS.pending} Tabla 'conversations': ${convErr.message}`);
        hasPending = true;
      } else {
        console.log(`  ${SYMBOLS.ok} Tabla 'conversations' accesible (${convCount ?? 0} registros)`);
      }

      // Test 4: webhook_events (Migración 001)
      const { count: webhookCount, error: webhookErr } = await supabase
        .from('webhook_events')
        .select('*', { count: 'exact', head: true });

      if (webhookErr) {
        console.log(`  ${SYMBOLS.pending} Tabla 'webhook_events' (Migración 001 Stripe): ${COLORS.yellow}Pendiente de migrar${COLORS.reset}`);
        hasPending = true;
      } else {
        console.log(`  ${SYMBOLS.ok} Tabla 'webhook_events' (Migración 001 Stripe): ${COLORS.green}Instalada${COLORS.reset} (${webhookCount ?? 0} eventos)`);
      }

      // Test 5: minerd_documents & minerd_chunks (Migración 002)
      const { count: docCount, error: docErr } = await supabase
        .from('minerd_documents')
        .select('*', { count: 'exact', head: true });

      if (docErr) {
        console.log(`  ${SYMBOLS.pending} Tabla 'minerd_documents' (Migración 002 RAG): ${COLORS.yellow}Pendiente de migrar${COLORS.reset}`);
        hasPending = true;
      } else {
        console.log(`  ${SYMBOLS.ok} Tabla 'minerd_documents' (Migración 002 RAG): ${COLORS.green}Instalada${COLORS.reset} (${docCount ?? 0} docs indexados)`);
      }

      const { count: chunkCount, error: chunkErr } = await supabase
        .from('minerd_chunks')
        .select('*', { count: 'exact', head: true });

      if (chunkErr) {
        console.log(`  ${SYMBOLS.pending} Tabla 'minerd_chunks' (Migración 002 RAG): ${COLORS.yellow}Pendiente de migrar${COLORS.reset}`);
        hasPending = true;
      } else {
        console.log(`  ${SYMBOLS.ok} Tabla 'minerd_chunks' (Migración 002 RAG): ${COLORS.green}Instalada${COLORS.reset} (${chunkCount ?? 0} chunks)`);
      }

      // Test 6: published_artifacts (Migración 003 Cloud Artifacts)
      const { count: artCount, error: artErr } = await supabase
        .from('published_artifacts')
        .select('*', { count: 'exact', head: true });

      if (artErr) {
        console.log(`  ${SYMBOLS.pending} Tabla 'published_artifacts' (Migración 003 Artifacts): ${COLORS.yellow}Pendiente de migrar${COLORS.reset}`);
        hasPending = true;
      } else {
        console.log(`  ${SYMBOLS.ok} Tabla 'published_artifacts' (Migración 003 Artifacts): ${COLORS.green}Instalada${COLORS.reset} (${artCount ?? 0} artefactos)`);
      }
    } catch (e) {
      console.log(`  ${SYMBOLS.error} Excepción al conectar con Supabase: ${e.message}`);
      hasErrors = true;
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 3. CONECTIVIDAD POSTGRES DIRECTA & EXTENSIONES
  // ───────────────────────────────────────────────────────────────────────────
  console.log(`\n${COLORS.bright}3. POSTGRESQL DIRECTO & EXTENSIONES (DATABASE_URL):${COLORS.reset}`);

  const databaseUrl = process.env.DATABASE_URL;
  if (!databaseUrl) {
    console.log(`  ${SYMBOLS.pending} DATABASE_URL no configurada en .env. Omitiendo verificación directa de pgvector.`);
    console.log(`  ${COLORS.dim}  (Nota: Para verificar extensiones directas, configura DATABASE_URL en .env)${COLORS.reset}`);
    hasPending = true;
  } else {
    try {
      const { Pool } = require('pg');
      const pool = new Pool({
        connectionString: databaseUrl,
        ssl: databaseUrl.includes('localhost') || databaseUrl.includes('127.0.0.1')
          ? false
          : { rejectUnauthorized: false },
      });

      const client = await pool.connect();
      console.log(`  ${SYMBOLS.ok} Conexión directa a PostgreSQL exitosa`);

      const extRes = await client.query(
        `SELECT extname, extversion FROM pg_extension WHERE extname IN ('vector', 'pg_trgm', 'pgcrypto')`
      );
      const exts = new Map(extRes.rows.map((r) => [r.extname, r.extversion]));

      console.log(`  • Extensión vector (pgvector): ${exts.has('vector') ? `${COLORS.green}✅ ACTIVA (v${exts.get('vector')})${COLORS.reset}` : `${COLORS.yellow}⚠️ NO INSTALADA${COLORS.reset}`}`);
      console.log(`  • Extensión pg_trgm (búsqueda): ${exts.has('pg_trgm') ? `${COLORS.green}✅ ACTIVA (v${exts.get('pg_trgm')})${COLORS.reset}` : `${COLORS.yellow}⚠️ NO INSTALADA${COLORS.reset}`}`);
      console.log(`  • Extensión pgcrypto:           ${exts.has('pgcrypto') ? `${COLORS.green}✅ ACTIVA (v${exts.get('pgcrypto')})${COLORS.reset}` : `${COLORS.yellow}⚠️ NO INSTALADA${COLORS.reset}`}`);

      client.release();
      await pool.end();
    } catch (dbErr) {
      console.log(`  ${SYMBOLS.error} Error conectando a PostgreSQL directo: ${dbErr.message}`);
      hasErrors = true;
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 4. RESUMEN EJECUTIVO / SEMÁFORO
  // ───────────────────────────────────────────────────────────────────────────
  console.log('\n' + '═'.repeat(64));
  if (hasErrors) {
    console.log(`${COLORS.red}${COLORS.bright}ESTADO GENERAL: 🔴 ATENCIÓN REQUERIDA (Errores detectados)${COLORS.reset}`);
    console.log('Revisa los campos marcados en rojo arriba antes de poner en producción.');
  } else if (hasPending) {
    console.log(`${COLORS.yellow}${COLORS.bright}ESTADO GENERAL: 🟡 OPERATIVO CON TAREAS PENDIENTES${COLORS.reset}`);
    console.log('El servidor puede arrancar, pero algunas funcionalidades (RAG / Pagos) tienen migraciones o configuraciones pendientes.');
  } else {
    console.log(`${COLORS.green}${COLORS.bright}ESTADO GENERAL: 🟢 INFRAESTRUCTURA 100% OPERATIVA Y VERIFICADA${COLORS.reset}`);
    console.log('Todas las conexiones, variables, extensiones y tablas están listas.');
  }
  console.log('═'.repeat(64) + '\n');
}

main().catch((err) => {
  console.error('[FATAL]', err);
  process.exit(1);
});
