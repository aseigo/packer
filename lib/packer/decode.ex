defmodule Packer.Decode do
  use Packer.Defs

  def from_iodata([header, schema, buffer], opts) do
    header_type = Keyword.get(opts, :header, :version)
    if check_header(header_type, header) do
      decompressed_buffer = Packer.Utils.decompress(buffer)
      decode_one(schema, decompressed_buffer, opts)
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

  defp decoded(<<>>, _buffer, _opts, term), do: term
  defp decoded(schema, buffer, opts, term), do: decode_one(schema, buffer, opts)

  defp decode_one(<<>>, _buffer, _opts), do: :empty

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
end
