module.exports = {
  root: true,
  env: {
    es6: true,
    node: true,
  },
  extends: [
    "eslint:recommended",
    "plugin:import/errors",
    "plugin:import/warnings",
    "plugin:import/typescript",
    "google",
    "plugin:@typescript-eslint/recommended",
  ],
  parser: "@typescript-eslint/parser",
  parserOptions: {
    project: ["tsconfig.json"],
    sourceType: "module",
  },
  ignorePatterns: [
    "/lib/**/*", // Ignora salidas del compilador.
    "/generated/**/*",
    ".eslintrc.js", // El propio config no está en tsconfig.json.
    "/test/**/*", // Tests usan node:test simple, no requieren lint
                  // typescript. El parser typescript-eslint exige que
                  // los archivos esten en tsconfig.json y no quiero
                  // sumar test/ al include de TS (compilaria tests
                  // a lib/ y se subirian al deploy).
  ],
  plugins: ["@typescript-eslint", "import"],
  rules: {
    "quotes": ["error", "double"],
    "import/no-unresolved": 0,
    "indent": ["error", 2],
    "object-curly-spacing": ["error", "always"],
    "max-len": ["warn", { code: 100 }],
    "require-jsdoc": 0,
    "valid-jsdoc": 0,
    "@typescript-eslint/no-unused-vars": ["warn"],
  },
};
