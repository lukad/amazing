defmodule Amazing.Maze.Generator.Prims do
  @moduledoc """
  Uses Prim's algorithm to generate a maze.

  This algorithm is one of the simplest ones for maze generation.
  The results however are not the prettiest as it results in many short and straight corridors.
  """
  alias Amazing.Maze

  use Maze.Generator

  @impl Maze.Generator
  def generate(%Maze{} = maze) do
    visited = MapSet.new() |> MapSet.put(maze.start)
    candidates = Maze.neighbor_coords(maze.start, maze)
    generate(maze, visited, candidates)
  end

  defp generate(maze, _visited, []), do: maze

  defp generate(maze, visited, candidates) do
    {next, candidates} = pop_random(candidates)

    candidates =
      next
      |> Maze.neighbor_coords(maze)
      |> Enum.reject(&MapSet.member?(visited, &1))
      |> Enum.concat(candidates)
      |> Enum.uniq()

    {to, _} =
      next
      |> Maze.neighbor_coords(maze)
      |> Enum.into(MapSet.new())
      |> MapSet.intersection(visited)
      |> MapSet.to_list()
      |> pop_random()

    visited = MapSet.put(visited, next)
    maze = Maze.connect(maze, next, to)

    generate(maze, visited, candidates)
  end

  defp pop_random(list) do
    index = :rand.uniform(length(list))
    index = index - 1
    {item, rest} = List.pop_at(list, index)
    {item, rest}
  end
end
