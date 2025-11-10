defmodule SampleApp.PwmBackLight do
  @moduledoc """
  ソフトウェアPWMモジュール (GPIO出力ベース)
  バックライトなどの簡易明るさ制御に使用。
  """

  use GenServer
  alias Circuits.GPIO

  @type state :: %{
          gpio: GPIO.gpio_ref(),
          pin: integer(),
          duty: float(),
          period_ms: integer(),
          running: boolean()
        }

  ## --- Public API ---

  @doc """
  PWMを開始します。

  例:
      {:ok, _pid} = SampleApp.PwmBackLight.start_link(18, 0.3, 4)

  第2引数 duty は 0.0〜1.0
  第3引数 period_ms は 1周期あたりの時間（ミリ秒）
  """
  def start_link(pin, duty \\ 0.5, period_ms \\ 4) do
    GenServer.start_link(__MODULE__, {pin, duty, period_ms}, name: __MODULE__)
  end

  @doc """
  明るさ（duty比）を変更。
  """
  def set_duty(duty) when is_float(duty) and duty >= 0.0 and duty <= 1.0 do
    GenServer.cast(__MODULE__, {:set_duty, duty})
  end

  @doc """
  PWMを停止（GPIOをLowに）。
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

    # ON/OFF時間計算
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
