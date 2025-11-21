defmodule SampleApp.LCD.Behaviour do
  @moduledoc """
  Common behaviour for LCD drivers.
  """

  @type size :: %{width: pos_integer(), height: pos_integer()}

  @callback start_link(opts :: keyword()) :: GenServer.on_start()
  @callback size(pid()) :: size()
  @callback display_565(pid(), binary() | iolist()) :: :ok
end
