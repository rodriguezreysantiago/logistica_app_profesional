// Logger trivial con timestamp local + nivel. Sin dependencias para
// mantener el bundle chico -- para produccion real conviene usar pino o
// winston, pero para una flota chica con un solo proceso esto alcanza.
//
// Antes usabamos new Date().toISOString() que SIEMPRE devuelve UTC
// (termina en Z). Eso confundia al admin porque tenia que restar 3 hs
// en la cabeza para entender cuando paso cada cosa. Ahora el timestamp
// va directamente en hora local del proceso (que esta forzada a TZ
// ART por process.env.TZ en index.js).

function _timestampLocal() {
  const d = new Date();
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  const hh = String(d.getHours()).padStart(2, '0');
  const mm = String(d.getMinutes()).padStart(2, '0');
  const ss = String(d.getSeconds()).padStart(2, '0');
  return `${day}-${m}-${y} ${hh}:${mm}:${ss}`;
}

function fmt(level, args) {
  return [`[${_timestampLocal()}] [${level}]`, ...args];
}

module.exports = {
  info: (...args) => console.log(...fmt('INFO', args)),
  warn: (...args) => console.warn(...fmt('WARN', args)),
  error: (...args) => console.error(...fmt('ERROR', args)),
  debug: (...args) => {
    if (process.env.DEBUG === '1' || process.env.DEBUG === 'true') {
      console.log(...fmt('DEBUG', args));
    }
  },
};
