defmodule Amazing.Repo.Migrations.CreatePlayers do
  use Ecto.Migration

  def change do
    create table(:players) do
      add :name, :string
      add :password_hash, :string

      timestamps()
    end

    create unique_index(:players, [:name])
  end
end
