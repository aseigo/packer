defmodule Packer.Decode do
  use Packer.Defs

  def from_iodata([header, schema, buffer], opts) do
    header_type = Keyword.get(opts, :header, :version)
    if check_header(header_type, header) do
      decode(schema, buffer, opts)
    else
      {:error, :bad_header}
    end
  end

  def from_iodata([schema, buffer], opts) do
    if Keyword.get(opts, :header, :version) === :none do
      decode(schema, buffer, opts)
    else
      {:error, :bad_header}
    end
  end

  defp check_header(:version, @c_version_header), do: true
  defp check_header(:version, _version), do: false

  defp check_header(:full, <<@c_full_header_prefix, version :: binary>>) do
    check_header(:version, version)
  end

  defp check_header(type, header), do: false

  defp decode(schema, buffer, opts) do
    []
  end
end
