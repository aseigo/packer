defmodule Packer do
  @doc """
  Encodes a term. Returns an array with the version-specific magic string, the
  data schema, and buffer.

  Options supported include:

  * compress: boolean, defaulting to true
  * small_int: boolean, defaulting to true. When false integers that would fit into a single byte
    are instead encoded in 2 bytes; for large terms with a mix of single- and two-byte
    encodable integers, setting small_int to false to can result in a significantly
    smaller schema
  * header: atom, defaulting to :version; controls what sort of header information, if any, to
    prepend to return. Recognized values:
    ** :version -> the version number of the encoding is prepended
    ** :full -> a header suitable for durable storage (e.g. a file) is prepended
    ** :none -> no header; fewer bytes, less safety. buckle up, cowboy!
  """
  @spec encode(term :: any(), opts :: encode_options()) :: iolist()
  @type encode_options() :: [{:compress, boolean}, {:short_int, boolean}]
  defdelegate encode(term, opts \\ []), to: Packer.Encode, as: :from_term

  @doc """
  Returns the magic string header prepended to encodings. The type parameter can be either
  :full or :version
  """
  defdelegate encoded_term_header(type \\ :version), to: Packer.Encode
end
