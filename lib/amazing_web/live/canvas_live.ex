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
    </style>

    <div id="container" class="flex w-full h-full justify-center items-center flex-col">
      <pre id="title" class="text-center text-neutral-50">
        Connect to <pre class="text-green-300 inline">tcp://<%= @host %>:2342</pre> to play!
      </pre>

      <canvas id="maze" width="1" height="1" class="aspect-square" phx-hook="Maze"></canvas>
    </div>
    """
  end

  @impl true
  def handle_info({:tick, %{maze: maze, players: players}}, socket) do
    socket = socket |> push_event("maze", %{maze: maze, players: Map.values(players)})
    {:noreply, socket}
  end
end
