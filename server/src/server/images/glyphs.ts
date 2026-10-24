/**
 * A 5 by 7 pixel font for the watermark: the viewer-code alphabet (A to Z without I and O,
 * 2 to 9) plus a dot. Drawn as SVG rectangles, so the watermark renders the same on every
 * machine and on Vercel, which has no system fonts for SVG text.
 */

const ROWS: Readonly<Record<string, readonly string[]>> = {
  A: ['.###.', '#...#', '#...#', '#####', '#...#', '#...#', '#...#'],
  B: ['####.', '#...#', '#...#', '####.', '#...#', '#...#', '####.'],
  C: ['.###.', '#...#', '#....', '#....', '#....', '#...#', '.###.'],
  D: ['####.', '#...#', '#...#', '#...#', '#...#', '#...#', '####.'],
  E: ['#####', '#....', '#....', '####.', '#....', '#....', '#####'],
  F: ['#####', '#....', '#....', '####.', '#....', '#....', '#....'],
  G: ['.###.', '#...#', '#....', '#.###', '#...#', '#...#', '.####'],
  H: ['#...#', '#...#', '#...#', '#####', '#...#', '#...#', '#...#'],
  J: ['..###', '...#.', '...#.', '...#.', '...#.', '#..#.', '.##..'],
  K: ['#...#', '#..#.', '#.#..', '##...', '#.#..', '#..#.', '#...#'],
  L: ['#....', '#....', '#....', '#....', '#....', '#....', '#####'],
  M: ['#...#', '##.##', '#.#.#', '#.#.#', '#...#', '#...#', '#...#'],
  N: ['#...#', '#...#', '##..#', '#.#.#', '#..##', '#...#', '#...#'],
  P: ['####.', '#...#', '#...#', '####.', '#....', '#....', '#....'],
  Q: ['.###.', '#...#', '#...#', '#...#', '#.#.#', '#..#.', '.##.#'],
  R: ['####.', '#...#', '#...#', '####.', '#.#..', '#..#.', '#...#'],
  S: ['.####', '#....', '#....', '.###.', '....#', '....#', '####.'],
  T: ['#####', '..#..', '..#..', '..#..', '..#..', '..#..', '..#..'],
  U: ['#...#', '#...#', '#...#', '#...#', '#...#', '#...#', '.###.'],
  V: ['#...#', '#...#', '#...#', '#...#', '#...#', '.#.#.', '..#..'],
  W: ['#...#', '#...#', '#...#', '#.#.#', '#.#.#', '#.#.#', '.#.#.'],
  X: ['#...#', '#...#', '.#.#.', '..#..', '.#.#.', '#...#', '#...#'],
  Y: ['#...#', '#...#', '.#.#.', '..#..', '..#..', '..#..', '..#..'],
  Z: ['#####', '....#', '...#.', '..#..', '.#...', '#....', '#####'],
  '2': ['.###.', '#...#', '....#', '...#.', '..#..', '.#...', '#####'],
  '3': ['#####', '...#.', '..#..', '...#.', '....#', '#...#', '.###.'],
  '4': ['...#.', '..##.', '.#.#.', '#..#.', '#####', '...#.', '...#.'],
  '5': ['#####', '#....', '####.', '....#', '....#', '#...#', '.###.'],
  '6': ['..##.', '.#...', '#....', '####.', '#...#', '#...#', '.###.'],
  '7': ['#####', '....#', '...#.', '..#..', '.#...', '.#...', '.#...'],
  '8': ['.###.', '#...#', '#...#', '.###.', '#...#', '#...#', '.###.'],
  '9': ['.###.', '#...#', '#...#', '.####', '....#', '...#.', '.##..'],
  '·': ['.....', '.....', '.....', '..#..', '.....', '.....', '.....'],
};

export const GLYPH_WIDTH = 5;
export const GLYPH_HEIGHT = 7;
/** One empty column between characters. */
export const GLYPH_ADVANCE = GLYPH_WIDTH + 1;

export function hasGlyph(char: string): boolean {
  return char in ROWS;
}

/**
 * SVG path data for `text`, one unit per font pixel, with its top left corner at (x, y).
 * Runs of lit pixels in a row become one rectangle, which keeps the path short.
 */
export function textPath(text: string, unit: number, x = 0, y = 0): string {
  const parts: string[] = [];
  [...text].forEach((char, index) => {
    const rows = ROWS[char];
    if (!rows) throw new Error('No glyph for a watermark character');
    const left = x + index * GLYPH_ADVANCE * unit;
    rows.forEach((row, r) => {
      let c = 0;
      while (c < row.length) {
        if (row[c] !== '#') {
          c += 1;
          continue;
        }
        let end = c;
        while (end < row.length && row[end] === '#') end += 1;
        parts.push(
          `M${left + c * unit} ${y + r * unit}h${(end - c) * unit}v${unit}h${-(end - c) * unit}z`,
        );
        c = end;
      }
    });
  });
  return parts.join('');
}

/** Width in units of `text`, without the trailing gap. */
export function textWidth(text: string): number {
  const n = [...text].length;
  return n === 0 ? 0 : n * GLYPH_ADVANCE - 1;
}
