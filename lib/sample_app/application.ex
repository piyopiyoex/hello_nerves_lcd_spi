defmodule SampleApp.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    setup_wifi()

    children =
      [
        # Children for all targets
        # Starts a worker by calling: SampleApp.Worker.start_link(arg)
        # {SampleApp.Worker, arg},
      ] ++ target_children()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: SampleApp.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # List all child processes to be supervised
  if Mix.target() == :host do
    defp target_children() do
      [
        # Children that only run on the host during development or test.
        # In general, prefer using `config/host.exs` for differences.
        #
        # Starts a worker by calling: Host.Worker.start_link(arg)
        # {Host.Worker, arg},
      ]
    end
  else
    defp target_children() do
      [
        # Children for all targets except host
        # Starts a worker by calling: Target.Worker.start_link(arg)
        # {Target.Worker, arg},
        SampleApp.ui_mod(),
        SampleApp.touch_mod()
      ]
    end
  end

  defp setup_wifi() do
    kv = Nerves.Runtime.KV.get_all()

    if true?(kv["wifi_force"]) or VintageNet.get_configuration("wlan0") == %{type: VintageNetWiFi} do
      _ = VintageNetWiFi.quick_configure(kv["wifi_ssid"], kv["wifi_passphrase"])
      :ok
    end
  end

  defp true?(""), do: false
  defp true?(nil), do: false
  defp true?("false"), do: false
  defp true?("FALSE"), do: false
  defp true?(_), do: true
end
