/* Arrays describing the available user registers. -*- mode: c -*- */

// #ifdef orgy factored out to common include file

static const jit_gpr_t rregs[] = {
  JIT_R0,
  JIT_R1,
  JIT_R2,
#ifdef JIT_R3
  JIT_R3,
#endif
#ifdef JIT_R4
  JIT_R4,
#endif
#ifdef JIT_R5
  JIT_R5,
#endif
#ifdef JIT_R6
  JIT_R6,
#endif
#ifdef JIT_R7
  JIT_R7,
#endif
#ifdef JIT_R8
  JIT_R8,
#endif
#ifdef JIT_R9
  JIT_R9,
#endif
#ifdef JIT_R10
  JIT_R10,
#endif
#ifdef JIT_R11
  JIT_R11,
#endif
#ifdef JIT_R12
  JIT_R12,
#endif
#ifdef JIT_R13
  JIT_R13,
#endif
#ifdef JIT_R14
  JIT_R14,
#endif
#ifdef JIT_R15
  JIT_R15,
#endif
#ifdef JIT_R16
  JIT_R16,
#endif
};

static const jit_gpr_t vregs[] = {
  JIT_V0, JIT_V1, JIT_V2,
#ifdef JIT_V3
  JIT_V3,
#endif
#ifdef JIT_V4
  JIT_V4,
#endif
#ifdef JIT_V5
  JIT_V5,
#endif
#ifdef JIT_V6
  JIT_V6,
#endif
#ifdef JIT_V7
  JIT_V7,
#endif
#ifdef JIT_V8
  JIT_V8,
#endif
#ifdef JIT_V9
  JIT_V9,
#endif
#ifdef JIT_V10
  JIT_V10,
#endif
#ifdef JIT_V11
  JIT_V11,
#endif
#ifdef JIT_V12
  JIT_V12,
#endif
#ifdef JIT_V13
  JIT_V13,
#endif
#ifdef JIT_V14
  JIT_V14,
#endif
#ifdef JIT_V15
  JIT_V15,
#endif
#ifdef JIT_V16
  JIT_V16,
#endif
};

static const jit_fpr_t fregs[] = {
  JIT_F0, JIT_F1, JIT_F2,
  JIT_F2, JIT_F3, JIT_F4,
#ifdef JIT_F7
  JIT_F7,
#endif
#ifdef JIT_F8
  JIT_F8,
#endif
#ifdef JIT_F9
  JIT_F9,
#endif
#ifdef JIT_F10
  JIT_F10,
#endif
#ifdef JIT_F11
  JIT_F11,
#endif
#ifdef JIT_F12
  JIT_F12,
#endif
#ifdef JIT_F13
  JIT_F13,
#endif
#ifdef JIT_F14
  JIT_F14,
#endif
#ifdef JIT_F15
  JIT_F15,
#endif
#ifdef JIT_F16
  JIT_F16,
#endif
};

static const jit_fpr_t vfregs[] = {
#ifdef JIT_VF0
  JIT_VF0,
#endif
#ifdef JIT_VF1
  JIT_VF1,
#endif
#ifdef JIT_VF2
  JIT_VF2,
#endif
#ifdef JIT_VF2
  JIT_VF2,
#endif
#ifdef JIT_VF3
  JIT_VF3,
#endif
#ifdef JIT_VF4
  JIT_VF4,
#endif
#ifdef JIT_VF5
  JIT_VF5,
#endif
#ifdef JIT_VF6
  JIT_VF6,
#endif
#ifdef JIT_VF7
  JIT_VF7,
#endif
#ifdef JIT_VF8
  JIT_VF8,
#endif
#ifdef JIT_VF9
  JIT_VF9,
#endif
#ifdef JIT_VF10
  JIT_VF10,
#endif
#ifdef JIT_VF11
  JIT_VF11,
#endif
#ifdef JIT_VF12
  JIT_VF12,
#endif
#ifdef JIT_VF13
  JIT_VF13,
#endif
#ifdef JIT_VF14
  JIT_VF14,
#endif
#ifdef JIT_VF15
  JIT_VF15,
#endif
#ifdef JIT_VF16
  JIT_VF16,
#endif
};

#define ARRAY_SIZE(X) (sizeof (X)/sizeof ((X)[0]))
static const size_t r_count = ARRAY_SIZE (rregs);
static const size_t v_count = ARRAY_SIZE (vregs);
static const size_t f_count = ARRAY_SIZE (fregs);
static const size_t vf_count = ARRAY_SIZE (vfregs);
static const size_t gpr_count = r_count + v_count;

static jit_gpr_t
gpr_ref (uintptr_t i)
{
  if (i < r_count)
    return rregs[i];
  if (i < r_count + v_count)
    return vregs[i - r_count];
  abort ();
}
