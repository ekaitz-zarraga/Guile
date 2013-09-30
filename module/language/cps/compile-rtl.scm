;;; Continuation-passing style (CPS) intermediate language (IL)

;; Copyright (C) 2013 Free Software Foundation, Inc.

;;;; This library is free software; you can redistribute it and/or
;;;; modify it under the terms of the GNU Lesser General Public
;;;; License as published by the Free Software Foundation; either
;;;; version 3 of the License, or (at your option) any later version.
;;;;
;;;; This library is distributed in the hope that it will be useful,
;;;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;;;; Lesser General Public License for more details.
;;;;
;;;; You should have received a copy of the GNU Lesser General Public
;;;; License along with this library; if not, write to the Free Software
;;;; Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA

;;; Commentary:
;;;
;;; Compiling CPS to RTL.  The result is in the RTL language, which
;;; happens to be an ELF image as a bytecode.
;;;
;;; Code:

(define-module (language cps compile-rtl)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-1)
  #:use-module (language cps)
  #:use-module (language cps arities)
  #:use-module (language cps closure-conversion)
  #:use-module (language cps contification)
  #:use-module (language cps dfg)
  #:use-module (language cps primitives)
  #:use-module (language cps reify-primitives)
  #:use-module (language cps slot-allocation)
  #:use-module (system vm assembler)
  #:export (compile-rtl))

;; TODO: Source info, local var names.  Needs work in the linker and the
;; debugger.

(define (kw-arg-ref args kw default)
  (match (memq kw args)
    ((_ val . _) val)
    (_ default)))

