defmodule Packer.Defs do
  defmacro __using__(_) do
    quote do
      @c_collect_end 0x00
      @c_small_int   0x01
      @c_small_uint  0x02
      @c_short_int   0x03
      @c_short_uint  0x04
      @c_int         0x05
      @c_uint        0x06
      @c_big_int     0x07
      #@c_huge_int   0x08

      @c_byte        0x09
      @c_binary      0x0A
      @c_float       0x0B
      @c_atom        0x0C

      @c_list        0x21
      @c_map         0x22
      @c_tuple       0b01000000
      @c_repeat_1    0b10100000
      @c_repeat_2    0b10100001
      @c_repeat_4    0b10100010
      #@c_repeat_up   0b10100100

      @c_max_short_tuple 0b01111111 - 0b01000000
      @c_header <<0x45, 0x50, 0x4B, 0x52, 0x00, 0x01>> # 'EPKR01'
    end
  end
end
