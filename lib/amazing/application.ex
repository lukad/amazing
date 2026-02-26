defmodule Amazing.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    port = Application.get_env(:amazing, :port)

    children = [
      AmazingWeb.Telemetry,
      Amazing.Repo,
      {DNSCluster, query: Application.get_env(:amazing, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Amazing.PubSub},
      # Start a worker by calling: FoobarTest.Worker.start_link(arg)
      # {Amazing.Worker, arg},
      {Amazing.Game, [generator: Amazing.Maze.Generator.RecursiveBacktracking]},
      {ThousandIsland, port: port, handler_module: Amazing.Handler},
      # Start to serve requests, typically the last entry
      AmazingWeb.Endpoint,
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Amazing.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AmazingWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