(define (optimize exp opts)
  (define (run-pass exp pass kw default)
    (if (kw-arg-ref opts kw default)
        (pass exp)
        exp))

  ;; Calls to source-to-source optimization passes go here.
  (let* ((exp (run-pass exp contify #:contify? #t)))
    ;; Passes that are needed:
    ;; 
    ;;  * Abort contification: turning abort primcalls into continuation
    ;;    calls, and eliding prompts if possible.
    ;;
    ;;  * Common subexpression elimination.  Desperately needed.  Requires
    ;;    effects analysis.
    ;;
    ;;  * Loop peeling.  Unrolls the first round through a loop if the
    ;;    loop has effects that CSE can work on.  Requires effects
    ;;    analysis.  When run before CSE, loop peeling is the equivalent
    ;;    of loop-invariant code motion (LICM).
    ;;
    ;;  * Generic simplification pass, to be run as needed.  Used to
    ;;    "clean up", both on the original raw input and after specific
    ;;    optimization passes.

    exp))

(define (visit-funs proc exp)
  (match exp
    (($ $continue _ exp)
     (visit-funs proc exp))

    (($ $fun meta free body)
     (proc exp)
     (visit-funs proc body))

    (($ $letk conts body)
     (visit-funs proc body)
     (for-each (lambda (cont) (visit-funs proc cont)) conts))

    (($ $cont sym src ($ $kargs names syms body))
     (visit-funs proc body))

    (($ $cont sym src ($ $kclause arity body))
     (visit-funs proc body))

    (($ $cont sym src ($ $kentry self tail clauses))
     (for-each (lambda (clause) (visit-funs proc clause)) clauses))

    (_ (values))))

(define (emit-rtl-sequence asm exp allocation nlocals cont-table)
  (define (slot sym)
    (lookup-slot sym allocation))

  (define (constant sym)
    (lookup-constant-value sym allocation))

  (define (emit-rtl label k exp next-label)
    (define (maybe-mov dst src)
      (unless (= dst src)
        (emit-mov asm dst src)))

    (define (maybe-jump label)
      (unless (eq? label next-label)
        (emit-br asm label)))

    (define (maybe-load-constant slot src)
      (call-with-values (lambda ()
                          (lookup-maybe-constant-value src allocation))
        (lambda (has-const? val)
          (and has-const?
               (begin
                 (emit-load-constant asm slot val)
                 #t)))))

    (define (emit-tail)
      ;; There are only three kinds of expressions in tail position:
      ;; tail calls, multiple-value returns, and single-value returns.
      (match exp
        (($ $call proc args)
         (for-each (match-lambda
                    ((src . dst) (emit-mov asm dst src)))
                   (lookup-parallel-moves label allocation))
         (let ((tail-slots (cdr (iota (1+ (length args))))))
           (for-each maybe-load-constant tail-slots args))
         (emit-tail-call asm (1+ (length args))))
        (($ $values args)
         (let ((tail-slots (cdr (iota (1+ (length args))))))
           (for-each (match-lambda
                      ((src . dst) (emit-mov asm dst src)))
                     (lookup-parallel-moves label allocation))
           (for-each maybe-load-constant tail-slots args))
         (emit-reset-frame asm (1+ (length args)))
         (emit-return-values asm))
        (($ $primcall 'return (arg))
         (emit-return asm (slot arg)))))

    (define (emit-val sym)
      (let ((dst (slot sym)))
        (match exp
          (($ $var sym)
           (maybe-mov dst (slot sym)))
          (($ $void)
           (when dst
             (emit-load-constant asm dst *unspecified*)))
          (($ $const exp)
           (when dst
             (emit-load-constant asm dst exp)))
          (($ $fun meta () ($ $cont k))
           (emit-load-static-procedure asm dst k))
          (($ $fun meta free ($ $cont k))
           (emit-make-closure asm dst k (length free)))
          (($ $call proc args)
           (let ((proc-slot (lookup-call-proc-slot label allocation))
                 (nargs (length args)))
             (or (maybe-load-constant proc-slot proc)
                 (maybe-mov proc-slot (slot proc)))
             (let lp ((n (1+ proc-slot)) (args args))
               (match args
                 (()
                  (emit-call asm proc-slot (+ nargs 1))
                  (emit-receive asm dst proc-slot nlocals))
                 ((arg . args)
                  (or (maybe-load-constant n arg)
                      (maybe-mov n (slot arg)))
                  (lp (1+ n) args))))))
          (($ $primcall 'current-module)
           (emit-current-module asm dst))
          (($ $primcall 'cached-toplevel-box (scope name bound?))
           (emit-cached-toplevel-box asm dst (constant scope) (constant name)
                                     (constant bound?)))
          (($ $primcall 'cached-module-box (mod name public? bound?))
           (emit-cached-module-box asm dst (constant mod) (constant name)
                                   (constant public?) (constant bound?)))
          (($ $primcall 'resolve (name bound?))
           (emit-resolve asm dst (constant bound?) (slot name)))
          (($ $primcall 'free-ref (closure idx))
           (emit-free-ref asm dst (slot closure) (constant idx)))
          (($ $primcall name args)
           ;; FIXME: Inline all the cases.
           (let ((inst (prim-rtl-instruction name)))
             (emit-text asm `((,inst ,dst ,@(map slot args))))))
          (($ $values (arg))
           (or (maybe-load-constant dst arg)
               (maybe-mov dst (slot arg))))
          (($ $prompt escape? tag handler)
           (emit-prompt asm escape? tag handler)))
        (maybe-jump k)))

    (define (emit-vals syms)
      (match exp
        (($ $primcall name args)
         (error "unimplemented primcall in values context" name))
        (($ $values args)
         (for-each (match-lambda
                    ((src . dst) (emit-mov asm dst src)))
                   (lookup-parallel-moves label allocation))
         (for-each maybe-load-constant (map slot syms) args)))
      (maybe-jump k))

    (define (emit-seq)
      (match exp
        (($ $primcall 'cache-current-module! (sym scope))
         (emit-cache-current-module! asm (slot sym) (constant scope)))
        (($ $primcall 'free-set! (closure idx value))
         (emit-free-set! asm (slot closure) (slot value) (constant idx)))
        (($ $primcall 'box-set! (box value))
         (emit-box-set! asm (slot box) (slot value)))
        (($ $primcall 'struct-set! (struct index value))
         (emit-struct-set! asm (slot struct) (slot index) (slot value)))
        (($ $primcall 'vector-set! (vector index value))
         (emit-vector-set asm (slot vector) (slot index) (slot value)))
        (($ $primcall 'set-car! (pair value))
         (emit-set-car! asm (slot pair) (slot value)))
        (($ $primcall 'set-cdr! (pair value))
         (emit-set-cdr! asm (slot pair) (slot value)))
        (($ $primcall 'define! (sym value))
         (emit-define asm (slot sym) (slot value)))
        (($ $primcall name args)
         (error "unhandled primcall in seq context" name))
        (($ $values ()) #f))
      (maybe-jump k))

    (define (emit-test kt kf)
      (define (unary op sym)
        (cond
         ((eq? kt next-label)
          (op asm (slot sym) #t kf))
         (else
          (op asm (slot sym) #f kt)
          (maybe-jump kf))))
      (define (binary op a b)
        (cond
         ((eq? kt next-label)
          (op asm (slot a) (slot b) #t kf))
         (else
          (op asm (slot a) (slot b) #f kt)
          (maybe-jump kf))))
      (match exp
        (($ $var sym) (unary emit-br-if-true sym))
        (($ $primcall 'null? (a)) (unary emit-br-if-null a))
        (($ $primcall 'nil? (a)) (unary emit-br-if-nil a))
        (($ $primcall 'pair? (a)) (unary emit-br-if-pair a))
        (($ $primcall 'struct? (a)) (unary emit-br-if-struct a))
        (($ $primcall 'char? (a)) (unary emit-br-if-char a))
        ;; Add TC7 tests here
        (($ $primcall 'eq? (a b)) (binary emit-br-if-eq a b))
        (($ $primcall 'eq? (a b)) (binary emit-br-if-eq a b))
        (($ $primcall 'eqv? (a b)) (binary emit-br-if-eqv a b))
        (($ $primcall 'equal? (a b)) (binary emit-br-if-equal a b))
        (($ $primcall '< (a b)) (binary emit-br-if-< a b))
        (($ $primcall '<= (a b)) (binary emit-br-if-<= a b))
        (($ $primcall '= (a b)) (binary emit-br-if-= a b))
        (($ $primcall '>= (a b)) (binary emit-br-if-<= b a))
        (($ $primcall '> (a b)) (binary emit-br-if-< b a))))

    (define (emit-trunc nreq rest? k)
      (match exp
        (($ $call proc args)
         (let ((proc-slot (lookup-call-proc-slot label allocation))
               (nargs (length args)))
           (or (maybe-load-constant proc-slot proc)
               (maybe-mov proc-slot (slot proc)))
           (let lp ((n (1+ proc-slot)) (args args))
             (match args
               (()
                (emit-call asm proc-slot (+ nargs 1))
                (emit-receive-values asm proc-slot nreq)
                (when rest?
                  (emit-bind-rest asm (+ proc-slot 1 nreq)))
                (for-each (match-lambda
                           ((src . dst) (emit-mov asm dst src)))
                          (lookup-parallel-moves label allocation))
                (emit-reset-frame asm nlocals))
               ((arg . args)
                (or (maybe-load-constant n arg)
                    (maybe-mov n (slot arg)))
                (lp (1+ n) args)))))))
      (maybe-jump k))

    (match (lookup-cont k cont-table)
      (($ $ktail) (emit-tail))
      (($ $kargs (name) (sym)) (emit-val sym))
      (($ $kargs () ()) (emit-seq))
      (($ $kargs names syms) (emit-vals syms))
      (($ $kargs (name) (sym)) (emit-val sym))
      (($ $kif kt kf) (emit-test kt kf))
      (($ $ktrunc ($ $arity req () rest () #f) k)
       (emit-trunc (length req) (and rest #t) k))))

  (define (collect-exps k src cont tail)
    (define (find-exp k src term)
      (match term
        (($ $continue exp-k exp)
         (cons (list k src exp-k exp) tail))
        (($ $letk conts body)
         (find-exp k src body))))
    (match cont
      (($ $kargs names syms body)
       (find-exp k src body))
      (_ tail)))

  (let lp ((exps (reverse (fold-local-conts collect-exps '() exp))))
    (match exps
      (() #t)
      (((k src exp-k exp) . exps)
       (let ((next-label (match exps
                           (((k . _) . _) k)
                           (() #f))))
         (emit-label asm k)
         (when src
           (emit-source asm src))
         (emit-rtl k exp-k exp next-label)
         (lp exps))))))

(define (compile-fun f asm)
  (let ((allocation (allocate-slots f))
        (cont-table (match f
                      (($ $fun meta free body)
                       (build-local-cont-table body)))))
    (define (emit-fun-clause clause alternate)
      (match clause
        (($ $cont k src
            ($ $kclause ($ $arity req opt rest kw allow-other-keys?)
               body))
         (let ((kw-indices (map (match-lambda
                                 ((key name sym)
                                  (cons key (lookup-slot sym allocation))))
                                kw))
               (nlocals (lookup-nlocals k allocation)))
           (emit-label asm k)
           (when src
             (emit-source asm src))
           (emit-begin-kw-arity asm req opt rest kw-indices allow-other-keys?
                                nlocals alternate)
           (emit-rtl-sequence asm body allocation nlocals cont-table)
           (emit-end-arity asm)))))

    (define (emit-fun-clauses clauses)
      (match clauses
        ((clause . clauses)
         (let ((kalternate (match clauses
                             (() #f)
                             ((($ $cont k) . _) k))))
           (emit-fun-clause clause kalternate)
           (when kalternate
             (emit-fun-clauses clauses))))))

    (match f
      (($ $fun meta free ($ $cont k src ($ $kentry self tail clauses)))
       (emit-begin-program asm k (or meta '()))
       (when src
         (emit-source asm src))
       (emit-fun-clauses clauses)
       (emit-end-program asm)))))

(define (compile-rtl exp env opts)
  (let* ((exp (fix-arities exp))
         (exp (optimize exp opts))
         (exp (convert-closures exp))
         (exp (reify-primitives exp))
         (asm (make-assembler)))
    (visit-funs (lambda (fun)
                  (compile-fun fun asm))
                exp)
    (values (link-assembly asm #:page-aligned? (kw-arg-ref opts #:to-file? #f))
            env
            env)))
