defmodule ST7796 do
  use GenServer
  import Bitwise

  @enforce_keys [:gpio, :opts, :lcd_spi, :data_bus, :display_mode, :chunk_size]
  defstruct [
    :gpio,
    :opts,
    :lcd_spi,
    :pix_fmt,
    :rotation,
    :mad_mode,
    :data_bus,
    :display_mode,
    :chunk_size
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    port = opts[:port] || 0
    lcd_cs = opts[:lcd_cs] || 0
    dc = opts[:dc] || 24
    speed_hz = opts[:speed_hz] || 16_000_000
    width = opts[:width] || 480
    height = opts[:height] || 320
    offset_top = opts[:offset_top] || 0
    offset_left = opts[:offset_left] || 0
    rst = opts[:rst]
    pix_fmt = opts[:pix_fmt] || :bgr565
    rotation = opts[:rotation] || 90
    mad_mode = opts[:mad_mode] || :right_down
    display_mode = opts[:display_mode] || :normal
    is_high_speed = opts[:is_high_speed] || false

    chunk_size =
      case opts[:chunk_size] do
        n when is_integer(n) and n > 0 -> n
        _ -> if is_high_speed, do: 0x8000, else: 4_096
      end

    data_bus = if is_high_speed, do: :parallel_16bit, else: :parallel_8bit

    lcd_spi =
      Keyword.get_lazy(opts, :spi_lcd, fn ->
        {:ok, bus} = _init_spi(port, lcd_cs, speed_hz)
        bus
      end)

    gpio_dc =
      Keyword.get_lazy(opts, :gpio_dc, fn ->
        {:ok, pin} = Circuits.GPIO.open(dc, :output)
        pin
      end)

    gpio_rst =
      Keyword.get_lazy(opts, :gpio_rst, fn ->
        if rst, do: _init_reset(rst)
      end)

    display =
      %__MODULE__{
        lcd_spi: lcd_spi,
        gpio: [dc: gpio_dc, rst: gpio_rst],
        opts: [
          port: port,
          lcd_cs: lcd_cs,
          dc: dc,
          speed_hz: speed_hz,
          width: width,
          height: height,
          offset_top: offset_top,
          offset_left: offset_left,
          rst: rst
        ],
        pix_fmt: pix_fmt,
        rotation: rotation,
        mad_mode: mad_mode,
        data_bus: data_bus,
        display_mode: display_mode,
        chunk_size: chunk_size
      }
      |> _reset()
      |> _init(is_high_speed)

    {:ok, display}
  end

  @impl true
  def terminate(_reason, %{lcd_spi: lcd_spi, gpio: gpio}) do
    dc_pin = gpio[:dc]
    rst_pin = gpio[:rst]

    Circuits.SPI.close(lcd_spi)
    Circuits.GPIO.close(dc_pin)
    if rst_pin, do: Circuits.GPIO.close(rst_pin)

    :ok
  end

  def reset(self_pid) do
    GenServer.call(self_pid, :reset)
  end

  defp _reset(display = %__MODULE__{gpio: gpio}) do
    gpio_rst = gpio[:rst]

    if gpio_rst != nil do
      Circuits.GPIO.write(gpio_rst, 1)
      :timer.sleep(500)
      Circuits.GPIO.write(gpio_rst, 0)
      :timer.sleep(500)
      Circuits.GPIO.write(gpio_rst, 1)
      :timer.sleep(500)
    end

    display
  end

  def size(self_pid) do
    GenServer.call(self_pid, :size)
  end

  defp _size(%__MODULE__{opts: opts}) do
    %{height: opts[:height], width: opts[:width]}
  end

  def pix_fmt(self_pid) do
    GenServer.call(self_pid, :pix_fmt)
  end

  defp _pix_fmt(%__MODULE__{pix_fmt: pix_fmt}) do
    pix_fmt
  end

  def set_pix_fmt(self_pid, pix_fmt)
      when pix_fmt in [:bgr565, :rgb565, :bgr666, :rgb666] do
    GenServer.call(self_pid, {:set_pix_fmt, pix_fmt})
  end

  defp _set_pix_fmt(display = %__MODULE__{}, pix_fmt)
       when pix_fmt in [:bgr565, :rgb565, :bgr666, :rgb666] do
    display = %__MODULE__{display | pix_fmt: pix_fmt}

    display
    |> _command(kPIXFMT(), cmd_data: _get_pix_fmt(display))
    |> _command(kMADCTL(), cmd_data: _mad_mode(display))
  end

  def set_display(self_pid, status) when status in [:on, :off] do
    GenServer.call(self_pid, {:set_display, status})
  end

  defp _set_display(display = %__MODULE__{}, :on) do
    _command(display, kDISPON())
  end

  defp _set_display(display = %__MODULE__{}, :off) do
    _command(display, kDISPOFF())
  end

  def set_display_mode(self_pid, display_mode) do
    GenServer.call(self_pid, {:set_display_mode, display_mode})
  end

  defp _set_display_mode(display = %__MODULE__{}, :normal) do
    %__MODULE__{display | display_mode: :normal}
    |> _command(kIDLEOFF())
    |> _command(kNORON())
  end

  defp _set_display_mode(display = %__MODULE__{}, :partial) do
    %__MODULE__{display | display_mode: :partial}
    |> _command(kIDLEOFF())
    |> _command(kPTLON())
  end

  defp _set_display_mode(display = %__MODULE__{}, :idle) do
    %__MODULE__{display | display_mode: :idle}
    |> _command(kIDLEON())
  end

  def display_565(self_pid, image_data) when is_binary(image_data) or is_list(image_data) do
    GenServer.call(self_pid, {:display_565, image_data})
  end

  defp _display_565(display, image_data) when is_binary(image_data) do
    _display_565(display, :binary.bin_to_list(image_data))
  end

  defp _display_565(display, image_data) when is_list(image_data) do
    display
    |> _set_window(x0: 0, y0: 0, x1: nil, y1: nil)
    |> _send(image_data, true, false)
  end

  def display_666(self_pid, image_data) when is_binary(image_data) or is_list(image_data) do
    GenServer.call(self_pid, {:display_666, image_data})
  end

  defp _display_666(display, image_data) when is_binary(image_data) do
    _display_666(display, :binary.bin_to_list(image_data))
  end

  defp _display_666(display, image_data) when is_list(image_data) do
    display
    |> _set_window(x0: 0, y0: 0, x1: nil, y1: nil)
    |> _send(image_data, true, false)
  end

  def display(self_pid, image_data, source_color)
      when is_binary(image_data) and source_color in [:rgb888, :bgr888] do
    GenServer.call(self_pid, {:display, image_data, source_color})
  end

  defp _display(display = %__MODULE__{pix_fmt: target_color}, image_data, source_color)
       when is_binary(image_data) and source_color in [:rgb888, :bgr888] and
              target_color in [:rgb565, :bgr565] do
    _display_565(display, _to_565(image_data, source_color, target_color))
  end

  defp _display(display = %__MODULE__{pix_fmt: target_color}, image_data, source_color)
       when is_binary(image_data) and source_color in [:rgb888, :bgr888] and
              target_color in [:rgb666, :bgr666] do
    _display_666(display, _to_666(image_data, source_color, target_color))
  end

  defp _display(display, image_data, source_color)
       when is_list(image_data) and source_color in [:rgb888, :bgr888] do
    _display(display, image_data_to_binary(image_data), source_color)
  end

  defp image_data_to_binary(image_data) do
    image_data
    |> Enum.map(fn
      row when is_list(row) -> Enum.map(row, &<<&1::8>>)
      byte when is_integer(byte) -> <<byte::8>>
    end)
    |> IO.iodata_to_binary()
  end

  def command(self_pid, cmd, opts \\ []) when is_integer(cmd) do
    GenServer.call(self_pid, {:command, cmd, opts})
  end

  defp _command(display, cmd, opts \\ [])

  defp _command(display = %__MODULE__{data_bus: :parallel_8bit}, cmd, opts)
       when is_integer(cmd) do
    cmd_data = opts[:cmd_data] || []
    delay = opts[:delay] || 0

    display
    |> _send(cmd, false, false)
    |> _data(cmd_data)

    :timer.sleep(delay)
    display
  end

  defp _command(display = %__MODULE__{data_bus: :parallel_16bit}, cmd, opts)
       when is_integer(cmd) do
    cmd_data = opts[:cmd_data] || []
    delay = opts[:delay] || 0

    display
    |> _send(cmd, false, true)
    |> _data(cmd_data)

    :timer.sleep(delay)
    display
  end

  def data(_self_pid, []), do: :ok

  def data(self_pid, data) do
    GenServer.call(self_pid, {:data, data})
  end

  defp _data(display, []), do: display

  defp _data(display = %__MODULE__{data_bus: :parallel_8bit}, data) do
    _send(display, data, true, false)
  end

  defp _data(display = %__MODULE__{data_bus: :parallel_16bit}, data) do
    _send(display, data, true, true)
  end

  def send(self_pid, bytes, is_data)
      when (is_integer(bytes) or is_list(bytes)) and is_boolean(is_data) do
    GenServer.call(self_pid, {:send, bytes, is_data})
  end

  defp to_be_u16(u8_bytes) do
    u8_bytes
    |> Enum.map(fn u8 -> [0x00, u8] end)
    |> IO.iodata_to_binary()
  end

  defp chunk_binary(binary, chunk_size) when is_binary(binary) do
    total_bytes = byte_size(binary)
    full_chunks = div(total_bytes, chunk_size)

    chunks =
      if full_chunks > 0 do
        for i <- 0..(full_chunks - 1), reduce: [] do
          acc -> [:binary.part(binary, chunk_size * i, chunk_size) | acc]
        end
      else
        []
      end

    remaining = rem(total_bytes, chunk_size)

    chunks =
      if remaining > 0 do
        [:binary.part(binary, chunk_size * full_chunks, remaining) | chunks]
      else
        chunks
      end

    Enum.reverse(chunks)
  end

  defp _send(display, bytes, is_data, to_be16 \\ false)

  defp _send(display = %__MODULE__{}, bytes, true, to_be16) do
    _send(display, bytes, 1, to_be16)
  end

  defp _send(display = %__MODULE__{}, bytes, false, to_be16) do
    _send(display, bytes, 0, to_be16)
  end

  defp _send(display = %__MODULE__{}, bytes, is_data, to_be16)
       when is_data in [0, 1] and is_integer(bytes) do
    _send(display, <<band(bytes, 0xFF)>>, is_data, to_be16)
  end

  defp _send(display = %__MODULE__{}, bytes, is_data, to_be16)
       when is_data in [0, 1] and is_list(bytes) do
    _send(display, IO.iodata_to_binary(bytes), is_data, to_be16)
  end

  defp _send(
         display = %__MODULE__{gpio: gpio, lcd_spi: spi, chunk_size: chunk_size},
         bytes,
         is_data,
         to_be16
       )
       when is_data in [0, 1] and is_binary(bytes) do
    gpio_dc = gpio[:dc]
    bytes = if to_be16, do: to_be_u16(:binary.bin_to_list(bytes)), else: bytes

    Circuits.GPIO.write(gpio_dc, is_data)

    for xfdata <- chunk_binary(bytes, chunk_size) do
      {:ok, _ret} = Circuits.SPI.transfer(spi, xfdata)
    end

    display
  end

  @impl true
  def handle_call(:reset, _from, display) do
    {:reply, :ok, _reset(display)}
  end

  @impl true
  def handle_call(:size, _from, display) do
    {:reply, _size(display), display}
  end

  @impl true
  def handle_call(:pix_fmt, _from, display) do
    {:reply, _pix_fmt(display), display}
  end

  @impl true
  def handle_call({:set_pix_fmt, pix_fmt}, _from, display) do
    {:reply, :ok, _set_pix_fmt(display, pix_fmt)}
  end

  @impl true
  def handle_call({:set_display, status}, _from, display) do
    {:reply, :ok, _set_display(display, status)}
  end

  @impl true
  def handle_call({:set_display_mode, display_mode}, _from, display) do
    {:reply, :ok, _set_display_mode(display, display_mode)}
  end

  @impl true
  def handle_call({:display_565, image_data}, _from, display) do
    {:reply, :ok, _display_565(display, image_data)}
  end

  @impl true
  def handle_call({:display_666, image_data}, _from, display) do
    {:reply, :ok, _display_666(display, image_data)}
  end

  @impl true
  def handle_call({:display, image_data, source_color}, _from, display) do
    {:reply, :ok, _display(display, image_data, source_color)}
  end

  @impl true
  def handle_call({:command, cmd, opts}, _from, display) do
    {:reply, :ok, _command(display, cmd, opts)}
  end

  @impl true
  def handle_call({:data, data}, _from, display) do
    {:reply, :ok, _data(display, data)}
  end

  @impl true
  def handle_call({:send, bytes, is_data}, _from, display) do
    {:reply, :ok, _send(display, bytes, is_data)}
  end

  defp _init_spi(_port, nil, _speed_hz), do: {:ok, nil}

  defp _init_spi(port, cs, speed_hz) when cs >= 0 do
    Circuits.SPI.open("spidev#{port}.#{cs}", speed_hz: speed_hz)
  end

  defp _init_spi(_port, _cs, _speed_hz), do: {:error, :invalid_cs}

  defp _init_reset(nil), do: nil

  defp _init_reset(rst) when rst >= 0 do
    {:ok, gpio} = Circuits.GPIO.open(rst, :output)
    gpio
  end

  defp _init_reset(_), do: nil

  defp _get_channel_order(%__MODULE__{pix_fmt: :rgb565}), do: kMAD_RGB()
  defp _get_channel_order(%__MODULE__{pix_fmt: :bgr565}), do: kMAD_BGR()
  defp _get_channel_order(%__MODULE__{pix_fmt: :rgb666}), do: kMAD_RGB()
  defp _get_channel_order(%__MODULE__{pix_fmt: :bgr666}), do: kMAD_BGR()

  defp _get_pix_fmt(%__MODULE__{pix_fmt: :rgb565}), do: k16BIT_PIX()
  defp _get_pix_fmt(%__MODULE__{pix_fmt: :bgr565}), do: k16BIT_PIX()
  defp _get_pix_fmt(%__MODULE__{pix_fmt: :rgb666}), do: k18BIT_PIX()
  defp _get_pix_fmt(%__MODULE__{pix_fmt: :bgr666}), do: k18BIT_PIX()

  defp _mad_mode(display = %__MODULE__{rotation: 0, mad_mode: :right_down}) do
    display
    |> _get_channel_order()
    |> bor(kMAD_X_RIGHT())
    |> bor(kMAD_Y_DOWN())
  end

  defp _mad_mode(display = %__MODULE__{rotation: 90, mad_mode: :right_down}) do
    display
    |> _get_channel_order()
    |> bor(kMAD_X_LEFT())
    |> bor(kMAD_Y_DOWN())
    |> bor(kMAD_VERTICAL())
  end

  defp _mad_mode(display = %__MODULE__{rotation: 180, mad_mode: :right_down}) do
    display
    |> _get_channel_order()
    |> bor(kMAD_X_LEFT())
    |> bor(kMAD_Y_UP())
  end

  defp _mad_mode(display = %__MODULE__{rotation: 270, mad_mode: :right_down}) do
    display
    |> _get_channel_order()
    |> bor(kMAD_X_RIGHT())
    |> bor(kMAD_Y_UP())
    |> bor(kMAD_VERTICAL())
  end

  defp _mad_mode(display = %__MODULE__{rotation: 0, mad_mode: :right_up}) do
    display
    |> _get_channel_order()
    |> bor(kMAD_X_RIGHT())
    |> bor(kMAD_Y_UP())
  end

  defp _mad_mode(display = %__MODULE__{rotation: 90, mad_mode: :right_up}) do
    display
    |> _get_channel_order()
    |> bor(kMAD_X_RIGHT())
    |> bor(kMAD_Y_DOWN())
    |> bor(kMAD_VERTICAL())
  end

  defp _mad_mode(display = %__MODULE__{rotation: 180, mad_mode: :right_up}) do
    display
    |> _get_channel_order()
    |> bor(kMAD_X_LEFT())
    |> bor(kMAD_Y_DOWN())
  end

  defp _mad_mode(display = %__MODULE__{rotation: 270, mad_mode: :right_up}) do
    display
    |> _get_channel_order()
    |> bor(kMAD_X_LEFT())
    |> bor(kMAD_Y_UP())
    |> bor(kMAD_VERTICAL())
  end

  defp _mad_mode(display = %__MODULE__{rotation: 0, mad_mode: :rgb_mode}) do
    display
    |> _get_channel_order()
    |> bor(kMAD_X_LEFT())
    |> bor(kMAD_Y_DOWN())
  end

  defp _mad_mode(display = %__MODULE__{rotation: 90, mad_mode: :rgb_mode}) do
    display
    |> _get_channel_order()
    |> bor(kMAD_X_RIGHT())
    |> bor(kMAD_Y_DOWN())
  end

  defp _mad_mode(display = %__MODULE__{rotation: 180, mad_mode: :rgb_mode}) do
    display
    |> _get_channel_order()
    |> bor(kMAD_X_RIGHT())
    |> bor(kMAD_Y_UP())
  end

  defp _mad_mode(display = %__MODULE__{rotation: 270, mad_mode: :rgb_mode}) do
    display
    |> _get_channel_order()
    |> bor(kMAD_X_LEFT())
    |> bor(kMAD_Y_UP())
  end

  defp _init(display = %__MODULE__{}, _is_high_speed) do
    display
    |> _command(kSWRESET(), delay: 120)
    |> _command(kSLPOUT(), delay: 120)
    |> _command(kPIXFMT(), cmd_data: _get_pix_fmt(display))
    |> _command(kMADCTL(), cmd_data: _mad_mode(display))
    |> _command(kCMDSET(), cmd_data: 0xC3)
    |> _command(kCMDSET(), cmd_data: 0x96)
    |> _command(kINVCTR(), cmd_data: 0x01)
    |> _command(kDISPCTRL(), cmd_data: 0xC6)
    |> _command(kPWCTR1(), cmd_data: [0x80, 0x45])
    |> _command(kPWCTR2(), cmd_data: 0x13)
    |> _command(kPWCTR3(), cmd_data: 0xA7)
    |> _command(kVMCTR1(), cmd_data: 0x0A)
    |> _command(kADJCTRL3())
    |> _data([0x40, 0x8A, 0x00, 0x00, 0x29, 0x19, 0xA5, 0x33])
    |> _command(kPGAMCTRL())
    |> _data([0xD0, 0x08, 0x0F, 0x06, 0x06, 0x33, 0x30, 0x33, 0x47, 0x17, 0x13, 0x13, 0x2B, 0x31])
    |> _command(kNGAMCTRL())
    |> _data([0xD0, 0x0A, 0x11, 0x0B, 0x09, 0x07, 0x2F, 0x33, 0x47, 0x38, 0x15, 0x16, 0x2C, 0x32])
    |> _command(kCMDSET(), cmd_data: 0x3C)
    |> _command(kCMDSET(), cmd_data: 0x69)
    |> _set_display_mode(:normal)
    |> _command(kINVON())
    |> _command(kDISPON(), delay: 100)
  end

  defp _set_window(display = %__MODULE__{opts: board}, opts) do
    width = board[:width]
    height = board[:height]
    offset_top = board[:offset_top]
    offset_left = board[:offset_left]

    x0 = opts[:x0] || 0
    x1 = opts[:x1] || width - 1
    y0 = opts[:y0] || 0
    y1 = opts[:y1] || height - 1

    y0 = y0 + offset_top
    y1 = y1 + offset_top
    x0 = x0 + offset_left
    x1 = x1 + offset_left

    display
    |> _command(kCASET())
    |> _data(bsr(x0, 8))
    |> _data(band(x0, 0xFF))
    |> _data(bsr(x1, 8))
    |> _data(band(x1, 0xFF))
    |> _command(kPASET())
    |> _data(bsr(y0, 8))
    |> _data(band(y0, 0xFF))
    |> _data(bsr(y1, 8))
    |> _data(band(y1, 0xFF))
    |> _command(kRAMWR())
  end

  defp _to_565(image_data, source_color, target_color)
       when is_binary(image_data) do
    image_data
    |> CvtColor.cvt(source_color, target_color)
    |> :binary.bin_to_list()
  end

  defp _to_666(image_data, :bgr888, :bgr666)
       when is_binary(image_data) do
    image_data
    |> :binary.bin_to_list()
  end

  defp _to_666(image_data, source_color, target_color)
       when is_binary(image_data) do
    image_data
    |> CvtColor.cvt(source_color, target_color)
    |> :binary.bin_to_list()
  end

  def kSWRESET, do: 0x01
  def kSLPOUT, do: 0x11
  def kNORON, do: 0x13
  def kPTLON, do: 0x12
  def kINVOFF, do: 0x20
  def kINVON, do: 0x21
  def kDISPOFF, do: 0x28
  def kDISPON, do: 0x29
  def kCASET, do: 0x2A
  def kPASET, do: 0x2B
  def kRAMWR, do: 0x2C
  def kMADCTL, do: 0x36
  def kIDLEOFF, do: 0x38
  def kIDLEON, do: 0x39
  def kPIXFMT, do: 0x3A
  def kINVCTR, do: 0xB4
  def kDISPCTRL, do: 0xB7
  def kPWCTR1, do: 0xC0
  def kPWCTR2, do: 0xC1
  def kPWCTR3, do: 0xC2
  def kVMCTR1, do: 0xC5
  def kADJCTRL3, do: 0xE8
  def kPGAMCTRL, do: 0xE0
  def kNGAMCTRL, do: 0xE1
  def kCMDSET, do: 0xF0
  def kMAD_RGB, do: 0x08
  def kMAD_BGR, do: 0x00
  def kMAD_VERTICAL, do: 0x20
  def kMAD_X_RIGHT, do: 0x40
  def kMAD_X_LEFT, do: 0x00
  def kMAD_Y_UP, do: 0x80
  def kMAD_Y_DOWN, do: 0x00
  def k16BIT_PIX, do: 0x55
  def k18BIT_PIX, do: 0x66
end
