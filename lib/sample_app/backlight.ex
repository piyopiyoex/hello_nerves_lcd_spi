defmodule SampleApp.Backlight do
  @moduledoc """
  バックライト制御モジュール。

  pigpiox に依存せず、SampleApp.PwmBackLight（ソフトウェアPWM）を利用。
  """

  alias SampleApp.PwmBackLight

  @default_pin 18
  @default_period_ms 4

  @doc """
  バックライトPWMを開始します。

  例:
      {:ok, _pid} = SampleApp.Backlight.start(18, 0.5)

  - `pin`: GPIOピン番号（デフォルト18）
  - `duty`: 明るさ（0.0〜1.0）
  - `period_ms`: PWM周期（ミリ秒、デフォルト4）
  """
  def start(pin \\ @default_pin, duty \\ 0.5, period_ms \\ @default_period_ms) do
    PwmBackLight.start_link(pin, duty, period_ms)
  end

  @doc """
  明るさを変更します（duty比 0.0〜1.0）。
  """
  def set_brightness(duty) when is_float(duty) and duty >= 0.0 and duty <= 1.0 do
    PwmBackLight.set_duty(duty)
  end

  @doc """
  バックライトを停止（GPIOをLowに）。
  """
  def stop() do
    PwmBackLight.stop()
  end
end
