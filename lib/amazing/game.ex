defmodule Amazing.Game do
  @moduledoc false

  use GenServer

  alias Amazing.Maze
  alias Amazing.Players
  alias Amazing.Players.Player, as: P

  require Logger

  defmodule Player do
    @moduledoc false

    @enforce_keys [:player, :pos, :dir, :handler]
    defstruct [:player, :pos, :dir, :handler]

    @type t() :: %__MODULE__{
            player: P.t(),
            pos: Maze.coord(),
            dir: Maze.coord() | nil,
            handler: pid()
          }
  end

  defimpl Jason.Encoder, for: Player do
    def encode(%Player{player: %P{} = player, pos: {x, y}}, opts) do
      %{
        name: player.name,
        x: x,
        y: y,
        color: player.color
      }
      |> Jason.Encode.map(opts)
    end
  end

  defmodule State do
    @moduledoc false
    defstruct players: %{},
              generator: nil,
              maze: nil,
              timer: nil,
              revealed: nil,
              size: nil,
              tickrate_in_ms: 100

    @type t :: %__MODULE__{
            players: %{integer() => Player.t()},
            maze: Maze.t() | nil,
            revealed: MapSet.t(Maze.coord()),
            generator: module(),
            timer: pid(),
            size: {non_neg_integer(), non_neg_integer()},
            tickrate_in_ms: non_neg_integer()
          }
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def init(state) do
    generator = Keyword.get(state, :generator, Maze.Generator.RecursiveBacktracking)
    :timer.apply_after(1000, __MODULE__, :generate_maze, [])
    {:ok, %State{generator: generator, players: %{}, revealed: MapSet.new(), size: {16, 16}}}
  end

  def generate_maze(size \\ nil) do
    GenServer.cast(__MODULE__, {:generate_maze, size})
  end

  @spec maze :: Maze.t()
  def maze do
    GenServer.call(__MODULE__, :maze)
  end

  def public_maze do
    GenServer.call(__MODULE__, :public_maze)
  end

  def set_size({_w, _h} = size) do
    GenServer.cast(__MODULE__, {:set_size, size})
  end

  def players do
    GenServer.call(__MODULE__, :players)
  end

  def add_player(player, pid) do
    GenServer.call(__MODULE__, {:add_player, player, pid})
  end

  def remove_player(player) do
    GenServer.call(__MODULE__, {:remove_player, player})
  end

  def move_player(player_id, dir) do
    GenServer.cast(__MODULE__, {:move_player, player_id, dir})
  end

  @topic "game"

  def subscribe do
    Phoenix.PubSub.subscribe(Amazing.PubSub, @topic)
  end

  def metrics do
    GenServer.cast(__MODULE__, :metrics)
  end

  def increment_score(player_id) do
    GenServer.cast(__MODULE__, {:increment_score, player_id})
  end

  @impl GenServer
  def handle_call({:add_player, %P{} = player, pid}, _from, %State{} = state) do
    if Map.has_key?(state.players, player.id) do
      Logger.info("Player tried to join twice: #{player.name}")
      {:reply, {:error, :already_joined}, state}
    else
      player_state = %Player{
        player: player,
        handler: pid,
        pos: state.maze.start,
        dir: nil
      }

      state = %State{state | players: Map.put(state.players, player.id, player_state)}

      send_player_update({:moved, player_state}, state.maze)

      Logger.info("Player joined: #{player.name}")

      {:reply, {:ok, player}, state}
    end
  end

  @impl GenServer
  def handle_call({:remove_player, player}, _from, %State{} = state) do
    {removed, players} = Map.pop(state.players, player.id)
    state = %State{state | players: players}

    Logger.info("Player left: #{player.name}")

    {:reply, {:ok, removed}, state}
  end

  @impl GenServer
  def handle_call(:maze, _from, %State{maze: maze} = state) do
    {:reply, maze, state}
  end

  @impl GenServer
  def handle_call(:public_maze, _from, %State{maze: nil} = state) do
    {:reply, Maze.new(1, 1), state}
  end

  @impl GenServer
  def handle_call(:public_maze, _from, %State{maze: maze} = state) do
    {:reply, maze |> Maze.hide_unrevealed(state.revealed), state}
  end

  @impl GenServer
  def handle_call(:players, _from, %State{players: players} = state) do
    {:reply, players, state}
  end

  @impl GenServer
  def handle_cast({:set_size, {width, height}}, %State{} = state)
      when is_integer(width) and is_integer(height) and width > 0 and height > 0 do
    state = %State{state | size: {width, height}}
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:set_size, _}, %State{} = state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast(:metrics, %State{players: players} = state) do
    :telemetry.execute([:amazing, :game, :players], %{total: map_size(players)}, %{})
    {:noreply, state}
  end

  @impl GenServer

  def handle_cast({:generate_maze, {width, height}}, %State{} = state) do
    maze = Maze.new(width, height) |> Maze.generate(state.generator)

    players =
      state.players
      |> Enum.map(fn {k, %Player{} = player} ->
        {k, %Player{player | pos: maze.start, dir: nil}}
      end)
      |> Map.new()

    Players

    {:ok, timer} = :timer.send_interval(state.tickrate_in_ms, :tick)

    state = %State{
      state
      | maze: maze,
        players: players,
        timer: timer,
        revealed: MapSet.new([maze.start])
    }

    players
    |> Map.values()
    |> Enum.each(&send_player_update({:moved, &1}, maze))

    {:noreply, state}
  end

  def handle_cast({:generate_maze, nil}, %State{size: size} = state) do
    handle_cast({:generate_maze, size}, state)
  end

  @impl GenServer
  def handle_cast({:move_player, player_id, dir}, %State{players: players} = state) do
    case Map.get(players, player_id) do
      nil ->
        {:noreply, state}

      %Player{} = player ->
        new_player = %Player{player | dir: dir}
        state = %State{state | players: Map.put(players, player_id, new_player)}
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_cast({:increment_score, player_id}, %State{players: players} = state) do
    case Map.get(players, player_id) do
      nil ->
        {:noreply, state}

      %Player{} = player ->
        {:ok, p} = Players.increment_score(player.player)
        new_player = %Player{player | player: p}
        state = %State{state | players: Map.put(players, player_id, new_player)}
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info(:tick, %State{} = state) do
    state =
      state
      |> move_players()
      |> update_revealed()
      |> broadcast_maze()
      |> check_win()

    {:noreply, state}
  end

  defp broadcast_maze(%State{maze: maze, players: players} = state) do
    Phoenix.PubSub.broadcast(Amazing.PubSub, @topic, {:tick, %{maze: maze, players: players}})
    state
  end

  defp move_players(%State{maze: maze, players: players} = state) do
    updates =
      players
      |> Map.values()
      |> Enum.map(&do_move_player(&1, maze))

    updates
    |> Enum.each(&send_player_update(&1, maze))

    {_, players} = Enum.unzip(updates)

    players = Map.new(players, fn %Player{player: %P{id: id}} = player -> {id, player} end)

    %State{state | players: players}
  end

  defp update_revealed(%State{players: players, revealed: revealed} = state) do
    revealed =
      players
      |> Map.values()
      |> Enum.map(& &1.pos)
      |> Enum.reduce(revealed, &MapSet.put(&2, &1))

    %State{state | revealed: revealed}
  end

  defp check_win(%State{maze: maze, players: players} = state) do
    {winners, losers} =
      players
      |> Map.values()
      |> Enum.split_with(&(&1.pos == maze.goal))

    case {winners, losers} do
      {[], _} -> state
      {winners, losers} -> end_game(winners, losers, state)
    end
  end

  defp end_game(winners, losers, %State{timer: timer} = state) do
    {:ok, :cancel} = :timer.cancel(timer)
    Enum.each(winners, &GenServer.cast(__MODULE__, {:increment_score, &1.player.id}))
    Enum.each(winners, &GenServer.cast(&1.handler, {:end_game, :win}))
    Enum.each(losers, &GenServer.cast(&1.handler, {:end_game, :lose}))
    generate_maze()
    %State{state | maze: nil}
  end

  @type status() :: :moved | :not_moved | :wall

  @spec do_move_player(Player.t(), Maze.t()) :: {status(), Player.t()}
  defp do_move_player(%Player{pos: _, dir: nil} = player, _maze), do: {:not_moved, player}

  defp do_move_player(%Player{pos: pos, dir: dir} = player, maze) do
    {status, new_pos} =
      case {pos, move(pos, dir, maze)} do
        {pos, pos} -> {:wall, pos}
        {_, new_pos} -> {:moved, new_pos}
      end

    {status, %Player{player | pos: new_pos, dir: nil}}
  end

  defp move(pos, nil, _maze), do: pos

  defp move({x, y} = pos, {dx, dy} = dir, %Maze{} = maze) do
    new_pos = {x + dx, dy + y}

    if can_move_in_dir?(pos, dir, maze) and Maze.in_bounds?(new_pos, maze) do
      new_pos
    else
      pos
    end
  end

  defp can_move_in_dir?(pos, dir, maze) do
    cell_index = Maze.coord_to_index(pos, maze)
    cell = Enum.at(maze.cells, cell_index)

    case {dir, elem(cell, 0)} do
      {{0, -1}, {false, _, _, _}} -> true
      {{1, 0}, {_, false, _, _}} -> true
      {{0, 1}, {_, _, false, _}} -> true
      {{-1, 0}, {_, _, _, false}} -> true
      _ -> false
    end
  end

  defp send_player_update({:not_moved, _player}, _maze), do: nil

  defp send_player_update({status, %Player{handler: handler, pos: pos}}, maze) do
    cell_index = Maze.coord_to_index(pos, maze)
    {walls, _coord} = Enum.at(maze.cells, cell_index)
    GenServer.cast(handler, {:update, status, pos, walls})
  end
end
