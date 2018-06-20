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

  defmacro encoding(unpacked, schema, encoded_term, opts \\ []) do
    #line = __CALLER__.line
    quote do
      packed = Packer.encode(unquote(unpacked), unquote(opts))
      [_header, gen_schema, compressed_buffer] = packed
      #IO.inspect(compressed_buffer)
      assert gen_schema === unquote(schema)
      assert Packer.Utils.decompress(compressed_buffer) === unquote(encoded_term)
      assert :erlang.iolist_size(packed) <= :erlang.term_to_binary(unquote(unpacked)) |> byte_size()
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
    M.encoding(-512, <<3>>, <<254, 0>>)
    M.encoding(1_000_000, <<6>>, <<0, 15, 66, 64>>)
    M.encoding(-1_000_000, <<5>>, <<255, 240, 189, 192>>)
    M.encoding(1_000_000_000_000, <<7>>, <<0, 0, 0, 232, 212, 165, 16, 0>>)
    M.encoding(-1_000_000_000_0000, <<7>>, <<255, 255, 246, 231, 177, 141, 96, 0>>)
    M.encoding("b", <<9>>, "b")
    M.encoding(3.14, <<9>>, <<64, 9, 30, 184, 81, 235, 133, 31>>)
    M.encoding(:atom, <<14, 4>>, "atom")
  end

  test "packs short binaries" do
    binary = "binary"
    M.encoding(binary, <<11, 6>>, binary)
  end

  test "packs medium binaries" do
    binary = String.duplicate("f", 30_000)
    M.encoding(binary, <<12, 30_000 :: unsigned-16-integer>>, binary)
  end

  test "packs long binaries" do
    binary = String.duplicate("f", 300_000)
    M.encoding(binary, <<13, 300_000 :: unsigned-32-integer>>, binary)
  end

  test "packs flat lists" do
    M.encoding([], <<33, 0>>, <<>>)
    M.encoding([1], <<33, 1, 0>>, <<1>>)
    M.encoding([1, 2, 3, 4, 5, 6, 7000], <<33, 160, 6, 1, 3, 0>>, <<1, 2, 3, 4, 5, 6, 27, 88>>)
    M.encoding([1, :atom, "binary"], <<33, 1, 12, 4, 10, 0, 0, 0, 6, 0>>, <<1, "atom", "binary">>)
  end

  test "packs nested lists" do
    M.encoding([[]], <<33, 33, 0, 0>>, <<>>)
    M.encoding([[1]], <<33, 33, 2, 0, 0>>, <<1>>)
    M.encoding([1, [1], 2], <<33, 2, 33, 2, 0, 2, 0>>, <<1, 1, 2>>)
    M.encoding([1, [1, [], [:atom, [3]]], 2], <<33, 2, 33, 2, 33, 0, 33, 14, 4, 33, 2, 0, 0, 0, 2, 0>>, <<1, 1, 97, 116, 111, 109, 3, 2>>)
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
             <<64, 0, 63, 160, 63, 2>>,
             << 1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
               20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38,
               39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57,
               58, 59, 60, 61, 62, 63>>
            )
    M.encoding([{1, 2}, {1, 2}], <<33, 160, 2, 66, 160, 2, 2, 0>>, <<1, 2, 1, 2>>)
  end

  test "packs maps" do
    M.encoding(%{}, <<34, 0>>, "")
    M.encoding(%{a: 1, b: 2}, <<34, 160, 2, 14, 1, 2, 0>>, <<97, 1, 98, 2>>)
    M.encoding(%{{"b", 123} => 1, {"c", 124} => 2}, <<34, 160, 2, 66, 10, 2, 2, 0>>, <<98, 123, 1, 99, 124, 2>>)
  end

  test "packs structs" do
    M.encoding(%Foo{}, <<34, 160, 2, 14, 1, 2, 14, 10, 14, 10, 0>>, <<97, 1, 98, 2, 95, 95, 115, 116, 114, 117, 99, 116, 95, 95, 69, 108, 105, 120, 105, 114, 46, 70, 111, 111>>)
  end

  test "small integers are options" do
    M.encoding([1, 2, 3, 4, 5, 6, 7000], <<33, 160, 6, 2, 4, 0>>, <<1, 2, 3, 4, 5, 6, 27, 88>>)
    M.encoding([1, 2, 3, 4, 5, 6, 7000], <<33, 160, 7, 4, 0>>, <<0, 1, 0, 2, 0, 3, 0, 4, 0, 5, 0, 6, 27, 88>>, small_int: false)
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
  end

  test "unpacking with `header: :none` fails if there is a header" do
    assert Packer.decode([Packer.encoded_term_header(), <<>>, <<>>], header: :none) === {:error, :bad_header}
  end

  test "unpacking with wrong version header fails" do
    assert Packer.decode([<<>>, <<>>, <<>>]) === {:error, :bad_header}
  end

  test "unpacking with full header requires `header: :full`" do
    assert Packer.decode([Packer.encoded_term_header(:full), <<>>, <<>>], header: :full) != {:error, :bad_header}
    assert Packer.decode([Packer.encoded_term_header(:full), <<>>, <<>>]) === {:error, :bad_header}
  end

  test "unpacking with no define header type works with a version header" do
    assert Packer.decode([Packer.encoded_term_header(:full), <<>>, <<>>]) === {:error, :bad_header}
    assert Packer.decode([Packer.encoded_term_header(), <<>>, <<>>]) !== {:error, :bad_header}
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
    assert "too short" === Packer.decode([Packer.encoded_term_header(), <<13, 300_000 :: unsigned-32-integer>>, "too short"])
  end
end
