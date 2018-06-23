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
  @type encode_options() :: [
                             {:compress, boolean},
                             {:short_int, boolean},
                             {:header, :version | :full | :none}
                            ]
  defdelegate encode(term, opts \\ []), to: Packer.Encode, as: :from_term

  @doc """
  Decodes iodata to a term. The output of Packer.encode/2 is expected, and this function is
  indeed symetric to Packer.encode/2. It also supports a similar set of options:

  * compress: boolean, defaults to true; if the payload was not compressed, leaving this as
    true will be less efficient but should not be harmful
  * header: the type of header that is expected, from :version (the default), :full, or :none
  """
  @spec decode(data :: iodata(), opts :: decode_options()) :: any()
  @type decode_options() :: [
                             {:compress, boolean},
                             {:header, :version | :full | :none}
                            ]
  defdelegate decode(data, opts \\ []), to: Packer.Decode, as: :from

  @doc """
  Returns the magic string header prepended to encodings. The type parameter can be :none,
  :full or :version. The default is :version, which is a minimal prefix of one byte containing
  the version of the encoding.
  """
  @spec encoded_term_header(type :: :none | :full | :version) :: String.t()
  defdelegate encoded_term_header(type \\ :version), to: Packer.Encode
end
