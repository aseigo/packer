defmodule Packer.Encode do
  use Packer.Defs
  use Bitwise

  def from_term(term, opts) do
    {schema, buffer} = encode_one(opts, [], <<>>, term)
    encoded_schema = schema
                     |> Enum.reverse()
                     |> encode_schema()

    compress? = Keyword.get(opts, :compress, true)
    header_type = Keyword.get(opts, :header, :version)
    if compress? do
      compressed_buffer = :zstd.compress(buffer, 5)
      if byte_size(compressed_buffer) < byte_size(buffer) do
        encoded_iodata(encoded_schema, compressed_buffer, header_type)
      else
        encoded_iodata(encoded_schema, buffer, header_type)
      end
    else
      encoded_iodata(encoded_schema, buffer, header_type)
    end
  end

  def encoded_term_header(:full), do: @c_full_header
  def encoded_term_header(:version), do: @c_version_header

  defp encoded_iodata(schema, buffer, :none), do: [schema, buffer]
  defp encoded_iodata(schema, buffer, :full), do: [@c_full_header, schema, buffer]
  defp encoded_iodata(schema, buffer, :version), do: [@c_version_header, schema, buffer]

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

  defp encode_one(opts, schema, buffer, t) when is_tuple(t) do
    arity = tuple_size(t)
    {tuple_schema, buffer} = add_tuple(opts, [], buffer, t, arity, 0)
    tuple_schema = tuple_schema
                   |> Enum.reverse()
                   |> compress_schema()

    {[{@c_tuple, arity, tuple_schema} | schema], buffer}
  end

  defp encode_one(opts, schema, buffer, t) when is_map(t) do
    case Map.get(t, :__struct__) do
      nil    -> add_map(opts, schema, buffer, t)
      module -> add_struct(opts, schema, buffer, t, module)
    end
  end

  defp encode_one(opts, schema, buffer, t) when is_list(t) do
    {list_schema, buffer} = add_list(opts, [], buffer, t)
    list_schema = compress_schema(list_schema)
    {[{@c_list, list_schema} | schema], buffer}
  end

  defp encode_one(opts, schema, buffer, t) when is_integer(t) do
    add_integer(opts, schema, buffer, t)
  end

  defp encode_one(_opts, schema, buffer, <<_byte :: 8>> = t) do
    {[@c_byte | schema], buffer <> t}
  end

  defp encode_one(_opts, schema, buffer, t) when is_bitstring(t) do
    {[{@c_binary, byte_size(t)} | schema], buffer <> t}
  end

  defp encode_one(_opts, schema, buffer, t) when is_atom(t) do
    bin = to_string(t)
    {[{@c_atom, byte_size(bin)} | schema], buffer <> bin}
  end

  defp encode_one(_opts, schema, buffer, t) when is_float(t) do
    {[@c_float | schema], buffer <> <<t :: 64-float>>}
  end

  defp add_struct(opts, schema, buffer, t, module) do
    {_, map_schema, buffer} = t
                           |> Map.from_struct()
                           |> Enum.reduce({opts, [], buffer}, &add_map_tuple/2)
    {_, map_schema, buffer} = add_map_tuple({:__struct__, module}, {opts, map_schema, buffer})

    map_schema =
      map_schema
      |> Enum.reverse()
      |> compress_schema()

    {[{@c_map, map_schema} | schema], buffer}
  end

  defp add_map(opts, schema, buffer, t)  do
    {_opts, map_schema, buffer} = Enum.reduce(t, {opts, [], buffer}, &add_map_tuple/2)

    map_schema =
      map_schema
      |> Enum.reverse()
      |> compress_schema()

    {[{@c_map, map_schema} | schema], buffer}
  end

  defp add_map_tuple({key, value}, {opts, schema, buffer}) do
    {[key_schema], buffer} = encode_one(opts, [], buffer, key)
    {[value_schema], buffer} = encode_one(opts, [], buffer, value)
    {opts, [{key_schema, value_schema} | schema], buffer}
  end

  defp add_tuple(_opts, schema, buffer, _tuple, arity, count) when count >= arity do
    {schema, buffer}
  end

  defp add_tuple(opts, schema, buffer, tuple, arity, count) do
    {tuple_schema, tuple_buffer} =
      tuple
      |> elem(count)
      |> (fn x -> encode_one(opts, schema, buffer, x) end).()
    add_tuple(opts, tuple_schema, tuple_buffer, tuple, arity, count + 1)
  end

  defp add_list(_opts, schema, buffer, []) do
    {Enum.reverse(schema), buffer}
  end

  defp add_list(opts, schema, buffer, [next | rest]) do
    {schema, buffer} = encode_one(opts, schema, buffer, next)
    add_list(opts, schema, buffer, rest)
  end

  defp add_integer(opts, schema, buffer, t) when t >= 0 and t <=255 do
    if Keyword.get(opts, :small_int, true) do
      {[@c_small_int | schema], buffer <> <<t :: 8-unsigned-integer>>}
    else
      {[@c_short_int | schema], buffer <> <<t :: 16-unsigned-integer>>}
    end
  end

  defp add_integer(opts, schema, buffer, t) when t >= -127 and t < 0 do
    if Keyword.get(opts, :small_int, true) do
      {[@c_small_uint | schema], buffer <> <<t :: 8-signed-integer>>}
    else
      {[@c_short_uint | schema], buffer <> <<t :: 16-signed-integer>>}
    end
  end

  defp add_integer(_opts, schema, buffer, t) when t >= 0 and t <= 65_535 do
    {[@c_short_int | schema], buffer <> <<t :: 16-unsigned-integer>>}
  end

  defp add_integer(_opts, schema, buffer, t) when t >= -32_767 and t < 0 do
    {[@c_short_uint | schema], buffer <> <<t :: 16-signed-integer>>}
  end

  defp add_integer(_opts, schema, buffer, t) when t >= 0 and t <= 4_294_967_295 do
    {[@c_int | schema], buffer <> <<t :: 32-unsigned-integer>>}
  end

  defp add_integer(_opts, schema, buffer, t) when t >= -2_147_483_647 and t < 0 do
    {[@c_uint | schema], buffer <> <<t :: 32-signed-integer>>}
  end

  defp add_integer(_opts, schema, buffer, t) do
    {[@c_big_int | schema], buffer <> <<t :: 64-signed-integer>>}
  end
end
