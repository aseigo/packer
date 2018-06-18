defmodule Packer do

  # TODO
  #
  # * schema compression actually inflates the size of encode({1, 2})
  #
  # * implement @c_huge_int
  #
  # * compressing the schema probably should be done while building the schema
  #   to avoid going through it more than once.
  #   this would perhaps open up additional opportunities for efficiency when
  #   small and not-so-small numbers end up alternating
  #
  # * consider adding a "this list is just small numbers" to save a few bytes
  #   this is a trick :erlang.term_to_binary employs, implying such lists are
  #   super common enough to warrant a unique id and saving an extra byte or two

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
