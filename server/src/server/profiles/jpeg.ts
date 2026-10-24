/**
 * Server-side metadata removal for profile photos, a second line behind the app (which already
 * re-encodes without metadata). A JPEG's EXIF, XMP, IPTC, ICC and comment segments can carry a
 * location, a device, a name or a thumbnail of the uncropped photo, and a match would see them.
 *
 * This walks the JPEG's segments and keeps only what a decoder needs to draw the picture: the
 * quantization and Huffman tables, the frame and scan headers, restart intervals, the scan data,
 * plus the JFIF and Adobe headers (density and color transform flags only). Everything else,
 * and anything after the end marker, is dropped. No re-encoding, so no quality loss.
 */

export type JpegInfo = { readonly width: number; readonly height: number };

export class InvalidJpegError extends Error {
  override readonly name = 'InvalidJpegError';
}

const SOI = 0xd8;
const EOI = 0xd9;
const SOS = 0xda;
const APP0 = 0xe0;
const APP14 = 0xee;
const COM = 0xfe;

/** Start-of-frame markers: C0 to CF, except DHT (C4), JPG (C8) and DAC (CC). */
const isStartOfFrame = (marker: number) =>
  marker >= 0xc0 && marker <= 0xcf && marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc;

const isRestart = (marker: number) => marker >= 0xd0 && marker <= 0xd7;

const startsWith = (bytes: Uint8Array, at: number, ascii: string) =>
  [...ascii].every((ch, i) => bytes[at + i] === ch.charCodeAt(0));

/** Whether a segment is kept. Every APPn and COM segment is dropped except plain JFIF and Adobe. */
function keep(marker: number, bytes: Uint8Array, payloadAt: number): boolean {
  if (marker === APP0) return startsWith(bytes, payloadAt, 'JFIF\0');
  if (marker === APP14) return startsWith(bytes, payloadAt, 'Adobe');
  if (marker > APP0 && marker <= 0xef) return false;
  if (marker === COM) return false;
  return true;
}

/**
 * Returns the same picture without metadata, and its size from the frame header.
 * Throws `InvalidJpegError` for anything that isn't a complete baseline or progressive JPEG.
 */
export function stripJpegMetadata(input: Uint8Array): { bytes: Uint8Array; info: JpegInfo } {
  const out: Uint8Array[] = [];
  const fail = (why: string): never => {
    throw new InvalidJpegError(why);
  };
  if (input.length < 4 || input[0] !== 0xff || input[1] !== SOI) fail('no start marker');
  out.push(input.subarray(0, 2));

  let at = 2;
  let info: JpegInfo | undefined;
  let sawScan = false;

  for (;;) {
    if (at + 1 >= input.length) fail('ended before the end marker');
    if (input[at] !== 0xff) fail('expected a marker');
    // Fill bytes: any number of 0xFF may come before a marker.
    let markerAt = at + 1;
    while (input[markerAt] === 0xff && markerAt < input.length) markerAt += 1;
    const marker = input[markerAt]!;
    const segmentStart = markerAt + 1;

    if (marker === EOI) {
      if (!sawScan || !info) fail('no picture data');
      out.push(Uint8Array.of(0xff, EOI));
      break;
    }
    if (marker === SOI || isRestart(marker) || marker === 0x00) fail('unexpected marker');

    if (segmentStart + 1 >= input.length) fail('truncated segment');
    const length = (input[segmentStart]! << 8) | input[segmentStart + 1]!;
    if (length < 2) fail('bad segment length');
    const segmentEnd = segmentStart + length;
    if (segmentEnd > input.length) fail('truncated segment');

    if (isStartOfFrame(marker)) {
      if (length < 7) fail('short frame header');
      const height = (input[segmentStart + 3]! << 8) | input[segmentStart + 4]!;
      const width = (input[segmentStart + 5]! << 8) | input[segmentStart + 6]!;
      if (width === 0 || height === 0) fail('empty frame');
      info = { width, height };
    }

    if (keep(marker, input, segmentStart + 2)) {
      out.push(Uint8Array.of(0xff, marker), input.subarray(segmentStart, segmentEnd));
    }
    at = segmentEnd;

    if (marker === SOS) {
      if (!info) fail('scan before frame');
      sawScan = true;
      // Entropy-coded data runs until a marker that isn't a stuffed 0xFF00 or a restart marker.
      let end = at;
      while (end + 1 < input.length) {
        if (input[end] === 0xff) {
          const next = input[end + 1]!;
          if (next !== 0x00 && !isRestart(next) && next !== 0xff) break;
        }
        end += 1;
      }
      if (end + 1 >= input.length) fail('scan never ended');
      out.push(input.subarray(at, end));
      at = end;
    }
  }

  const size = out.reduce((n, part) => n + part.length, 0);
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const part of out) {
    bytes.set(part, offset);
    offset += part.length;
  }
  return { bytes, info: info! };
}
