/**
 * Keeps AGENTS.md true as the repo grows:
 * - the rules and privacy invariants are still word for word from docs/BUILD_PLAN.md
 * - every file in git has an owner in the ownership map
 */
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const ROOT = fileURLToPath(new URL('../../..', import.meta.url));
const read = (path: string) => readFileSync(join(ROOT, path), 'utf8');

/** The text from `## {title}` up to the next `## ` heading. */
function section(markdown: string, title: string): string {
  const start = markdown.indexOf(`\n## ${title}\n`);
  if (start === -1) throw new Error(`no "## ${title}" section`);
  const rest = markdown.slice(start + 1);
  const end = rest.indexOf('\n## ', 4);
  return (end === -1 ? rest : rest.slice(0, end)).trimEnd();
}

const agents = read('AGENTS.md');

describe('AGENTS.md', () => {
  it.each(['Rules every agent follows', 'Privacy invariants'])(
    'copies "%s" word for word from the build plan',
    (title) => {
      expect(section(agents, title)).toBe(section(read('docs/BUILD_PLAN.md'), title));
    },
  );

  it('lists an owner for every file in git', () => {
    const map = section(agents, 'Ownership map');
    const listed = [...map.matchAll(/`([^`\s]+)`/g)]
      .map(([, path]) => path!)
      .filter((p) => p.includes('/') || p.includes('.'))
      .map((p) => p.replace(/\/\*\*$/, '/').replace(/\*.*$/, ''));

    const owned = (file: string) =>
      listed.some((p) => (p.endsWith('/') ? file.startsWith(p) : file === p)) ||
      // Module folders, owned by the module named in the iOS table.
      /^ios\/Packages\/GlowKit\/(Sources|Tests)\/[A-Za-z]+/.test(file) ||
      file.endsWith('Localizable.xcstrings');

    const files = execFileSync('git', ['ls-files', '--cached', '--others', '--exclude-standard'], {
      cwd: ROOT,
      encoding: 'utf8',
    })
      .split('\n')
      .filter(Boolean);
    expect(files.length).toBeGreaterThan(0);
    expect(files.filter((f) => !owned(f))).toEqual([]);
  });

  it('names an owner for every iOS module folder', () => {
    const map = section(agents, 'Ownership map');
    const files = execFileSync('git', ['ls-files', 'ios/Packages/GlowKit/Sources'], {
      cwd: ROOT,
      encoding: 'utf8',
    });
    const modules = new Set(
      [...files.matchAll(/^ios\/Packages\/GlowKit\/Sources\/([A-Za-z]+)\//gm)].map(([, m]) => m!),
    );
    const missing = [...modules].filter((m) => !new RegExp(`\\b${m}\\b`).test(map));
    expect(missing).toEqual([]);
  });
});
