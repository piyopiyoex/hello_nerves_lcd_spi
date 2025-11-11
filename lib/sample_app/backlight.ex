defmodule SampleApp.Backlight do
  @moduledoc """
  バックライト制御モジュール。

  pigpiox に依存せず、内部でソフトウェアPWMを実装。
  バックライトなどの簡易明るさ制御に利用します。
  """

  use GenServer
  alias Circuits.GPIO

  @default_pin 18
  @default_period_ms 4

  @type state :: %{
          gpio: GPIO.gpio_ref(),
          pin: integer(),
          duty: float(),
          period_ms: integer(),
          running: boolean()
        }

  ## --- Public API ---

  @doc """
  バックライトPWMを開始します。

  例:
      {:ok, _pid} = SampleApp.Backlight.start(18, 0.5)

  - `pin`: GPIOピン番号（デフォルト18）
  - `duty`: 明るさ（0.0〜1.0）
  - `period_ms`: PWM周期（ミリ秒、デフォルト4）
  """
  def start(pin \\ @default_pin, duty \\ 0.5, period_ms \\ @default_period_ms) do
    GenServer.start_link(__MODULE__, {pin, duty, period_ms}, name: __MODULE__)
  end

  @doc """
  明るさを変更します（duty比 0.0〜1.0）。
  """
  def set_brightness(duty) when is_float(duty) and duty >= 0.0 and duty <= 1.0 do
    GenServer.cast(__MODULE__, {:set_duty, duty})
  end

  @doc """
  バックライトを停止（GPIOをLowに）。
  """
  def stop() do
    GenServer.cast(__MODULE__, :stop)
  end

  ## --- Callbacks ---

  @impl true
  def init({pin, duty, period_ms}) do
    {:ok, gpio} = GPIO.open(pin, :output)

    state = %{
      gpio: gpio,
      pin: pin,
      duty: duty,
      period_ms: period_ms,
      running: true
    }

    Process.send_after(self(), :pwm_cycle, 0)
    {:ok, state}
  end

  @impl true
  def handle_cast({:set_duty, duty}, state) do
    {:noreply, %{state | duty: duty}}
  end

  @impl true
  def handle_cast(:stop, state) do
    GPIO.write(state.gpio, 0)
    {:noreply, %{state | running: false}}
  end

  @impl true
  def handle_info(:pwm_cycle, %{running: true} = state) do
    %{gpio: gpio, duty: duty, period_ms: period_ms} = state

    on_time = trunc(period_ms * duty)
    off_time = period_ms - on_time

    if on_time > 0 do
      GPIO.write(gpio, 1)
      Process.sleep(on_time)
    end

    if off_time > 0 do
      GPIO.write(gpio, 0)
      Process.sleep(off_time)
    end

    Process.send_after(self(), :pwm_cycle, 0)
    {:noreply, state}
  end

  def handle_info(:pwm_cycle, %{running: false} = state), do: {:noreply, state}
end
