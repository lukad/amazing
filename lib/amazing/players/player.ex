defmodule Amazing.Players.Player do
  use Ecto.Schema
  import Ecto.Changeset

  @type t() :: %__MODULE__{
          name: String.t(),
          password: String.t(),
          password_hash: String.t(),
          score: integer()
        }

  schema "players" do
    field :name, :string
    field :password, :string, virtual: true, redact: true
    field :password_hash, :string, redact: true
    field :score, :integer
    field :color, :string

    timestamps()
  end

  @doc false
  @spec changeset(t() | Ecto.Changeset.t(), any) :: Ecto.Changeset.t()
  def changeset(player, params \\ %{}) do
    player
    |> cast(params, [:name, :password])
    |> validate_required([:name, :password])
    |> unique_constraint(:name)
    |> validate_length(:name, min: 1, max: 16, count: :bytes)
    |> validate_length(:password, min: 8, max: 128)
    |> put_random_color()
    |> validate_format(:color, ~r/^#[0-9A-F]{6}$/i)
    |> put_password_hash()
  end

  def score_changeset(player, params \\ %{}) do
    player
    |> cast(params, [:score])
    |> validate_required([:score])
    |> validate_number(:score, greater_than_or_equal_to: 0)
  end

  # add a random color if no color was given
  defp put_random_color(changeset) do
    if changeset.changes[:color] == nil do
      change(changeset, %{color: random_hex_color()})
    else
      changeset
    end
  end

  defp put_password_hash(
         %Ecto.Changeset{valid?: true, changes: %{password: password}} = changeset
       ) do
    change(changeset, Argon2.add_hash(password))
  end

  defp put_password_hash(changeset), do: changeset

  # Generates random hex colors with the format #RRGGBB
  # The colors should be visible on a dark background and should have a similar brightness
  defp random_hex_color() do
    saturation = 75.0
    lightness = 75.0

    hue = :rand.uniform() * 360.0

    # Convert the HSL values to RGB
    {r, g, b} =
      HSLuv.new(hue, saturation, lightness)
      |> HSLuv.to_rgb()

    # Convert the RGB values to hex
    [r, g, b]
    |> Enum.map(&(&1 * 1.0))
    |> Enum.map(&trunc/1)
    |> Enum.map(&Integer.to_string(&1, 16))
    |> Enum.map(&String.pad_leading(&1, 2, "0"))
    |> Enum.join()
    |> String.upcase()
    |> then(&("#" <> &1))
  end
end
