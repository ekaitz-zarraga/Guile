;;; Functional name maps
;;; Copyright (C) 2014, 2015 Free Software Foundation, Inc.
;;;
;;; This library is free software: you can redistribute it and/or modify
;;; it under the terms of the GNU Lesser General Public License as
;;; published by the Free Software Foundation, either version 3 of the
;;; License, or (at your option) any later version.
;;; 
;;; This library is distributed in the hope that it will be useful, but
;;; WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;;; Lesser General Public License for more details.
;;; 
;;; You should have received a copy of the GNU Lesser General Public
;;; License along with this program.  If not, see
;;; <http://www.gnu.org/licenses/>.

;;; Commentary:
;;;
;;; Some CPS passes need to perform a flow analysis in which every
;;; program point has an associated map over some set of labels or
;;; variables.  The naive way to implement this is with an array of
;;; arrays, but this has N^2 complexity, and it really can hurt us.
;;;
;;; Instead, this module provides a functional map that can share space
;;; between program points, reducing the amortized space complexity of
;;; the representations down to O(n log n).  Adding entries to the
;;; mapping and lookup are O(log n).  Intersection and union between
;;; intmaps that share state are fast, too. 
;;;
;;; Code:

(define-module (language cps intmap)
  #:use-module (srfi srfi-9)
  #:use-module (srfi srfi-9 gnu)
  #:use-module (srfi srfi-18)
  #:use-module (ice-9 match)
  #:export (empty-intmap
            intmap?
            transient-intmap?
            persistent-intmap
            transient-intmap
            intmap-add
            intmap-add!
            intmap-remove
            intmap-ref
            intmap-next
            intmap-prev
            intmap-fold
            intmap-union
            intmap-intersect))

;; Persistent sparse intmaps.

(define-syntax-rule (define-inline name val)
  (define-syntax name (identifier-syntax val)))

;; FIXME: This should make an actual atomic reference.
(define-inlinable (make-atomic-reference value)
  (list value))
(define-inlinable (get-atomic-reference reference)
  (car reference))
(define-inlinable (set-atomic-reference! reference value)
  (set-car! reference value))

(define-inline *branch-bits* 5)
(define-inline *branch-size* (ash 1 *branch-bits*))
(define-inline *branch-size-with-edit* (1+ *branch-size*))
(define-inline *edit-index* *branch-size*)
(define-inline *branch-mask* (1- *branch-size*))

(define-record-type <intmap>
  (make-intmap min shift root)
  intmap?
  (min intmap-min)
  (shift intmap-shift)
  (root intmap-root))

(define-record-type <transient-intmap>
  (make-transient-intmap min shift root edit)
  transient-intmap?
  (min transient-intmap-min set-transient-intmap-min!)
  (shift transient-intmap-shift set-transient-intmap-shift!)
  (root transient-intmap-root set-transient-intmap-root!)
  (edit transient-intmap-edit set-transient-intmap-edit!))

