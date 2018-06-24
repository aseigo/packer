defmodule Packer.Utils do
  @moduledoc false

  use Packer.Defs
  use Bitwise

  def is_container_type?(@c_list), do: true
  def is_container_type?(@c_map), do: true
  def is_container_type?(type), do: is_tuple_type?(type)

  def is_tuple_type?(type) do
    (type &&& @c_tuple) == @c_tuple
  end

  def tuple_arity(type, schema) do
    arity = type &&& @c_tuple_arity_mask
    if (arity >= @c_max_short_tuple) do
      #FIXME: if the schema does not have any more bytes?
      if byte_size(schema) > 2 do
        <<arity :: 24-unsigned-little-integer, rem_schema :: binary>> = schema
        {arity, rem_schema}
      else
        {0, <<>>}
      end
    else
      {arity, schema}
    end
  end

  def compress(buffer) do
    :zstd.compress(buffer, 5)
  end

  def decompress(buffer) do
    case :zstd.decompress(buffer) do
      :error -> buffer
      res -> res
    end
  end
end
