import { describe, expect, it } from 'vitest';
import { zGlow } from '@/contracts';
import { CODE_WORDS } from '@/server/glow/words';

// Owner: C3. The rules the code words were picked by (C3-D1), so a later edit can't break them.

const words: readonly string[] = CODE_WORDS;

/** The glow colors' names (contract GlowColor), which the app shows next to the word. */
const GLOW_COLORS: readonly string[] = zGlow.shape.color.options;

/** Everyday color words. */
const COLORS = [
  'red', 'orange', 'yellow', 'green', 'blue', 'purple', 'pink', 'black', 'white', 'gray', 'grey',
  'brown', 'gold', 'silver', 'amber', 'coral', 'ruby', 'jade', 'olive', 'mustard', 'salmon',
  'lemon', 'peach', 'cherry', 'plum', 'teal', 'navy', 'indigo', 'scarlet', 'emerald', 'sapphire',
]; // prettier-ignore

/**
 * Words that must never be a code word: romantic or suggestive, rude or slangy, insults, body
 * comments, and common first names. Not exhaustive (the list itself is hand-picked), but it stops
 * the obvious ones from creeping back in.
 */
const NEVER = [
  // Romantic or suggestive.
  'love', 'heart', 'kiss', 'honey', 'sweet', 'sweetie', 'darling', 'cupid', 'crush', 'flame', 'spark',
  'angel', 'babe', 'baby', 'cutie', 'sugar', 'candy', 'cupcake', 'muffin', 'cookie', 'pumpkin',
  'dumpling', 'valentine', 'wink', 'hug', 'cuddle', 'date', 'tulip', 'lilac', 'daisy', 'blossom',
  'petal', 'sonnet', 'ballad', 'lullaby', 'candle', 'velvet', 'oyster', 'banana', 'eggplant',
  'pickle', 'taco', 'melon', 'vanilla', 'fudge', 'cream', 'starling', 'plover', 'swallow', 'tango',
  'stork', 'trophy', 'zipper', 'pillow', 'blanket', 'quilt', 'bed',
  // Rude, slangy or insulting.
  'cougar', 'kitten', 'kitty', 'bunny', 'fox', 'foxy', 'stud', 'stallion', 'beaver', 'cock',
  'rooster', 'peacock', 'woodpecker', 'pussy', 'donkey', 'pig', 'cow', 'rat', 'snake', 'weasel',
  'skunk', 'shrimp', 'camel', 'cheetah', 'jackal', 'raccoon', 'coconut', 'snowflake', 'bear', 'cub',
  'otter', 'wolf',
  // Comments on a body.
  'hippo', 'walrus', 'whale', 'elephant', 'buffalo', 'mammoth', 'moose',
  // Sound like something else.
  'heron', 'ferry', 'fairy', 'cellar', 'celery', 'carrot', 'cymbal', 'prism', 'pigeon', 'lynx',
  'palette', 'scone', 'moose', 'flour', 'flower', 'knight', 'night',
  // Common first names.
  'robin', 'hazel', 'jasper', 'raven', 'willow', 'aspen', 'juniper', 'holly', 'ivy', 'iris',
  'lily', 'jasmine', 'poppy', 'ginger', 'basil', 'sage', 'autumn', 'summer', 'dawn', 'river',
  'heather', 'laurel', 'rowan', 'clementine',
]; // prettier-ignore

/** The word after its leading consonants: "rocket" and "pocket" both give "ocket", so they rhyme. */
const rime = (word: string) => word.replace(/^[^aeiouy]+/, '');

function editDistance(a: string, b: string): number {
  let previous = Array.from({ length: b.length + 1 }, (_, j) => j);
  for (let i = 1; i <= a.length; i++) {
    const current = [i];
    for (let j = 1; j <= b.length; j++) {
      current[j] = Math.min(
        previous[j]! + 1,
        current[j - 1]! + 1,
        previous[j - 1]! + (a[i - 1] === b[j - 1] ? 0 : 1),
      );
    }
    previous = current;
  }
  return previous[b.length]!;
}

function pairs(): [string, string][] {
  const out: [string, string][] = [];
  for (let i = 0; i < words.length; i++) {
    for (let j = i + 1; j < words.length; j++) out.push([words[i]!, words[j]!]);
  }
  return out;
}

describe('code words', () => {
  it('has exactly 300, each one once', () => {
    expect(words).toHaveLength(300);
    expect(new Set(words).size).toBe(300);
  });

  it('are short lowercase words the contract accepts', () => {
    const codeWord = zGlow.shape.codeWord;
    for (const word of words) {
      expect(word).toMatch(/^[a-z]{3,9}$/);
      expect(codeWord.safeParse(word).success).toBe(true);
    }
  });

  it('stay in alphabetical order', () => {
    expect([...words].sort()).toEqual(words);
  });

  it('never use a color, so the word never fights the glow color', () => {
    // "Sun" and "sundial" side by side is confusing, so glow colors can't appear anywhere in a
    // word. Everyday colors only can't be the whole word ("stingray" is fine).
    const found = words.filter(
      (word) => GLOW_COLORS.some((color) => word.includes(color)) || COLORS.includes(word),
    );
    expect(found).toEqual([]);
    expect(GLOW_COLORS).toContain('sun');
  });

  it('are nothing romantic, rude, insulting or a common first name', () => {
    expect(words.filter((word) => NEVER.includes(word))).toEqual([]);
  });

  it('never rhyme, differ by one letter, or contain each other, so they are hard to mishear', () => {
    const confusable = pairs().filter(
      ([a, b]) =>
        rime(a) === rime(b) ||
        editDistance(a, b) < 2 ||
        (a.length >= 4 && b.length >= 4 && (a.includes(b) || b.includes(a))),
    );
    expect(confusable).toEqual([]);
  });

  it('checks for confusable pairs correctly', () => {
    expect(rime('rocket')).toBe(rime('pocket'));
    expect(rime('noodle')).toBe(rime('doodle'));
    expect(editDistance('beagle', 'eagle')).toBe(1);
    expect(editDistance('canoe', 'kazoo')).toBeGreaterThanOrEqual(2);
  });
});
