defmodule Amazing.Maze do
  @moduledoc """
  Provides a data structure for a maze as well as functions to mutate it.

  ## Examples

    iex> Amazing.Maze.new(2, 2)
    %Amazing.Maze{
      cells: [
        {{true, true, true, true}, {0, 0}},
        {{true, true, true, true}, {1, 0}},
        {{true, true, true, true}, {0, 1}},
        {{true, true, true, true}, {1, 1}}
      ],
      height: 2,
      width: 2
    }

    iex> Amazing.Maze.new(2, 2)
    ...> |> Amazing.Maze.connect({0, 0}, {0, 1})
    ...> |> Amazing.Maze.connect({0, 1}, {1, 1})
    ...> |> Amazing.Maze.connect({1, 1}, {1, 0})
    %Amazing.Maze{
      cells: [
        {{true, true, false, true}, {0, 0}},
        {{true, true, false, true}, {1, 0}},
        {{false, false, true, true}, {0, 1}},
        {{false, true, true, false}, {1, 1}}
      ],
      height: 2,
      width: 2
    }
  """

  alias Amazing.Maze

  @enforce_keys [:width, :height, :cells, :start, :goal]
  defstruct [:width, :height, :cells, :start, :goal]

  @type t() :: %Maze{
          width: pos_integer(),
          height: pos_integer(),
          cells: list(cell()),
          start: Maze.coord(),
          goal: Maze.coord()
        }

  @type coord() :: {integer(), integer()}

  @type cell() :: {{boolean(), boolean(), boolean(), boolean()}, coord()}

  @spec new(pos_integer(), pos_integer()) :: t()
  def new(width, height)
      when is_integer(width) and is_integer(height) and width > 0 and height > 0 do
    maze = %Maze{
      width: width,
      height: height,
      cells: [],
      start: {width - 1, height - 1},
      goal: {0, 0}
    }

    cells =
      0..(width * height - 1)
      |> Enum.to_list()
      |> Enum.map(&index_to_coord(&1, maze))
      |> Enum.map(&{{true, true, true, true}, &1})

    %Maze{maze | cells: cells}
  end

  def new(_width, _height) do
    raise ArgumentError, "width and height must be positive integers"
  end

  @spec generate(t(), Maze.Generator.t()) :: t()
  def generate(maze, generator) do
    generator.generate(maze)
  end

  def hide_unrevealed(%Maze{} = maze, revealed) do
    cells =
      maze.cells
      |> Enum.map(fn
        {cell, coord} ->
          if MapSet.member?(revealed, coord) do
            {cell, coord}
          else
            {{true, true, true, true}, coord}
          end
      end)

    %Maze{maze | cells: cells}
  end

  @spec index_to_coord(non_neg_integer(), t()) :: coord()
  def index_to_coord(index, %Maze{width: width, height: height} = maze) when is_integer(index) do
    if index >= maze.width * maze.height || index < 0 do
      raise ArgumentError, "index #{index} is out of bounds for a #{width}x#{height} maze"
    end

    {
      Integer.mod(index, width),
      div(index, width)
    }
  end

  @spec coord_to_index(coord(), t()) :: non_neg_integer()
  def coord_to_index({x, y}, %Maze{width: width, height: height}) do
    if x < 0 || x >= width || y < 0 || y >= height do
      raise ArgumentError,
            "coordinate {#{x}, #{y}} is out of bounds for a #{width}x#{height} maze"
    end

    y * width + x
  end

  @spec neighbor_coords(coord(), t()) :: list(coord())
  def neighbor_coords({x, y}, maze) do
    [{x - 1, y}, {x + 1, y}, {x, y - 1}, {x, y + 1}]
    |> Enum.reject(&out_of_bounds?(&1, maze))
  end

  @spec out_of_bounds?(coord(), t()) :: boolean()
  def out_of_bounds?({x, y}, %Maze{width: width, height: height}) do
    x < 0 || x >= width || y < 0 || y >= height
  end

  @spec in_bounds?(coord(), t()) :: boolean()
  def in_bounds?(pos, maze), do: not out_of_bounds?(pos, maze)

  @spec connect(t(), coord(), coord()) :: t()
  def connect(%Maze{} = maze, {x1, y1}, {x2, y2}) do
    if abs(x1 - x2) + abs(y1 - y2) != 1 do
      raise ArgumentError, "cannot connect #{x1}, #{y1} to #{x2}, #{y2}"
    end

    i = x1 + maze.width * y1
    j = x2 + maze.width * y2

    cells =
      cond do
        x1 < x2 ->
          maze.cells
          |> List.update_at(i, fn {{n, _, s, w}, coord} -> {{n, false, s, w}, coord} end)
          |> List.update_at(j, fn {{n, e, s, _}, coord} -> {{n, e, s, false}, coord} end)

        x2 < x1 ->
          maze.cells
          |> List.update_at(i, fn {{n, e, s, _}, coord} -> {{n, e, s, false}, coord} end)
          |> List.update_at(j, fn {{n, _, s, w}, coord} -> {{n, false, s, w}, coord} end)

        y1 < y2 ->
          maze.cells
          |> List.update_at(i, fn {{n, e, _, w}, coord} -> {{n, e, false, w}, coord} end)
          |> List.update_at(j, fn {{_, e, s, w}, coord} -> {{false, e, s, w}, coord} end)

        y2 < y1 ->
          maze.cells
          |> List.update_at(i, fn {{_, e, s, w}, coord} -> {{false, e, s, w}, coord} end)
          |> List.update_at(j, fn {{n, e, _, w}, coord} -> {{n, e, false, w}, coord} end)
      end

    %Maze{maze | cells: cells}
  end
end

defimpl Jason.Encoder, for: Amazing.Maze do
  def encode(maze, opts) do
    {start_x, start_y} = maze.start
    {goal_x, goal_y} = maze.goal
    padding = 32 - rem(maze.width * maze.height, 32)
    cells = maze.cells ++ List.duplicate({{true, true, true, true}, {0, 0}}, padding)

    [
      maze.width,
      maze.height,
      start_x,
      start_y,
      goal_x,
      goal_y
      | cells
        |> Enum.flat_map(fn {walls, _pos} ->
          walls
          |> Tuple.to_list()
        end)
        |> Enum.map(fn
          true -> 1
          false -> 0
        end)
        |> Enum.chunk_every(32)
        |> Enum.map(fn chunk ->
          chunk
          |> Enum.with_index()
          |> Enum.reduce(0, fn
            {1, i}, acc -> Bitwise.bor(acc, 2 ** i)
            {0, _i}, acc -> acc
          end)
        end)
    ]
    |> Jason.Encode.list(opts)
  end
end
