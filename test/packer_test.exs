defmodule Foo do
  defstruct a: 1, b: 2
end

defmodule PackerTest.Expect do
  defmacro decoding(term, opts \\ []) do
    quote do
      roundtrip = Packer.encode(unquote(term), unquote(opts)) |> Packer.decode(unquote(opts))
      #IO.inspect(unquote(term), label: "Input term")
      #IO.inspect(roundtrip, label: "Decoded")
      assert roundtrip === unquote(term)
    end
  end

  defmacro encoding(unpacked, schema, encoded_term, opts \\ [], expect_shorter \\ true) do
    #line = __CALLER__.line
    quote do
      packed = Packer.encode(unquote(unpacked), unquote(opts))
      [_header, gen_schema, compressed_buffer] = packed
      #IO.inspect(compressed_buffer)
      assert gen_schema === unquote(schema)
      assert Packer.Utils.decompress(compressed_buffer) === unquote(encoded_term)
      if unquote(expect_shorter) do
        assert :erlang.iolist_size(packed) <= :erlang.term_to_binary(unquote(unpacked)) |> byte_size()
      end
      #Logger.debug("Line #{unquote(line)} => sizes: #{:erlang.iolist_size(packed)} <= #{:erlang.term_to_binary(unquote(unpacked)) |> byte_size()}")
    end
  end
end

