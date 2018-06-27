== Packer Serialization Format

This document describes the binary format used by Packer to serialize
arbitrary Erlang/Elixir terms.

== Header, Schema, Data

A term encoded using packer has three segments:

 * An optional header, which contains version information
 * A schema, containing the layout of the data in the payload
 * The data payload, containing the actual data in the term (numbers, strings, bytes, etc.)

The purpose of separating the data types (schema) from the data itself is
based on the observation that data within containers (lists, maps, ..)
are often quite repetitive. Lists often contain the same type of data,
keys in maps are usually the same type (e.g. atoms), etc. By separating
the schema, it offers opportunity for easy compression of that content,
often resulting in a dramatic reduction in bytes used.

    tuple_list = Enum.reduce(1..500, [], fn  x, acc -> [{x * 2, x * 2 + 1} | acc] end)
    tuple_map = Enum.reduce(1..10_000, %{},
                            fn x, acc ->
                              Map.put(acc, {x * 2, x * 2 + 1}, tuple_list)
                            end)

    :erlang.term_to_binary(tuple_map) |> byte_size() |> (fn x -> x / 1024 / 1024 end).()     
    501.2504997253418

    Packer.encode(tuple_map) |> byte_size() |> (fn x -> x / 1024 / 1024 end).()     
    1.5183916091918945

That is a 331x reduction in size. In fact, for all but the simplest of terms, this encoding
beats `term_to_binary` in encoded size. For communicating over networks, this is vital.

== Current limitations

Current limitations include:

 * currently no support for:
    * PIDs
    * ports
    * node names
    * functions
    * integers requiring more than 64 bits of storage

   there is space available in the type codes for these, it is just a matter of
   definition and implementation.

 * It could be even better! Several opportunities for further optimizations exist,
   as noted in the documentation below. 

 * All atoms encoded with their names as literal binaries

 * The only implementation is in Elixir, so not the fastest possible thing

== Format

Packer can serialize to one of two formats:

 * An iolist: [header :: binary, schema :: binary, data :: binary]
 * A binary:

    0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |     Header    |                 Schema Length                 |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |               |                     Schema...                 |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |                                                               |
  +                              Data...                          +
  |                                                               |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+


== Header

The head is optional and can be skipped altogether for cases where you can
guarantee the same version of Packer is being used. By default, the version
number is the only content of the header and is 1 byte in length:

   0                   1                   2                   3
   0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |    Version    |                   Schema...                   |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

A full header includes some "magic" bytes to allow for content-based detection
of type:

   0                   1                   2                   3  
   0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |       E       |       P       |       K       |       R       |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |    Version    |                   Schema...                   |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

== Schema

The schema contains a binary record of the data types that appear in the
term, separate from the data in the term which is stored in the data
section that follows the schema.

When encoding to a binary (as opposed to an iolist), the schema begins with the number
of bytes in the schema as a 32 bit value.

  NOTE: This could be optimized in future revisions to be variable length, allowing it
  to be as short as 1 byte and as long as 255 bytes. This would allow squeezing another
  2-3 bytes in common usage.

   0                   1                   2                   3
   0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |                         Schema Length                         |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |                                                               |
  +                             Schema...                         +
  |                                                               |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

There are three categories of entries in schemas:

 * Primitives: numeric data, binaries, atoms ...
 * Containers: lists, tuples, structs, maps ...
 * Repeat directives

Each entry consists of a one byte "type code" that maps to the kind of data that
appears next in the data block; containers and repeat directives may have
additional information encoded diretly after the type code.

=== Primitives

==== Numeric

To limit the number of bytes required, integers support variable size encoding depending
on the value of the number. All numbers are stored in little endian order.

      Type        Code           MinVal         MaxVal   Bytes encoded
      ==========  ====   ==============  =============   =============
      small_int   0x01             -127            127   1
      small_uint  0x02                0            255   1
      short_int   0x03          -32 767         32 767   2
      short_uint  0x04                0         65_535   2
      int         0x05   -2 147 483 647  2 147 483 647   4
      uint        0x06                0  4 294 967 295   4
      big_int     0x07                                   8


  NOTE: large_int for arbitrary bignum integers is not yet implemented; 0x08 is reserved for this purpose

Example encoding of 10,000, including the version header (v = 3):

   0                   1                   2                   3  
   0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |      0x03     |      0x04     |      0x10     |      0x27     |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+


Floats are encoded as 64-bit floats (64-float in Erlangese):

      Type        Code   Bytes encoded
      ==========  ====   =============
      float       0x09   8

Example of 3.14:

   0                   1                   2                   3
   0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |      0x03     |      0x09     |      0x1F     |      0x85     |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |      0xEB     |      0x51     |      0xB8     |      0x1E     |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |      0x09     |      0x04     |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

  [<<3>>, "\t", <<64, 9, 30, 184, 81, 235, 133, 31>>]

==== Binary

