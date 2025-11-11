defmodule SampleApp.LCD.ILI9486 do
  @behaviour SampleApp.LCD.Behaviour

  @impl true
  def start_link(opts) do
    ILI9486.start_link(opts)
  end

  @impl true
  def size(pid) do
    ILI9486.size(pid)
  end

  @impl true
  def display_565(pid, buffer) when is_binary(buffer) do
    ILI9486.display_565(pid, buffer)
  end
end
