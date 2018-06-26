# Packer

```
  NOTE: this library is still in early development, and not ready for production use.
```

A space-efficient term serializer, with specific attention paid to handling
large, nested / repetitive terms. The latter is something that :erlang.term_to_binary/1
really struggles with, often to the point of preventing the transmission of messages
containing large lists / maps of lists / maps / tuples between nodes.

Pack significantly reduces the space required to serialize a term by utilizing a
schema + data buffer approach with support for shape repetition (e.g. "N * two-tuple
of integers") and using zstd for compression of the data buffer.

For repetative structures, it is not unusual to achieve 30-70%+ space savings, and
Packer can often handle serialization of large terms than `:erlang.term_to_binary`
simply fails on with memory allocation errors. If `:erlang.term_to_binary` is used
without compression (often the default for internal uses of `term_to_binary`) then
the savings are even more dramatic, up 99%+ for larger repetative data structures.

As for speed, Packer is up against a function written in C, and one that has seen
recent improvements (i.e. in ERTS 21.0). So it will not be as fast as
`:erlang.term_to_binary`, but it can make up for that speed due to producing
smaller encoded terms which are faster to send/write and receive/read. YMMV.

The [packerbench](https://github.com/aseigo/packerbench) repository contains
benchmarks. You may wish to try out.

And of course, contributions of all sorts are welcome :)

## Usage

Using Packer is quite straight-forward:

    Packer.encode(some_term)
    |> Packer.decode()

By default, Packer returns three binaries in a list: a header used to store
the version and optionally a set of "magic bytes" to allow content-based
identification (useful if storing to files or other external storage).

But Packer can also return a all-in-one-binary result suitable for immediate
use over the netowrk or as an Elixir message:

    send(some_pid, Packer.encode(some_term, format: :binary))

Decoding is identical, as Packer detects which style of encoding was used.

There are other options available to encoding and decoding, which can be
found in the [online documentation](https://hexdocs.pm/packer).

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

