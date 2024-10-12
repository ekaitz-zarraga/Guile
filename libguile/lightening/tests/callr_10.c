#include "test.h"
#include "regarrays.inc"

static int32_t f(int32_t a, int32_t b, int32_t c, int32_t d, int32_t e,
                 int32_t f, int32_t g, int32_t h, int32_t i, int32_t j) {
  ASSERT(a == 0);
  ASSERT(b == 1);
  ASSERT(c == 2);
  ASSERT(d == 3);
  ASSERT(e == 4);
  ASSERT(f == 5);
  ASSERT(g == 6);
  ASSERT(h == 7);
  ASSERT(i == 8);
  ASSERT(j == 9);
  return 42;
}

static void
run_test_2 (jit_state_t *j, uint8_t *arena_base, size_t arena_size,
	    jit_gpr_t base, jit_gpr_t fun)
{
  jit_begin(j, arena_base, arena_size);
  size_t align = jit_enter_jit_abi(j, v_count, 0, 0);
  jit_load_args_1(j, jit_operand_gpr (JIT_OPERAND_ABI_POINTER, base));

  jit_operand_t args[10] = {
    jit_operand_mem(JIT_OPERAND_ABI_INT32, base, 0 * sizeof(int32_t)),
    jit_operand_mem(JIT_OPERAND_ABI_INT32, base, 1 * sizeof(int32_t)),
    jit_operand_mem(JIT_OPERAND_ABI_INT32, base, 2 * sizeof(int32_t)),
    jit_operand_mem(JIT_OPERAND_ABI_INT32, base, 3 * sizeof(int32_t)),
    jit_operand_mem(JIT_OPERAND_ABI_INT32, base, 4 * sizeof(int32_t)),
    jit_operand_mem(JIT_OPERAND_ABI_INT32, base, 5 * sizeof(int32_t)),
    jit_operand_mem(JIT_OPERAND_ABI_INT32, base, 6 * sizeof(int32_t)),
    jit_operand_mem(JIT_OPERAND_ABI_INT32, base, 7 * sizeof(int32_t)),
    jit_operand_mem(JIT_OPERAND_ABI_INT32, base, 8 * sizeof(int32_t)),
    jit_operand_mem(JIT_OPERAND_ABI_INT32, base, 9 * sizeof(int32_t))
  };
  jit_movi(j, fun, (uintptr_t)f);
  jit_callr(j, fun, 10, args);
  jit_leave_jit_abi(j, v_count, 0, align);
  jit_ret(j);

  size_t size = 0;
  void* ret = jit_end(j, &size);

  int32_t (*f)(int32_t*) = ret;

  int32_t iargs[10] = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 };
  ASSERT(f(iargs) == 42);
}

static void
run_test (jit_state_t *jit, uint8_t *arena_base, size_t arena_size)
{
  for (unsigned i = 0; i < gpr_count; i++)
    for (unsigned j = 0; j < gpr_count; j++)
      if (i != j)
	run_test_2 (jit, arena_base, arena_size, gpr_ref(i), gpr_ref(j));
}

int
main (int argc, char *argv[])
{
  return main_helper(argc, argv, run_test);
}
