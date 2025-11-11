defmodule SampleAppTest do
  use ExUnit.Case, async: false

  # NOTE:
  # - We touch Application env and System env, so we back them up and restore.
  # - We don't mock Nerves.Runtime.KV here; in most setups it returns "" unless set.

  @app :sample_app

  setup do
    # backup current envs
    prev_app_env = Application.get_all_env(@app)
    prev_lcd_env = System.get_env("LCD_TYPE")

    on_exit(fn ->
      # restore app env
      Enum.each(Application.get_all_env(@app), fn {k, _} -> Application.delete_env(@app, k) end)
      Enum.each(prev_app_env, fn {k, v} -> Application.put_env(@app, k, v) end)

      # restore system env
      case prev_lcd_env do
        nil -> System.delete_env("LCD_TYPE")
        v -> System.put_env("LCD_TYPE", v)
      end
    end)

    # start each test from a clean slate for keys we care about
    Application.delete_env(@app, :lcd_type)
    System.delete_env("LCD_TYPE")

    :ok
  end

  test "app_name/0 returns the OTP app atom" do
    assert SampleApp.app_name() == :sample_app
  end

  test "lcd_type/0 defaults to \"a\" and is downcased" do
    assert SampleApp.lcd_type() == "a"
    Application.put_env(@app, :lcd_type, "C")
    assert SampleApp.lcd_type() == "c"
  end

  test "app_version/0 returns the running application version as string" do
    assert is_binary(SampleApp.app_version())
  end

  test "display_name/0 composes name, lcd, version, and target" do
    Application.put_env(@app, :lcd_type, "A")
    name = SampleApp.display_name()

    assert name =~ "lcd_a"
    assert name =~ "v" <> SampleApp.app_version()
    assert String.ends_with?(name, " host")
  end

  test "piyopiyoex_rgb565_path/0 points into priv" do
    path = SampleApp.piyopiyoex_rgb565_path()
    assert is_binary(path)
    assert String.contains?(path, "/priv/piyopiyoex_320x480.rgb565")
  end

  test "ui_child_spec/0 and touch_child_spec/0 pick modules for lcd type" do
    Application.put_env(@app, :lcd_type, "A")

    assert SampleApp.ui_child_spec() ==
             {SampleApp.UI.ILI9486, [is_high_speed: false, rotation: 0]}

    assert SampleApp.touch_child_spec() == {SampleApp.Touch.XPT2046, [ui: SampleApp.UI.ILI9486]}
  end
end
