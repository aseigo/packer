defmodule PackerTestMacros do
  defmacro expect(unpacked, packed) do
    quote do
      packed = Packer.encode(unquote(unpacked))
      assert packed === unquote(packed)
      #assert byte_size(packed) <= :erlang.term_to_binary(unquote(unpacked)) |> byte_size()
    end
  end
end

defmodule PackerTest do
  use ExUnit.Case
  require PackerTestMacros, as: M

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
    M.expect(:atom, [<<12, 0, 0, 0, 4>>, "atom"])
  end

  test "packs flat lists" do
    M.expect([], [<<33, 0>>, <<>>])
    M.expect([1], [<<33, 1, 0>>, <<1>>])
    M.expect([1, :atom, "binary"], [<<33, 1, 12, 0, 0, 0, 4, 10, 0, 0, 0, 6, 0>>, <<1, "atom", "binary">>])
  end

  test "packs nested lists" do
    M.expect([[]], [<<33, 33, 0, 0>>, <<>>])
    M.expect([[1]], [<<33, 33, 1, 0, 0>>, <<1>>])
    M.expect([1, [1], 2], [<<33, 1, 33, 1, 0, 1, 0>>, <<1, 1, 2>>])
  end
end
