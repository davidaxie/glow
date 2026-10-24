/**
 * The printable poster: a big QR code with the room's poster link, the room code, and three
 * steps. US Letter, black on white so any printer and any phone camera handle it, with the
 * design system's accent for the brand. The poster carries the room's name and code only:
 * never its location or anything about the people in it.
 */
import { PDFDocument, StandardFonts, rgb, type PDFFont, type PDFPage } from 'pdf-lib';
import { roomLink } from './links';
import { QUIET_ZONE, qrMatrix, qrSvgPath } from './qr-code';
import type { RoomRecord } from './repo';

const PAGE = { width: 612, height: 792 } as const;
const MARGIN = 54;

const INK = rgb(0x0b / 255, 0x0b / 255, 0x10 / 255);
const MUTED = rgb(0x5a / 255, 0x5a / 255, 0x66 / 255);
const ACCENT = rgb(0xff / 255, 0x4f / 255, 0xa3 / 255);
const WHITE = rgb(1, 1, 1);

export const POSTER_STEPS = [
  'Scan the code with your iPhone camera, or enter the room code in Glow.',
  "Snap today's outfit. Faces are blurred on your phone before anything is sent.",
  "Tap who you noticed. They'll only know if they tap you too.",
] as const;

function wrap(text: string, font: PDFFont, size: number, width: number): string[] {
  const lines: string[] = [];
  let line = '';
  for (const word of text.split(/\s+/)) {
    const next = line ? `${line} ${word}` : word;
    if (font.widthOfTextAtSize(next, size) <= width || !line) line = next;
    else {
      lines.push(line);
      line = word;
    }
  }
  if (line) lines.push(line);
  return lines;
}

function centered(
  page: PDFPage,
  text: string,
  y: number,
  font: PDFFont,
  size: number,
  color = INK,
) {
  const x = (PAGE.width - font.widthOfTextAtSize(text, size)) / 2;
  page.drawText(text, { x, y, size, font, color });
}

/** Fits a room name on one line by shrinking it, down to 14 pt, then trimming. */
function fitLine(text: string, font: PDFFont, size: number, width: number): [string, number] {
  let s = size;
  while (s > 14 && font.widthOfTextAtSize(text, s) > width) s -= 1;
  let t = text;
  while (t.length > 1 && font.widthOfTextAtSize(t, s) > width) t = `${t.slice(0, -2)}…`;
  return [t, s];
}

/** WinAnsi (the standard PDF fonts) can't draw every character; swap the rest. */
function printable(text: string): string {
  return text
    .normalize('NFKD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^\x20-\x7e…]/g, '?');
}

export async function posterPdf(room: RoomRecord): Promise<Uint8Array> {
  const link = roomLink(room.slug, room.staticQrToken);
  const doc = await PDFDocument.create();
  doc.setTitle(`Glow poster: ${printable(room.name)}`);
  doc.setSubject('Scan to join this room in Glow');
  doc.setCreator('Glow admin');
  doc.setProducer('Glow');
  // No author, keywords or dates that could say who printed it or when.
  doc.setCreationDate(new Date(0));
  doc.setModificationDate(new Date(0));

  const page = doc.addPage([PAGE.width, PAGE.height]);
  const bold = await doc.embedFont(StandardFonts.HelveticaBold);
  const regular = await doc.embedFont(StandardFonts.Helvetica);
  const inner = PAGE.width - 2 * MARGIN;

  // Brand bar.
  page.drawRectangle({ x: 0, y: PAGE.height - 10, width: PAGE.width, height: 10, color: ACCENT });
  let y = PAGE.height - MARGIN - 28;
  page.drawText('Glow', { x: MARGIN, y, size: 30, font: bold, color: ACCENT });
  const [roomName, roomSize] = fitLine(printable(room.name), regular, 14, inner - 110);
  page.drawText(roomName, {
    x: PAGE.width - MARGIN - regular.widthOfTextAtSize(roomName, roomSize),
    y: y + 8,
    size: roomSize,
    font: regular,
    color: MUTED,
  });

  y -= 56;
  centered(page, 'Noticed someone here?', y, bold, 36);
  y -= 28;
  centered(page, 'Find out, privately, if they noticed you too.', y, regular, 17, MUTED);

  // The QR code, drawn as vector squares so it prints sharp at any size.
  const matrix = qrMatrix(link);
  const modules = matrix.size + 2 * QUIET_ZONE;
  const qrSize = 320;
  const cell = qrSize / modules;
  const qrX = (PAGE.width - qrSize) / 2;
  const qrTop = y - 22;
  page.drawRectangle({ x: qrX, y: qrTop - qrSize, width: qrSize, height: qrSize, color: WHITE });
  // One filled path for every dark module (in module units, quiet zone included), so no
  // seams show between modules at any print or screen resolution.
  page.drawSvgPath(qrSvgPath(matrix), { x: qrX, y: qrTop, scale: cell, color: INK });

  const hintY = qrTop - qrSize - 26;
  centered(page, 'Point your iPhone camera here', hintY, bold, 15);

  // The room code, for people who open Glow first.
  const boxWidth = 300;
  const boxHeight = 70;
  const boxTop = hintY - 22;
  page.drawRectangle({
    x: (PAGE.width - boxWidth) / 2,
    y: boxTop - boxHeight,
    width: boxWidth,
    height: boxHeight,
    borderColor: INK,
    borderWidth: 1.5,
    color: WHITE,
  });
  centered(page, 'Or open Glow and enter the room code', boxTop - 18, regular, 11, MUTED);
  centered(page, room.code.split('').join(' '), boxTop - boxHeight + 14, bold, 30);

  // Three steps.
  const stepsY = boxTop - boxHeight - 44;
  const colWidth = (inner - 2 * 18) / 3;
  POSTER_STEPS.forEach((step, i) => {
    const x = MARGIN + i * (colWidth + 18);
    page.drawCircle({ x: x + 12, y: stepsY + 4, size: 12, color: ACCENT });
    const digit = String(i + 1);
    page.drawText(digit, {
      x: x + 12 - bold.widthOfTextAtSize(digit, 13) / 2,
      y: stepsY - 0.5,
      size: 13,
      font: bold,
      color: WHITE,
    });
    wrap(step, regular, 11.5, colWidth).forEach((line, n) => {
      page.drawText(line, { x, y: stepsY - 26 - n * 15, size: 11.5, font: regular, color: INK });
    });
  });

  // Reassurance, in the app's voice.
  const footer = [
    "Glow checks once that you're in this room, then forgets where you are.",
    "No names, faces or distances. A tap stays secret unless it's mutual.",
  ];
  footer.forEach((line, n) => {
    centered(page, line, 36 - n * 13, regular, 9.5, MUTED);
  });

  return doc.save({ useObjectStreams: true });
}
