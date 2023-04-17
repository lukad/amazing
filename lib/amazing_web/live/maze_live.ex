defmodule AmazingWeb.MazeLive do
  alias Amazing.Game
  alias Amazing.Maze
  use AmazingWeb, :live_view

  import Bitwise

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Game.subscribe()
    if connected?(socket), do: :timer.send_interval(50, self(), :update)

    maze =
      if connected?(socket) do
        Game.maze()
      else
        Maze.new(2, 2) |> Maze.hide_unrevealed(MapSet.new())
      end

    width = maze.width
    height = maze.height

    cells = maze.cells

    host = AmazingWeb.Endpoint.config(:url)[:host]

    streamed_cells =
      cells
      |> Enum.with_index()
      |> Enum.map(fn {{walls, _pos}, i} ->
        %{
          id: i,
          walls: walls |> Tuple.to_list() |> Enum.map(&if &1, do: "1", else: "0") |> Enum.join()
        }
      end)

    {:ok,
     socket
     |> push_event("maze", maze)
     |> assign(cells: cells, width: width, height: height, host: host)
     |> stream(:cells, streamed_cells)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" class="hidden">
      <symbol id="w0000" viewbox="0 0 10 10">
        <path d="M 0 0 L 0 1 L 1 1 L 1 0 Z" />
        <path d="M 9 0 L 9 1 L 10 1 L 10 0 Z" />
        <path d="M 0 9 L 0 10 L 1 10 L 1 9 Z" />
        <path d="M 9 9 L 9 10 L 10 10 L 10 9 Z" />
      </symbol>
      <symbol id="w1000" viewbox="0 0 10 10">
        <use xlink:href="#w0000" />
        <path d="M 0 0 L 0 1 L 10 1 L 10 0 Z" />
      </symbol>
      <symbol id="w0100" viewbox="0 0 10 10">
        <use xlink:href="#w0000" />
        <path d="M 9 0 L 9 10 L 10 10 L 10 0 Z" />
      </symbol>
      <symbol id="w0010" viewbox="0 0 10 10">
        <use xlink:href="#w0000" />
        <path d="M 0 9 L 0 10 L 10 10 L 10 9 Z" />
      </symbol>
      <symbol id="w0001" viewbox="0 0 10 10">
        <use xlink:href="#w0000" />
        <path d="M 0 0 L 0 10 L 1 10 L 1 0 Z" />
      </symbol>
      <symbol
        :for={
          i <-
            Enum.to_list(0..0b1111)
            |> Enum.reject(&(&1 in [0, 1, 2, 4, 8, 15]))
        }
        id={("w" <> Enum.join([bsr(i &&& 8, 3), bsr(i &&& 4, 2), bsr(i &&& 2, 1), i &&& 1]))}
      >
        <use xlink:href="#w0000" />
        <use :if={(i &&& 0b1000) != 0} xlink:href="#w1000" />
        <use :if={(i &&& 0b0100) != 0} xlink:href="#w0100" />
        <use :if={(i &&& 0b0010) != 0} xlink:href="#w0010" />
        <use :if={(i &&& 0b0001) != 0} xlink:href="#w0001" />
      </symbol>
    </svg>

    <style>
      @media (orientation:portrait) {
        #maze {
            width: 90vw;
            height: 90vw;
        }
      }
      @media (orientation:landscape) {
        #maze {
            width: 90vh;
            height: 90vh;
        }
      }
      #title {
        font-size: 2.5vh;
      }
      #container {
        padding: 2.5vh;
      }
    </style>

    <div id="container" class="flex w-full h-full justify-center items-center flex-col">
      <pre id="title" class="text-center text-neutral-50">
        Connect to <pre class="text-green-300 inline">tcp://<%= @host %>:2342</pre> to play!
      </pre>

      <div
        class="grid"
        style={"grid-template-columns: repeat(#{@width}, 1fr);"}
        id="maze"
        phx-update="append"
      >
        <div :for={{dom_id, %{walls: walls}} <- @streams.cells} id={dom_id} class="relative block">
          <div class="w-full h-full">
            <svg xmlns="http:://www.w3.org/2000/svg" class="absolute w-full h-full fill-neutral-200">
              <use xlink:href={"#w" <> walls} />
            </svg>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # handle update
  @impl true
  def handle_info(:update, socket) do
    cells = socket.assigns.cells

    {:noreply, assign(socket, cells: cells)}
  end

  @impl true
  def handle_info({:tick, %{maze: maze, players: _players}}, socket) do
    width = maze.width
    height = maze.height

    old_cells = socket.assigns.cells
    cells = maze.cells

    streamed_cells =
      cells
      |> Enum.with_index()
      |> Enum.reject(fn {cell, id} -> Enum.at(old_cells, id) == cell end)
      |> Enum.map(fn {{walls, _pos}, i} ->
        %{
          id: i,
          walls: walls |> Tuple.to_list() |> Enum.map(&if &1, do: "1", else: "0") |> Enum.join()
        }
      end)

    socket = assign(socket, cells: cells, width: width, height: height)

    socket =
      Enum.reduce(streamed_cells, socket, fn cell, socket ->
        stream_insert(socket, :cells, cell, at: cell.id)
      end)

    {:noreply, socket}
  end
end
