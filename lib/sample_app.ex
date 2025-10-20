defmodule SampleApp do
  @moduledoc """
  Documentation for `SampleApp`.
  """

  @default_lcd_type "a"

  def app_name, do: :sample_app

  def lcd_type do
    (get_kv("lcd_type") ||
       Application.get_env(app_name(), :lcd_type) ||
       System.get_env("LCD_TYPE") ||
       @default_lcd_type)
    |> String.downcase()
  end

  def build_target do
    Application.get_env(app_name(), :build_target, "unknown")
  end

  def app_version do
    {:ok, version} = :application.get_key(app_name(), :vsn)
    to_string(version)
  end

  def display_name do
    "lcd_#{lcd_type()} v#{app_version()} #{build_target()}"
  end

  def piyopiypo_rgb565_path do
    Application.app_dir(app_name(), "priv/piyopiyoex_320x480.rgb565")
  end

  def ui_mod do
    case lcd_type() do
      "a" -> SampleApp.LcdA.UI
      "b" -> SampleApp.LcdB.UI
      _ -> SampleApp.LcdA.UI
    end
  end

  def touch_mod do
    case lcd_type() do
      "a" -> SampleApp.LcdA.XPT2046
      "b" -> SampleApp.LcdB.XPT2046
      _ -> SampleApp.LcdA.XPT2046
    end
  end

  defp get_kv(key) do
    try do
      case Nerves.Runtime.KV.get(key) do
        "" -> nil
        v -> v
      end
    catch
      _, _ -> nil
    end
  end
end
