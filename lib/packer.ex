defmodule Packer do
  @c_collect_end 0x00
  @c_small_int   0x01
  @c_small_uint  0x02
  @c_short_int   0x03
  @c_short_uint  0x04
  @c_int         0x05
  @c_uint        0x06
  @c_big_int     0x07
  #TODO: @c_huge_int   0x08

  @c_byte        0x09
  @c_binary      0x0A
  @c_float       0x0B
  @c_atom        0x0C

  @c_list        0x21
  @c_map         0x22
  @c_struct      0x23
  @c_tuple       0b01000000
  @c_repeat      0b10000010
  @c_repeat_up   0b10000001

  @c_max_short_tuple 0b01111111 - 0b01000000
  #@c_header_magic <<0x45, 0x50, 0x4B, 0x52>> # 'EPKR'

  use Bitwise

  def encode(term) do
    #TODO: measure if the schema performs better as a :queue?
    {schema, buffer} = e([], <<>>, term)
    encoded_schema = schema
                     |> Enum.reverse()
                     |> encode_schema()
    [encoded_schema, buffer]
  end

  defp encode_schema(schema) do
    #TODO: remove repetition in the schema
    Enum.reduce(schema, <<>>, &encode_schema/2)
    #length = byte_size(encoded)
    #<<length :: 32-unsigned-integer, encoded :: binary>>
  end

  defp encode_schema({@c_atom, length}, acc) do
    acc <> <<@c_atom :: 8-unsigned-integer, length :: 8-unsigned-integer>>
  end

  defp encode_schema({@c_tuple, elements}, acc) do
    arity = Enum.count(elements)
    subschema = encode_schema(elements)
    if arity < @c_max_short_tuple do
      acc <> <<@c_tuple + arity :: 8-unsigned-integer>> <> subschema
    else
      acc <> <<@c_tuple :: 8-unsigned-integer, arity :: 16-unsigned-integer>> <> subschema
    end
  end

  defp encode_schema({@c_list, elements}, acc) when is_list(elements) do
    acc <> <<@c_list>> <> encode_schema(elements) <> <<0>>
  end

  defp encode_schema({code, length}, acc) do
    acc <> <<code :: 8-unsigned-integer, length :: 32-unsigned-integer>>
  end

  defp encode_schema(code, acc) do
    acc <> <<code :: 8-unsigned-integer>>
  end

  defp e(schema, buffer, t) when is_tuple(t) do
    arity = tuple_size(t)
    {tuple_schema, buffer} = add_tuple([], buffer, t, arity, 0)
    {[{@c_tuple, tuple_schema} | schema], buffer}
  end

  defp e(schema, buffer, t) when is_list(t) do
    {list_schema, buffer} = add_list([], buffer, t)
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

  defp add_tuple(schema, buffer, _tuple, arity, count) when count >= arity do
    {Enum.reverse(schema), buffer}
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
