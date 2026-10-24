/**
 * QR codes for posters and the display screen, drawn by the server so the browser never
 * needs a QR library. Error correction is Q (25%): a poster survives tape, glare and a
 * crease, and a screen survives a phone held at an angle.
 */
import QRCode from 'qrcode';

/** Quiet zone in modules on each side. The QR spec asks for 4. */
export const QUIET_ZONE = 4;

export type QrMatrix = {
  /** Modules per side, without the quiet zone. */
  readonly size: number;
  readonly isDark: (row: number, col: number) => boolean;
};

export function qrMatrix(text: string): QrMatrix {
  const { modules } = QRCode.create(text, { errorCorrectionLevel: 'Q' });
  return { size: modules.size, isDark: (row, col) => modules.get(row, col) === 1 };
}

/**
 * One SVG path for every dark module, in a viewBox of `size + 2 * QUIET_ZONE` units. Runs of
 * dark modules in a row become one rectangle, which keeps the path short.
 */
export function qrSvgPath(matrix: QrMatrix): string {
  const parts: string[] = [];
  for (let row = 0; row < matrix.size; row++) {
    let col = 0;
    while (col < matrix.size) {
      if (!matrix.isDark(row, col)) {
        col++;
        continue;
      }
      const start = col;
      while (col < matrix.size && matrix.isDark(row, col)) col++;
      parts.push(`M${start + QUIET_ZONE} ${row + QUIET_ZONE}h${col - start}v1h-${col - start}z`);
    }
  }
  return parts.join('');
}

export type QrSvg = { readonly path: string; readonly viewBox: number };

export function qrSvg(text: string): QrSvg {
  const matrix = qrMatrix(text);
  return { path: qrSvgPath(matrix), viewBox: matrix.size + 2 * QUIET_ZONE };
}

/**
 * Greyscale pixels (0 dark, 255 light) with the quiet zone, `scale` pixels per module. For
 * tests that read the code back with a QR decoder.
 */
export function qrPixels(text: string, scale = 4): { width: number; data: Uint8ClampedArray } {
  const matrix = qrMatrix(text);
  const modules = matrix.size + 2 * QUIET_ZONE;
  const width = modules * scale;
  const data = new Uint8ClampedArray(width * width * 4).fill(255);
  for (let y = 0; y < width; y++) {
    for (let x = 0; x < width; x++) {
      const row = Math.floor(y / scale) - QUIET_ZONE;
      const col = Math.floor(x / scale) - QUIET_ZONE;
      const inside = row >= 0 && col >= 0 && row < matrix.size && col < matrix.size;
      if (inside && matrix.isDark(row, col)) {
        const i = (y * width + x) * 4;
        data[i] = 0;
        data[i + 1] = 0;
        data[i + 2] = 0;
      }
    }
  }
  return { width, data };
}
