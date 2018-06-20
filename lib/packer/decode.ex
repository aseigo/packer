defmodule Packer.Decode do
  use Packer.Defs

  def from_iodata([header, schema, buffer], opts) do
    header_type = Keyword.get(opts, :header, :version)
    if check_header(header_type, header) do
      decompressed_buffer = Packer.Utils.decompress(buffer)
      {_rem_schema, _rem_buffer, term} = decode_one(schema, decompressed_buffer, opts)
      term
    else
      {:error, :bad_header}
    end
  end

  def from_iodata([schema, buffer], opts) do
    if Keyword.get(opts, :header, :version) === :none do
      decompressed_buffer = Packer.Utils.decompress(buffer)
      decode_one(schema, decompressed_buffer, opts)
    else
      {:error, :bad_header}
    end
  end

  defp check_header(:version, @c_version_header), do: true
  defp check_header(:version, _version), do: false

  defp check_header(:full, <<@c_full_header_prefix, version :: binary>>) do
    check_header(:version, version)
  end

  defp check_header(_type, _header), do: false

  defp decoded(schema, buffer, _opts, term), do: {schema, buffer, term}

  defp decode_one(<<>>, _buffer, _opts), do: {:error, :empty_header}

  defp decode_one(<<@c_list, rem_schema :: binary>>, buffer, opts) do
    decode_next_list_item(rem_schema, buffer, opts, [])
  end

  decode_primitive(@c_small_int, 1, 8-signed-integer, 0)
  decode_primitive(@c_small_uint, 1, 8-unsigned-integer, 0)
  decode_primitive(@c_short_int, 2, 16-signed-integer, 0)
  decode_primitive(@c_short_uint, 2, 16-unsigned-integer, 0)
  decode_primitive(@c_int, 4, 32-signed-integer, 0)
  decode_primitive(@c_uint, 4, 32-unsigned-integer, 0)
  decode_primitive(@c_big_int, 8, 64-signed-integer, 0)
  decode_primitive(@c_byte, 1, 8-bits, "")
  decode_primitive(@c_float, 8, 64-float, 0.0)

  decode_binary(@c_atom, 8, nil, &String.to_atom/1)
  decode_binary(@c_binary_1, 8)
  decode_binary(@c_binary_2, 16)
  decode_binary(@c_binary_4, 32)

  defp decode_one(_, _, _), do: {:error, :unexpected_data}

  defp decode_next_list_item(<<>>, buffer, opts, acc) do
    decoded(<<>>, buffer, opts, Enum.reverse(acc))
  end

  defp decode_next_list_item(<<0, rem_schema :: binary>>, buffer, opts, acc) do
    decoded(rem_schema, buffer, opts, Enum.reverse(acc))
  end

  defp decode_next_list_item(schema, buffer, opts, acc) do
    {rem_schema, rem_buffer, term} = decode_one(schema, buffer, opts)
    decode_next_list_item(rem_schema, rem_buffer, opts, [term | acc])
  end
end
