defmodule Packer.Decode do
  def from_iodata([header, schema, buffer], opts) do
    []
  end

  def from_iodata([schema, buffer], opts) do
    []
  end
end