(define *absent* (list 'absent))
(define-inlinable (absent? x)
  (eq? x *absent*))
(define-inlinable (present? x)
  (not (absent? x)))

(define-inlinable (new-branch edit)
  (let ((vec (make-vector *branch-size-with-edit* *absent*)))
    (vector-set! vec *edit-index* edit)
    vec))
(define-inlinable (clone-branch-with-edit branch edit)
  (let ((new (vector-copy branch)))
    (vector-set! new *edit-index* edit)
    new))
(define (clone-branch-and-set branch i elt)
  (let ((new (clone-branch-with-edit branch #f)))
    (vector-set! new i elt)
    new))
(define-inlinable (assert-readable! root-edit)
  (unless (eq? (get-atomic-reference root-edit) (current-thread))
    (error "Transient intmap owned by another thread" root-edit)))
(define-inlinable (writable-branch branch root-edit)
  (let ((edit (vector-ref branch *edit-index*)))
    (if (eq? root-edit edit)
        branch
        (clone-branch-with-edit branch root-edit))))
(define (branch-empty? branch)
  (let lp ((i 0))
    (or (= i *branch-size*)
        (and (absent? (vector-ref branch i))
             (lp (1+ i))))))

(define-inlinable (round-down min shift)
  (logand min (lognot (1- (ash 1 shift)))))

(define empty-intmap (make-intmap 0 0 *absent*))

(define (add-level min shift root)
  (let* ((shift* (+ shift *branch-bits*))
         (min* (round-down min shift*))
         (idx (logand (ash (- min min*) (- shift))
                      *branch-mask*))
         (root* (new-branch #f)))
    (vector-set! root* idx root)
    (make-intmap min* shift* root*)))

(define (make-intmap/prune min shift root)
  (if (zero? shift)
      (make-intmap min shift root)
      (let lp ((i 0) (elt #f))
        (cond
         ((< i *branch-size*)
          (if (present? (vector-ref root i))
              (if elt
                  (make-intmap min shift root)
                  (lp (1+ i) i))
              (lp (1+ i) elt)))
         (elt
          (let ((shift (- shift *branch-bits*)))
            (make-intmap/prune (+ min (ash elt shift))
                               shift
                               (vector-ref root elt))))
         ;; Shouldn't be reached...
         (else empty-intmap)))))

(define (meet-error old new)
  (error "Multiple differing values and no meet procedure defined" old new))

(define* (transient-intmap #:optional (source empty-intmap))
  (match source
    (($ <transient-intmap> min shift root edit)
     (assert-readable! edit)
     source)
    (($ <intmap> min shift root)
     (let ((edit (make-atomic-reference (current-thread))))
       (make-transient-intmap min shift root edit)))))

(define* (persistent-intmap #:optional (source empty-intmap))
  (match source
    (($ <transient-intmap> min shift root edit)
     (assert-readable! edit)
     ;; Make a fresh reference, causing any further operations on this
     ;; transient to clone its root afresh.
     (set-transient-intmap-edit! source
                                 (make-atomic-reference (current-thread)))
     ;; Clear the reference to the current thread, causing our edited
     ;; data structures to be persistent again.
     (set-atomic-reference! edit #f)
     (if min
         (make-intmap min shift root)
         empty-intmap))
    (($ <intmap>)
     source)))

(define* (intmap-add! map i val #:optional (meet meet-error))
  (define (ensure-branch! root idx)
    (let ((edit (vector-ref root *edit-index*))
          (v (vector-ref root idx)))
      (if (absent? v)
          (let ((v (new-branch edit)))
            (vector-set! root idx v)
            v)
          (let ((v* (writable-branch v edit)))
            (unless (eq? v v*)
              (vector-set! root idx v*))
            v*))))
  (define (adjoin! i shift root)
    (let* ((shift (- shift *branch-bits*))
           (idx (logand (ash i (- shift)) *branch-mask*)))
      (if (zero? shift)
          (let ((node (vector-ref root idx)))
            (unless (eq? node val)
              (vector-set! root idx (if (present? node) (meet node val) val))))
          (adjoin! i shift (ensure-branch! root idx)))))
  (match map
    (($ <transient-intmap> min shift root edit)
     (assert-readable! edit)
     (cond
      ((< i 0)
       ;; The power-of-two spanning trick doesn't work across 0.
       (error "Intmaps can only map non-negative integers." i))
      ((absent? root)
       (set-transient-intmap-min! map i)
       (set-transient-intmap-shift! map 0)
       (set-transient-intmap-root! map val))
      ((and (<= min i) (< i (+ min (ash 1 shift))))
       ;; Add element to map; level will not change.
       (if (zero? shift)
           (unless (eq? root val)
             (set-transient-intmap-root! map (meet root val)))
           (let ((root* (writable-branch root edit)))
             (unless (eq? root root*)
               (set-transient-intmap-root! map root*))
             (adjoin! (- i min) shift root*))))
      (else
       (let lp ((min min)
                (shift shift)
                (root root))
         (let* ((shift* (+ shift *branch-bits*))
                (min* (round-down min shift*))
                (idx (logand (ash (- min min*) (- shift))
                             *branch-mask*))
                (root* (new-branch edit)))
           (vector-set! root* idx root)
           (cond
            ((and (<= min* i) (< i (+ min* (ash 1 shift*))))
             (set-transient-intmap-min! map min*)
             (set-transient-intmap-shift! map shift*)
             (set-transient-intmap-root! map root*)
             (adjoin! (- i min*) shift* root*))
            (else
             (lp min* shift* root*)))))))
     map)
    (($ <intmap>)
     (intmap-add! (transient-intmap map) i val meet))))

(define* (intmap-add map i val #:optional (meet meet-error))
  (define (adjoin i shift root)
    (if (zero? shift)
        (cond
         ((eq? root val) root)
         ((absent? root) val)
         (else (meet root val)))
        (let* ((shift (- shift *branch-bits*))
               (idx (logand (ash i (- shift)) *branch-mask*)))
          (if (absent? root)
              (let ((root* (new-branch #f))
                    (node* (adjoin i shift root)))
                (vector-set! root* idx node*)
                root*)
              (let* ((node (vector-ref root idx))
                     (node* (adjoin i shift node)))
                (if (eq? node node*)
                    root
                    (clone-branch-and-set root idx node*)))))))
  (match map
    (($ <intmap> min shift root)
     (cond
      ((< i 0)
       ;; The power-of-two spanning trick doesn't work across 0.
       (error "Intmaps can only map non-negative integers." i))
      ((absent? root)
       ;; Add first element.
       (make-intmap i 0 val))
      ((and (<= min i) (< i (+ min (ash 1 shift))))
       ;; Add element to map; level will not change.
       (let ((old-root root)
             (root (adjoin (- i min) shift root)))
         (if (eq? root old-root)
             map
             (make-intmap min shift root))))
      ((< i min)
       ;; Rebuild the tree by unioning two intmaps.
       (intmap-union (intmap-add empty-intmap i val error) map error))
      (else
       ;; Add a new level and try again.
       (intmap-add (add-level min shift root) i val error))))
    (($ <transient-intmap>)
     (intmap-add (persistent-intmap map) i val meet))))

(define (intmap-remove map i)
  (define (remove i shift root)
    (cond
     ((zero? shift) *absent*)
     (else
      (let* ((shift (- shift *branch-bits*))
             (idx (logand (ash i (- shift)) *branch-mask*))
             (node (vector-ref root idx)))
        (if (absent? node)
            root
            (let ((node* (remove i shift node)))
              (if (eq? node node*)
                  root
                  (clone-branch-and-set root idx node*))))))))
  (match map
    (($ <intmap> min shift root)
     (cond
      ((absent? root) map)
      ((and (<= min i) (< i (+ min (ash 1 shift))))
       ;; Add element to map; level will not change.
       (let ((root* (remove (- i min) shift root)))
         (if (eq? root root*)
             map
             (make-intmap/prune min shift root*))))
      (else map)))
    (($ <transient-intmap>)
     (intmap-remove (persistent-intmap map) i))))

(define* (intmap-ref map i #:optional (not-found (lambda (i)
                                                   (error "not found" i))))
  (define (ref min shift root)
    (if (zero? shift)
        (if (and min (= i min) (present? root))
            root
            (not-found i))
        (if (and (<= min i) (< i (+ min (ash 1 shift))))
            (let ((i (- i min)))
              (let lp ((node root) (shift shift))
                (if (present? node)
                    (if (= shift *branch-bits*)
                        (let ((node (vector-ref node (logand i *branch-mask*))))
                          (if (present? node)
                              node
                              (not-found i)))
                        (let* ((shift (- shift *branch-bits*))
                               (idx (logand (ash i (- shift))
                                            *branch-mask*)))
                          (lp (vector-ref node idx) shift)))
                    (not-found i))))
            (not-found i))))
  (match map
    (($ <intmap> min shift root)
     (ref min shift root))
    (($ <transient-intmap> min shift root edit)
     (assert-readable! edit)
     (ref min shift root))))

(define* (intmap-next map #:optional i)
  (define (visit-branch node shift i)
    (let lp ((i i) (idx (logand (ash i (- shift)) *branch-mask*)))
      (and (< idx *branch-size*)
           (or (visit-node (vector-ref node idx) shift i)
               (let ((inc (ash 1 shift)))
                 (lp (+ (round-down i shift) inc) (1+ idx)))))))
  (define (visit-node node shift i)
    (and (present? node)
         (if (zero? shift)
             i
             (visit-branch node (- shift *branch-bits*) i))))
  (define (next min shift root)
    (let ((i (if (and i (< min i))
                 (- i min)
                 0)))
      (and (< i (ash 1 shift))
           (let ((i (visit-node root shift i)))
             (and i (+ min i))))))
  (match map
    (($ <intmap> min shift root)
     (next min shift root))
    (($ <transient-intmap> min shift root edit)
     (assert-readable! edit)
     (next min shift root))))

(define* (intmap-prev map #:optional i)
  (define (visit-branch node shift i)
    (let lp ((i i) (idx (logand (ash i (- shift)) *branch-mask*)))
      (and (<= 0 idx)
           (or (visit-node (vector-ref node idx) shift i)
               (lp (1- (round-down i shift)) (1- idx))))))
  (define (visit-node node shift i)
    (and (present? node)
         (if (zero? shift)
             i
             (visit-branch node (- shift *branch-bits*) i))))
  (define (prev min shift root)
    (let* ((i (if (and i (< i (+ min (ash 1 shift))))
                  (- i min)
                  (1- (ash 1 shift)))))
      (and (<= 0 i)
           (let ((i (visit-node root shift i)))
             (and i (+ min i))))))
  (match map
    (($ <intmap> min shift root)
     (prev min shift root))
    (($ <transient-intmap> min shift root edit)
     (assert-readable! edit)
     (prev min shift root))))

(define (intmap-fold f map seed)
  (define (visit-branch node shift min seed)
    (let ((shift (- shift *branch-bits*)))
      (if (zero? shift)
          (let lp ((i 0) (seed seed))
            (if (< i *branch-size*)
                (let ((elt (vector-ref node i)))
                  (lp (1+ i)
                      (if (present? elt)
                          (f (+ i min) elt seed)
                          seed)))
                seed))
          (let lp ((i 0) (seed seed))
            (if (< i *branch-size*)
                (let ((elt (vector-ref node i)))
                  (lp (1+ i)
                      (if (present? elt)
                          (visit-branch elt shift (+ min (ash i shift)) seed)
                          seed)))
                seed)))))
  (match map
    (($ <intmap> min shift root)
     (cond
      ((absent? root) seed)
      ((zero? shift) (f min root seed))
      (else (visit-branch root shift min seed))))
    (($ <transient-intmap>)
     (intmap-fold f (persistent-intmap map) seed))))

(define* (intmap-union a b #:optional (meet meet-error))
  ;; Union A and B from index I; the result will be fresh.
  (define (union-branches/fresh shift a b i fresh)
    (let lp ((i 0))
      (cond
       ((< i *branch-size*)
        (let* ((a-child (vector-ref a i))
               (b-child (vector-ref b i)))
          (vector-set! fresh i (union shift a-child b-child))
          (lp (1+ i))))
       (else fresh))))
  ;; Union A and B from index I; the result may be eq? to A.
  (define (union-branches/a shift a b i)
    (let lp ((i i))
      (cond
       ((< i *branch-size*)
        (let* ((a-child (vector-ref a i))
               (b-child (vector-ref b i)))
          (if (eq? a-child b-child)
              (lp (1+ i))
              (let ((child (union shift a-child b-child)))
                (cond
                 ((eq? a-child child)
                  (lp (1+ i)))
                 (else
                  (let ((result (clone-branch-and-set a i child)))
                    (union-branches/fresh shift a b (1+ i) result))))))))
       (else a))))
  ;; Union A and B; the may could be eq? to either.
  (define (union-branches shift a b)
    (let lp ((i 0))
      (cond
       ((< i *branch-size*)
        (let* ((a-child (vector-ref a i))
               (b-child (vector-ref b i)))
          (if (eq? a-child b-child)
              (lp (1+ i))
              (let ((child (union shift a-child b-child)))
                (cond
                 ((eq? a-child child)
                  (union-branches/a shift a b (1+ i)))
                 ((eq? b-child child)
                  (union-branches/a shift b a (1+ i)))
                 (else
                  (let ((result (clone-branch-and-set a i child)))
                    (union-branches/fresh shift a b (1+ i) result))))))))
       ;; Seems they are the same but not eq?.  Odd.
       (else a))))
  (define (union shift a-node b-node)
    (cond
     ((absent? a-node) b-node)
     ((absent? b-node) a-node)
     ((eq? a-node b-node) a-node)
     ((zero? shift) (meet a-node b-node))
     (else (union-branches (- shift *branch-bits*) a-node b-node))))
  (match (cons a b)
    ((($ <intmap> a-min a-shift a-root) . ($ <intmap> b-min b-shift b-root))
     (cond
      ((not (= b-shift a-shift))
       ;; Hoist the map with the lowest shift to meet the one with the
       ;; higher shift.
       (if (< b-shift a-shift)
           (intmap-union a (add-level b-min b-shift b-root) meet)
           (intmap-union (add-level a-min a-shift a-root) b meet)))
      ((not (= b-min a-min))
       ;; Nodes at the same shift but different minimums will cover
       ;; disjoint ranges (due to the round-down call on min).  Hoist
       ;; both until they cover the same range.
       (intmap-union (add-level a-min a-shift a-root)
                     (add-level b-min b-shift b-root)
                     meet))
      (else
       ;; At this point, A and B cover the same range.
       (let ((root (union a-shift a-root b-root)))
         (cond
          ((eq? root a-root) a)
          ((eq? root b-root) b)
          (else (make-intmap a-min a-shift root)))))))))

(define* (intmap-intersect a b #:optional (meet meet-error))
  ;; Intersect A and B from index I; the result will be fresh.
  (define (intersect-branches/fresh shift a b i fresh)
    (let lp ((i 0))
      (cond
       ((< i *branch-size*)
        (let* ((a-child (vector-ref a i))
               (b-child (vector-ref b i)))
          (vector-set! fresh i (intersect shift a-child b-child))
          (lp (1+ i))))
       ((branch-empty? fresh) *absent*)
       (else fresh))))
  ;; Intersect A and B from index I; the result may be eq? to A.
  (define (intersect-branches/a shift a b i)
    (let lp ((i i))
      (cond
       ((< i *branch-size*)
        (let* ((a-child (vector-ref a i))
               (b-child (vector-ref b i)))
          (if (eq? a-child b-child)
              (lp (1+ i))
              (let ((child (intersect shift a-child b-child)))
                (cond
                 ((eq? a-child child)
                  (lp (1+ i)))
                 (else
                  (let ((result (clone-branch-and-set a i child)))
                    (intersect-branches/fresh shift a b (1+ i) result))))))))
       (else a))))
  ;; Intersect A and B; the may could be eq? to either.
  (define (intersect-branches shift a b)
    (let lp ((i 0))
      (cond
       ((< i *branch-size*)
        (let* ((a-child (vector-ref a i))
               (b-child (vector-ref b i)))
          (if (eq? a-child b-child)
              (lp (1+ i))
              (let ((child (intersect shift a-child b-child)))
                (cond
                 ((eq? a-child child)
                  (intersect-branches/a shift a b (1+ i)))
                 ((eq? b-child child)
                  (intersect-branches/a shift b a (1+ i)))
                 (else
                  (let ((result (clone-branch-and-set a i child)))
                    (intersect-branches/fresh shift a b (1+ i) result))))))))
       ;; Seems they are the same but not eq?.  Odd.
       (else a))))
  (define (intersect shift a-node b-node)
    (cond
     ((or (absent? a-node) (absent? b-node)) *absent*)
     ((eq? a-node b-node) a-node)
     ((zero? shift) (meet a-node b-node))
     (else (intersect-branches (- shift *branch-bits*) a-node b-node))))

  (define (different-mins lo-min lo-shift lo-root hi-min hi-shift hi lo-is-a?)
    (cond
     ((<= lo-shift hi-shift)
      ;; If LO has a lower shift and a lower min, it is disjoint.  If
      ;; it has the same shift and a different min, it is also
      ;; disjoint.
      empty-intmap)
     (else
      (let* ((lo-shift (- lo-shift *branch-bits*))
             (lo-idx (ash (- hi-min lo-min) (- lo-shift))))
        (if (>= lo-idx *branch-size*)
            ;; HI has a lower shift, but it not within LO.
            empty-intmap
            (let ((lo-root (vector-ref lo-root lo-idx)))
              (if (absent? lo-root)
                  empty-intmap
                  (let ((lo (make-intmap (+ lo-min (ash lo-idx lo-shift))
                                         lo-shift
                                         lo-root)))
                    (if lo-is-a?
                        (intmap-intersect lo hi meet)
                        (intmap-intersect hi lo meet))))))))))

  (define (different-shifts-same-min min hi-shift hi-root lo lo-is-a?)
    (let ((hi-root (vector-ref hi-root 0)))
      (if (absent? hi-root)
          empty-intmap
          (let ((hi (make-intmap min
                                 (- hi-shift *branch-bits*)
                                 hi-root)))
            (if lo-is-a?
                (intmap-intersect lo hi meet)
                (intmap-intersect hi lo meet))))))

  (match (cons a b)
    ((($ <intmap> a-min a-shift a-root) . ($ <intmap> b-min b-shift b-root))
     (cond
      ((< a-min b-min)
       (different-mins a-min a-shift a-root b-min b-shift b #t))
      ((< b-min a-min)
       (different-mins b-min b-shift b-root a-min a-shift a #f))
      ((< a-shift b-shift)
       (different-shifts-same-min b-min b-shift b-root a #t))
      ((< b-shift a-shift)
       (different-shifts-same-min a-min a-shift a-root b #f))
      (else
       ;; At this point, A and B cover the same range.
       (let ((root (intersect a-shift a-root b-root)))
         (cond
          ((eq? root a-root) a)
          ((eq? root b-root) b)
          (else (make-intmap/prune a-min a-shift root)))))))))

(define (intmap->alist intmap)
  (reverse (intmap-fold acons intmap '())))

(define (print-intmap intmap port)
  (format port "#<intmap ~a>" (intmap->alist intmap)))
(define (print-transient-intmap intmap port)
  (format port "#<transient-intmap ~a>" (intmap->alist intmap)))

(set-record-type-printer! <intmap> print-intmap)
(set-record-type-printer! <transient-intmap> print-transient-intmap)
