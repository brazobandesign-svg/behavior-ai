// src/config/systemPrompt.js
// Éxodo by Behavior — Configuración y Reglas Estrictas de Generación de Artefactos

'use strict';

const ARTIFACT_GENERATION_RULES = {
  domAutoInitialization: `
- DOM AUTO-INITIALIZATION (OBLIGATORIO):
  Todas las métricas, tarjetas KPI, resúmenes e indicadores iniciales (ej. % de asistencia, promedios generales, conteo de aprobados/reprobados, totales) DEBEN calcularse y renderizarse inmediatamente al cargar la página (DOMContentLoaded o ejecución inmediata de la función de cálculo).
  NUNCA dejes tarjetas KPI, etiquetas o campos de salida vacíos, en blanco o con guiones en el primer render.`,

  realTimeReactivity: `
- REACTIVIDAD EN TIEMPO REAL Y PROTECCIÓN ANTI-NAN (OBLIGATORIO):
  Vincula siempre los inputs numéricos o de cálculo usando addEventListener('input', ...) (o oninput).
  Implementa siempre parseo seguro con fallback: const val = parseFloat(input.value) || 0; para que los cálculos y promedios se actualicen fluidamente mientras el usuario escribe sin arrojar jamás NaN, null o undefined.`,

  fullDataCompleteness: `
- COMPLETITUD TOTAL DE DATOS Y CERO TABLAS TRUNCADAS (MINERD):
  Cuando se soliciten datos educativos, calificaciones o planificaciones del MINERD, SIEMPRE renderiza las 4 áreas curriculares fundamentales completas: Lengua Española, Matemática, Ciencias Sociales y Ciencias de la Naturaleza.
  Incluye listas de estudiantes completas con datos realistas y consistentes, sin dejar tablas cortadas, columnas vacías o filas a medias.`,

  activeTabState: `
- GESTIÓN LIMPIA DE PESTAÑAS Y ESTADOS (ACTIVE TAB STATE):
  La navegación por pestañas debe alternar limpiamente la visibilidad de los paneles (display: block / display: none o clase .active con display: block), actualizando las clases activas en los botones de navegación.
  Asegura que al cambiar de pestaña los cálculos, gráficos y el layout responsivo se mantengan sincronizados.`,

  webviewScriptExecution: `
- PATRÓN DE EJECUCIÓN DE SCRIPTS PARA WEBVIEW MÓVIL (CRÍTICO — INTERACTIVIDAD):
  Todo el JavaScript debe colocarse AL FINAL del <body>, envuelto en una función autoejecutable (function() { ... })(); — nunca depender exclusivamente de DOMContentLoaded ni de window.onload.
  Toda función interactiva debe adjuntarse al objeto global window (ej. window.switchTab = function(name) { ... };) y los elementos deben invocarla con handlers inline (onclick="window.switchTab('registro')") o delegación robusta sobre document.
  Ejecuta el cálculo inicial inmediatamente al final de la IIFE (window.init() o render directo): los KPI nunca deben mostrar 0 o estado vacío en el primer render.
  PROHIBIDO: scripts externos (CDN), type="module", import/export, require. Solo vanilla ES6 inline autocontenido.`,
};

const { buildSystemPrompt } = require('../prompts/groundingMinerd');

module.exports = {
  ARTIFACT_GENERATION_RULES,
  buildSystemPrompt,
};
