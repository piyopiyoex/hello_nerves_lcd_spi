defmodule SampleApp.NetInfo do
  @interfaces ["eth0", "wlan0"]

  def get_status_strings do
    Enum.map(@interfaces, fn iface ->
      addresses = VintageNet.get(["interface", iface, "addresses"]) || []

      ip =
        case Enum.find(addresses, fn a -> a[:family] == :inet end) do
          %{address: {a, b, c, d}} -> "#{a}.#{b}.#{c}.#{d}"
          _ -> "Waiting..."
        end

      formatted_iface = String.pad_trailing(iface, 6)
      "#{formatted_iface}: #{ip}"
    end)
  end
end