There are three data types encoded as binaries: bitstring binaries, atoms and single bytes. Both
atoms and binaries include their length in the data segement. The number of bytes used to
encode the length varies depending on the size of the data: atoms are always 1 byte (as they
can only have 255 characters) while binaries can have a length encoding of 1-4 bytes. Single bytes
do not require a length encoding.

      Type        Code   Length Bytes  Bytes encoded
      ==========  ====   ============  =============
      byte        0x0A   0             1
      binary_1    0x0B   1             0..255
      binary_2    0x0C   2             0..65_535
      binary_3    0x0D   3             0..2 147 483 647
      binary_4    0x0E   4             0..18 446 744 073 709 551 615
      atom        0x0F   1             0..255

Example of the atom "true":

   0                   1                   2                   3
   0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |      0x03     |      0x0F     |      0x04     |      0x74     |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |      0x72     |      0x75     |      0x65     |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

  [<<3>>, <<15>>, <<4, 116, 114, 117, 101>>]


    NOTE: it would be very nice to be able to use the atom cache to send integer values
    rather than full strings for atoms when available.

= Collections

== Lists

Lists are encoded much like primitives with code 0x21 with the exception that the
end of a list is marked in the schema with a null byte.

Example of [1, 2, 3]:

   0                   1                   2                   3
   0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |      0x03     |      0x21     |      0xA0     |      0x03     |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |      0x02     |      0x1      |      0x2      |      0x3      |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |      0x00     |
  +-+-+-+-+-+-+-+-+


    [<<3>>, <<33, 160, 2, 2, 0>>, <<1, 2>>]

=== Maps

Maps are denoted with type code 0x22, end with a null byte, and contain pairs of key
and value types.

NOTE: This is not optimal. Keys and values should be encoded separately with key type
codes first in one sub-buffer in the schema data, and values to follow. The rational is
that keys are often of the same data type, but values often are not. This will allow
for more efficient encoding as the key types are likely to repeat.

=== Structs

Structs are encoded exactly like maps except that the name of the struct is encoded
in the schema:

    defmodule F do
      defstruct a: 1
    end

    [<<4>>, <<35, 8, 69, 108, 105, 120, 105, 114, 46, 70, 15, 2, 0>>, <<1, 97, 1>>]

As can be seen in the above, the module name is in the schema. The rational is that
it is not uncommon for structs of the same type to appear in collections like lists
and this gives the opportunity to easily remove those bytes altogether from the data
when they do appear in sequence.

=== Tuples

Tuples are the special beast. A tuple with no items ({}) is represented as 0x40. Tuples
with 1..63 elements are 0x40 + the number of items in the tuple. This allows encoding
most tuples with just one byte in the schema. Tuples with more than 63 elements are
followed by 3 bytes containing an integer value equal to the number of elements in
the tuple.

The value 0x40 was selected specifically as it allows to check with a simple bitmask
operation whether any tuple type value is a tuple: type &&& 0b00111111

Tuples were singled out for this sort of encoding as the common case for tuples is
a small number of elements, whereas other containers commonly have in excess of 63
entries, allowing for the often used tuple type to benefit maximally from setting
aside that much of the 255 values available to the single byte type code.

Empty tuple:

  [<<4>>, "@", ""]

{1, 2, 3}:

  [<<4>>, <<67, 160, 3, 2>>, <<1, 2, 3>>]

== Repeat directives

A repeat diretive denotes that the next term in the schema is repeated 2 or more times.
To remain thrifty, repititions consist of a repition type code (1 byte) and then the
number of times the following term is repeated in 1, 2 or 4 bytes as needed.

The repition type codes all have bits 8 and 6 set to 1 (e.g. are >= 160), allowing for
them to be easily detected from other types by bit mask (0b1000000) and by simple
greater than as the largest tuple type code is 127 (0b01111111).

  NOTE: another optimization that is not taken advantage of yet would be to have a
  repeat_0 matching mask 0b11xxxxxx and use bits 1-6 to encode repititions of 64
  or less iterations

      Type        Code   Rep Count Bytes
      ==========  ====   ===============
      repeat_1    0xA0   1
      repeat_2    0xA1   2
      repeat_4    0xA2   4

Example of [1, 2, 3]:

   0                   1                   2                   3
   0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |      0x03     |      0x21     |      0xA0     |      0x03     |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |      0x02     |      0x1      |      0x2      |      0x3      |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |      0x00     |
  +-+-+-+-+-+-+-+-+


    [<<3>>, <<33, 160, 2, 2, 0>>, <<1, 2>>]

== Data

The data segment is encoded with all numeric values in little-endian byte order. Virtually
all machines are little-endian, and so even though endianness conversion is quite cheap these
days, it is more convnient and even fewer cycles (in theory, anyways) to stick to "native"
encodings.

When compressed (the default for the data segment), zstd is used as the compression algorithm.
It produces fewer bytes in fewer cycles than zlib, and indeed many other algorithms including
zopfli/brotli.

When compression results in a larger payload size, it is dropped and the uncompressed data is
returned in the data segment.

    NOTE: Due to the compression library used (:zstd), a streaming decoder is not currently
    implemented. However, :zstd does support streaming compression/decompression so this would
    be possible.
