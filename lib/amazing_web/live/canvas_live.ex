defmodule AmazingWeb.CanvasLive do
  alias Amazing.Game
  alias Amazing.Maze
  use AmazingWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Game.subscribe()

    maze =
      if connected?(socket) do
        Game.public_maze()
      else
        Maze.new(2, 2) |> Maze.hide_unrevealed(MapSet.new())
      end

    host = AmazingWeb.Endpoint.config(:url)[:host]

    {:ok,
     socket
     |> push_event("maze", maze)
     |> assign(host: host)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <style>
      #maze {
          width: 90vmin;
          height: 90vmin;
      }
      #title {
        font-size: 2.5vh;
      }
      #container {
        // padding: 2.5vh;
      }
    </style>

    <div id="container" class="flex w-full h-full justify-center items-center flex-col">
      <pre id="title" class="text-center text-neutral-50">
        Connect to <pre class="text-green-300 inline">tcp://<%= @host %>:2342</pre> to play!
      </pre>

      <canvas id="maze" width="1" height="1" class="aspect-square" phx-hook="Maze"></canvas>
    </div>

    <script type="module" phx-ignore>
      const canvas = document.getElementById("maze");
      const ctx = canvas.getContext("2d");

      let maze = {width: 0, height: 0, cells: []};

      const parseMaze = (data) => {
        const [width, height, startX, startY, endX, endY, ...chunks] = data;

        let cells = chunks.flatMap((chunk, i) => {
          let cells = [];

          let walls = Array(32).fill(0).map((_, j) => {
            return (chunk & (1 << j)) != 0;
          });

          for (let j = 0; j < walls.length; j += 4) {
              const chunk = walls.slice(j, j + 4);
              let cell = {
                  walls: {
                    top: chunk[0],
                    right: chunk[1],
                    bottom: chunk[2],
                    left: chunk[3]
                  }
              }
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
          cells
        };
      };

      let players = [];

      const resizeCanvas = () => {
        canvas.width = canvas.clientWidth;
        canvas.height = canvas.clientHeight;
      };
      window.addEventListener("resize", resizeCanvas);

      window.Hooks.Maze = {
        mounted() {
          this.handleEvent("maze", ({maze: new_maze, players: new_players}) => {
            if (typeof new_maze !== 'undefined') {
              maze = parseMaze(new_maze);
            }
            if (typeof new_players !== 'undefined') {
              players = new_players;
            }
          });
        }
      };

      const drawMaze = () => {
        resizeCanvas();
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
        ctx.fillRect(
          endX * cellWidth,
          endY * cellHeight,
          cellWidth,
          cellHeight
        );

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
            ctx.fillRect(x * cellWidth + cellWidth - wallWidth, y * cellHeight, wallWidth, cellHeight);
          }

          if (walls.bottom) {
            ctx.fillRect(x * cellWidth, y * cellHeight + cellHeight - wallWidth, cellWidth, wallWidth);
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
          ctx.fillText(name, (x + 1) * cellWidth + 5, y * cellHeight + cellHeight / 2);
        });

        window.requestAnimationFrame(drawMaze);
      };

      window.requestAnimationFrame(drawMaze);
    </script>
    """
  end

  @impl true
  def handle_info({:tick, %{maze: maze, players: players}}, socket) do
    socket = socket |> push_event("maze", %{maze: maze, players: Map.values(players)})
    {:noreply, socket}
  end
end
