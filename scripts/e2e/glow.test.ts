// Owner: D1. Unit tests for the end-to-end helpers: node --test scripts/e2e/
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { PrivacyWatch, freshEmail, isLocalUrl, loadEnv } from './glow.ts';
import { isStep } from './player-b.ts';

const A_ID = '7e570000-0000-4000-8000-0000000000aa';

test('the privacy watch catches the other user ID anywhere, in any case (P1)', () => {
  const watch = new PrivacyWatch();
  watch.watchUserId(A_ID);
  watch.check(
    'getDeck',
    JSON.stringify({ cards: [{ id: 'bbbbbbbb-0000-4000-8000-000000000001' }] }),
  );
  assert.deepEqual(watch.violations, []);
  watch.check('getMatch', JSON.stringify({ other: A_ID.toUpperCase() }));
  assert.deepEqual(watch.violations, ["getMatch: the other person's user ID"]);
});

test('the privacy watch allows the first name only in match routes', () => {
  const watch = new PrivacyWatch();
  watch.watchName('Avery');
  watch.check('getMatch', JSON.stringify({ firstName: 'Avery' }));
  watch.check('listMatches', JSON.stringify({ matches: [{ firstName: 'Avery' }] }));
  assert.deepEqual(watch.violations, []);
  watch.check('getDeck', JSON.stringify({ note: 'avery' }));
  assert.deepEqual(watch.violations, ["getDeck: the other person's first name outside a match"]);
});

test('names match whole words only, so a card ID or a longer word is not a sighting', () => {
  const watch = new PrivacyWatch();
  watch.watchName('Ann');
  watch.check('getDeck', JSON.stringify({ tag: 'annual', id: 'ann0000' }));
  assert.deepEqual(watch.violations, []);
});

test('only local servers are played against', () => {
  assert.ok(isLocalUrl('http://localhost:3121'));
  assert.ok(isLocalUrl('http://127.0.0.1:54421'));
  assert.ok(!isLocalUrl('https://glow.example.com'));
  assert.ok(!isLocalUrl('http://localhost.example.com'));
  assert.throws(() => loadEnv('https://glow.example.com'), /local servers only/);
});

test('fresh test addresses are unique and at glow.test', () => {
  const one = freshEmail('b');
  assert.match(one, /^b-[0-9a-f]{8}@glow\.test$/);
  assert.notEqual(one, freshEmail('b'));
});

test('player B knows its steps', () => {
  assert.ok(isStep('tap'));
  assert.ok(isStep('metboth'));
  assert.ok(!isStep('pay'));
});
