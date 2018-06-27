defmodule Packer.Decode do
  @moduledoc false
  @compile {:inline, decoded: 3}

  use Packer.Defs

  def from([header, schema, buffer], opts) do
    header_type = Keyword.get(opts, :header, :version)
    if check_header(header_type, header) do
      decompressed_buffer =
        if Keyword.get(opts, :compress, true) do
          Packer.Utils.decompress(buffer)
        else
          buffer
        end

      {_rem_schema, _rem_buffer, term} = decode_one(schema, decompressed_buffer)
      term
    else
      {:error, :bad_header}
    end
  end

  def from([schema, buffer], opts) do
    if Keyword.get(opts, :header, :version) === :none do
      decompressed_buffer = Packer.Utils.decompress(buffer)
      {_rem_schema, _rem_buffer, term} = decode_one(schema, decompressed_buffer)
      term
    else
      {:error, :bad_header}
    end
  end

  def from(combined_buffer, opts) do
    header_type = Keyword.get(opts, :header, :version)
    case split_schema_and_buffer(combined_buffer, header_type) do
      {:error, _} = error ->
        error

      {schema, buffer} ->
        decompressed_buffer = Packer.Utils.decompress(buffer)
        {_rem_schema, _rem_buffer, term} = decode_one(schema, decompressed_buffer)
        term
    end
  end

  defp split_schema_and_buffer(<<@c_version_header, schema_len :: 32-unsigned-little-integer, rest :: binary>>, :version) do
    if schema_len <= byte_size(rest) do
      String.split_at(rest, schema_len)
    else
      {:error, :bad_header}
    end
  end

  defp split_schema_and_buffer(_buffer, :version) do
    {:error, :bad_header}
  end

  defp split_schema_and_buffer(<<@c_full_header, schema_len :: 32-unsigned-little-integer, rest :: binary>>, :full) do
    if schema_len <= byte_size(rest) do
      String.split_at(rest, schema_len)
    else
      {:error, :bad_header}
    end
  end

  defp split_schema_and_buffer(_buffer, :full) do
    {:error, :bad_header}
  end

  defp split_schema_and_buffer(<<schema_len :: 32-unsigned-little-integer, rest :: binary>>, :none) do
    if schema_len <= byte_size(rest) do
      String.split_at(rest, schema_len)
    else
      {:error, :bad_header}
    end
  end

  defp split_schema_and_buffer(_buffer, _) do
    {:error, :bad_header}
  end

  defp check_header(:version, @c_version_header), do: true
  defp check_header(:version, _version), do: false

  defp check_header(:full, <<@c_full_header_prefix, version :: binary>>) do
    check_header(:version, version)
  end

  defp check_header(_type, _header), do: false

  defp decoded(schema, buffer, term), do: {schema, buffer, term}

  defp decode_one(<<>>, _buffer), do: {:error, :empty_header}

  defp decode_one(<<@c_list, rem_schema :: binary>>, buffer) do
    decode_next_list_item(rem_schema, buffer, [])
  end

  defp decode_one(<<@c_map, rem_schema :: binary>>, buffer) do
    decode_next_map_pair(rem_schema, buffer, %{})
  end

  defp decode_one(<<@c_struct, rem_schema :: binary>>, buffer) do
    debuffer_one(@c_struct, rem_schema, buffer)
  end

  defp decode_one(<<type :: 8-unsigned-little-integer, rem_schema :: binary>>, buffer) do
    if Packer.Utils.is_tuple_type?(type) do
      {arity, rem_schema} = Packer.Utils.tuple_arity(type, rem_schema)
      decode_next_tuple_item(rem_schema, buffer, arity, {})
    else
      debuffer_one(type, rem_schema, buffer)
    end
  end

  defp decode_one(_schema, _buffer), do: {:error, :unexpected_data}

  debuffer_primitive(@c_small_int, 1, 8-signed-little-integer, 0)
  debuffer_primitive(@c_small_uint, 1, 8-unsigned-little-integer, 0)
  debuffer_primitive(@c_short_int, 2, 16-signed-little-integer, 0)
  debuffer_primitive(@c_short_uint, 2, 16-unsigned-little-integer, 0)
  debuffer_primitive(@c_int, 4, 32-signed-little-integer, 0)
  debuffer_primitive(@c_uint, 4, 32-unsigned-little-integer, 0)
  debuffer_primitive(@c_big_int, 8, 64-signed-little-integer, 0)
  debuffer_primitive(@c_byte, 1, 8-bits, "")
  debuffer_primitive(@c_float, 8, 64-little-float, 0.0)

  debuffer_binary(@c_atom, 8, nil, &String.to_atom/1)
  debuffer_binary(@c_binary_1, 8)
  debuffer_binary(@c_binary_2, 16)
  debuffer_binary(@c_binary_4, 32)
  debuffer_binary(@c_binary_8, 64)

  defp debuffer_one(@c_list, schema, buffer) do
    decode_next_list_item(schema, buffer, [])
  end

  defp debuffer_one(@c_map, schema, buffer) do
    decode_next_map_pair(schema, buffer, %{})
  end

  defp debuffer_one(@c_struct, <<name_len :: 8-unsigned-little-integer, rem_schema :: binary>>, buffer) do
    {name, rem_schema} = String.split_at(rem_schema, name_len)
    {rem_schema, rem_buffer, term} = decode_next_map_pair(rem_schema, buffer, %{})
    #TODO: should we bother to check if the code for this struct is even loaded?
    struct = Map.put(term, :__struct__, String.to_atom(name))
    decoded(rem_schema, rem_buffer, struct)
  end

  defp debuffer_one(type, schema, buffer) do
    if Packer.Utils.is_tuple_type?(type) do
      {arity, rem_schema} = Packer.Utils.tuple_arity(type, schema)
      decode_next_tuple_item(rem_schema, buffer, arity, {})
    else
      {:error, :unhandled_debuf_type}
    end
  end

  defp decode_next_list_item(<<>>, buffer, acc) do
    decoded(<<>>, buffer, Enum.reverse(acc))
  end

  defp decode_next_list_item(<<0, rem_schema :: binary>>, buffer, acc) do
    decoded(rem_schema, buffer, Enum.reverse(acc))
  end

  defp decode_next_list_item(<<@c_repeat_1, rem_schema :: binary>>, buffer, acc) do
    if byte_size(buffer) < 2 do
      decoded(rem_schema, buffer, Enum.reverse(acc))
    else
      <<count :: 8-unsigned-little-integer, type :: 8-unsigned-little-integer, rem_schema :: binary>> = rem_schema
      is_container = Packer.Utils.is_container_type?(type)
      decode_n_list_items(type, rem_schema, buffer, is_container, acc, count)
    end
  end

  defp decode_next_list_item(<<@c_repeat_2, rem_schema :: binary>>, buffer, acc) do
    if byte_size(buffer) < 3 do
      decoded(rem_schema, buffer, Enum.reverse(acc))
    else
      <<count :: 16-unsigned-little-integer, type :: 8-unsigned-little-integer, rem_schema :: binary>> = rem_schema
      is_container = Packer.Utils.is_container_type?(type)
      decode_n_list_items(type, rem_schema, buffer, is_container, acc, count)
    end
  end

  defp decode_next_list_item(<<@c_repeat_4, rem_schema :: binary>>, buffer, acc) do
    if byte_size(buffer) < 5 do
      decoded(rem_schema, buffer, Enum.reverse(acc))
    else
      <<count :: 32-unsigned-little-integer, type :: 8-unsigned-little-integer, rem_schema :: binary>> = rem_schema
      is_container = Packer.Utils.is_container_type?(type)
      decode_n_list_items(type, rem_schema, buffer, is_container, acc, count)
    end
  end

  defp decode_next_list_item(schema, buffer, acc) do
    {rem_schema, rem_buffer, term} = decode_one(schema, buffer)
    decode_next_list_item(rem_schema, rem_buffer, [term | acc])
  end

  defp decode_n_list_items(type, schema, buffer, _is_container, acc, 1) do
    {rem_schema, rem_buffer, term} = debuffer_one(type, schema, buffer)
    decode_next_list_item(rem_schema, rem_buffer, [term | acc])
  end

  defp decode_n_list_items(type, schema, buffer, is_container, acc, count) do
    {rem_schema, rem_buffer, term} = debuffer_one(type, schema, buffer)

    # when we are decoding a repeating container, we need to re-use the schema
    if is_container do
      decode_n_list_items(type, schema, rem_buffer, is_container, [term | acc], count - 1)
    else
      decode_n_list_items(type, rem_schema, rem_buffer, is_container, [term | acc], count - 1)
    end
  end

  defp decode_next_tuple_item(schema, buffer, 0, acc), do: decoded(schema, buffer, acc)

  defp decode_next_tuple_item(<<@c_repeat_1, rem_schema :: binary>>, buffer, count, acc) do
    if byte_size(buffer) < 2 do
      decoded(rem_schema, buffer, acc)
    else
      <<rep_count :: 8-unsigned-little-integer, type :: 8-unsigned-little-integer, rem_schema :: binary>> = rem_schema
      is_container = Packer.Utils.is_container_type?(type)
      decode_n_tuple_items(type, rem_schema, buffer, is_container, count, acc, rep_count)
    end
  end

  defp decode_next_tuple_item(<<@c_repeat_2, rem_schema :: binary>>, buffer, count, acc) do
    if byte_size(buffer) < 3 do
      decoded(rem_schema, buffer, acc)
    else
      <<rep_count :: 16-unsigned-little-integer, type :: 8-unsigned-little-integer, rem_schema :: binary>> = rem_schema
      is_container = Packer.Utils.is_container_type?(type)
      decode_n_tuple_items(type, rem_schema, buffer, is_container, count, acc, rep_count)
    end
  end

  defp decode_next_tuple_item(<<@c_repeat_4, rem_schema :: binary>>, buffer, count, acc) do
    if byte_size(buffer) < 5 do
      decoded(rem_schema, buffer, acc)
    else
      <<rep_count :: 32-unsigned-little-integer, type :: 8-unsigned-little-integer, rem_schema :: binary>> = rem_schema
      is_container = Packer.Utils.is_container_type?(type)
      decode_n_tuple_items(type, rem_schema, buffer, is_container, count, acc, rep_count)
    end
  end

  defp decode_next_tuple_item(schema, buffer, count, acc) do
    {rem_schema, rem_buffer, term} = decode_one(schema, buffer)
    acc = Tuple.append(acc, term)
    decode_next_tuple_item(rem_schema, rem_buffer, count - 1, acc)
  end

  defp decode_n_tuple_items(type, schema, buffer, _is_container, count, acc, 1) do
    {rem_schema, rem_buffer, term} = debuffer_one(type, schema, buffer)
    acc = Tuple.append(acc, term)
    decode_next_tuple_item(rem_schema, rem_buffer, count - 1, acc)
  end

  defp decode_n_tuple_items(type, schema, buffer, is_container, count, acc, rep_count) do
    {rem_schema, rem_buffer, term} = debuffer_one(type, schema, buffer)
    acc = Tuple.append(acc, term)

    if is_container do
      decode_n_tuple_items(type, schema, rem_buffer, is_container, count - 1, acc, rep_count - 1)
    else
      decode_n_tuple_items(type, rem_schema, rem_buffer, is_container, count - 1, acc, rep_count - 1)
    end
  end

  defp decode_next_map_pair(<<>>, buffer, acc) do
    decoded(<<>>, buffer, acc)
  end

  defp decode_next_map_pair(<<0, rem_schema :: binary>>, buffer, acc) do
    decoded(rem_schema, buffer, acc)
  end

  defp decode_next_map_pair(<<@c_repeat_1, rem_schema :: binary>>, buffer, acc) do
    if byte_size(buffer) < 2 do
      decoded(rem_schema, buffer, acc)
    else
      <<count :: 8-unsigned-little-integer, type :: 8-unsigned-little-integer, rem_schema :: binary>> = rem_schema
      decode_n_map_pairs(type, rem_schema, buffer, acc, count)
    end
  end

  defp decode_next_map_pair(<<@c_repeat_2, rem_schema :: binary>>, buffer, acc) do
    if byte_size(buffer) < 3 do
      decoded(rem_schema, buffer, acc)
    else
      <<count :: 16-unsigned-little-integer, type :: 8-unsigned-little-integer, rem_schema :: binary>> = rem_schema
      decode_n_map_pairs(type, rem_schema, buffer, acc, count)
    end
  end

  defp decode_next_map_pair(<<@c_repeat_4, rem_schema :: binary>>, buffer, acc) do
    if byte_size(buffer) < 5 do
      decoded(rem_schema, buffer, acc)
    else
      <<count :: 32-unsigned-little-integer, type :: 8-unsigned-little-integer, rem_schema :: binary>> = rem_schema
      decode_n_map_pairs(type, rem_schema, buffer, acc, count)
    end
  end

  defp decode_next_map_pair(schema, buffer, acc) do
    {rem_schema, rem_buffer, key} = decode_one(schema, buffer)
    {rem_schema, rem_buffer, value} = decode_one(rem_schema, rem_buffer)
    decode_next_map_pair(rem_schema, rem_buffer, Map.put(acc, key, value))
  end

  defp decode_n_map_pairs(type, schema, buffer, acc, 1) do
    {rem_schema, rem_buffer, key} = debuffer_one(type, schema, buffer)
    {rem_schema, rem_buffer, value} = decode_one(rem_schema, rem_buffer)
    decode_next_map_pair(rem_schema, rem_buffer, Map.put(acc, key, value))
  end

  defp decode_n_map_pairs(type, schema, buffer, acc, count) do
    {rem_schema, rem_buffer, key} = debuffer_one(type, schema, buffer)
    {_rem_schema, rem_buffer, value} = decode_one(rem_schema, rem_buffer)

    # the repetition in maps is always equivalent to a tuple, so we need to re-use the schema
    decode_n_map_pairs(type, schema, rem_buffer, Map.put(acc, key, value), count - 1)
  end
end
