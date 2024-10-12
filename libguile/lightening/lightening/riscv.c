/*
 * Copyright (C) 2012-2021  Free Software Foundation, Inc.
 *
 * This file is part of GNU lightning.
 *
 * GNU lightning is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published
 * by the Free Software Foundation; either version 3, or (at your option)
 * any later version.
 *
 * GNU lightning is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
 * or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
 * License for more details.
 *
 * Authors:
 *      Ekaitz Zarraga <ekaitz@elenq.tech>
 */

#include "riscv-cpu.c"
#include "riscv-fpu.c"

static const jit_gpr_t abi_gpr_args[] = {
  _A0, _A1, _A2, _A3, _A4, _A5, _A6, _A7
};
static const jit_fpr_t abi_fpr_args[] = {
  _FA0, _FA1, _FA2, _FA3, _FA4, _FA5, _FA6, _FA7
};
static const int abi_gpr_arg_count = sizeof(abi_gpr_args) / sizeof(abi_gpr_args[0]);
static const int abi_fpr_arg_count = sizeof(abi_fpr_args) / sizeof(abi_fpr_args[0]);

struct abi_arg_iterator
{
  const jit_operand_t *args;
  size_t argc;

  size_t arg_idx;
  size_t gpr_idx;
  size_t fpr_idx;
  uint32_t vfp_used_registers;
  size_t stack_size;
  size_t stack_padding;
};

static size_t page_size;

jit_bool_t
jit_get_cpu(void)
{
  page_size = sysconf(_SC_PAGE_SIZE);
  // FIXME check version, extensions, hardware fp support
  //
  // List of macro definitions for riscv support:
  // -------------------------------------------
  // __riscv: defined for any RISC-V target. Older versions of the GCC
  // toolchain defined __riscv__.
  //
  // __riscv_xlen: 32 for RV32 and 64 for RV64.
  //
  // __riscv_float_abi_soft, __riscv_float_abi_single,
  // __riscv_float_abi_double: one of these three will be defined, depending on
  // target ABI.
  //
  // __riscv_cmodel_medlow, __riscv_cmodel_medany: one of these two will be
  // defined, depending on the target code model.
  //
  // __riscv_mul: defined when targeting the 'M' ISA extension.
  //
  // __riscv_muldiv: defined when targeting the 'M' ISA extension and -mno-div
  // has not been used.
  //
  // __riscv_div: defined when targeting the 'M' ISA extension and -mno-div has
  // not been used.
  //
  // __riscv_atomic: defined when targeting the 'A' ISA extension.
  //
  // __riscv_flen: 32 when targeting the 'F' ISA extension (but not 'D') and 64
  // when targeting 'FD'.
  //
  // __riscv_fdiv: defined when targeting the 'F' or 'D' ISA extensions and
  // -mno-fdiv has not been used.
  //
  // __riscv_fsqrt: defined when targeting the 'F' or 'D' ISA extensions and
  // -mno-fdiv has not been used.
  //
  // __riscv_compressed: defined when targeting the 'C' ISA extension.
  return 1;
}

jit_bool_t
jit_init(jit_state_t *_jit)
{
  return 1;
}

static size_t
jit_initial_frame_size (void)
{
  return 0;
}

static void
reset_abi_arg_iterator(struct abi_arg_iterator *iter, size_t argc,
                       const jit_operand_t *args)
{
  memset(iter, 0, sizeof *iter);
  iter->argc = argc;
  iter->args = args;
}

static void
next_abi_arg(struct abi_arg_iterator *iter, jit_operand_t *arg)
{
  ASSERT(iter->arg_idx < iter->argc);
  enum jit_operand_abi abi = iter->args[iter->arg_idx].abi;
  iter->arg_idx++;
  if (is_gpr_arg(abi) && iter->gpr_idx < abi_gpr_arg_count) {
    *arg = jit_operand_gpr (abi, abi_gpr_args[iter->gpr_idx++]);
    return;
  }
  if (is_fpr_arg(abi) && iter->fpr_idx < abi_fpr_arg_count) {
    *arg = jit_operand_fpr (abi, abi_fpr_args[iter->fpr_idx++]);
    return;
  }
  *arg = jit_operand_mem (abi, JIT_SP, iter->stack_size);
#if __WORDSIZE == 32
  iter->stack_size += 4;
#elif __WORDSIZE == 64
  iter->stack_size += 8;
#endif
}

static void
jit_flush(void *fptr, void *tptr)
{
  jit_word_t f = (jit_word_t)fptr & -page_size;
  jit_word_t t = (((jit_word_t)tptr) + page_size - 1) & -page_size;
  __clear_cache((void *)f, (void *)t);
}

static inline size_t
jit_stack_alignment(void)
{
  return 8;
  // NOTE: See: https://github.com/riscv/riscv-gcc/issues/61
}

static void
jit_try_shorten(jit_state_t *_jit, jit_reloc_t reloc, jit_pointer_t addr)
{
}

static void*
bless_function_pointer(void *ptr)
{
  return ptr;
}


/*
 * Veneers
 */
