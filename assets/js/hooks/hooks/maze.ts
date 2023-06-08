type Cell = {
  walls: { top: boolean; right: boolean; bottom: boolean; left: boolean };
};
type Maze = {
  width: number;
  height: number;
  startX: number;
  startY: number;
  endX: number;
  endY: number;
  cells: Cell[];
};

const parseMaze = (data: number[]): Maze => {
  const [width, height, startX, startY, endX, endY, ...chunks] = data;

  let cells = chunks.flatMap((chunk, i) => {
    let cells: Cell[] = [];

    let walls = Array(32)
      .fill(0)
      .map((_, j) => {
        return (chunk & (1 << j)) != 0;
      });

    for (let j = 0; j < walls.length; j += 4) {
      const chunk = walls.slice(j, j + 4);
      let cell = {
        walls: {
          top: chunk[0],
          right: chunk[1],
          bottom: chunk[2],
          left: chunk[3],
        },
      };
      cells.push(cell);
    }

    return cells;
  });

  return {
    width,
    height,
    startX,
    startY,
    endX,
    endY,
    cells,
  };
};

function resize(canvas: HTMLCanvasElement) {
  const dpr = window.devicePixelRatio || 1;
  const rect = canvas.getBoundingClientRect();
  canvas.width = rect.width * dpr;
  canvas.height = rect.height * dpr;
}

export function setup(canvas: HTMLCanvasElement) {
  const ctx = canvas.getContext("2d")!;

  let maze: Maze = {
    width: 0,
    height: 0,
    startX: 0,
    startY: 0,
    endX: 0,
    endY: 0,
    cells: [],
  };
  let players = [];

  const draw = () => {
    resize(canvas);
    const { width, height, startX, startY, endX, endY, cells } = maze;
    const cellWidth = Math.floor(canvas.width / width);
    const cellHeight = Math.floor(canvas.height / height);
    const wallWidth = 1;

    ctx.clearRect(0, 0, cellWidth * width, cellHeight * height);

    ctx.fillStyle = "#1f2937";
    ctx.fillRect(0, 0, cellWidth * width, cellHeight * height);

    ctx.fillStyle = "#4b5563";
    ctx.fillRect(
      startX * cellWidth,
      startY * cellHeight,
      cellWidth,
      cellHeight
    );

    ctx.fillStyle = "#10b981";
    ctx.fillRect(endX * cellWidth, endY * cellHeight, cellWidth, cellHeight);

    players.forEach((player) => {
      const { x, y, color } = player;
      ctx.fillStyle = color;
      ctx.beginPath();
      ctx.arc(
        x * cellWidth + cellWidth / 2,
        y * cellHeight + cellHeight / 2,
        cellWidth / 2,
        0,
        2 * Math.PI
      );
      ctx.fill();
    });

    ctx.fillStyle = "#374151";
    cells.forEach((cell, i) => {
      const { walls } = cell;
      let x = i % width;
      let y = Math.floor(i / width);
      if (i >= width * height) {
        return;
      }

      if (walls.top) {
        ctx.fillRect(x * cellWidth, y * cellHeight, cellWidth, wallWidth);
      }

      if (walls.right) {
        ctx.fillRect(
          x * cellWidth + cellWidth - wallWidth,
          y * cellHeight,
          wallWidth,
          cellHeight
        );
      }

      if (walls.bottom) {
        ctx.fillRect(
          x * cellWidth,
          y * cellHeight + cellHeight - wallWidth,
          cellWidth,
          wallWidth
        );
      }

      if (walls.left) {
        ctx.fillRect(x * cellWidth, y * cellHeight, wallWidth, cellHeight);
      }
    });

    // draw player names to the right of the players
    players.forEach((player) => {
      const { x, y, name } = player;
      ctx.fillStyle = "#f9fafb";
      ctx.font = "3vh sans-serif";
      ctx.textAlign = "left";
      ctx.textBaseline = "middle";
      ctx.fillText(
        name,
        (x + 1) * cellWidth + 5,
        y * cellHeight + cellHeight / 2
      );
    });

    window.requestAnimationFrame(draw);
  };

  window.addEventListener("resize", () => resize(canvas));
  window.requestAnimationFrame(draw);

  this.handleEvent("maze", ({ maze: newMaze, players: newPlayers }) => {
    if (newMaze) {
      maze = parseMaze(newMaze);
    }
    if (newPlayers) {
      players = newPlayers;
    }
  });
}
