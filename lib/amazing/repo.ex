defmodule Amazing.Repo do
  use Ecto.Repo,
    otp_app: :amazing,
    adapter: Ecto.Adapters.Postgres
end