defmodule PackerTest do
  use ExUnit.Case
  require PackerTest.Expect, as: M
  require Logger

  doctest Packer

  @tag :packer

  test "packs numbers" do
    M.encoding(0, <<2>>, <<0>>)
    M.encoding(1, <<2>>, <<1>>)
    M.encoding(-1, <<1>>, <<255>>)
    M.encoding(-126, <<1>>, <<130>>)
    M.encoding(257, <<4>>, <<1, 1>>)
    M.encoding(-512, <<3>>, <<0, 254>>)
    M.encoding(1_000_000, <<6>>, <<64, 66, 15, 0>>)
    M.encoding(-1_000_000, <<5>>, <<192, 189, 240, 255>>)
    M.encoding(1_000_000_000_000, <<7>>, <<0, 16, 165, 212, 232, 0, 0, 0>>, [], false)
    M.encoding(-1_000_000_000_0000, <<7>>, <<0, 96, 141, 177, 231, 246, 255, 255>>)
    M.encoding("b", <<10>>, "b")
    M.encoding(3.14, <<9>>, <<64, 9, 30, 184, 81, 235, 133, 31>>)
    M.encoding(:atom, <<14>>, <<4>> <> "atom")
  end

  test "packs short binaries" do
    binary = "binary"
    M.encoding(binary, <<11>>, <<6>> <> binary)
  end

  test "packs medium binaries" do
    binary = String.duplicate("f", 30_000)
    M.encoding(binary, <<12>>, <<30_000 :: unsigned-16-little-integer, binary :: binary>>)
  end

  test "packs long binaries" do
    binary = String.duplicate("f", 300_000)
    M.encoding(binary, <<13>>, <<300_000 :: unsigned-32-little-integer, binary :: binary>>)
  end

  test "packs flat lists" do
    M.encoding([], <<33, 0>>, <<>>, [], false)
    M.encoding([1], <<33, 2, 0>>, <<1>>)
    M.encoding([1, 2, 3, 4, 5, 6, 7000], <<33, 160, 6, 2, 4, 0>>, <<1, 2, 3, 4, 5, 6, 88, 27>>)
    M.encoding([1, :atom, "binary"], <<33, 2, 14, 11, 0>>, <<1, 4, "atom", 6, "binary">>)
  end

  test "packs nested lists" do
    M.encoding([[]], <<33, 33, 0, 0>>, <<>>)
    M.encoding([[1]], <<33, 33, 2, 0, 0>>, <<1>>)
    M.encoding([1, [1], 2], <<33, 2, 33, 2, 0, 2, 0>>, <<1, 1, 2>>)
    M.encoding([1, [1, [], [:atom, [3]]], 2], <<33, 2, 33, 2, 33, 0, 33, 14, 33, 2, 0, 0, 0, 2, 0>>, <<1, 1, 4, 97, 116, 111, 109, 3, 2>>)
  end

  test "packs tuples" do
    M.encoding({1, 2}, <<66, 160, 2, 2>>, <<1, 2>>)
    M.encoding({ 1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
              21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40,
              41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60,
              61, 62},
             <<126, 160, 62, 2>>,
             << 1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
               20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38,
               39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57,
               58, 59, 60, 61, 62>>
            )
    M.encoding({ 1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
              21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40,
              41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60,
              61, 62, 63},
             <<127, 63, 0, 0, 160, 63, 2>>,
             << 1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
               20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38,
               39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57,
               58, 59, 60, 61, 62, 63>>
            )
    M.encoding([{1, 2}, {1, 2}], <<33, 160, 2, 66, 160, 2, 2, 0>>, <<1, 2, 1, 2>>)
  end

  test "packs maps" do
    M.encoding(%{}, <<34, 0>>, "")
    M.encoding(%{a: 1, b: 2}, <<34, 160, 2, 14, 2, 0>>, <<1, 97, 1, 1, 98, 2>>)
    M.encoding(%{{"b", 123} => 1, {"c", 124} => 2}, <<34, 160, 2, 66, 10, 2, 2, 0>>, <<98, 123, 1, 99, 124, 2>>)
  end

  test "packs structs" do
    M.encoding(%Foo{}, <<35, 10, 160, 2, 14, 2, 0>>, <<69, 108, 105, 120, 105, 114, 46, 70, 111, 111, 1, 97, 1, 1, 98, 2>>)
  end

  test "small integers are options" do
    M.encoding([1, 2, 3, 4, 5, 6, 7000], <<33, 160, 6, 2, 4, 0>>, <<1, 2, 3, 4, 5, 6, 88, 27>>)
    M.encoding([1, 2, 3, 4, 5, 6, 7000], <<33, 160, 7, 4, 0>>, <<1, 0, 2, 0, 3, 0, 4, 0, 5, 0, 6, 0, 88, 27>>, small_int: false)
  end

  test "compression is optional" do
    a = [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
    [_header, _schema, buffer] = Packer.encode(a, compress: false)
    assert buffer === <<1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1>>
    [_header, _schema, buffer] = Packer.encode(a)
    assert buffer != <<1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1>>
  end

  test "magic header bytes are optional" do
    [header, _, _] = Packer.encode(1, header: :full)
    assert Packer.encoded_term_header(:full) === header
    [header, _, _] = Packer.encode(1, header: :version)
    assert Packer.encoded_term_header(:version) === header
    assert 2 === Enum.count(Packer.encode(1, header: :none))
    assert 3 === Enum.count(Packer.encode(1))
  end

  test "unpacking with no header fails without `header: :none`" do
    assert Packer.decode([<<>>, <<>>]) === {:error, :bad_header}
    assert Packer.decode(<<>>) == {:error, :bad_header}
  end

  test "unpacking with `header: :none` fails if there is a header" do
    header = Packer.encoded_term_header()
    assert Packer.decode([header, <<>>, <<>>], header: :none) === {:error, :bad_header}
    assert Packer.decode(header <> <<1 :: 32-unsigned-little-integer, 2, 1>>, header: :none) === {:error, :bad_header}
  end

  test "unpacking with wrong version header fails" do
    assert Packer.decode([<<0x01>>, <<>>, <<>>]) === {:error, :bad_header}
    assert Packer.decode(<<0x01, 1 :: 32-unsigned-little-integer, 2, 1>>) === {:error, :bad_header}
  end

  test "unpacking with full header requires `header: :full`" do
    header = Packer.encoded_term_header(:full)
    assert Packer.decode([header, <<2>>, <<1>>], header: :full) != {:error, :bad_header}
    assert Packer.decode(header <> <<1 :: 32-unsigned-little-integer, 2, 1>>, header: :full) != {:error, :bad_header}
    assert Packer.decode([header, <<2>>, <<1>>]) === {:error, :bad_header}
    assert Packer.decode(header <> <<1 :: 32-unsigned-little-integer, 2, 1>>) === {:error, :bad_header}
  end

  test "unpacking with no defined header type works with a version header" do
    assert Packer.decode([Packer.encoded_term_header(:full), <<2>>, <<1>>]) === {:error, :bad_header}
    assert Packer.decode(Packer.encoded_term_header(:full) <> <<1 :: 32-unsigned-little-integer, 2, 1>>) === {:error, :bad_header}
    assert Packer.decode([Packer.encoded_term_header(), <<2>>, <<1>>]) !== {:error, :bad_header}
    assert Packer.decode(Packer.encoded_term_header() <> <<1 :: 32-unsigned-little-integer, 2, 1>>) !== {:error, :bad_header}
  end

  test "unpacking a unified binary with a bad schema size failes" do
    assert Packer.decode(Packer.encoded_term_header() <> <<20 :: 32-unsigned-little-integer, 2, 1>>) === {:error, :bad_header}
  end
  test "unpacks numbers" do
    M.decoding(0)
    M.decoding(1)
    M.decoding(-1)
    M.decoding(-126)
    M.decoding(257)
    M.decoding(-512)
    M.decoding(1_000_000)
    M.decoding(-1_000_000)
    M.decoding(1_000_000_000_000)
    M.decoding(-1_000_000_000_0000)
    M.decoding(3.14)
  end

  test "unpacks a byte" do
    M.decoding("b")
  end

  test "unpacks atoms" do
    M.decoding(:atom)
  end

  test "poorly formed buffers the schema says should contain an atom return nil" do
    assert nil === Packer.decode([Packer.encoded_term_header(), <<14, 300>>, "too short"])
  end

  test "unpacks short binaries" do
    M.decoding("binary")
  end

  test "unpacks medium binaries" do
    String.duplicate("f", 30_000) |> M.decoding()
  end

  test "unpacks long binaries" do
    String.duplicate("f", 300_000) |> M.decoding()
  end

  test "unpacks a partial buffer when there are not enough bytes" do
    assert "too short" === Packer.decode([Packer.encoded_term_header(), <<13>>, <<300_000 :: unsigned-32-little-integer, "too short">>])
  end

  test "unpacks flat lists" do
    M.decoding([])
    M.decoding([1])
    M.decoding([1, 2, 3, 4, 5, 6, 7000])
    M.decoding([1, :atom, "binary"])
  end

  test "unpacks nested lists" do
    M.decoding([[]])
    M.decoding([[1]])
    M.decoding([1, [1], 2])
    M.decoding([1, [1, [], [:atom, [3]]], 2])
  end

  test "unpacks lists with repeating containers" do
    M.decoding([[1, 2], [3, 4]])
    M.decoding([{1, 2}, {3, 4}])
    M.decoding([1, {1, 2}, {3, 4}])
    M.decoding([1, {1, 2}, {3, 4}, 2])
    M.decoding([{1, 2}, {3, 4}, 2])
  end

  test "unpacks tuples" do
    M.decoding({1, 2})
    M.decoding({ 1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
                21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40,
                41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60,
                61, 62})
    M.decoding({ 1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
                21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40,
                41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60,
                61, 62, 63})
    M.decoding({:nothing, :but, :atoms})
    M.decoding({"just", "binary", "strings"})
    M.decoding({[1, 2], [:atom, "binary"]})
    M.decoding({%{a: 2}, 1, 2})
  end

  test "unpacks tuples with repeating containers" do
    M.decoding({{1, 2}, {2, 3}})
    M.decoding({[1, 2], [2, 3]})
    M.decoding({1, [1, 2], [2, 3]})
    M.decoding({1, [1, 2], [2, 3], 2})
    M.decoding({[1, 2], [2, 3], 2})
  end

  test "unpacks maps" do
    M.decoding(%{})
    M.decoding(%{:a => 1, 2 => 3})
    M.decoding(%{{"b", 123} => 1, {:c, 124} => [1, 2, 3], [1, 2] => :alpha})
  end

  test "unpacks maps with repeating containers" do
    M.decoding(%{a: 1, b: 2})
    M.decoding(%{{"b", 123} => 1, {"c", 124} => 2})
  end

  test "unpacks structs" do
    M.decoding(%Foo{})
  end

  test "unpacking without compresion" do
    M.decoding([1, 1, 1, 1], compress: false)

    compressable = [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
    assert compressable === (Packer.encode(compressable, compress: false) |> Packer.decode())
  end

  test "unpacking with compression" do
    compressable = [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
    assert compressable === (Packer.encode(compressable) |> Packer.decode())
    refute compressable == (Packer.encode(compressable) |> Packer.decode(compress: false))
  end

  test "unpacks unified buffers" do
    M.decoding([1, 1, 1, 1, 1], format: :binary)
  end
end
