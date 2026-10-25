/**
 * What a Release build or the admin web's browser bundle could hand an attacker. Static
 * checks over the repo, so they run everywhere, with no stack and no Simulator:
 *
 * - "Find the test sign-in in a Release build": every Swift line that reaches test sign-in or
 *   reads a `GlowDebug*` launch argument sits inside `#if DEBUG`, so Release never compiles it.
 *   B9's release gate also greps the built binary (ios/fastlane, verify_release).
 * - "Find the service role key in the app or admin bundle": no file in ios/ holds a Supabase
 *   secret key or a service_role JWT; no admin web client component imports server modules or
 *   the env; and, when `next build` has run, no browser chunk holds a secret.
 */
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const ROOT = fileURLToPath(new URL('../../../', import.meta.url));
const SERVER = join(ROOT, 'server');

function walk(
  dir: string,
  keep: (path: string) => boolean,
  skip = /\/(build|node_modules|\.build|DerivedData|\.next|\.git)(\/|$)/,
): string[] {
  if (!existsSync(dir)) return [];
  const out: string[] = [];
  for (const name of readdirSync(dir)) {
    const path = join(dir, name);
    if (skip.test(path)) continue;
    const stat = statSync(path);
    if (stat.isDirectory()) out.push(...walk(path, keep, skip));
    else if (keep(path)) out.push(path);
  }
  return out;
}

