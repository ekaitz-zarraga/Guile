/* classes: h_files */

#ifndef SCM_GSUBR_H
#define SCM_GSUBR_H

/* Copyright (C) 1995,1996,1998,2000,2001, 2006, 2008, 2009 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public License
 * as published by the Free Software Foundation; either version 3 of
 * the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
 * 02110-1301 USA
 */



#include "libguile/__scm.h"



/* Return an integer describing the arity of GSUBR, a subr of type
   `scm_tc7_gsubr'.  The result can be interpreted with `SCM_GSUBR_REQ ()'
   and similar.  */
#define SCM_GSUBR_TYPE(gsubr)  (SCM_CELL_TYPE (gsubr) >> 8)

#define SCM_GSUBR_MAKTYPE(req, opt, rst) ((req)|((opt)<<4)|((rst)<<8))
#define SCM_GSUBR_MAX    33
#define SCM_GSUBR_REQ(x) ((long)(x)&0xf)
#define SCM_GSUBR_OPT(x) (((long)(x)&0xf0)>>4)
#define SCM_GSUBR_REST(x) ((long)(x)>>8)

SCM_API SCM scm_c_make_gsubr (const char *name, 
			      int req, int opt, int rst, SCM (*fcn) ());
SCM_API SCM scm_c_make_gsubr_with_generic (const char *name,
					   int req, int opt, int rst,
					   SCM (*fcn) (), SCM *gf);
SCM_API SCM scm_c_define_gsubr (const char *name, 
				int req, int opt, int rst, SCM (*fcn) ());
SCM_API SCM scm_c_define_gsubr_with_generic (const char *name,
					     int req, int opt, int rst,
					     SCM (*fcn) (), SCM *gf);

SCM_INTERNAL SCM scm_i_gsubr_apply (SCM proc, SCM arg, ...);
SCM_INTERNAL SCM scm_i_gsubr_apply_list (SCM proc, SCM args);
SCM_INTERNAL void scm_init_gsubr (void);

#endif  /* SCM_GSUBR_H */

/*
  Local Variables:
  c-file-style: "gnu"
  End:
*/
