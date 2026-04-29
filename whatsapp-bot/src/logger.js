// Logger trivial con timestamp ISO + nivel. Sin dependencias para
// mantener el bundle chico — para producción real conviene usar pino o
// winston, pero para una flota chica con un solo proceso esto alcanza.

function fmt(level, args) {
  const ts = new Date().toISOString();
  return [`[${ts}] [${level}]`, ...args];
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
