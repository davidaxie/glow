import { defineConfig, globalIgnores } from 'eslint/config';
import nextVitals from 'eslint-config-next/core-web-vitals';
import nextTs from 'eslint-config-next/typescript';
import prettier from 'eslint-config-prettier/flat';

export default defineConfig([
  ...nextVitals,
  ...nextTs,
  prettier,
  {
    rules: {
      // Use `logger` from src/server/log.ts, which redacts personal data (P2).
      'no-console': 'error',
      // Secrets and config come from getEnv() in src/env.ts, never process.env directly.
      'no-restricted-properties': [
        'error',
        {
          object: 'process',
          property: 'env',
          message: 'Read configuration through getEnv() from @/env.',
        },
      ],
      'no-restricted-imports': [
        'error',
        {
          patterns: [
            {
              group: ['**/contract-placeholder', '**/http/operations'],
              message: 'Import from @/server/http. The operation registry is internal to it.',
            },
          ],
        },
      ],
      '@typescript-eslint/no-unused-vars': [
        'error',
        { argsIgnorePattern: '^_', varsIgnorePattern: '^_' },
      ],
      '@typescript-eslint/consistent-type-imports': ['error', { disallowTypeAnnotations: false }],
    },
  },
  {
    files: [
      'src/env.ts',
      'next.config.ts',
      'instrumentation.ts',
      'src/server/log.ts',
      'src/server/observability.ts',
      'tests/**',
      'vitest.config.ts',
    ],
    rules: { 'no-restricted-properties': 'off' },
  },
  {
    files: ['src/server/log.ts', 'next.config.ts', 'tests/**'],
    rules: { 'no-console': 'off' },
  },
  {
    files: ['src/server/http/**', 'tests/**'],
    rules: { 'no-restricted-imports': 'off' },
  },
  globalIgnores([
    '.next/**',
    'out/**',
    'build/**',
    'coverage/**',
    'next-env.d.ts',
    'src/contracts/**',
  ]),
]);
