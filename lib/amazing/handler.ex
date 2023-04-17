defmodule Amazing.Handler do
  @moduledoc """
  Handle player connections.
  """

  use ThousandIsland.Handler

  require Logger

  alias Amazing.Players.Player
  alias Amazing.Repo
  alias Ecto.Changeset
  alias ThousandIsland.Socket

  @timeout_in_ms 60_000

  defmodule State do
    @moduledoc """
    Keeps track of the connection's state.
    """
    defstruct player: nil

    @type t :: %__MODULE__{
            player: Player.t()
          }
  end

  @impl ThousandIsland.Handler
  def handle_connection(%Socket{} = socket, _state) do
    # Logger.metadata(connection_id: socket.socket.connection_id)
    IO.inspect(socket)
    Logger.info("New connection")
    Socket.send(socket, "motd|enter help for instructions\n")
    {:continue, %State{}, {:persistent, @timeout_in_ms}}
  end

  @impl ThousandIsland.Handler
  def handle_data(data, socket, state) do
    response = handle(String.trim(data), socket, state)

    case {state, elem(response, 1)} do
      {%State{player: nil}, %State{player: %Player{}} = state} ->
        join_game(state)

      _ ->
        nil
    end

    response
  end

  @impl ThousandIsland.Handler
  def handle_close(_socket, state) do
    Logger.info("Connection closed by client")
    leave_game(state)
  end

  @impl ThousandIsland.Handler
  def handle_timeout(socket, state) do
    Logger.info("Connection timed out")
    Socket.send(socket, "Error|Connection timed out\n")
    leave_game(state)
  end

  @impl ThousandIsland.Handler
  def handle_error(reason, _socket, state) do
    Logger.error("Connection error: #{inspect(reason)}")
    leave_game(state)
  end

  defp format_wall(true), do: "1"
  defp format_wall(false), do: "0"

  @impl GenServer
  def handle_cast({:update, :not_moved, _pos, _walls}, state), do: {:noreply, state}

  def handle_cast({:update, :wall, _pos, _walls}, {%Socket{} = socket, _} = state) do
    Socket.send(socket, "error|can't move into wall\n")
    {:noreply, state}
  end

  def handle_cast({:update, :moved, {x, y}, walls}, {%Socket{} = socket, _} = state) do
    walls = walls |> Tuple.to_list() |> Enum.map_join("|", &format_wall/1)
    Socket.send(socket, "pos|#{x}|#{y}|#{walls}\n")
    {:noreply, state}
  end

  def handle_cast({:end_game, :win}, {%Socket{} = socket, _} = state) do
    Socket.send(socket, "won\n")
    {:noreply, state}
  end

  def handle_cast({:end_game, :lose}, {%Socket{} = socket, _} = state) do
    Socket.send(socket, "lost\n")
    {:noreply, state}
  end

  @help_text """
  Welcome to Amazing!
  The goal of the game is to the position 0,0 of the maze.

  You move by sending one of the direction commands and your move will be executed on the next tick.

  After you have moved you will receive a `pos` message with your new position and the walls around you.
  The walls are encoded as a 4-tuple of 0s and 1s, where 1 means there is a wall and 0 means there is no wall.
  They are in the order of north, east, south, west.

  commands:
    - register|<username>|<password>
    - login|<username>|<password>
    - scores
    - up
    - down
    - left
    - right

  server responses:
    - motd|<message>
    - pos|<x>|<y>|<wall1>|<wall2>|<wall3>|<wall4>
    - Ok
    - won
    - lost
    - error|<message>
  """

  defp handle("help", socket, state) do
    Socket.send(socket, @help_text)
    {:continue, state}
  end

  defp handle("register|" <> args, socket, %State{player: nil} = state) do
    state =
      with [name, password] <- String.split(args, "|"),
           {:ok, %Player{} = player} <- insert_player(name, password) do
        Logger.metadata(player_id: player.id)
        Logger.info("Player registered")
        Socket.send(socket, "Ok\n")
        %State{state | player: player}
      else
        {:error, %Changeset{} = changeset} ->
          errors = format_changeset_errors(changeset)
          Logger.info("Failed registration attempt")
          Socket.send(socket, "Error|#{errors}\n")
          state

        _ ->
          Logger.info("Failed registration attempt")
          Socket.send(socket, "Error\n")
          state
      end

    {:continue, state}
  end

  defp handle("register|" <> _args, socket, %State{} = state) do
    Socket.send(socket, "Error|Already logged in\n")
    {:continue, state}
  end

  defp handle("login|" <> args, socket, %State{player: nil} = state) do
    with [name, password] <- String.split(args, "|"),
         player <- Repo.get_by(Player, name: name),
         {:ok, %Player{} = player} <- Argon2.check_pass(player, password) do
      Socket.send(socket, "Ok\n")
      Logger.metadata(player_id: player.id)
      Logger.info("Player logged in")
      {:continue, %State{state | player: player}}
    else
      _ ->
        Logger.info("Failed login attempt")
        Socket.send(socket, "Error|Invalid credentials\n")
        {:continue, state}
    end
  end

  defp handle("login|" <> _args, socket, %State{} = state) do
    Socket.send(socket, "Error|Already logged in\n")
    {:continue, state}
  end

  defp handle("scores", socket, state) do
    scores =
      Amazing.Players.list_players(%{sort: {:desc, :score}})
      |> Enum.map(fn player -> "  - #{player.name}: #{player.score}" end)
      |> Enum.join("\n")

    Socket.send(socket, scores <> "\n")
    {:continue, state}
  end

  defp handle("up", socket, state), do: handle_dir({0, -1}, socket, state)
  defp handle("down", socket, state), do: handle_dir({0, 1}, socket, state)
  defp handle("left", socket, state), do: handle_dir({-1, 0}, socket, state)
  defp handle("right", socket, state), do: handle_dir({1, 0}, socket, state)

  defp handle(_data, socket, state) do
    Socket.send(socket, "Error|Unrecognized command\n")
    {:continue, state}
  end

  defp handle_dir(_dir, socket, %State{player: nil} = state) do
    Socket.send(socket, "Error|Not logged in\n")
    {:continue, state}
  end

  defp handle_dir(dir, _socket, state) do
    :ok = Amazing.Game.move_player(state.player.id, dir)
    {:continue, state}
  end

  @spec insert_player(binary(), binary()) :: {:ok, Player.t()} | {:error, Changeset.t()}
  defp insert_player(name, password) do
    attrs = %{name: name, password: password, score: 0, color: "red"}

    %Player{}
    |> Player.changeset(attrs)
    |> Repo.insert()
  end

  defp format_changeset_errors(%Changeset{} = changeset) do
    Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.reduce([], fn {key, value}, acc ->
      errors = Enum.join(value, ", ")
      ["#{key}: #{errors}" | acc]
    end)
    |> Enum.join("|")
  end

  defp join_game(%State{player: player} = _state) do
    Logger.debug("Joining game")

    {:ok, _} = Amazing.Game.add_player(player, self())
  end

  defp leave_game(%State{player: nil} = _state), do: nil

  defp leave_game(%State{player: player}) do
    Logger.debug("Leaving game")
    {:ok, _} = Amazing.Game.remove_player(player)
  end
end
