defmodule SampleApp.Touch.None do
  @moduledoc """
  タッチ入力を扱わないダミードライバ。
  """

  @behaviour SampleApp.Touch.Behaviour

  @impl true
  def init(_opts), do: {:ok, :no_state}

  @impl true
  def read_touch(state), do: {:ok, :no_touch, state}
end
