# Pack

A space-efficient term serializer, with specific attention paid to handling
large, nested / repetitive terms. The latter is somewhere that the usual
:erlang.term_to_binary/1 really struggles with, often to the point of preventing
the transmission of messages containing large lists / maps of lists / maps / tuples
between nodes.

Pack significantly reduces the space required to serialize a term by utilizing a
schema + buffer approach with support for shape repetition (e.g. "N * two-tuple of
integers").

```
  NOTE: this library is still in early development, and not ready for production use.
  Documentation of the serialization format, apidocs, etc. will come once things calm
  down a bit. The encoding is still in flux, and the api is still growing and what is
  there is not finalized, so one step at a time. :)
```

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `pack` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:pack, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/pack](https://hexdocs.pm/pack).

