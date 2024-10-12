#include "test.h"
#include "regarrays.inc"

#define DEFINE_TEST_INT(ABI_TYPE, TYPE, LIT, NEGATE)			\
static TYPE								\
check_##TYPE (TYPE a, TYPE b, TYPE c, TYPE d, TYPE e,			\
              TYPE f, TYPE g, TYPE h, TYPE i, TYPE j)			\
{									\
  ASSERT(a == LIT(0));							\
  ASSERT(b == NEGATE(1));						\
  ASSERT(c == LIT(2));							\
  ASSERT(d == NEGATE(3));						\
  ASSERT(e == LIT(4));							\
  ASSERT(f == NEGATE(5));						\
  ASSERT(g == LIT(6));							\
  ASSERT(h == NEGATE(7));						\
  ASSERT(i == LIT(8));							\
  ASSERT(j == NEGATE(9));						\
  return LIT(42);							\
}									\
									\
static void								\
run_test_##TYPE (jit_state_t *j, uint8_t *arena_base, size_t arena_size, \
		 jit_gpr_t base)					\
{									\
  jit_begin(j, arena_base, arena_size);					\
  size_t align = jit_enter_jit_abi(j, v_count, 0, 0);			\
  jit_load_args_1(j, jit_operand_gpr (JIT_OPERAND_ABI_POINTER, base));	\
									\
  jit_operand_t args[10] = {						\
    jit_operand_mem(ABI_TYPE, base, 0 * sizeof(TYPE)),			\
    jit_operand_mem(ABI_TYPE, base, 1 * sizeof(TYPE)),			\
    jit_operand_mem(ABI_TYPE, base, 2 * sizeof(TYPE)),			\
    jit_operand_mem(ABI_TYPE, base, 3 * sizeof(TYPE)),			\
    jit_operand_mem(ABI_TYPE, base, 4 * sizeof(TYPE)),			\
    jit_operand_mem(ABI_TYPE, base, 5 * sizeof(TYPE)),			\
    jit_operand_mem(ABI_TYPE, base, 6 * sizeof(TYPE)),			\
    jit_operand_mem(ABI_TYPE, base, 7 * sizeof(TYPE)),			\
    jit_operand_mem(ABI_TYPE, base, 8 * sizeof(TYPE)),			\
    jit_operand_mem(ABI_TYPE, base, 9 * sizeof(TYPE)),			\
  };									\
  jit_calli(j, check_##TYPE, 10, args);					\
  jit_leave_jit_abi(j, v_count, 0, align);				\
  jit_ret(j);								\
									\
  size_t size = 0;							\
  void* ret = jit_end(j, &size);					\
									\
  TYPE (*f)(TYPE*) = ret;						\
									\
  TYPE iargs[10] = { LIT(0), NEGATE(1), LIT(2), NEGATE(3), LIT(4),	\
		     NEGATE(5), LIT(6), NEGATE(7), LIT(8), NEGATE(9) };	\
  ASSERT(f(iargs) == LIT(42));						\
}

#define LIT(X) (X)
#define NEGATE(X) (-X)
DEFINE_TEST_INT(JIT_OPERAND_ABI_INT32, int32_t, LIT, NEGATE);
#if (UINTPTR_MAX == UINT64_MAX)
DEFINE_TEST_INT(JIT_OPERAND_ABI_INT64, int64_t, LIT, NEGATE);
#endif
#undef NEGATE

#define NEGATE(X) (~X)
DEFINE_TEST_INT(JIT_OPERAND_ABI_UINT32, uint32_t, LIT, NEGATE);
#if (UINTPTR_MAX == UINT64_MAX)
DEFINE_TEST_INT(JIT_OPERAND_ABI_UINT64, uint64_t, LIT, NEGATE);
#endif
#undef NEGATE
#undef LIT

typedef uint8_t* ptr_t;
#define LIT(X) ((ptr_t)(uintptr_t)(X))
#define NEGATE(X) ((ptr_t)(~(uintptr_t)(X)))
DEFINE_TEST_INT(JIT_OPERAND_ABI_POINTER, ptr_t, LIT, NEGATE);

static double
check_double (double a, double b, double c, double d, double e,
	      double f, double g, double h, double i, double j)
{
  ASSERT(a == 0.0);
  ASSERT(b == -1.0);
  ASSERT(c == -0xfffffffffffffp+100l);
  ASSERT(d == +0xfffffffffffffp-100l);
  ASSERT(e == -0xfffffffffffffp+101l);
  ASSERT(f == +0xfffffffffffffp-102l);
  ASSERT(g == -0xfffffffffffffp+102l);
  ASSERT(h == +0xfffffffffffffp-103l);
  ASSERT(i == -0xfffffffffffffp+103l);
  ASSERT(j == +0xfffffffffffffp-104l);
  return 42;
}

static void
run_test_double (jit_state_t *j, uint8_t *arena_base, size_t arena_size,
		 jit_gpr_t base)
{
  double dargs[10] = {
    0.0,
    -1.0,
    -0xfffffffffffffp+100l,
    +0xfffffffffffffp-100l,
    -0xfffffffffffffp+101l,
    +0xfffffffffffffp-102l,
    -0xfffffffffffffp+102l,
    +0xfffffffffffffp-103l,
    -0xfffffffffffffp+103l,
    +0xfffffffffffffp-104l,
  };
  jit_begin(j, arena_base, arena_size);
  size_t align = jit_enter_jit_abi(j, v_count, 0, 0);
  jit_load_args_1(j, jit_operand_gpr (JIT_OPERAND_ABI_POINTER, base));
  enum jit_operand_abi abi = JIT_OPERAND_ABI_DOUBLE;
  jit_movi_d(j, JIT_F0, dargs[0]);
  jit_movi_d(j, JIT_F1, dargs[1]);
  jit_movi_d(j, JIT_F2, dargs[2]);
  jit_movi_d(j, JIT_F3, dargs[3]);
  jit_movi_d(j, JIT_F4, dargs[4]);
  jit_movi_d(j, JIT_F5, dargs[5]);
  jit_movi_d(j, JIT_F6, dargs[6]);
  jit_operand_t args[10] = {
    jit_operand_fpr(abi, JIT_F0),
    jit_operand_fpr(abi, JIT_F1),
    jit_operand_fpr(abi, JIT_F2),
    jit_operand_fpr(abi, JIT_F3),
    jit_operand_fpr(abi, JIT_F4),
    jit_operand_fpr(abi, JIT_F5),
    jit_operand_fpr(abi, JIT_F6),
    jit_operand_mem(abi, base, 7 * sizeof(double)),
    jit_operand_mem(abi, base, 8 * sizeof(double)),
    jit_operand_mem(abi, base, 9 * sizeof(double)),
  };
  jit_calli(j, check_double, 10, args);
  jit_leave_jit_abi(j, v_count, 0, align);
  jit_ret(j);

  size_t size = 0;
  void* ret = jit_end(j, &size);

  double (*f)(double*) = ret;

  ASSERT(f(dargs) == 42);
}

static void
run_test (jit_state_t * j, uint8_t * arena_base, size_t arena_size)
{
  for (unsigned i = 0; i < gpr_count; i++)
    {
      run_test_int32_t (j, arena_base, arena_size, gpr_ref (i));
      run_test_uint32_t (j, arena_base, arena_size, gpr_ref (i));
#if (UINTPTR_MAX == UINT64_MAX)
      run_test_int64_t (j, arena_base, arena_size, gpr_ref (i));
      run_test_uint64_t (j, arena_base, arena_size, gpr_ref (i));
#endif
      run_test_ptr_t (j, arena_base, arena_size, gpr_ref (i));
      run_test_double (j, arena_base, arena_size, gpr_ref (i));
    }
}

int
main (int argc, char *argv[])
{
  return main_helper(argc, argv, run_test);
}
