#!/usr/bin/env node
// Owner: A1. Adds a 501 stub route for every operation in the generated contract that
// doesn't have one yet. Run it after a contract change adds endpoints (`pnpm stubs`).
// It never touches an export that already exists, so built endpoints are safe.
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, relative } from 'node:path';
import { ROOT, readOperations, routeFile } from './lib/contract-operations.mjs';

// Where each owner keeps handlers, for the comment at the top of a new route file.
const MODULE = {
  B1: 'src/server/profiles',
  B2: 'src/server/rooms',
  B3: 'src/server/images',
  B4: 'src/server/deck',
  B5: 'src/server/notify',
  B7: 'src/server/admin',
  B8: 'src/server/safety',
  C2: 'src/server/choice',
  C3: 'src/server/glow',
  C4: 'src/server/chat',
  E1: 'src/server/glow',
  E3: 'src/server/badges',
};

const ops = readOperations();
let created = 0;
let extended = 0;
for (const op of ops) {
  const file = routeFile(op.path);
  const exportLine = `export const ${op.method} = route('${op.id}', notImplemented);`;
  if (!existsSync(file)) {
    mkdirSync(dirname(file), { recursive: true });
    const where = MODULE[op.owner] ? ` that lives in \`server/${MODULE[op.owner]}\`` : '';
    writeFileSync(
      file,
      [
        `// Owner: ${op.owner}. Replace \`notImplemented\` with a handler${where}.`,
        `import { notImplemented, route } from '@/server/http';`,
        '',
        exportLine,
        '',
      ].join('\n'),
    );
    created++;
    console.log(`created  ${relative(ROOT, file)}  ${op.method} ${op.id} (${op.owner})`);
    continue;
  }
  const text = readFileSync(file, 'utf8');
  if (new RegExp(`export (const|async function|function) ${op.method}\\b`).test(text)) continue;
  writeFileSync(file, `${text.trimEnd()}\n${exportLine}\n`);
  extended++;
  console.log(`extended ${relative(ROOT, file)}  ${op.method} ${op.id} (${op.owner})`);
}
console.log(
  `stub-routes: ${ops.length} operations, ${created} files created, ${extended} extended.`,
);
