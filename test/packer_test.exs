defmodule F do
  defstruct a: 1, b: 2
end

defmodule PackerTestMacros do
  defmacro expect(unpacked, packed) do
    #line = __CALLER__.line
    quote do
      packed = Packer.encode(unquote(unpacked))
      [schema, compressed_buffer] = packed
      buffer = PackerTestMacros.decompress(compressed_buffer)
      assert [schema, buffer] === unquote(packed)
      assert :erlang.iolist_size([schema, compressed_buffer]) <= :erlang.term_to_binary(unquote(unpacked)) |> byte_size()
      #Logger.debug("Line #{unquote(line)} => sizes: #{:erlang.iolist_size(packed)} <= #{:erlang.term_to_binary(unquote(unpacked)) |> byte_size()}")
    end
  end

  def decompress(buffer) do
    z = :zlib.open()
    :ok = :zlib.inflateInit(z)

    uncompressed =
      try do
        v =
        case :zlib.inflate(z, buffer) do
          []  -> ""
          [v] -> v
        end
        :ok = :zlib.inflateEnd(z)
        v
      rescue
        ErlangError -> buffer
      end
    :zlib.close(z)
    uncompressed
  end
end

defmodule PackerTest do
  use ExUnit.Case
  require PackerTestMacros, as: M
  require Logger

  doctest Packer

  @tag :packer

  test "packs individual primitives" do
    M.expect(0, [<<1>>, <<0>>])
    M.expect(1, [<<1>>, <<1>>])
    M.expect(-1, [<<2>>, <<255>>])
    M.expect(-126, [<<2>>, <<130>>])
    M.expect(257, [<<3>>, <<1, 1>>])
    M.expect(-512, [<<4>>, <<254, 0>>])
    M.expect(1_000_000, [<<5>>, <<0, 15, 66, 64>>])
    M.expect(-1_000_000, [<<6>>, <<255, 240, 189, 192>>])
    M.expect(1_000_000_000_000, [<<7>>, <<0, 0, 0, 232, 212, 165, 16, 0>>])
    M.expect(-1_000_000_000_0000, [<<7>>, <<255, 255, 246, 231, 177, 141, 96, 0>>])
    M.expect("b", [<<9>>, "b"])
    M.expect("binary", [<<10, 0, 0, 0, 6>>, "binary"])
    M.expect(3.14, [<<11>>, <<64, 9, 30, 184, 81, 235, 133, 31>>])
    M.expect(:atom, [<<12, 4>>, "atom"])
  end

  test "packs flat lists" do
    M.expect([], [<<33, 0>>, <<>>])
    M.expect([1], [<<33, 1, 0>>, <<1>>])
    M.expect([1, :atom, "binary"], [<<33, 1, 12, 4, 10, 0, 0, 0, 6, 0>>, <<1, "atom", "binary">>])
  end

  test "packs nested lists" do
    M.expect([[]], [<<33, 33, 0, 0>>, <<>>])
    M.expect([[1]], [<<33, 33, 1, 0, 0>>, <<1>>])
    M.expect([1, [1], 2], [<<33, 1, 33, 1, 0, 1, 0>>, <<1, 1, 2>>])
    M.expect([1, [1, [], [:atom, [3]]], 2], [<<33, 1, 33, 1, 33, 0, 33, 12, 4, 33, 1, 0, 0, 0, 1, 0>>, <<1, 1, 97, 116, 111, 109, 3, 2>>])
  end

  test "packs tuples" do
    M.expect({1, 2}, [<<66, 1, 1>>, <<1, 2>>])
    M.expect({ 1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
              21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40,
              41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60,
              61, 62},
             [
               <<126, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
                      1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
                      1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1>>,
               << 1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
                 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38,
                 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57,
                 58, 59, 60, 61, 62>>
             ])
    M.expect({ 1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
              21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40,
              41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60,
              61, 62, 63},
             [
               <<64, 0, 63,
                     1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
                     1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
                     1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1>>,
               << 1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
                 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38,
                 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57,
                 58, 59, 60, 61, 62, 63>>
             ])
    M.expect([{1, 2}, {1, 2}], [<<33, 160, 2, 66, 160, 2, 1, 0>>, <<1, 2, 1, 2>>])
  end

  test "packs maps" do
    M.expect(%{}, [<<34, 0>>, ""])
    M.expect(%{a: 1, b: 2}, [<<34, 160, 2, 12, 1, 1, 0>>, <<97, 1, 98, 2>>])
    M.expect(%{{"b", 123} => 1, {"c", 124} => 2}, [<<34, 160, 2, 66, 9, 1, 1, 0>>, <<98, 123, 1, 99, 124, 2>>])
  end

  test "packs structs" do
    M.expect(%F{},
              [
                <<34, 160, 2, 12, 1, 1, 12, 10, 12, 8, 0>>,
                <<97, 1, 98, 2, 95, 95, 115, 116, 114, 117, 99, 116, 95, 95, 69, 108, 105,
                  120, 105, 114, 46, 70>>
              ]
            )
  end
end
