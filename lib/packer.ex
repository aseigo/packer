defmodule Packer do
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
  #@c_header_magic <<0x45, 0x50, 0x4B, 0x52>> # 'EPKR'

  use Bitwise

  # TODO
  #
  # * schema compression actually inflates the size of encode({1, 2})
  #
  # * implement @c_huge_int
  #
  # * compressing the schema probably should be done while building the schema
  #   to avoid going through it more than once.
  #   this would perhaps open up additional opportunities for efficiency when
  #   small and not-so-small numbers end up alternating
  #
  # * consider adding a "this list is just small numbers" to save a few bytes
  #   this is a trick :erlang.term_to_binary employs, implying such lists are
  #   super common enough to warrant a unique id and saving an extra byte or two

  def encode(term) do
    #TODO: measure if the schema performs better as a :queue?
    {schema, buffer} = e([], <<>>, term)
    encoded_schema = schema
                     |> Enum.reverse()
                     |> encode_schema()

    if byte_size(buffer) > 15 do
      z = :zlib.open()
      :ok = :zlib.deflateInit(z)
      [compressed_buffer] = :zlib.deflate(z, buffer, :finish)
      :ok = :zlib.deflateEnd(z)
      :zlib.close(z)
      if byte_size(compressed_buffer) < byte_size(buffer) do
        [encoded_schema, compressed_buffer]
      else
        [encoded_schema, buffer]
      end
    else
      [encoded_schema, buffer]
    end
  end

  defp encode_schema(schema) do
    Enum.reduce(schema, <<>>, &encode_schema/2)
    #length = byte_size(encoded)
    #<<length :: 32-unsigned-integer, encoded :: binary>>
  end

  defp encode_schema({@c_atom, length}, acc) do
    acc <> <<@c_atom :: 8-unsigned-integer, length :: 8-unsigned-integer>>
  end

  defp encode_schema({@c_tuple, arity, elements}, acc) do
    subschema = encode_schema(elements)
    if arity < @c_max_short_tuple do
      acc <> <<@c_tuple + arity :: 8-unsigned-integer>> <> subschema
    else
      acc <> <<@c_tuple :: 8-unsigned-integer, arity :: 16-unsigned-integer>> <> subschema
    end
  end

  defp encode_schema({@c_map, elements}, acc) do
    encoded_elements =
      Enum.reduce(elements, <<>>, fn
        {value, key}, e ->
          e = encode_schema(value, e)
          encode_schema(key, e)

        value, e ->
          # repeaters, e.g.
          encode_schema(value, e)
      end)

    acc <> <<@c_map:: 8-unsigned-integer>> <> encoded_elements <> <<@c_collect_end>>
  end

  defp encode_schema({:rep, @c_repeat_1, reps}, acc) do
    acc <> <<@c_repeat_1 :: 8-unsigned-integer, reps :: 8-unsigned-integer>>
  end

  defp encode_schema({:rep, @c_repeat_2, reps}, acc) do
    acc <> <<@c_repeat_1 :: 8-unsigned-integer, reps :: 16-unsigned-integer>>
  end

  defp encode_schema({:rep, @c_repeat_4, reps}, acc) do
    acc <> <<@c_repeat_1 :: 8-unsigned-integer, reps :: 32-unsigned-integer>>
  end

  defp encode_schema({code, elements}, acc) when is_list(elements) do
    acc <> <<code :: 8-unsigned-integer>> <> encode_schema(elements) <> <<@c_collect_end>>
  end

  defp encode_schema({code, length}, acc) do
    acc <> <<code :: 8-unsigned-integer, length :: 32-unsigned-integer>>
  end

  defp encode_schema(code, acc) do
    acc <> <<code :: 8-unsigned-integer>>
  end

  defp compress_schema(schema) do
    compress_schema(schema, [], :__nothing_equals_me__, 0)
    |> Enum.reverse()
  end

  defp compress_schema([], schema, :__nothing_equals_me__, 0), do: schema
  defp compress_schema([], schema, last, 0), do: [last | schema]
  defp compress_schema([], schema, last, reps), do: [last, repeater_tuple(reps) | schema]
  defp compress_schema([next | rest], schema, last, reps) when next === last do
    compress_schema(rest, schema, last, reps + 1)
  end
  defp compress_schema([next | rest], schema, last, reps) when reps > 0 do
    compress_schema(rest, [last, repeater_tuple(reps) | schema], next, 0)
  end
  defp compress_schema([next | rest], schema, :__nothing_equals_me__, _reps) do
    compress_schema(rest, schema, next, 0)
  end
  defp compress_schema([next | rest], schema, last, _reps) do
    compress_schema(rest, [last | schema], next, 0)
  end

  # note: 1 is added to the reps since at the time of being called, the last
  # rep will have not been tallied, or looked at another way the first item
  # is "zeroth rep'd", and so we always are one short here
  defp repeater_tuple(reps) when reps < 256, do: {:rep, @c_repeat_1, reps + 1}
  defp repeater_tuple(reps) when reps < 65536, do: {:rep, @c_repeat_2, reps + 1}
  defp repeater_tuple(reps), do: {:rep, @c_repeat_4, reps + 1}

  defp e(schema, buffer, t) when is_tuple(t) do
    arity = tuple_size(t)
    {tuple_schema, buffer} = add_tuple([], buffer, t, arity, 0)
    tuple_schema = tuple_schema
                   |> Enum.reverse()
                   |> compress_schema()

    {[{@c_tuple, arity, tuple_schema} | schema], buffer}
  end

  defp e(schema, buffer, t) when is_map(t) do
    case Map.get(t, :__struct__) do
      nil    -> add_map(schema, buffer, t)
      module -> add_struct(schema, buffer, t, module)
    end
  end

  defp e(schema, buffer, t) when is_list(t) do
    {list_schema, buffer} = add_list([], buffer, t)
    list_schema = compress_schema(list_schema)
    {[{@c_list, list_schema} | schema], buffer}
  end

  defp e(schema, buffer, t) when is_integer(t) do
    add_integer(schema, buffer, t)
  end

  defp e(schema, buffer, <<_byte :: 8>> = t) do
    {[@c_byte | schema], buffer <> t}
  end

  defp e(schema, buffer, t) when is_bitstring(t) do
    {[{@c_binary, byte_size(t)} | schema], buffer <> t}
  end

  defp e(schema, buffer, t) when is_atom(t) do
    bin = to_string(t)
    {[{@c_atom, byte_size(bin)} | schema], buffer <> bin}
  end

  defp e(schema, buffer, t) when is_float(t) do
    {[@c_float | schema], buffer <> <<t :: 64-float>> }
  end

  defp add_struct(schema, buffer, t, module) do
    {map_schema, buffer} = t
                           |> Map.from_struct()
                           |> Enum.reduce({[], buffer}, &add_map_tuple/2)
    {map_schema, buffer} = add_map_tuple({:__struct__, module}, {map_schema, buffer})

    map_schema =
      map_schema
      |> Enum.reverse()
      |> compress_schema()

    {[{@c_map, map_schema} | schema], buffer}
  end

  defp add_map(schema, buffer, t)  do
    {map_schema, buffer} = Enum.reduce(t, {[], buffer}, &add_map_tuple/2)

    map_schema =
      map_schema
      |> Enum.reverse()
      |> compress_schema()

    {[{@c_map, map_schema} | schema], buffer}
  end

  defp add_map_tuple({key, value}, {schema, buffer}) do
    {[key_schema], buffer} = e([], buffer, key)
    {[value_schema], buffer} = e([], buffer, value)
    {[{key_schema, value_schema} | schema], buffer}
  end

  defp add_tuple(schema, buffer, _tuple, arity, count) when count >= arity do
    {schema, buffer}
  end

  defp add_tuple(schema, buffer, tuple, arity, count) do
    {tuple_schema, tuple_buffer} =
      tuple
      |> elem(count)
      |> (fn x -> e(schema, buffer, x) end).()
    add_tuple(tuple_schema, tuple_buffer, tuple, arity, count + 1)
  end

  defp add_list(schema, buffer, []) do
    {Enum.reverse(schema), buffer}
  end

  defp add_list(schema, buffer, [next | rest]) do
    {schema, buffer} = e(schema, buffer, next)
    add_list(schema, buffer, rest)
  end

  defp add_integer(schema, buffer, t) when t >= 0 and t <=255 do
    {[@c_small_int | schema], buffer <> <<t :: 8-unsigned-integer>>}
  end

  defp add_integer(schema, buffer, t) when t >= -127 and t < 0 do
    {[@c_small_uint | schema], buffer <> <<t :: 8-signed-integer>>}
  end

  defp add_integer(schema, buffer, t) when t >= 0 and t <= 65_535 do
    {[@c_short_int | schema], buffer <> <<t :: 16-unsigned-integer>>}
  end

  defp add_integer(schema, buffer, t) when t >= -32_767 and t < 0 do
    {[@c_short_uint | schema], buffer <> <<t :: 16-signed-integer>>}
  end

  defp add_integer(schema, buffer, t) when t >= 0 and t <= 4_294_967_295 do
    {[@c_int | schema], buffer <> <<t :: 32-unsigned-integer>>}
  end

  defp add_integer(schema, buffer, t) when t >= -2_147_483_647 and t < 0 do
    {[@c_uint | schema], buffer <> <<t :: 32-signed-integer>>}
  end

  defp add_integer(schema, buffer, t) do
    {[@c_big_int | schema], buffer <> <<t :: 64-signed-integer>>}
  end
end
