defmodule Packer.Utils do
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
