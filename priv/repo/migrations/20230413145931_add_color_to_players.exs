defmodule Amazing.Repo.Migrations.AddColorToPlayers do
  use Ecto.Migration

  def change do
    alter table(:players) do
      add :color, :string, default: "#FFFFFF", null: false
    end
  end
end
