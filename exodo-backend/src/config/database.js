'use strict';

require('dotenv').config();
const { Pool } = require('pg');

// Cadena de conexión Postgres. Supabase expone una en Dashboard ->
// Settings -> Database -> Connection string. También acepta SUPABASE_DB_URL
// o POSTGRES_URL como alias.
const connectionString =
  process.env.DATABASE_URL ||
  process.env.SUPABASE_DB_URL ||
  process.env.POSTGRES_URL;

const pool = connectionString
  ? new Pool({
      connectionString,
      ssl: { rejectUnauthorized: false },
      max: 5,
    })
  : null;

if (!pool) {
  console.warn(
    '[database] DATABASE_URL / SUPABASE_DB_URL no configurado: el RPC transition_subscription no estará disponible.'
  );
}

module.exports = pool;
