defmodule Amazing.Repo.Migrations.AddScoreToPlayers do
  use Ecto.Migration

  def change do
    alter table(:players) do
      add :score, :integer, default: 0, null: false
    end
  end
end
