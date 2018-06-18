defmodule Packer do
  @doc """
  Encodes a term. Returns an array with the version-specific magic string, the
  data schema, and buffer.

  Options supported include compress (boolean, defaulting to true) and small_int
  (boolean, default to true; when false integers that would fit into a single byte
  are instead encoded in 2 bytes; for large terms with a mix of single- and two-byte
  encodable integers, setting small_int to false to can result in a significantly
  smaller schema)
  """
  @spec encode(term :: any(), opts :: encode_options()) :: iolist()
  @type encode_options() :: [{:compress, boolean}, {:short_int, boolean}]
  defdelegate encode(term, opts \\ []), to: Packer.Encode, as: :from_term

  @doc """
  Returns the magic string header prepended to encodings
  """
  defdelegate encoded_term_header(), to: Packer.Encode
end
