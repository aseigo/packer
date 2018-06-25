defmodule Packer.Encode do
  @moduledoc false
  @compile {:inline,
            add_integer: 4,
            add_list: 6,
            new_schema_fragment: 6,
            last_schema_fragment: 5,
            repeater_schema_frag: 1}

  use Packer.Defs

  def from_term(term, opts) do
    encoding_opts = %{small_ints: Keyword.get(opts, :small_int, true)}

    {schema, buffer} =
    case encode_one(encoding_opts, <<>>, <<>>, <<>>, 0, term) do
        {schema, buffer, last_schema_frag, rep_count} ->
            last_schema_fragment(opts, schema, buffer, last_schema_frag, rep_count)

        final -> final
    end

    encoded_schema = schema

    compress? = Keyword.get(opts, :compress, true)
    header_type = Keyword.get(opts, :header, :version)
    format = Keyword.get(opts, :format, :iolist)
    if compress? do
      compressed_buffer = Packer.Utils.compress(buffer)
      if byte_size(compressed_buffer) < byte_size(buffer) do
        encoded_iodata(encoded_schema, compressed_buffer, header_type, format)
      else
        encoded_iodata(encoded_schema, buffer, header_type, format)
      end
    else
      encoded_iodata(encoded_schema, buffer, header_type, format)
    end
  end

  def encoded_term_header(:full), do: @c_full_header
  def encoded_term_header(:version), do: @c_version_header

  defp encoded_iodata(schema, buffer, :none, :iolist), do: [schema, buffer]

  defp encoded_iodata(schema, buffer, :none, :binary) do
    schema_length = byte_size(schema)
    <<schema_length :: 32-unsigned-little-integer>> <> schema <> buffer
  end

  defp encoded_iodata(schema, buffer, :full, :iolist), do: [@c_full_header, schema, buffer]

  defp encoded_iodata(schema, buffer, :full, :binary) do
    schema_length = byte_size(schema)
    @c_full_header <> <<schema_length :: 32-unsigned-little-integer>> <> schema <> buffer
  end

  defp encoded_iodata(schema, buffer, :version, :iolist), do: [@c_version_header, schema, buffer]

  defp encoded_iodata(schema, buffer, :version, :binary) do
    schema_length = byte_size(schema)
    @c_version_header <> <<schema_length :: 32-unsigned-little-integer>> <> schema <> buffer
  end

  defp repeater_schema_frag(reps) when reps <= 255, do: <<@c_repeat_1 :: 8-unsigned-little-integer, reps :: 8-unsigned-little-integer>>
  defp repeater_schema_frag(reps) when reps <= 65_535, do: <<@c_repeat_2 :: 8-unsigned-little-integer, reps :: 16-unsigned-little-integer>>
  defp repeater_schema_frag(reps), do: <<@c_repeat_4 :: 8-unsigned-little-integer, reps :: 32-unsigned-little-integer>>

  defp encode_one(opts, schema, buffer, last_schema_frag, rep_count, t) when is_tuple(t) do
    arity = tuple_size(t)
    {tuple_schema, buffer} = add_tuple(opts, [], buffer, t, arity, 0)

    {tuple_schema, buffer}
  end

  defp encode_one(opts, schema, buffer, last_schema_frag, rep_count, t) when is_map(t) do
    case Map.get(t, :__struct__) do
      nil    -> add_map(opts, schema, buffer, t)
      module -> add_struct(opts, schema, buffer, t, module)
    end
  end

  defp encode_one(opts, schema, buffer, last_schema_frag, rep_count, t) when is_list(t) do
    {list_schema, buffer} = add_list(opts, schema <> <<@c_list>>, buffer, <<>>, 0, t)
    {list_schema <> <<@c_collection_end>>, buffer}
  end

  defp encode_one(opts, schema, buffer, last_schema_frag, rep_count, t) when is_integer(t) do
    {added_schema, buffer} = add_integer(opts, schema, buffer, t)
    new_schema_fragment(opts, schema, buffer, last_schema_frag, rep_count, added_schema)
  end

  defp encode_one(_opts, schema, buffer, last_schema_frag, rep_count, <<_byte :: 8>> = t) do
    {[@c_byte | schema], buffer <> t}
  end

  defp encode_one(opts, schema, buffer, last_schema_frag, rep_count, t) when is_bitstring(t) do
    case byte_size(t) do
      length when length <= 0xFF ->
        new_schema_fragment(opts, schema,
                            buffer <> <<length :: 8-unsigned-little-integer>> <> t,
                            last_schema_frag, rep_count,
                            <<@c_binary_1>>)

      length when length <= 0xFFFF ->
        new_schema_fragment(opts, schema,
                            buffer <> <<length :: 16-unsigned-little-integer>> <> t,
                            last_schema_frag, rep_count,
                            <<@c_binary_2>>)

      length when length <= 0xFFFFFFFF ->
        new_schema_fragment(opts, schema,
                            buffer <> <<length :: 32-unsigned-little-integer>> <> t,
                            last_schema_frag, rep_count,
                            <<@c_binary_4>>)

      length ->
        new_schema_fragment(opts, schema,
                            buffer <> <<length :: 64-unsigned-little-integer>> <> t,
                            last_schema_frag, rep_count,
                            <<@c_binary_8>>)
    end
  end

  defp encode_one(opts, schema, buffer, last_schema_frag, rep_count, t) when is_atom(t) do
    bin = Atom.to_string(t)
    bin_size = byte_size(bin)
    new_schema_fragment(opts, schema,
                        buffer <> <<bin_size :: 8-unsigned-little-integer>> <> bin,
                        last_schema_frag, rep_count,
                        <<@c_atom>>)
  end

  defp encode_one(opts, schema, buffer, last_schema_frag, rep_count, t) when is_float(t) do
    new_schema_fragment(opts, schema, buffer <> <<t :: 64-float>>, last_schema_frag, rep_count, <<@c_float>>)
  end

  defp add_struct(opts, schema, buffer, t, module) do
    name_bin = to_string(module)
    name_length = byte_size(name_bin)
    buffer = buffer <> name_bin

    {_, map_schema, buffer} = t
                           |> Map.from_struct()
                           |> Enum.reduce({opts, [], buffer}, &add_map_tuple/2)
    {[{@c_struct, name_length, map_schema} | schema], buffer}
  end

  defp add_map(opts, schema, buffer, t)  do
    {_opts, map_schema, buffer} = Enum.reduce(t, {opts, [], buffer}, &add_map_tuple/2)
    {[{@c_map, map_schema} | schema], buffer}
  end

  defp add_map_tuple({key, value}, {opts, schema, buffer}) do
    #FIXME
    last_schema_frag = <<>>
    rep_count = 0

    {[key_schema], buffer} = encode_one(opts, [], buffer, last_schema_frag, rep_count, key)
    {[value_schema], buffer} = encode_one(opts, [], buffer, last_schema_frag, rep_count, value)
    {opts, [{key_schema, value_schema} | schema], buffer}
  end

  defp add_tuple(_opts, schema, buffer, _tuple, arity, count) when count >= arity do
    {schema, buffer}
  end

  defp add_tuple(opts, schema, buffer, tuple, arity, count) do
    #FIXME
    last_schema_frag = <<>>
    rep_count = 0

    {tuple_schema, tuple_buffer} =
      tuple
      |> elem(count)
      |> (fn x -> encode_one(opts, schema, buffer, last_schema_frag, rep_count, x) end).()
    add_tuple(opts, tuple_schema, tuple_buffer, tuple, arity, count + 1)
  end

  defp add_list(opts, schema, buffer, last_schema_frag, rep_count, []) do
    last_schema_fragment(opts, schema, buffer, last_schema_frag, rep_count)
  end

  defp add_list(opts, schema, buffer, last_schema_frag, rep_count, [next | rest]) do
    {schema, buffer, last_schema_frag, rep_count} = encode_one(opts, schema, buffer, last_schema_frag, rep_count, next)
    add_list(opts, schema, buffer, last_schema_frag, rep_count, rest)
  end

  defp add_integer(%{small_ints: true}, schema, buffer, t) when t >= 0 and t <=255 do
    {<<@c_small_uint>>, buffer <> <<t :: 8-unsigned-little-integer>>}
  end

  defp add_integer(_opts, schema, buffer, t) when t >= 0 and t <=255 do
    {<<@c_short_uint>>, buffer <> <<t :: 16-unsigned-little-integer>>}
  end

  defp add_integer(%{small_ints: true}, schema, buffer, t) when t >= -127 and t < 0 do
    {<<@c_small_int>> , buffer <> <<t :: 8-signed-little-integer>>}
  end

  defp add_integer(_opts, schema, buffer, t) when t >= -127 and t < 0 do
    {<<@c_short_int>>, buffer <> <<t :: 16-signed-little-integer>>}
  end

  defp add_integer(_opts, schema, buffer, t) when t >= 0 and t <= 65_535 do
    {<<@c_short_uint>>, buffer <> <<t :: 16-unsigned-little-integer>>}
  end

  defp add_integer(_opts, schema, buffer, t) when t >= -32_767 and t < 0 do
    {<<@c_short_int>>, buffer <> <<t :: 16-signed-little-integer>>}
  end

  defp add_integer(_opts, schema, buffer, t) when t >= 0 and t <= 4_294_967_295 do
    {<<@c_uint>>, buffer <> <<t :: 32-unsigned-little-integer>>}
  end

  defp add_integer(_opts, schema, buffer, t) when t >= -2_147_483_647 and t < 0 do
    {<<@c_int>>, buffer <> <<t :: 32-signed-little-integer>>}
  end

  defp add_integer(_opts, schema, buffer, t) do
    {<<@c_big_int>>, buffer <> <<t :: 64-signed-little-integer>>}
  end

  defp new_schema_fragment(opts, schema, buffer, last_schema_frag, rep_count, added_schema) do
    if added_schema == last_schema_frag do
      {schema, buffer, last_schema_frag, rep_count + 1}
    else
      if rep_count > 0 do
        {schema <> repeater_schema_frag(rep_count + 1) <> last_schema_frag, buffer, added_schema, 0}
      else
        {schema <> last_schema_frag, buffer, added_schema, 0}
      end
    end
  end

  defp last_schema_fragment(_opts, schema, buffer, last_schema_frag, 0) do
    {schema <> last_schema_frag, buffer}
  end

  defp last_schema_fragment(_opts, schema, buffer, last_schema_frag, rep_count) do
    {schema <> repeater_schema_frag(rep_count + 1) <> last_schema_frag, buffer}
  end
end
