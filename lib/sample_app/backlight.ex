defmodule SampleApp.Backlight do
  if Mix.target() == :host do
    def set_pwm(_gpio, _frequency, _duty_millionths), do: :ok
  else
    def set_pwm(gpio, frequency, duty_millionths) do
      Pigpiox.Pwm.hardware_pwm(gpio, frequency, duty_millionths)
    end
  end
end
