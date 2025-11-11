import Config

# Use Ringlogger as the logger backend and remove :console.
# See https://hexdocs.pm/ring_logger/readme.html for more information on
# configuring ring_logger.

config :logger, backends: [RingLogger]

# Use shoehorn to start the main application. See the shoehorn
# library documentation for more control in ordering how OTP
# applications are started and handling failures.

config :shoehorn, init: [:nerves_runtime, :nerves_pack]

# Erlinit can be configured without a rootfs_overlay. See
# https://github.com/nerves-project/erlinit/ for more information on
# configuring erlinit.

# Advance the system clock on devices without real-time clocks.
config :nerves, :erlinit, update_clock: true

# Configure the device for SSH IEx prompt access and firmware updates
#
# * See https://hexdocs.pm/nerves_ssh/readme.html for general SSH configuration
# * See https://hexdocs.pm/ssh_subsystem_fwup/readme.html for firmware updates

keys =
  System.user_home!()
  |> Path.join(".ssh/id_{rsa,ecdsa,ed25519}.pub")
  |> Path.wildcard()

if keys == [],
  do:
    Mix.raise("""
    No SSH public keys found in ~/.ssh. An ssh authorized key is needed to
    log into the Nerves device and update firmware on it using ssh.
    See your project's config.exs for this error message.
    """)

config :nerves_ssh,
  authorized_keys: Enum.map(keys, &File.read!/1)

# Configure the network using vintage_net
#
# Update regulatory_domain to your 2-letter country code E.g., "US"
#
# See https://github.com/nerves-networking/vintage_net for more information
config :vintage_net,
  # Japan: JP, US: US, Global: 00, etc
  regulatory_domain: "JP",
  config: [
    {"usb0", %{type: VintageNetDirect}},
    {"eth0",
     %{
       type: VintageNetEthernet,
       ipv4: %{method: :dhcp}
     }},
    {"wlan0", %{type: VintageNetWiFi}}
  ]

config :mdns_lite,
  # The `hosts` key specifies what hostnames mdns_lite advertises.  `:hostname`
  # advertises the device's hostname.local. For the official Nerves systems, this
  # is "nerves-<4 digit serial#>.local".  The `"nerves"` host causes mdns_lite
  # to advertise "nerves.local" for convenience. If more than one Nerves device
  # is on the network, it is recommended to delete "nerves" from the list
  # because otherwise any of the devices may respond to nerves.local leading to
  # unpredictable behavior.

  hosts: [:hostname, "nerves"],
  ttl: 120,

  # Advertise the following services over mDNS.
  services: [
    %{
      protocol: "ssh",
      transport: "tcp",
      port: 22
    },
    %{
      protocol: "sftp-ssh",
      transport: "tcp",
      port: 22
    },
    %{
      protocol: "epmd",
      transport: "tcp",
      port: 4369
    }
  ]

# Import target specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
# Uncomment to use target specific configurations

# import_config "#{Mix.target()}.exs"

lcd_type = System.get_env("LCD_TYPE", "a")

touch_driver =
  case lcd_type do
    "f" ->
      {SampleApp.Touch.GT911, i2c_bus: "i2c-1", int_pin: 4, rst_pin: 17}

    _ ->
      {SampleApp.Touch.XPT2046, spi_bus: "spidev0.1", irq_pin: 17}
  end

lcd_driver =
  case lcd_type do
    "a" ->
      {SampleApp.LCD.ILI9486,
       port: 0,
       lcd_cs: 0,
       dc: 24,
       rst: 25,
       width: 320,
       height: 480,
       pix_fmt: :rgb565,
       rotation: 0,
       is_high_speed: false,
       speed_hz: 10_000_000}

    "b" ->
      {SampleApp.LCD.ILI9486,
       port: 0,
       lcd_cs: 0,
       dc: 24,
       rst: 25,
       width: 320,
       height: 480,
       pix_fmt: :rgb565,
       rotation: 180,
       is_high_speed: false,
       speed_hz: 10_000_000}

    "c" ->
      {SampleApp.LCD.ILI9486,
       port: 0,
       lcd_cs: 0,
       dc: 24,
       rst: 25,
       width: 320,
       height: 480,
       pix_fmt: :rgb565,
       rotation: 0,
       is_high_speed: true,
       speed_hz: 125_000_000}

    "f" ->
      {SampleApp.LCD.ST7796,
       port: 0,
       lcd_cs: 0,
       dc: 22,
       rst: 27,
       width: 320,
       height: 480,
       pix_fmt: :rgb565,
       rotation: 0,
       speed_hz: 60_000_000}

    "g" ->
      {SampleApp.LCD.ST7796,
       port: 0,
       lcd_cs: 0,
       dc: 22,
       rst: 27,
       width: 320,
       height: 480,
       pix_fmt: :rgb565,
       rotation: 180,
       speed_hz: 60_000_000}

    other ->
      Mix.raise("Invalid LCD_TYPE=#{inspect(other)}.")
  end

ui_child = {SampleApp.UI.Demo, lcd_driver: lcd_driver, touch_driver: touch_driver}

config :sample_app, lcd_type: lcd_type, ui_child: ui_child