/** Lines of Swift source, each with whether a `#if DEBUG` (and no `#else`) encloses it. */
function debugScopes(source: string): { line: string; n: number; debug: boolean }[] {
  const stack: boolean[] = [];
  return source.split('\n').map((line, i) => {
    const t = line.trim();
    if (/^#if\b/.test(t)) stack.push(/^#if\s+DEBUG\b/.test(t));
    else if (/^#else\b/.test(t) && stack.length) stack.push(!stack.pop());
    else if (/^#elseif\b/.test(t) && stack.length) {
      stack.pop();
      stack.push(false);
    } else if (/^#endif\b/.test(t)) stack.pop();
    return { line, n: i + 1, debug: stack.includes(true) };
  });
}

/**
 * Open findings in docs/SECURITY_REVIEW.md, each with its fix waiting on the owner. Delete the
 * entry when the fix merges; the test then holds the line.
 */
const KNOWN: Record<string, string> = {
  'ios/Packages/GlowKit/Sources/FeatureCheckIn/CaptureStep.swift': 'D2-F3',
};

const DEBUG_ONLY =
  /api\/dev\/test-login|signInForTesting\(|forKey:\s*"GlowDebug|GlowDebug\w*Fallback\(/;

describe('Release builds carry no test sign-in or debug hooks', () => {
  const swift = [
    ...walk(join(ROOT, 'ios/Glow'), (p) => p.endsWith('.swift')),
    ...walk(join(ROOT, 'ios/GlowLiveActivity'), (p) => p.endsWith('.swift')),
    ...walk(join(ROOT, 'ios/Packages/GlowKit/Sources'), (p) => p.endsWith('.swift')),
  ];

  it('finds the app sources', () => {
    expect(swift.length).toBeGreaterThan(50);
  });

  it('every use of test sign-in or a GlowDebug launch argument is inside #if DEBUG', () => {
    const outside: string[] = [];
    for (const file of swift) {
      for (const { line, n, debug } of debugScopes(readFileSync(file, 'utf8'))) {
        const code = line.replace(/\/\/.*$/, '');
        if (DEBUG_ONLY.test(code) && !debug && !KNOWN[relative(ROOT, file)])
          outside.push(`${relative(ROOT, file)}:${n}: ${line.trim()}`);
      }
    }
    expect(outside).toEqual([]);
  });
});

describe('No server secret reaches the app or the browser', () => {
  const SECRET_KEY = /sb_secret_[A-Za-z0-9_-]{16,}/;
  const jwtRoles = (text: string) =>
    [...text.matchAll(/eyJ[A-Za-z0-9_-]{10,}\.(eyJ[A-Za-z0-9_-]{10,})\.[A-Za-z0-9_-]{10,}/g)].map(
      (m) => {
        try {
          return (JSON.parse(Buffer.from(m[1]!, 'base64url').toString('utf8')) as { role?: string })
            .role;
        } catch {
          return undefined;
        }
      },
    );

  it('no file in ios/ holds a Supabase secret key or a service_role JWT', () => {
    // B9's release gate keeps test fixtures of what it refuses; those aren't keys.
    const files = walk(
      join(ROOT, 'ios'),
      (p) => !/\.(png|jpg|jpeg|heic|mp4|mov|car|a)$/i.test(p),
    ).filter((p) => !p.includes('/fastlane/'));
    const found: string[] = [];
    for (const file of files) {
      const text = readFileSync(file, 'latin1');
      if (SECRET_KEY.test(text) || jwtRoles(text).includes('service_role'))
        found.push(relative(ROOT, file));
    }
    expect(found).toEqual([]);
  });

  it('admin web client components import no server module and no env', () => {
    const clients = walk(join(SERVER, 'app'), (p) => /\.(tsx?|jsx?)$/.test(p)).filter((p) =>
      /^\s*['"]use client['"]/m.test(readFileSync(p, 'utf8')),
    );
    expect(clients.length).toBeGreaterThan(0);
    const bad: string[] = [];
    for (const file of clients) {
      for (const line of readFileSync(file, 'utf8').split('\n')) {
        if (!/^\s*import\b/.test(line) || /^\s*import\s+type\b/.test(line)) continue;
        if (/from\s+['"](@\/env|@\/server\/|next\/headers|node:|@supabase\/)/.test(line)) {
          bad.push(`${relative(ROOT, file)}: ${line.trim()}`);
        }
      }
    }
    expect(bad).toEqual([]);
  });

  it('after `next build`, no browser chunk holds a secret', (ctx) => {
    const staticDir = join(SERVER, '.next/static');
    if (!existsSync(staticDir)) ctx.skip();
    const envFile = join(SERVER, '.env.local');
    const secrets = existsSync(envFile)
      ? readFileSync(envFile, 'utf8')
          .split('\n')
          .map((l) =>
            /^(SUPABASE_SERVICE_ROLE_KEY|CRON_SECRET|JOIN_TICKET_SECRET|CARD_URL_SECRET|ANTHROPIC_API_KEY|UPSTASH_REDIS_REST_TOKEN|APNS_PRIVATE_KEY)=(.+)$/.exec(
              l.trim(),
            ),
          )
          .filter((m): m is RegExpExecArray => !!m && m[2]!.replace(/['"]/g, '').length >= 16)
          .map((m) => m[2]!.replace(/^['"]|['"]$/g, ''))
      : [];
    const found: string[] = [];
    for (const file of walk(staticDir, () => true, /\/node_modules\//)) {
      const text = readFileSync(file, 'latin1');
      if (SECRET_KEY.test(text) || jwtRoles(text).includes('service_role'))
        found.push(relative(SERVER, file));
      for (const secret of secrets)
        if (text.includes(secret)) found.push(`${relative(SERVER, file)} (an env secret)`);
      if (/SUPABASE_SERVICE_ROLE_KEY|CRON_SECRET|JOIN_TICKET_SECRET|CARD_URL_SECRET/.test(text)) {
        found.push(`${relative(SERVER, file)} (a secret's name)`);
      }
    }
    expect(found).toEqual([]);
  });
});

describe('App analytics carry no personal data (P1, P2)', () => {
  const FORBIDDEN =
    /^(name|first_?name|last_?name|lat|lng|lon|latitude|longitude|coords?|coordinates?|location|accuracy|email|phone|birth\w*|photo|image|token|text|body|address|user_?id|match_?id|room_?id|card_?id|ticket|code)$/i;

  it('no analytics event is keyed by a name, coordinate, ID, token or text', () => {
    const files = walk(
      join(ROOT, 'ios'),
      (p) => p.endsWith('.swift') && !/\/(Tests|GlowTests|GlowUITests)\//.test(p),
    );
    const bad: string[] = [];
    let events = 0;
    for (const file of files) {
      const source = readFileSync(file, 'utf8');
      for (const m of source.matchAll(/AnalyticsEvent\(\s*"([a-z_]+)"/g)) {
        events++;
        // The call up to its closing line, which holds the event's [key: value] literal.
        const call = source.slice(m.index!, m.index! + 400).split(/\)\)\s*$/m)[0]!;
        for (const key of call.matchAll(/"([A-Za-z_]+)"\s*:/g)) {
          if (FORBIDDEN.test(key[1]!))
            bad.push(`${relative(ROOT, file)}: ${m[1]} has the key "${key[1]}"`);
        }
      }
    }
    expect(events).toBeGreaterThan(20);
    expect(bad).toEqual([]);
  });
});
