defmodule Packer.Defs do
  defmacro __using__(_) do
    quote do
      import Packer.Defs

      @c_small_int   0x01 # 1 byte
      @c_small_uint  0x02 # 1 byte
      @c_short_int   0x03 # 2 bytes
      @c_short_uint  0x04 # 2 bytes
      @c_int         0x05 # 4 bytes
      @c_uint        0x06 # 4 bytes
      @c_big_int     0x07 # 8 bytes
      #@c_huge_int   0x08

      @c_byte        0x09 # 1 byte
      @c_binary      0x0A # N bytes
      @c_float       0x0B # 8 bytes
      @c_atom        0x0C # N bytes

      # collections, variable size, marked by an end byte value
      @c_list        0x21
      @c_map         0x22
      @c_collection_end 0x00

      # tuples are size 0..N where N up to 62 is encoded in the type byte
      # and above that the size of the tuple appears as a size as with the
      # other collections. tuple type values therefore range from 0b01000000
      # to 0b01111111, with that last type value being signifying that the next
      # 2 bytes are the length of the tuple
      @c_tuple       0b01000000

      # repeat markers: how many times to repeat the previous schema part
      # recorded in the next 1..4 bytes
      @c_repeat_1    0b10100000 # 1 byte repeat count
      @c_repeat_2    0b10100001 # 2 byte repeat counts
      @c_repeat_4    0b10100010 # 4 bytes repeat count
      #@c_repeat_up   0b10100100

      @c_max_short_tuple 0b01111111 - 0b01000000
      @c_version_header <<0x01>> # '01'
      @c_full_header <<0x45, 0x50, 0x4B, 0x52, 0x01>> # 'EPKR1'
      @c_full_header_prefix <<0x45, 0x50, 0x4B, 0x52>> # 'EPKR'
    end
  end

  defmacro decode_primitive(type, size, binary_desc, default_on_fail) do
    quote do
      defp decode_one(<<unquote(type), rem_schema :: binary>>, buffer, opts) do
        if byte_size(buffer) < unquote(size) do
          decoded(rem_schema, <<>>, opts, unquote(default_on_fail))
        else
          <<term :: unquote(binary_desc), rem_buffer :: binary>> = buffer
          decoded(rem_schema, rem_buffer, opts, term)
        end

      end
    end
  end
end
