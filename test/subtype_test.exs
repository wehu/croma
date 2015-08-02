defmodule Croma.SubtypeTest do
  use ExUnit.Case

  defmodule I1 do
    use Croma.SubtypeOfInt, [min: 1]
  end
  defmodule I2 do
    use Croma.SubtypeOfInt, [min: 0, max: 10]
  end
  defmodule I3 do
    use Croma.SubtypeOfInt, [max: -1]
  end
  defmodule I4 do
    use Croma.SubtypeOfInt, [min: -5, max: 5]
  end

  test "Croma.SubtypeOfInt: validate/1" do
    assert I1.validate(0) == {:error, "validation error for #{I1}: 0"}
    assert I1.validate(1) == {:ok   , 1}

    assert I2.validate(-1) == {:error, "validation error for #{I2}: -1"}
    assert I2.validate( 0) == {:ok   ,  0}
    assert I2.validate(10) == {:ok   , 10}
    assert I2.validate(11) == {:error, "validation error for #{I2}: 11"}

    assert I3.validate(-1) == {:ok   , -1}
    assert I3.validate( 0) == {:error, "validation error for #{I3}: 0"}

    assert I4.validate(-6) == {:error, "validation error for #{I4}: -6"}
    assert I4.validate(-5) == {:ok   , -5}
    assert I4.validate( 5) == {:ok   ,  5}
    assert I4.validate( 6) == {:error, "validation error for #{I4}: 6"}

    assert I1.validate(nil) == {:error, "validation error for #{I1}: nil"}
    assert I1.validate([] ) == {:error, "validation error for #{I1}: []"}
  end

  defmodule F1 do
    use Croma.SubtypeOfFloat, [min: -5.0]
  end
  defmodule F2 do
    use Croma.SubtypeOfFloat, [max: 10.0]
  end
  defmodule F3 do
    use Croma.SubtypeOfFloat, [min: 0.0, max: 1.5]
  end

  test "Croma.SubtypeOfFloat: validate/1" do
    assert F1.validate(-5.1) == {:error, "validation error for #{F1}: -5.1"}
    assert F1.validate(-5.0) == {:ok   , -5.0}

    assert F2.validate(10.0) == {:ok   , 10.0}
    assert F2.validate(10.1) == {:error, "validation error for #{F2}: 10.1"}

    assert F3.validate(-0.1) == {:error, "validation error for #{F3}: -0.1"}
    assert F3.validate( 0.0) == {:ok   , 0.0}
    assert F3.validate( 1.5) == {:ok   , 1.5}
    assert F3.validate( 1.6) == {:error, "validation error for #{F3}: 1.6"}

    assert F1.validate(nil) == {:error, "validation error for #{F1}: nil"}
    assert F1.validate([] ) == {:error, "validation error for #{F1}: []"}
  end

  defmodule S1 do
    use Croma.SubtypeOfString, pattern: ~r/^foo|bar$/
  end

  test "Croma.SubtypeOfString: validate/1" do
    assert S1.validate("foo") == {:ok   , "foo"}
    assert S1.validate("bar") == {:ok   , "bar"}
    assert S1.validate("buz") == {:error, "validation error for #{S1}: \"buz\""}
    assert S1.validate(nil  ) == {:error, "validation error for #{S1}: nil"}
    assert S1.validate([]   ) == {:error, "validation error for #{S1}: []"}
  end

  defmodule A1 do
    use Croma.SubtypeOfAtom, values: [:a1, :a2, :a3]
  end

  test "Croma.SubtypeOfAtom: validate/1" do
    assert A1.validate(:a1 ) == {:ok   , :a1}
    assert A1.validate("a1") == {:ok   , :a1}
    assert A1.validate(:a2 ) == {:ok   , :a2}
    assert A1.validate("a2") == {:ok   , :a2}
    assert A1.validate(:a3 ) == {:ok   , :a3}
    assert A1.validate("a3") == {:ok   , :a3}
    assert A1.validate(:a4 ) == {:error, "validation error for #{A1}: :a4"}
    assert A1.validate("a4") == {:error, "validation error for #{A1}: \"a4\""}
    assert A1.validate(nil ) == {:error, "validation error for #{A1}: nil"}
    assert A1.validate([]  ) == {:error, "validation error for #{A1}: []"}
  end

  defmodule L1 do
    use Croma.SubtypeOfList, elem_module: I1
  end
  defmodule L2 do
    use Croma.SubtypeOfList, elem_module: I2, max_length: 3
  end
  defmodule L3 do
    use Croma.SubtypeOfList, elem_module: I3, min_length: 2
  end
  defmodule L4 do
    use Croma.SubtypeOfList, elem_module: I4, min_length: 1, max_length: 3
  end

  test "Croma.SubtypeOfList: validate/1" do
    assert L1.validate([] ) == {:ok   , []}
    assert L1.validate([1]) == {:ok   , [1]}
    assert L1.validate([0]) == {:error, "validation error for #{I1}: 0"}

    assert L2.validate([]          ) == {:ok   , []}
    assert L2.validate([1, 2, 3]   ) == {:ok   , [1, 2, 3]}
    assert L2.validate([1, 2, 11]  ) == {:error, "validation error for #{I2}: 11"}
    assert L2.validate([1, 2, 3, 4]) == {:error, "validation error for #{L2}: [1, 2, 3, 4]"}

    assert L3.validate([ 1]    ) == {:error, "validation error for #{I3}: 1"}
    assert L3.validate([-1]    ) == {:error, "validation error for #{L3}: [-1]"}
    assert L3.validate([-1, -2]) == {:ok   , [-1, -2]}

    assert L4.validate([]          ) == {:error, "validation error for #{L4}: []"}
    assert L4.validate([-5]        ) == {:ok   , [-5]}
    assert L4.validate([-5, 0, 5]  ) == {:ok   , [-5, 0, 5]}
    assert L4.validate([-5, 10]    ) == {:error, "validation error for #{I4}: 10"}
    assert L4.validate([0, 0, 0, 0]) == {:error, "validation error for #{L4}: [0, 0, 0, 0]"}
  end
end