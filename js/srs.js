// js/srs.js — SRS (Super Rotation System) shape data + official wall-kick tables.
//
// Conventions:
// - Piece cells are [col, row] offsets inside the piece's bounding box; rows grow DOWNWARD.
//   Bounding boxes: I = 4x4, O = 2x2 (no effective kicks), all others 3x3.
// - rot: 0 = spawn, 1 = CW ("R"), 2 = 180, 3 = CCW ("L").
// - Kick offsets are (dx, dy) in BOARD coordinates: +dy moves the piece DOWN one row.
//   The official tables (Tetris wiki / harddrop) use +y = up; they have been converted
//   here by negating dy. CCW transitions are derived as the negation of the reverse
//   CW transition, per the guideline.

export const PIECE_TYPES = ['I', 'O', 'T', 'S', 'Z', 'J', 'L'];

// SHAPES[type][rot] -> list of [col, row] cells in the bounding box.
export const SHAPES = {
  I: [
    [[0, 1], [1, 1], [2, 1], [3, 1]], // spawn: middle row
    [[2, 0], [2, 1], [2, 2], [2, 3]], // CW: column 2
    [[0, 2], [1, 2], [2, 2], [3, 2]], // 180: row 2
    [[1, 0], [1, 1], [1, 2], [1, 3]], // CCW: column 1
  ],
  O: [
    [[0, 0], [1, 0], [0, 1], [1, 1]],
    [[0, 0], [1, 0], [0, 1], [1, 1]],
    [[0, 0], [1, 0], [0, 1], [1, 1]],
    [[0, 0], [1, 0], [0, 1], [1, 1]],
  ],
  T: [
    [[1, 0], [0, 1], [1, 1], [2, 1]], // spawn (facing up)
    [[1, 0], [1, 1], [2, 1], [1, 2]], // CW (facing right)
    [[0, 1], [1, 1], [2, 1], [1, 2]], // 180 (facing down)
    [[1, 0], [0, 1], [1, 1], [1, 2]], // CCW (facing left)
  ],
  S: [
    [[1, 0], [2, 0], [0, 1], [1, 1]],
    [[1, 0], [1, 1], [2, 1], [2, 2]],
    [[1, 1], [2, 1], [0, 2], [1, 2]],
    [[0, 0], [0, 1], [1, 1], [1, 2]],
  ],
  Z: [
    [[0, 0], [1, 0], [1, 1], [2, 1]],
    [[2, 0], [1, 1], [2, 1], [1, 2]],
    [[0, 1], [1, 1], [1, 2], [2, 2]],
    [[1, 0], [0, 1], [1, 1], [0, 2]],
  ],
  J: [
    [[0, 0], [0, 1], [1, 1], [2, 1]],
    [[1, 0], [2, 0], [1, 1], [1, 2]],
    [[0, 1], [1, 1], [2, 1], [2, 2]],
    [[1, 0], [1, 1], [0, 2], [1, 2]],
  ],
  L: [
    [[2, 0], [0, 1], [1, 1], [2, 1]],
    [[1, 0], [1, 1], [1, 2], [2, 2]],
    [[0, 1], [1, 1], [2, 1], [0, 2]],
    [[0, 0], [1, 0], [1, 1], [1, 2]],
  ],
};

// Official JLSTZ wall-kick data (board coordinates: +dy = down).
const JLSTZ_KICKS = {
  '0-1': [[0, 0], [-1, 0], [-1, -1], [0, 2], [-1, 2]],
  '1-2': [[0, 0], [1, 0], [1, -1], [0, -2], [1, -2]],
  '2-3': [[0, 0], [1, 0], [1, 1], [0, 2], [1, 2]],
  '3-0': [[0, 0], [-1, 0], [-1, -1], [0, -2], [-1, -2]],
};

// Official I-piece wall-kick data (board coordinates: +dy = down).
const I_KICKS = {
  '0-1': [[0, 0], [-2, 0], [1, 0], [-2, 1], [1, -2]],
  '1-2': [[0, 0], [-1, 0], [2, 0], [-1, -2], [2, 1]],
  '2-3': [[0, 0], [2, 0], [-1, 0], [2, -1], [-1, 2]],
  '3-0': [[0, 0], [1, 0], [-2, 0], [1, 2], [-2, -2]],
};

/**
 * Kick offsets to try (in order) when rotating `type` from state `from` to `to`.
 * The first offset that yields a non-colliding position is applied.
 */
export function getKicks(type, from, to) {
  if (type === 'O') return [[0, 0]]; // O rotates in place; no kicks needed.
  const table = type === 'I' ? I_KICKS : JLSTZ_KICKS;
  if ((from + 1) % 4 === to) {
    return table[`${from}-${to}`]; // CW transition: use the table directly.
  }
  // CCW transition: negate the kicks of the reverse (CW) transition.
  return table[`${to}-${from}`].map(([dx, dy]) => [-dx, -dy]);
}