struct veneer{
  instr_t auipc;
  instr_t load;        // `ld` in RV64 and `lw` in RV32
  instr_t jalr;
#if __WORDSIZE == 64
  uint64_t address;
#elif __WORDSIZE == 32
  uint32_t address;
#endif
};

static void
emit_veneer(jit_state_t *_jit, jit_pointer_t target)
{
  // We need to generate something like this (RV64):
  // ----------------------------------------------
  // auipc t0, 0
  // ld t0, 12(t0)
  // jalr zero, 0(t0)
  // ADDRESS_LITERAL
  jit_gpr_t t0 = get_temp_gpr(_jit);
  emit_u32(_jit, _AUIPC(jit_gpr_regno(t0), 0));
#if __WORDSIZE == 64
  emit_u32(_jit, _LD(jit_gpr_regno(t0), jit_gpr_regno(t0), 12));
#elif __WORDSIZE == 32
  emit_u32(_jit, _LW(jit_gpr_regno(t0), jit_gpr_regno(t0), 12));
#endif
  emit_u32(_jit, _JALR(jit_gpr_regno(_ZERO), jit_gpr_regno(t0), 0));
#if __WORDSIZE == 64
  emit_u64(_jit, (uint64_t) target);
#elif __WORDSIZE == 32
  emit_u32(_jit, (uint32_t) target);
#endif
  unget_temp_gpr(_jit);
}

static void
patch_veneer(uint32_t *loc, jit_pointer_t addr)
{
  struct veneer *v = (struct veneer*) loc;
#if __WORDSIZE == 64
  v->address = (uint64_t) addr;
#elif __WORDSIZE == 32
  v->address = (uint32_t) addr;
#endif
}


/*
 * Conditional jumps
 */
static void
patch_jcc_offset(uint32_t *loc, ptrdiff_t v)
{

  instr_t *i =  (instr_t *) loc;
  i->B.imm11   = (v >> 11) & 0x1;
  i->B.imm4_1  = (v >>  1) & 0xf;
  i->B.imm10_5 = (v >>  5) & 0x3f;
  i->B.imm12   = (v >> 12) & 0x1;
}
static void
patch_veneer_jcc_offset(uint32_t *loc, ptrdiff_t offset){
  patch_jcc_offset(loc, offset);
}

static int32_t
read_jcc_offset(uint32_t *loc)
{
  instr_t i;
  i.w = *loc;

  int32_t offset = i.B.imm12 << 31;
  offset >>= 20;
  offset |= (i.B.imm11   << 11);
  offset |= (i.B.imm10_5 <<  5);
  offset |= (i.B.imm4_1  <<  1);

  return offset;
}
static int
offset_in_jcc_range(ptrdiff_t offset, int flags)
{
  if(offset & 1)
    return 0;
  else
    return -0x1000 <= offset && offset <= 0xFFF;
}

/*
 * Unconditional jumps
 */
static int32_t read_jmp_offset(uint32_t *loc)
{
  instr_t i;
  i.w = *loc;

  int32_t offset = i.J.imm20 << 31;
  offset >>= 12;
  offset |= (i.J.imm19_12 << 12);
  offset |= (i.J.imm11    << 11);
  offset |= (i.J.imm10_1  <<  1);
  return offset;
}
static int
offset_in_jmp_range(ptrdiff_t offset, int flags)
{
  if(offset & 1)
    return 0;
  else
    return -0x100000 <= offset && offset <= 0xFFFFF;
}

static void
patch_jmp_offset(uint32_t *loc, ptrdiff_t v)
{
  instr_t *i =  (instr_t *) loc;
  i->J.imm20   = (v >> 20) &   0x1;
  i->J.imm19_12= (v >> 12) &  0xff;
  i->J.imm11   = (v >> 11) &   0x1;
  i->J.imm10_1 = (v >>  1) & 0x3ff;
}

static void
patch_veneer_jmp_offset(uint32_t *loc, ptrdiff_t offset)
{
  patch_jmp_offset(loc, offset);
}


/*
 * Jumps around the veneer
 */
static void
patch_jmp_without_veneer(jit_state_t *_jit, uint32_t *loc)
{
  patch_jmp_offset(loc, _jit->pc.ui - loc);
}
static uint32_t*
jmp_without_veneer(jit_state_t *_jit)
{
  uint32_t *loc = _jit->pc.ui;
  emit_u32(_jit, _JAL(jit_gpr_regno(_ZERO), 0));
  return loc;
}


/*
 * Load from pool offset
 */
static void
patch_load_from_pool_offset(uint32_t *loc, int32_t v)
{
  load_from_pool_t *i = (load_from_pool_t *) loc;
  int32_t hi20 = v >>12;
  i->inst.auipc.U.imm31_12 = hi20;
  i->inst.load.I.imm11_0   = v - (hi20<<12);
}
static int32_t
read_load_from_pool_offset(uint32_t *loc)
{
  load_from_pool_t *i =  (load_from_pool_t*) loc;
  return i->inst.auipc.U.imm31_12 + i->inst.load.I.imm11_0;
}

