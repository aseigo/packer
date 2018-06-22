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

      @c_float       0x09 # 8 bytes
      @c_byte        0x0A # 1 byte
      @c_binary_1    0x0B # N bytes, 1 byte length
      @c_binary_2    0x0C # N bytes, 1 byte length
      @c_binary_4    0x0D # N bytes, 1 byte length
      @c_atom        0x0E # N bytes

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
      @c_var_size_tuple 0b01111111
      @c_tuple_arity_mask 0b00111111
      @c_version_header <<0x01>> # '01'
      @c_full_header <<0x45, 0x50, 0x4B, 0x52, 0x01>> # 'EPKR1'
      @c_full_header_prefix <<0x45, 0x50, 0x4B, 0x52>> # 'EPKR'
    end
  end

  defmacro debuffer_primitive(type, length_bytes, binary_desc, default_on_fail) do
    quote do
      defp debuffer_one(unquote(type), schema, buffer) do
        if byte_size(buffer) < unquote(length_bytes) do
          decoded(schema, <<>>, unquote(default_on_fail))
        else
          <<term :: unquote(binary_desc), rem_buffer :: binary>> = buffer
          decoded(schema, rem_buffer, term)
        end
      end
    end
  end

  # NOTE:
  # there is some dusky magic in the follownig macro, but boy does it help make the decode module short
  # each invocation creates two functions, one that is a helper to avoid yet another level of nesting.
  # the complexity mostly comes from the fact that this can handle both the needs of atom and binary
  # decoding ...
  defmacro debuffer_binary(type, length_encoding_size, default_on_fail \\ :consume_rest, fun \\ nil) do
    final_term =
      if fun == nil do
        quote do
          term
        end
      else
        quote do
          unquote(fun).(term)
        end
      end

    on_fail =
      if default_on_fail == :consume_rest do
        quote do
          buffer
        end
     else
        default_on_fail
      end


    fn_name =
      type
      |> (fn {_, _, [{x, _, _}]} -> x end).()
      |> Atom.to_string
      |> (fn l -> l <> "_decode_helper" end).()
      |> String.to_atom

    quote do
      defp debuffer_one(unquote(type), schema, buffer) do
        unquote(fn_name)(schema, buffer)
      end

      defp unquote(fn_name)(<<size :: unquote(length_encoding_size)-unsigned-integer, rem_schema :: binary>>, buffer) do
        if byte_size(buffer) < size do
          decoded(rem_schema, <<>>, unquote(on_fail))
        else
          {term, rem_buffer} = String.split_at(buffer, size)
          decoded(rem_schema, rem_buffer, unquote(final_term))
        end
      end

      defp unquote(fn_name)(_schema, buffer) do
        decoded(<<>>, buffer, <<>>)
      end
    end
  end
end
