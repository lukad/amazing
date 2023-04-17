defmodule Amazing.Maze.Generator.RecursiveBacktracking do
  @moduledoc """
  Uses recursive backtracking to generate a maze.

  This algorithm generates very esthetically pleasing mazes
  with long and winding corridors.
  """

  alias Amazing.Maze

  use Maze.Generator

  @impl Maze.Generator
  def generate(%Maze{} = maze) do
    visited = MapSet.new() |> MapSet.put(maze.start)
    candidates = unvisited_neighbors(maze, maze.start, visited)
    generate(maze, maze.start, visited, [], candidates)
  end

  defp generate(maze, _current, _visited, [], []), do: maze

  defp generate(maze, current, visited, [next | rest], []) do
    visited = MapSet.put(visited, current)
    candidates = unvisited_neighbors(maze, next, visited)
    generate(maze, next, visited, rest, candidates)
  end

  defp generate(maze, current, visited, stack, candidates) do
    visited = MapSet.put(visited, current)

    stack =
      if length(candidates) > 1 do
        [current | stack]
      else
        stack
      end

    next = get_random(candidates)
    maze = Maze.connect(maze, current, next)
    candidates = unvisited_neighbors(maze, next, visited)
    generate(maze, next, visited, stack, candidates)
  end

  defp unvisited_neighbors(maze, coord, visited) do
    Maze.neighbor_coords(coord, maze)
    |> Enum.reject(&MapSet.member?(visited, &1))
  end

  defp get_random([]), do: nil

  defp get_random(list) do
    index = :rand.uniform(length(list))
    index = index - 1
    Enum.at(list, index)
  end
end
