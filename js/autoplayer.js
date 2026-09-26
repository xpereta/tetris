// js/autoplayer.js — simple heuristic AI that drives a Game instance using ONLY
// its public API (cellsOf/collides/moveLeft/moveRight/rotateCW/rotateCCW/hardDrop).
//
// Heuristic per CONTRACT.md: for the current piece, evaluate every candidate
// placement (x position x rotation state) by
//   score = -(holes*100 + height*20 + aggregateHeight*5 - clears*800)
// pick the best, execute moves/rotations to reach it, then hardDrop().

import { BOARD_WIDTH, BOARD_HEIGHT } from './engine.js';

const W_HOLES = 100;
const W_HEIGHT = 20;
const W_AGGREGATE = 5;
const W_CLEARS = 800;

export class AutoPlayer {
  constructor(game) {
    this.game = game;
  }

  /** One decision: place the current piece (rotate/move to target, then hard drop). */
  step() {
    const g = this.game;
    if (g.state !== 'playing' || !g.current) return;
    const piece = g.current;

    const best = this.evaluate(piece.type);
    if (!best) {
      // No legal candidate found (shouldn't happen): just drop where we are.
      g.hardDrop();
      return;
    }

    // Rotate toward the target rotation state (bounded loop; failed rotations
    // simply leave us in place and we proceed with what we have).
    let guard = 0;
    while (piece.rot !== best.rot && guard++ < 4) {
      const diff = (best.rot - piece.rot + 4) % 4;
      if (diff === 3) g.rotateCCW();
      else g.rotateCW(); // diff 1 or 2: one CW step, re-evaluate next iteration
    }

    // Slide horizontally toward the target column.
    guard = 0;
    while (piece.x < best.x && guard++ <= BOARD_WIDTH + 2) {
      if (!g.moveRight()) break;
    }
    guard = 0;
    while (piece.x > best.x && guard++ <= BOARD_WIDTH + 2) {
      if (!g.moveLeft()) break;
    }

    g.hardDrop();
  }

  /** Evaluate all candidate placements for `type`; return {rot, x} of the best. */
  evaluate(type) {
    const g = this.game;
    let best = null;
    let bestScore = -Infinity;

    for (let rot = 0; rot < 4; rot++) {
      for (let x = -2; x <= BOARD_WIDTH + 1; x++) {
        // Find the resting row: fall from above until the next step collides.
        let gy = -6; // safely above the board (negative rows are open space)
        while (!g.collides(g.cellsOf(type, x, gy + 1, rot))) gy++;

        const cells = g.cellsOf(type, x, gy, rot);

        // Validity: within horizontal bounds and at least partially on the board.
        let valid = true;
        let maxRow = -Infinity;
        for (const [cx, cy] of cells) {
          if (cx < 0 || cx >= BOARD_WIDTH || cy > BOARD_HEIGHT - 1) {
            valid = false;
            break;
          }
          if (cy > maxRow) maxRow = cy;
        }
        if (!valid || maxRow < 0) continue; // degenerate: rests entirely above row 0

        const metrics = this.boardMetrics(cells, type);
        const score = -(
          W_HOLES * metrics.holes +
          W_HEIGHT * metrics.height +
          W_AGGREGATE * metrics.aggregateHeight -
          W_CLEARS * metrics.clears
        );
        if (score > bestScore) {
          bestScore = score;
          best = { rot, x };
        }
      }
    }
    return best;
  }

  /** Simulate placing `cells` on a copy of the board; compute heuristic metrics. */
  boardMetrics(cells, type) {
    const g = this.game;
    const b = g.board.map((row) => row.slice());
    for (const [cx, cy] of cells) {
      if (cy >= 0 && cy < BOARD_HEIGHT) b[cy][cx] = type;
    }

    // Remove full rows (bottom-up so indices stay valid).
    let clears = 0;
    for (let r = BOARD_HEIGHT - 1; r >= 0; r--) {
      if (b[r].every((c) => c !== null)) {
        b.splice(r, 1);
        b.unshift(new Array(BOARD_WIDTH).fill(null));
        clears++;
      }
    }

    let holes = 0;
    let aggregateHeight = 0;
    let height = 0; // max column height (distance from floor to topmost block)
    for (let c = 0; c < BOARD_WIDTH; c++) {
      let seen = false;
      let topRow = -1;
      for (let r = 0; r < BOARD_HEIGHT; r++) {
        if (b[r][c] !== null) {
          if (!seen) {
            seen = true;
            topRow = r;
          }
        } else if (seen) {
          holes++; // empty cell with a block above it in the same column
        }
      }
      const h = topRow === -1 ? 0 : BOARD_HEIGHT - topRow;
      aggregateHeight += h;
      if (h > height) height = h;
    }

    return { holes, height, aggregateHeight, clears };
  }
}
