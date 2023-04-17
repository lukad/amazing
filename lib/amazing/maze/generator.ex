defmodule Amazing.Maze.Generator do
  @moduledoc """
  This module defines the behaviour that maze generator algorithms must implement.
  """

  alias Amazing.Maze

  @doc """
  Generates a maze starting at the given start cell.
  """
  @callback generate(Maze.t()) :: Maze.t()

  defmacro __using__(_) do
    quote do
      @behaviour Amazing.Maze.Generator
    end
  end
end
