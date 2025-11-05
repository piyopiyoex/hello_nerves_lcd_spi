defmodule SampleApp.NetInfo do
  if Mix.target() == :host do
    def get_status_strings, do: ["foo: 0.0.0.0", "bar: 0.0.0.0"]
    def get_ssid, do: "foo"
    def get_ssid(_iface), do: get_ssid()
  else
    def get_status_strings do
      Enum.map(["eth0", "wlan0"], fn interface ->
        addresses = VintageNet.get(["interface", interface, "addresses"]) || []

        ip =
          case Enum.find(addresses, fn a -> a[:family] == :inet end) do
            %{address: {a, b, c, d}} -> "#{a}.#{b}.#{c}.#{d}"
            _ -> "Waiting..."
          end

        formatted_iface = String.pad_trailing(interface, 6)
        "#{formatted_iface}: #{ip}"
      end)
    end

    def get_ssid(iface \\ "wlan0") do
      case VintageNet.get(["interface", iface, "wifi", "current_ap"]) do
        %VintageNetWiFi.AccessPoint{ssid: ssid} -> ssid
        _ -> "No SSID"
      end
    end
  end
end
