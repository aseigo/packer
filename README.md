# Packer

```
  NOTE: this library is still in early development, and not ready for production use.
```

A space-efficient term serializer, with specific attention paid to handling
large, nested / repetitive terms. The latter is somewhere that the usual
:erlang.term_to_binary/1 really struggles with, often to the point of preventing
the transmission of messages containing large lists / maps of lists / maps / tuples
between nodes.

Pack significantly reduces the space required to serialize a term by utilizing a
schema + data buffer approach with support for shape repetition (e.g. "N * two-tuple
of integers") and using zstd for compression of the data buffer.

For repetative structures, it is not unusual to achieve 30-70%+ space savings, and
Packer can often handle serialization of large terms than :erlang.term_to_binary
simply fails on with memory allocation errors.

The [packerbench](https://github.com/aseigo/packerbench) repository contains
benchmarks. You may wish to try out.

And of course, contributions of all sorts are welcome :)

## Installation

Packer can be installed by by adding `packer` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:packer, "~> 0.0.2"}
  ]
end
```

Docs can be found at [https://hexdocs.pm/packer](https://hexdocs.pm/packer).

