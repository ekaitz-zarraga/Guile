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
 *	Ekaitz Zarraga <ekaitz@elenq.tech>
 */

#ifndef _jit_riscv_h
#define _jit_riscv_h

#define JIT_NEEDS_LITERAL_POOL 1

// x registers
// Special registers
#define _RA     JIT_GPR(1)      // Return address
#define _SP     JIT_GPR(2)      // Stack pointer
#define _GP     JIT_GPR(3)      // Global pointer
#define _TP     JIT_GPR(4)      // Thread pointer
#define _FP     JIT_GPR(8)      // Frame pointer
#define _ZERO   JIT_GPR(0)      // Always zero
// Argument passing
#define _A0     JIT_GPR(10)
#define _A1     JIT_GPR(11)
#define _A2     JIT_GPR(12)
#define _A3     JIT_GPR(13)
#define _A4     JIT_GPR(14)
#define _A5     JIT_GPR(15)
#define _A6     JIT_GPR(16)
#define _A7     JIT_GPR(17)
// Saved registers
#define _S0     _FP             // S0 is the frame pointer normally
#define _S1     JIT_GPR(9)
#define _S2     JIT_GPR(18)
#define _S3     JIT_GPR(19)
#define _S4     JIT_GPR(20)
#define _S5     JIT_GPR(21)
#define _S6     JIT_GPR(22)
#define _S7     JIT_GPR(23)
#define _S8     JIT_GPR(24)
#define _S9     JIT_GPR(25)
#define _S10    JIT_GPR(26)
#define _S11    JIT_GPR(27)
// Temporaries
#define _T0     JIT_GPR(5)
#define _T1     JIT_GPR(6)
#define _T2     JIT_GPR(7)
#define _T3     JIT_GPR(28)
#define _T4     JIT_GPR(29)
#define _T5     JIT_GPR(30)
#define _T6     JIT_GPR(31)

// f registers
// Termporaries
#define _FT0    JIT_FPR(0)
#define _FT1    JIT_FPR(1)
#define _FT2    JIT_FPR(2)
#define _FT3    JIT_FPR(3)
#define _FT4    JIT_FPR(4)
#define _FT5    JIT_FPR(5)
#define _FT6    JIT_FPR(6)
#define _FT7    JIT_FPR(7)
#define _FT8    JIT_FPR(28)
#define _FT9    JIT_FPR(29)
#define _FT10   JIT_FPR(30)
#define _FT11   JIT_FPR(31)
// Saved registers
#define _FS0    JIT_FPR(8)
#define _FS1    JIT_FPR(9)
#define _FS2    JIT_FPR(18)
#define _FS3    JIT_FPR(19)
#define _FS4    JIT_FPR(20)
#define _FS5    JIT_FPR(21)
#define _FS6    JIT_FPR(22)
#define _FS7    JIT_FPR(23)
#define _FS8    JIT_FPR(24)
#define _FS9    JIT_FPR(25)
#define _FS10   JIT_FPR(26)
#define _FS11   JIT_FPR(27)
// Argument passing
#define _FA0    JIT_FPR(10)
#define _FA1    JIT_FPR(11)
#define _FA2    JIT_FPR(12)
#define _FA3    JIT_FPR(13)
#define _FA4    JIT_FPR(14)
#define _FA5    JIT_FPR(15)
#define _FA6    JIT_FPR(16)
#define _FA7    JIT_FPR(17)


// JIT Registers
// ----------------------------------------------------------------------
// Caller-save registers                            JIT_R${NUM}
// Callee-save registers                            JIT_V${NUM}
// Caller-save temporary registers                  JIT_TMP${NUM}
// Caller-save floating point registers             JIT_F${NUM}
// Callee-save floating point registers             JIT_VF${NUM}
// Caller-save floating point temporary registers   JIT_FTMP${NUM}

// Caller-save registers
#define JIT_R0  _A0
#define JIT_R1  _A1
#define JIT_R2  _A2
#define JIT_R3  _A3
#define JIT_R4  _A4
#define JIT_R5  _A5
#define JIT_R6  _A6
#define JIT_R7  _A7

// Use this as a CARRY
#define JIT_CARRY  _T0
#define JIT_TMP0 _T1
#define JIT_TMP1 _T2
#define JIT_TMP2 _T3

#define JIT_TMP3 _T4
// Temporaries
#define JIT_TMP4 _T5
#define JIT_TMP5 _T6

// Callee-save registers
#define JIT_V0  _S1
#define JIT_V1  _S2
#define JIT_V2  _S3
#define JIT_V3  _S4
#define JIT_V4  _S5
#define JIT_V5  _S6
#define JIT_V6  _S7
#define JIT_V7  _S8
#define JIT_V8  _S9
#define JIT_V9  _S10
#define JIT_V10 _S11


// Callee-save floating point registers
#define JIT_VF0  _FS0
#define JIT_VF1  _FS1
#define JIT_VF2  _FS2
#define JIT_VF3  _FS3
#define JIT_VF4  _FS4
#define JIT_VF5  _FS5
#define JIT_VF6  _FS6
#define JIT_VF7  _FS7
#define JIT_VF8  _FS8
#define JIT_VF9  _FS9
#define JIT_VF10 _FS10
#define JIT_VF11 _FS11

// Caller save floating point registers
#define JIT_F0   _FA0
#define JIT_F1   _FA1
#define JIT_F2   _FA2
#define JIT_F3   _FA3
#define JIT_F4   _FA4
#define JIT_F5   _FA5
#define JIT_F6   _FA6
#define JIT_F7   _FA7
// NOTE: These are temporaries, but we can use them as general purpose
// registers as there's only one temporary JIT_FTMP supported by lightening.c
#define JIT_F8   _FT0
#define JIT_F9   _FT1
#define JIT_F10  _FT2
#define JIT_F11  _FT3
#define JIT_F12  _FT4
#define JIT_F13  _FT5
#define JIT_F14  _FT6
#define JIT_F15  _FT7
#define JIT_F16  _FT8
#define JIT_F17  _FT9
#define JIT_F18  _FT10

// Floating point temporary register
#define JIT_FTMP _FT11

// Special purpose registers
#define JIT_FP   _FP
#define JIT_LR   _RA
#define JIT_SP   _SP

// TODO: Make sure this is correct
#define JIT_PLATFORM_CALLEE_SAVE_GPRS JIT_LR

#endif
