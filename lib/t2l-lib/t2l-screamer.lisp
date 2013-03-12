(in-package :t2l)

(defvar *t2l-screamer-fail* 'fail1)
(defvar *mess* 0)
(defvar *fuzz* 1d-6)


; Graph representation of context-free grammars
; Alex Shkotin arXiv:cs/0703015 http://arxiv.org/abs/cs/0703015
; 
; jan 2013 
;                                                         ocannon@gmail.com
(cl:defun mapprules-internal (list 
                              prules
                              &key continuation-mode
                                   ordered-partitions-nondeterministic-values-cap
                                   symbol-mode
                                   params
                                   print-graph-info)
  (labels
      ((rule-label (sym) 
         (cond ((null sym) (gensym))
               ((not (stringp sym)) (rule-label (write-to-string sym)))
               ((and (> (length sym) 1)
                     (string= (subseq sym 0 1) ":"))
                (gensym (subseq sym 1 (length sym))))
               (t (gensym sym))))
       (znd-rule? (rule) 
         (> (length (remove-if-not #'(lambda (x) (eq x (car rule))) (mapcar #'car prules))) 1))
       (zd-rule? (rule)
         (= (length (remove-if-not #'(lambda (x) (eq x (car rule))) (mapcar #'car prules))) 1))
       (one-to-one-transform (rule)
         (cond ((and (znd-rule? rule)
                     (> (length (cdr rule)) 1))
                (let* ((sym (rule-label (car rule))))
                  (list (list (car rule) sym)
                        (append (list sym) (cdr rule)))))
               (t (list rule))))
       (init-label (string)
         (cond ((not (stringp string)) (init-label (write-to-string string)))
               ((= 0 (length string)) string)
               ((string= ":" (subseq string 0 1)) string)
               (t (concatenate 'string ":" string))))
       (symeq (x y) (eql x y))
       (underscore? (x) (symeq x '_)))
    (let* ((dnd (flat1 (mapcar #'one-to-one-transform prules)))
           (syms (remove-duplicates (flat dnd) :test #'symeq :from-end t))
           (nonterminals (mapcar #'car dnd))
           (terminals (remove-duplicates
                       (remove-if-not
                        #'(lambda (sym)
                            (null (intersection (list sym) nonterminals :test #'symeq)))
                        syms)
                       :test #'list-eq
                       :from-end t)))
      (let ((and-syms (remove-if-not
                       #'(lambda (sym)
                           (or (and (not (position sym terminals :test #'symeq))
                                    (= (length (remove-if-not #'(lambda (x) (symeq sym x)) nonterminals)) 1))))
                       nonterminals))
            (or-syms (remove-if-not
                      #'(lambda (sym)                         
                          (and (not (position sym terminals :test #'symeq))
                               (> (length (remove-if-not #'(lambda (x) (symeq sym x)) nonterminals)) 1)))
                      nonterminals))
            (dmgassoc (mapcar #'(lambda (sym) 
                                  (cons sym (make-instance 't2l::node :name sym)))
                              syms)))
        (labels 
            ((terminal-sym? (sym) (position sym terminals))             
             (or-sym? (sym) (position sym or-syms))
             (and-sym? (sym) (position sym and-syms)))
          (let ((dmg (cdar dmgassoc))
                (dmg-sym-assoc nil)
                (dmg-wordsize-assoc nil))
            (if print-graph-info
                (dolist (x (mapcar #'car dmgassoc))
                  (print (format nil 
                                 "~A: terminal? ~A or-sym? ~A and-sym? ~A syms: ~A" 
                                 x
                                 (terminal-sym? x)
                                 (or-sym? x)
                                 (and-sym? x)
                                 (mapcar #'name (next-nodes (cdr-assoc x dmgassoc)))))))
            (labels 
                ((make-edges (node)
                   (cond ((or-sym? (name node))
                          (mapcar #'(lambda (sym) 
                                      (push (cdr-assoc sym dmgassoc) (next-nodes node)))
                                  (remove-duplicates
                                   (flat1
                                    (mapcar 
                                     #'cdr
                                     (remove-if-not
                                      #'(lambda (x) (symeq (car x) (name node)))
                                      dnd)))
                                   :test #'symeq
                                   :from-end t)))
                         ((and-sym? (name node))
                          (mapcar #'(lambda (sym)
                                      (push-to-end (cdr-assoc sym dmgassoc) (next-nodes node)))
                                  (flat1
                                   (mapcar 
                                    #'cdr
                                    (remove-if-not
                                     #'(lambda (x) (symeq (car x) (name node)))
                                     dnd)))))
                         (t nil)))
                 (make-list-input-variable () 
                   (cond (symbol-mode (make-variable))
                         (t (make-variable)))))
              (mapcar #'make-edges (mapcar #'cdr dmgassoc))
              (dolist (n (mapcar #'car dmgassoc))
                (setf (cdr-assoc n dmg-sym-assoc) 
                      (mapcar #'name (next-nodes (cdr-assoc n dmgassoc)))))
              (labels
                  ((dmg-max-wordsize (sym)
                     (let ((syms nil))
                       (labels
                           ((findmax (s)
                              (cond
                               ((terminal-sym? s) 1)
                               ((position s syms) nil)
                               (t
                                (push s syms)
                                (let ((rs (mapcar #'findmax (cdr-assoc s dmg-sym-assoc))))
                                  (cond
                                   ((position nil rs) nil)
                                   (t
                                    (cond
                                     ((and-sym? s) (reduce #'+ rs))
                                     (t (reduce #'max rs))))))))))
                         (findmax sym))))
                   (dmg-min-wordsize (sym)
                     (let ((syms nil))
                       (labels
                           ((findmin (s)
                              (cond
                               ((terminal-sym? s) 1)
                               ((position s syms) nil)
                               (t
                                ;(lprint 'findmin 's s)
                                (push s syms)
                                (let ((rs (mapcar #'findmin (cdr-assoc s dmg-sym-assoc))))
                                  (cond
                                   ((and-sym? s) (reduce #'+ (mapcar #'(lambda (x) (if (null x) 1 x)) rs)))
                                   ((null (remove nil rs)) 1)
                                   (t 
                                    ;(lprint 'findmin 'or-sym 's s 'rs rs)
                                    (reduce #'min (mapcar #'(lambda (x) (if (null x) 1 x)) rs)))))))))
                         (findmin sym))))
                   (dmg-and-syms (or-sym)                     
                     (let ((syms nil))
                       (labels
                           ((findsyms (s)
                              (cond
                               ((position s syms) (list s))
                               (t
                                (push s syms)
                                (append
                                 (remove-if-not #'and-sym? (cdr-assoc s dmg-sym-assoc))
                                 (mapcar #'findsyms (remove-if-not #'or-sym? (cdr-assoc s dmg-sym-assoc))))
                                ))))
                        (let ((list (remove-duplicates (flat (findsyms or-sym)) :test #'symeq :from-end t)))
                          (if (and-sym? nil) list (remove nil list))))))
                   (dmg-sym-domain (or-sym)
                     (let ((syms nil))
                       (labels
                           ((findsyms (s)
                              (if (= *mess* -1) (print (format nil " > dmg-sym-domain findsyms s: ~A" s)))
                              (cond
                               ((position s syms) (list s))
                               (t
                                (push s syms)
                                (append
                                 (remove-if-not #'terminal-sym? (cdr-assoc s dmg-sym-assoc))
                                 (mapcar #'findsyms (remove-if-not #'or-sym? (cdr-assoc s dmg-sym-assoc))))))))
                        (remove-duplicates (flat (findsyms or-sym)) :test #'symeq :from-end t)))))
                (dolist (n (mapcar #'car dmgassoc))
                  (setf (cdr-assoc n dmg-wordsize-assoc)
                        (cons (dmg-min-wordsize n)
                              (dmg-max-wordsize n))))
                (labels
                   ((min-wordsize (sym) (car (cdr-assoc sym dmg-wordsize-assoc)))
                    (max-wordsize (sym) (cdr (cdr-assoc sym dmg-wordsize-assoc))))
                  (if print-graph-info
                      (progn
                        (print (format nil "~A graph symbols" (length dmgassoc)))
                        (dolist (x (mapcar #'car dmgassoc))
                          (print (format nil
                                         "~A min-wordsize: ~A max-wordsize: ~A"
                                         x
                                         (min-wordsize x)
                                         (max-wordsize x))))))
                  (let ((vars (funcall-rec
                               #'(lambda (x) 
                                   (cond ((null x) nil)
                                         ((screamer::variable? x) x)
                                         ((underscore? x) (make-list-input-variable))
                                         ((integerp x) (make-intv= x))
                                         (t (let ((var (make-list-input-variable)))
                                              (assert! (equalv var x))
                                              var))))
                               list))
                        (rule-card-assoc
                         (mapcar
                          #'(lambda (sym)
                              (append (list sym)
                                      (mapcar #'(lambda (x) (cdr-assoc x dmg-wordsize-assoc))
                                              (cdr-assoc sym dmg-sym-assoc))))
                          (remove-if-not #'and-sym? (mapcar #'car dmgassoc))))
                        (or-sym-xs-assoc nil)
                        (term-sym-xs-assoc nil)
                        (or-and-sym-assoc nil)
                        (or-sym-domain-assoc nil))
                    (dolist (x (remove-if-not #'terminal-sym? (mapcar #'car dmg-sym-assoc)))
                      (setf (cdr-assoc x term-sym-xs-assoc) nil))
                    (dolist (x (remove-if-not #'or-sym? (mapcar #'car dmg-sym-assoc)))
                      (let ((and-syms (dmg-and-syms x)))
                        (let ((cards (remove-duplicates
                                      (mapcar #'(lambda (y) (cdr-assoc y rule-card-assoc)) 
                                              (dmg-and-syms x))
                                      :test #'list-eq
                                      :from-end t)))
                          (setf (cdr-assoc x or-and-sym-assoc)
                                (mapcar
                                 #'(lambda (c)
                                     (remove-if-not 
                                      #'(lambda (y) 
                                          (list-eq c (cdr-assoc y rule-card-assoc))) 
                                      and-syms))
                                 cards)))))
                    (dolist (x (remove-if-not #'or-sym? (mapcar #'car dmg-sym-assoc)))
                      (setf (cdr-assoc x or-sym-domain-assoc) (dmg-sym-domain x)))
                    (let ((first-var (car vars))
                          (last-var (last-atom vars)))
                      (labels
                          ((csp-variable-name (x) 
                             (cond ((null x) nil)
                                   ((screamer::variable? x) (screamer::variable-name x))
                                   (t x)))
                           (ordered-partitions-of (list card)
                             (all-values
                               (let ((p (an-ordered-partition-of list)))
                                 (unless (and (= (length card) (length p))
                                              (every
                                               #'(lambda (x y)
                                                   (and (or (null (car x))
                                                            (>= y (car x)))
                                                        (or (null (cdr x))
                                                            (<= y (cdr x)))))
                                               card
                                               (mapcar #'length p)))
                                   (fail))
                                 p)))
                           (maprule (xs r)
                             (cond
                              ((null xs) nil)
                              ((listp r)
                               (reduce
                                #'orv
                                (mapcar
                                 #'(lambda (p)
                                     (apply
                                      #'orv
                                      (mapcar
                                       #'(lambda (r1)
                                           (apply
                                            #'andv
                                            (mapcar
                                             #'(lambda (x y) (maprule x y))
                                             p
                                             (cdr-assoc r1 dmg-sym-assoc))))
                                       r)))
                                 xs)))
                              ((and (terminal-sym? r)
                                    (not (cdr xs)))
                               (cond
                                ((assoc (car xs) (cdr-assoc r term-sym-xs-assoc))
                                 (cdr-assoc (car xs) (cdr-assoc r term-sym-xs-assoc)))
                                (t
                                 (setf (cdr-assoc (car xs) (cdr-assoc r term-sym-xs-assoc))                                     
                                       (cond
                                                 ;((cdr xs) nil)
                                        ((or symbol-mode
                                             (not (numberp r)))
                                         (equalv (car xs) r))
                                        (t 
                                         (=v (car xs) r))))
                                 (cdr-assoc (car xs) (cdr-assoc r term-sym-xs-assoc)))))
                              ((terminal-sym? r) nil)
                              ((and-sym? r) 
                               (print (format nil " WARNING : ~A" r))
                               (let* ((xs-length (length xs))
                                      (rcard (cond
                                              ((and continuation-mode
                                                    (< xs-length (length (cdr-assoc r rule-card-assoc)))
                                                    (position last-var xs))
                                               (subseq (cdr-assoc r rule-card-assoc) 0 xs-length))
                                              (t
                                               (cdr-assoc r rule-card-assoc))))
                                      (rcard-length (length rcard)))
                                 (cond
                                  ((< xs-length rcard-length)
                                   nil)
                                  (t 
                                   (let* ((xs-partitions (ordered-partitions-of xs rcard))
                                          (next-syms
                                           (cond
                                            ((and (= (length xs) 1)
                                                  continuation-mode
                                                  (eq (car xs) last-var))
                                             (remove-if #'or-sym? (cdr-assoc r dmg-sym-assoc)))
                                            (t (cdr-assoc r dmg-sym-assoc)))))
                                     (unless (null xs-partitions)
                                       (let ((vs (mapcar
                                                  #'(lambda (p) ; ordered partition of xs
                                                      (apply 
                                                       #'andv
                                                       (mapcar
                                                        #'(lambda (x y) (maprule x y))
                                                        p
                                                        next-syms)))
                                                  xs-partitions)))
                                         (if (> (length xs-partitions) 1)
                                             (reduce #'orv vs)
                                           (car vs)))))))))
                              ((or-sym? r)
                               (cond ((cdr xs)
                                      (apply
                                       #'orv
                                       (mapcar
                                        #'(lambda (x) (maprule (ordered-partitions-of xs (cdr-assoc (car x) rule-card-assoc)) x))
                                        (cdr-assoc r or-and-sym-assoc))))
                                     (t 
                                      (let ((existing-var (find (cons r xs) or-sym-xs-assoc :key #'car :test #'list-eq)))
                                        (cond (existing-var (cadr existing-var))
                                              (t 
                                               (let ((var (reduce 
                                                           #'orv
                                                           (mapcar
                                                            #'(lambda (term) (maprule xs term))
                                                            (cdr-assoc r or-sym-domain-assoc)))))
                                                 (push (list (cons r xs) var) or-sym-xs-assoc)
                                                 var)))))))
                              (t nil))))
                        (values (andv (all-memberv vars terminals)
                                      (maprule vars (name dmg))) 
                                vars                                                                                 
                                dmg)))))))))))))

(defstruct (dmg-cursor (:conc-name nil) (:print-function print-dmg-cursor)) label sym stack rules)

(defvar *mapprules-default-input-process-increment* 4)
(define-box mapprules (input
                       prules 
                       &key process-chunk-size
                            input-process-increment
                            continue
                            init
                            listdxx
                            max
                            min
                            ordered-partitions-nondeterministic-values-cap
                            superset
                            symbol-mode
                            params
                            print-graph-info)
  :outputs 3
  :indoc '("input template list, screamer variable list or number" 
           "production rules"
           "process-chunk-size"
           "input-process-increment (use process-chunk-size)"
           "continue"
           "init"
           "listdxx"
           "max"
           "min"
           "ordered-partitions-nondeterministic-values-cap"
           "superset"
           "symbol-mode"
           "params"
           "print-graph-info")
  :icon 324
  (assert (not (and symbol-mode listdxx)))
  (if (and (null process-chunk-size) input-process-increment)
      (setf process-chunk-size input-process-increment))
  (setf process-chunk-size
        (cond ((and (null process-chunk-size) input-process-increment) input-process-increment)
              (t process-chunk-size)))
  (setf process-chunk-size
        (cond ((null process-chunk-size) nil)
              ((numberp process-chunk-size) process-chunk-size)
              (t *mapprules-default-input-process-increment*)))
  (labels
      ((init-label (string)
         (cond ((not (stringp string)) (init-label (write-to-string string)))
               ((= 0 (length string)) string)
               ((string= ":" (subseq string 0 1)) string)
               (t (concatenate 'string ":" string))))
       (symeq (x y)
         (let ((xS (init-label x))
               (yS (init-label y)))
           (string= xS yS)))
       (underscore? (x) (or (symeq x "_") (symeq x "t2l::_")))
       (atom->var (x)
         (cond ((null x) nil) 
               ((screamer::variable? x) x)
               ((underscore? x) 
                (cond (symbol-mode (make-variable))
                      (t (an-integerv))))
               ((integerp x) (make-intv= x))
               ((floatp x) (make-realv= x))
               ((numberp x) (make-numberv= x))
               (t
                (let ((v (make-variable)))                  
                  (assert! (equalv v x))
                  v))))
       (process-increment-adjusted-length (length) 
         (if process-chunk-size
             (* (ceiling (/ length process-chunk-size)) process-chunk-size)
           length))
       (make-input-sequence (length)
         (make-sequence 'list (process-increment-adjusted-length length) :initial-element '_)))
    (cond
     ((or (null input) (and (numberp input) (= 0 input)) (and (listp input) (every #'null (flat input)))) input)
     (t
      (let* ((list (cond ((null input) nil)
                         ((listp input) input)
                         ((numberp input) (make-input-sequence input))
                         (t input)))
             (list-vars (funcall-rec #'atom->var list))
             (list-vars-flat-subseq (if init
                                        (append (list init) (remove nil (flat list-vars)))
                                      (remove nil (flat list-vars))))
             (list-vars-flat (if (and process-chunk-size
                                      (< (length list-vars-flat-subseq) (process-increment-adjusted-length (length list-vars-flat-subseq))))
                                 (append list-vars-flat-subseq 
                                         (mapcar #'atom->var (make-sequence 'list (- (process-increment-adjusted-length (length list-vars-flat-subseq)) (length list-vars-flat-subseq)) :initial-element '_)))
                               list-vars-flat-subseq))
             (map-fn-input (if listdxx (listdxv list-vars-flat) list-vars-flat)))
        (if (not symbol-mode)
            (progn 
              (if min (push (reduce-chunks #'andv (mapcar #'(lambda (x) (>=v x min)) list-vars-flat) :default t) c))
              (if max (push (reduce-chunks #'andv (mapcar #'(lambda (x) (<=v x max)) list-vars-flat) :default t) c))))
        (if superset (push (reduce-chunks #'andv (mapcar #'(lambda (x) (memberv x superset)) list-vars-flat) :default t) c))
        (cond
         (process-chunk-size
          (let ((map-fn-input-chunks (let ((nsucc (nsucc map-fn-input process-chunk-size :step (1- process-chunk-size))))
                                       (cond ((and (> (length nsucc) 1)
                                                   (= (length (car (reverse nsucc))) 1)) (butlast nsucc))
                                             (t nsucc)))))
            (if (>= *mess* 5) (print (format nil "map-fn-input-chunks: ~A" map-fn-input-chunks)))              
            (let ((var-input-dmg-list 
                   (maplist
                    #'(lambda (chunks)
                        (if (>= *mess* 5) (print (format nil "mapprules: chunk ~A / ~A" (1+ (- (length map-fn-input-chunks) (length chunks))) (length map-fn-input-chunks))))
                        (multiple-value-list
                         (mapprules-internal (car chunks)
                                             prules
                                             :continuation-mode t
                                             :symbol-mode symbol-mode
                                             :ordered-partitions-nondeterministic-values-cap ordered-partitions-nondeterministic-values-cap
                                             :params params
                                             :print-graph-info print-graph-info)))
                    map-fn-input-chunks)))
              (values (apply #'andv (mapcar #'car var-input-dmg-list))
                      (cadar var-input-dmg-list)
                      (caddar var-input-dmg-list)))))
         (t 
          (multiple-value-bind 
              (var list dmg)
              (mapprules-internal map-fn-input                                            
                                  prules
                                  :continuation-mode continue
                                  :symbol-mode symbol-mode
                                  :ordered-partitions-nondeterministic-values-cap ordered-partitions-nondeterministic-values-cap
                                  :params params
                                  :print-graph-info print-graph-info) 
            (values var list-vars dmg)))))))))
              
;; screamer+ macro Copyright 1998-2000 University of Aberdeen 
(defmacro ifv (condition exp1 &optional (exp2 nil))
  ;; If the condition is bound then there is no need to create additional
  ;; constraint variables
  `(let ((c ,condition))
     (assert! (booleanpv c))
     (if (bound? c)
	 (if (screamer::known?-true c)
	     ,exp1
	   ,exp2)
       (let ((z (make-variable)))
	 (screamer::attach-noticer!
	  #'(lambda ()
	      ;; Change 31/8/99, SAW
	      ;; Used to check that z is not bound too, but that seemed wrong
	      (when (bound? c)
		(if (equal (value-of c) t)
		    (screamer::assert!-equalv z ,exp1)
		  (screamer::assert!-equalv z ,exp2))))
	  c)
	 z))))

;; screamer+ macro Copyright 1998-2000 University of Aberdeen 
(defun quote-up (f &rest args)
  (cond
   ((= (length args) 0)
    `(quote ,f))
   (t
    `(,f ,@args))))

;;; This function is also used by solution to return the values
;;; found by the search. If objects were explored by the search
;;; NEW instances of the same type are generated and returned.

#|(defun apply-substitution (x &aux retobj)
  (let ((val (value-of x)))
    ;; Changed from a cond to a typecase, 8/7/00
    (typecase val
      (cons
       (cons (apply-substitution (car val)) (apply-substitution (cdr val)))
       )
      (standard-object
       (setq retobj (make-instance (class-name (class-of val))))
       (copy-slots val retobj)
       retobj 
       )
      (array
       (setq retobj (make-array (array-dimensions val)))
       (copy-cells val retobj)
       retobj
       )
      (t val)
      )
    )
  )|#

;;; This function returns a variable which is constrained to return a list
;;; containing the distinct elements of x. The argument x can be either a
;;; value or a constraint variable at the time of function invocation.

(defun members-ofv (x)
  (let (
        (z (make-variable))
        )

     (screamer::attach-noticer!
       #'(lambda()
           (when (and (bound? x) (every #'bound? (value-of x)))
              (do* (
                    (dec (apply-substitution x) (cdr dec))
                    (curr (car dec) (car dec))
                    (vals nil)
                    )
                  ((endp dec) 
                   (assert! (equalv z vals))
                   )
                 (pushnew (value-of curr) vals :test #'equal)
                 )
              )
           )
       x)
     z)
  )

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Function: set-equalv
;;;
;;; This function returns a boolean variable constrained to indicate whether
;;; the lists x and y have the same members
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun set-equalv (x y)
  (let (
	(z (a-booleanv))
	noticer
	)
    
    (flet (;; This is just a function which can be used by 'sort' to
	   ;; derive some well-defined ordering for any known values x and y
	   (strcmp(x y)
		  (numberp (string< (format nil "~s" x)
				    (format nil "~s" y)))
		  )
	   )

      (setq noticer
	    #'(lambda()
		(when (and (ground? x) (ground? y))
		  (assert!
		   (equalv z
			   (equalv
			    (sort
			     (value-of (members-ofv (apply-substitution x)))
			     #'strcmp)
			    (sort
			     (value-of (members-ofv (apply-substitution y)))
			     #'strcmp)
			    )
			   )
		   )
		  )
		)
	    )
      (screamer::attach-noticer! noticer x)
      (screamer::attach-noticer! noticer y)
      )
    z)
  )





(defmacro n-values (n
		    &body forms)
"Copyright (c) 2007, Kilian Sprotte. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:

  * Redistributions of source code must retain the above copyright
    notice, this list of conditions and the following disclaimer.

  * Redistributions in binary form must reproduce the above
    copyright notice, this list of conditions and the following
    disclaimer in the documentation and/or other materials
    provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE AUTHOR 'AS IS' AND ANY EXPRESSED
OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE
GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE."
  (let ((values (gensym "VALUES-"))
        (last-value-cons  (gensym "LAST-VALUE-CONS-"))
        (value (gensym "VALUE-")))
    `(let ((,values '())
           (,last-value-cons nil)
	   (number 0))
       (block n-values
	 (for-effects
	   (let ((,value (progn ,@forms)))
	     (global (cond ((null ,values)
			    (setf ,last-value-cons (list ,value))
			    (setf ,values ,last-value-cons))
			   (t (setf (rest ,last-value-cons) (list ,value))
			      (setf ,last-value-cons (rest ,last-value-cons))))
		     (incf number))
	     (when (>= number ,n) (return-from n-values)))))
       ,values)))


(defun ith-random-value (n expression)
  (one-value
   (ith-value (a-random-member-of (arithm-ser 0 n 1))
              expression)))

(define-box om-assert!2 (&rest sequence)
  :icon 324
  t)
            
(defmacro om-assert! (&rest sequence)
  `(progn ,@(mapcar #'(lambda (x) `(assert! ,x)) (butlast sequence)) ,(car (reverse sequence))))

(defmacro om-one-solution-lf (form)
  `(one-value (solution ,form (static-ordering #'print-linear-force))))

(defun xorv (&rest xs)
  (andv (notv (apply #'andv xs))
        (apply #'orv xs)))
(defun nonev (&rest xs)
  (=v 0 (applyv #'count-trues xs)))

(defun om-call-one-value (fn)
  (one-value (funcall-nondeterministic fn)))

(defun om-apply-one-value (fn &rest args)
  (one-value 
   (cond (args
          (apply-nondeterministic fn args))
         (t
          (funcall-nondeterministic fn)))))

(defun om-solution (x &optional force-function)
  (solution x (cond ((null force-function)
                     (static-ordering #'linear-force))
                    ((string= (write-to-string force-function) "plf")
                     (static-ordering #'print-linear-force))
                    ((or (functionp force-function)
                         (screamer::nondeterministic-function? force-function))
                     (if (>= *mess* 10) 
                         (lprint 'om-solution "static-ordering force-function: user fn " force-function))
                     (static-ordering force-function))
                    ((string= (write-to-string force-function) "linear-force fn")
                     (if (>= *mess* 10) 
                         (lprint 'om-solution "static-ordering force-function: linear-force fn"))
                     (static-ordering #'linear-force))
                    ((string= (write-to-string force-function) "lf")
                     (if (>= *mess* 10) 
                         (lprint 'om-solution "static-ordering force-function: linear-force fn"))
                     (static-ordering #'linear-force))
                    ((string= (write-to-string force-function) "divide-and-conquer-force fn")
                     (if (>= *mess* 10) 
                         (lprint 'om-solution "static-ordering force-function: divide-and-conquer-force fn"))
                     (static-ordering #'divide-and-conquer-force))
                    ((string= (write-to-string force-function) "dacf")
                     (if (>= *mess* 10) 
                         (lprint 'om-solution "static-ordering force-function: divide-and-conquer-force fn"))
                     (static-ordering #'divide-and-conquer-force))
                    ((or (string= (write-to-string force-function) "reorder-domain-size-linear-force")
                         (string= (write-to-string force-function) "rodslf")
                         (string= (write-to-string force-function) "reorder"))
                     (if (>= *mess* 10) 
                         (lprint 'om-solution "reordering force-function: linear-force fn"))
                     (reorder #'domain-size
                              #'(lambda (x) (declare (ignore x)) nil)
                              #'<
                              #'linear-force))
                    ((or (string= (write-to-string force-function) "reorder-domain-size-divide-and-conquer-force")
                         (string= (write-to-string force-function) "rodsdacf")
                         (string= (write-to-string force-function) "reorder-dacf"))
                     (if (>= *mess* 10) 
                         (lprint 'om-solution "reordering force-function: divide-and-conquer-force fn"))
                     (reorder #'domain-size
                              #'(lambda (x) (declare (ignore x)) nil)
                              #'<
                              #'divide-and-conquer-force))
                    ((or (string= (write-to-string force-function) "print-reorder-domain-size-divide-and-conquer-force")
                         (string= (write-to-string force-function) "prodsdacf")
                         (string= (write-to-string force-function) "print-reorder-dacf"))
                     (if (>= *mess* 10) 
                         (lprint 'om-solution "reordering force-function: divide-and-conquer-force fn"))
                     (reorder #'domain-size
                              #'(lambda (x) (declare (ignore x)) nil)
                              #'<
                              #'print-divide-and-conquer-force))
                    (t
                     (if (>= *mess* 10) 
                         (lprint 'om-solution "static-ordering force-function: linear-force fn"))
                     (static-ordering #'linear-force)))))

(defun all-solutions (x &optional force-function)
  (all-values (om-solution x force-function)))

(defun one-solution (x &optional force-function fail-form)
  (cond (fail-form
         (one-value (om-solution x force-function) fail-form))
        (t 
         (one-value (om-solution x force-function)))))

(defun ith-solution (i x &optional force-function fail-form)
  "shortcut for screamer:ith-value context for solution"
  (cond (fail-form
         (ith-value i (om-solution x force-function) fail-form))
        (t 
         (ith-value i (om-solution x force-function)))))

(defun best-solution (form1 objective-form &optional force-function form2)
  (best-value (om-solution form1 force-function) objective-form form2))

(defun om-template (x)
  (multiple-value-list (template x)))

(defmacro om-nondeterministic-fn-reference (sym &rest args)
  `(screamer:one-value (lambda (x) 
                         (funcall-nondeterministic (function ,sym) x ,@args))))

(defun meanv (&rest xs)
  (list-meanv xs))

(defun list-meanv (list)
  (/v (sumv (mapcar #'(lambda (x) (make-realv= x)) list))
      (make-realv= (length list))))
(defun lists=v (list1 list2 &optional symbol-mode)
  (apply #'andv
         (mapcar #'(lambda (a b) (=v a b))
                 list1
                 list2)))
(defun list-boolean-opv (fn x value)
  (let ((input (flat x)))
    (reduce #'andv (mapcar #'(lambda (y) (funcall fn y value)) input))))
(defun list-binary-opv (fn x value)
  (mapcar #'(lambda (y) (funcall fn y value)) x))
(defun list+v (x value) (list-binary-opv #'+v x value))
(defun list-v (x value) (list-binary-opv #'-v x value))
(defun list*v (x value) (list-binary-opv #'*v x value))
(defun list/v (x value) (list-binary-opv #'/v x value))
(defun list<v (x value) (list-boolean-opv #'<v x value))
(defun list<=v (x value) (list-boolean-opv #'<=v x value))
(defun list>v (x value) (list-boolean-opv #'>v x value))
(defun list>=v (x value) (list-boolean-opv #'>=v x value))
(defun list=v (x value) (list-boolean-opv #'=v x value))
(defun list/=v (x value) (list-boolean-opv #'/=v x value))
(defun all<v (x)
  (apply #'<v (flat x)))
(defun all<=v (x)
  (apply #'<=v (flat x)))
(defun all>v (x)
  (apply #'>v (flat x)))
(defun all>=v (x)
  (apply #'>=v (flat x)))
(defun all<>v (x)
  (let ((vars (flat x)))
    (orv (apply #'<v vars)
         (apply #'>v vars))))
(defun all<>=v (x)
  (let ((vars (flat x)))
    (orv (apply #'<=v vars)
         (apply #'>=v vars))))
(define-box all-betweenv (x min max)
  :icon 324
  (let ((flat (remove-duplicates (remove nil (flat x)))))
    (andv (apply #'andv (mapcar #'(lambda (y) (>=v y min)) flat))
          (apply #'andv (mapcar #'(lambda (y) (<=v y max)) flat)))))
(define-box all/=v (x)
  :icon 324
  (reduce-chunks #'/=v (flat x)))
(define-box all=v (x)
  :icon 324
  (reduce-chunks #'=v (flat x)))
(define-box all-andv (x)
  :icon 324
  (reduce-chunks #'andv (flat x)))
(define-box all-orv (x)
  :icon 324
  (reduce-chunks #'orv (flat x)))
(define-box all-memberv (e sequence)
  :icon 324
  (let ((sequence-flat (flat sequence)))
    (cond ((listp e) (reduce-chunks #'andv (mapcar #'(lambda (x) (memberv x sequence-flat)) (flat e))))
          (t (memberv e sequence-flat)))))

(defun a-random-member-of (list)
  (a-member-of (permut-random list)))
(defun a-random-member-ofv (list)
  (a-member-ofv (permut-random list)))

(define-box om-count-truesv (list)
  (apply #'count-truesv list))

(defun real-absv (k)
  (let ((m (a-realv)))
    (assert! (orv (=v m k)
                  (=v m (*v -1 k))))
    (assert! (>=v m 0))
    m))
#|(defun real-abs-v (k)
  (let ((m (a-realv)))
    (assert! (orv (=v m k)
                  (=v m (*v -1 k))))
    (assert! (<=v m 0))
    m))|#

(defun integer-absv (k)
  (let ((m (an-integerv)))
    (assert! (orv (=v m k)
                  (=v m (*v -1 k))))
    (assert! (>=v m 0))
    m))
#|(defun integer-abs-v (k)
  (let ((m (an-integerv)))
    (assert! (orv (=v m k)
                  (=v m (*v -1 k))))
    (assert! (<=v m 0))
    m))|#


(defun absv (k)
  (let ((m (a-numberv)))
    (assert! (orv (equalv m k)
                  (equalv m (*v -1 k))))
    (assert! (>=v m 0))
    m))
#|(defun abs-v (k)
  (let ((m (a-numberv)))
    (assert! (orv (equalv m k)
                  (equalv m (*v -1 k))))
    (assert! (<=v m 0))
    m))|#
(defun %v (n d)
  (assert! (integerpv n))
  (assert! (integerpv d))
  (let ((g (-v n (*v d (an-integerv)))))
    (assert! (>=v g 0))
    (assert! (<v g d))
    g))
#|(defun modv (n d)
  (let ((m (an-integer-betweenv 0 (-v d 1))))
    (assert! (=v m (funcallv #'mod n d)))
    m))|#
(defun modv (n d)
  (%v n d))
(defun powv (a b)
  (let ((c (a-realv)))
    (assert! (=v c (funcallv #'pow a b)))
    c))

(cl:defun reduce-chunks (fn input &key default)
  (cond
   ((null input) default)
   ((not (listp input)) (reduce-chunks fn (list input) :default default))
   ((>= (length input) call-arguments-limit) 
    (reduce fn (mapcar #'(lambda (chunk) (apply fn chunk)) 
                       (nsucc input call-arguments-limit :step call-arguments-limit))))
   (t (apply fn input))))
(defun sumv (list)
  (reduce-chunks #'+v list :default 0))

(defun a-member-betweenv (list min max) 
  (let ((var (a-member-ofv list)))
    (assert! (>=v var min))
    (assert! (<=v var max))
    var))

(defun an-integer-member-ofv (l)
  (let ((v (a-member-ofv (list->intv l))))
    (assert! (integerpv v))))

(defun a-numeric-member-ofv (l)
  (let ((v (a-member-ofv (list->numberv l))))
    (assert! (numberpv v))))

(defun a-real-member-ofv (l)
  (let ((v (a-member-ofv (list->realv l))))
    (assert! (realpv v))))

(defun integer-member-ofv (v l)  
  (assert! (integerpv v))
  (assert! (memberv v l)))

(defun numeric-member-ofv (v l)
  (assert! (numberpv v))
  (assert! (memberv v l)))

(defun real-member-ofv (v l)
  (assert! (realpv v))
  (assert! (memberv v l)))

(defun make-integer-betweenv (min max)
  (let ((v (make-variable)))
    (assert! (numberpv v))
    (assert! (=v v (an-integer-betweenv min max)))
    v))

(defun choicev (sequence)
  (let ((var (make-variable)))
    (assert! (apply #'orv
                    (mapcar #'(lambda (x)
                                (equalv var x))
                            sequence)))
    var))

(defun listdxxv2-internal (p list)
  (if (null list)
      nil
   (either
    (progn
      (assert! (integerpv (car list)))
      (let ((f (+v p (car list))))
       (append
        (list f)
        (listdxxv2-internal f (cdr list)))))
    (progn
      (assert! (equalv nil (car list)))
      (append
       (list nil)
       (listdxxv2-internal p (cdr list)))))))

(defun listdxxv2 (list)
  (let ((head (car list)))
    (either
      (progn
        (assert! (integerpv head))
        (let ((var (an-integerv)))
        (append (list var)
                (listdxxv2-internal var list))))
      (progn
        (assert! (equalv nil head))
        (append (list head)
                (listdxxv2 (cdr list)))))))


(defun listdxv2-internal (p list)
  (if (null list)
      nil
   (either
    (progn
      (assert! (integerpv (car list)))
      (let ((f (-v (car list) p)))
       (append
        (list f)
        (listdxv2-internal (car list) (cdr list)))))
    (progn
      (assert! (equalv nil (car list)))
      (append
       (list nil)
       (listdxv2-internal p (cdr list)))))))
      
(defun listdxv2 (list)
    (either
      (progn
        (assert! (integerpv (car list)))
        (listdxv2-internal (car list) (cdr list)))
      (progn
        (assert! (equalv nil (car list)))
        (append (list (car list))
                (listdxv2 (cdr list))))))

(defun listdxv3 (list)
  (labels
      ((peek-numberv (stack)
         (if (null stack)
             nil
           (ifv (equalv nil (car stack))
                (peek-numberv (cdr stack))
                (car stack))))
       (dx (ls rs)
         (cond
          ((null rs) nil)
          ((null ls) (dx (list (car rs)) (cdr rs)))
          (t
           (append
            (list
             (let ((lvar (peek-numberv (reverse ls)))
                   (rvar (peek-numberv rs)))
               (ifv (andv (notv (equalv nil lvar)) (notv (equalv nil rvar)))
                    (-v rvar lvar)
                    nil)))
            (dx (append ls (list (car rs))) (cdr rs)))))))
    (dx nil list)))
         

(defun first-atomv (list)
  (if (null list)
      (fail)
    (either
      (progn
        (assert! (notv (equalv (car list) nil)))
        (car list))
      (progn
        (assert! (equalv (car list) nil))
        (first-atomv (cdr list))))))

(defun last-atomv (list)
  (first-atomv (reverse list)))

(defun atomsv (list)
  (if (null list)
      nil
    (append
     (either
       (progn
         (assert! (notv (equalv (car list) nil)))         
         (list (car list)))
       (progn
         (assert! (equalv (car list) nil))
         nil))
     (atomsv (cdr list)))))

(defun prolog-union (y z w)
  (either 
    (let ((a (make-variable))
          (y1 (make-variable)))
      (assert! (equalv y (cons a y1)))
      (either 
        (progn 
          (assert! (memberv a z))
          (prolog-union y1 z w))
        (progn 
          (assert! (notv (memberv a z)))
          (let ((w1 (make-variable)))
            (assert! (equalv w (cons a w1)))
            (prolog-union y1 z w1)))))
    (progn 
      (assert! (equalv y nil))
      (assert! (equalv z w)))))

(defun prolog-intersect (y m z)
  (if (>= *mess* 30) (print (list 'prolog-intersect 'y y 'm m 'z z)))
  (either
    (progn 
      (assert! (equalv y nil))
      (assert! (equalv z nil)))
    (let ((a (make-variable))
          (y1 (make-variable))
          (m1 (make-variable))
          (z1 (make-variable)))
      (assert! (equalv y (cons a y1)))
      (assert! (equalv m m1))
      (either 
        (progn 
          (assert! (memberv a m))
          (let ((z1 (make-variable)))
            (assert! (equalv z (cons a z1)))
            (prolog-intersect y1 m1 z1)))
        (progn
          (assert! (notv (memberv a m)))
          (assert! (equalv z z1))
          (prolog-intersect y1 m1 z1))))))

(defun prolog-difference (y m z)
  (either
    (progn 
      (assert! (equalv y nil))
      (assert! (equalv z nil)))
    (let ((a (make-variable))
          (y1 (make-variable))
          (m1 (make-variable))
          (z1 (make-variable)))
      (assert! (equalv y (cons a y1)))
      (assert! (equalv m m1))
      (either 
        (progn 
          (assert! (memberv a m))
          (assert! (equalv z z1))
          (prolog-difference y1 m1 z1))
        (progn
          (assert! (equalv z (cons a z1)))
          (prolog-difference y1 m1 z1))))))

(defun prolog-delete (a x z) ; iffy
  (print (list 'prolog-delete 'a a 'x x 'z z))
  (either
    (progn 
      (assert! (equalv x (cons a z))))
    (let ((a1 (make-variable))
          (b (make-variable))
          (x1 (make-variable))
          (z1 (make-variable)))
      (assert! (equalv a a1))
      (assert! (equalv x (cons b x1)))
      (assert! (equalv z (cons b z1)))
      (prolog-delete a1 x1 z1))))

(defun setof (l)
  (let ((c)
        (r (make-variable))
        (l1 (make-variable)))
    (prolog-maplist3 (lambda (x)
                       (cond ((memberv x c) x)
                             (t 
                              (push x c)
                              x)))
                       l
                       l1)
    (prolog-reverse c r)
    r))

(defun prolog+v3 (y z value)
  (either 
   (progn 
     (assert! (equalv nil y))
     (assert! (equalv z nil)))
   (progn 
     (assert! (numberpv y))
     (assert! (equalv z (+v y value))))
   (progn 
     (let ((y1 (make-variable))
	   (y2 (make-variable)))
       (assert! (equalv y (cons y1 y2)))
       (let ((z1 (make-variable))
	     (z2 (make-variable)))
         (assert! (equalv z (cons z1 z2)))
	 (prolog+v3 y1 z1 value)
	 (prolog+v3 y2 z2 value))))
   (progn 
     (assert! (notv (numberpv y)))
     (assert! (equalv z 0)))))

(defun prolog-v3 (y z value)
  (either 
   (progn 
     (assert! (equalv nil y))
     (assert! (equalv z nil)))
   (progn 
     (assert! (numberpv y))
     (assert! (equalv z (-v y value))))
   (progn 
     (let ((y1 (make-variable))
	   (y2 (make-variable)))
       (assert! (equalv y (cons y1 y2)))
       (let ((z1 (make-variable))
	     (z2 (make-variable)))
	 (prolog-v3 y1 z1 value)
	 (prolog-v3 y2 z2 value)
	 (assert! (equalv z (cons z1 z2))))))
   (progn 
     (assert! (notv (numberpv y)))
     (assert! (equalv z 0)))))


(defun prolog*v3 (y z value)
  (either 
   (progn 
     (assert! (equalv nil y))
     (assert! (equalv z nil)))
   (progn 
     (assert! (numberpv y))
     (assert! (equalv z (*v y value))))
   (progn 
     (let ((y1 (make-variable))
	   (y2 (make-variable)))
       (assert! (equalv y (cons y1 y2)))
       (let ((z1 (make-variable))
	     (z2 (make-variable)))
	 (prolog*v3 y1 z1 value)
	 (prolog*v3 y2 z2 value)
	 (assert! (equalv z (cons z1 z2))))))
   (progn 
     (assert! (notv (numberpv y)))
     (assert! (equalv z 0)))))

(defun prolog/v3 (y z value)
  (assert! (notv (=v value 0)))
  (either 
   (progn 
     (assert! (equalv nil y))
     (assert! (equalv z 0)))
   (progn 
     (assert! (numberpv y))
     (assert! (equalv z (/v y value))))
   (progn 
     (let ((y1 (make-variable))
	   (y2 (make-variable)))
       (assert! (equalv y (cons y1 y2)))
       (let ((z1 (make-variable))
	     (z2 (make-variable)))
	 (prolog/v3 y1 z1 value)
	 (prolog/v3 y2 z2 value)
	 (assert! (equalv z (cons z1 z2))))))
   (progn 
     (assert! (notv (numberpv y)))
     (assert! (equalv z 0)))))

(defun list-within? (l minmax)
  (andv (<=v (list-maxv l) (list-maxv minmax))
        (>=v (list-minv l) (list-minv minmax))))

(defun funcallv-rec (fn tree)
  (cond ((equalv nil tree) nil)
        ((funcallv #'consp tree) 
         (cons (funcallv-rec fn (funcallv #'car tree))
               (funcallv-rec fn (funcallv #'cdr tree))))
        (t (funcallv fn tree))))

(defun make-numberv= (n)
  (let ((v (make-variable)))
    (assert! (numberpv v))
    (assert! (=v v n))
    v))

(defun make-intv= (n)
  (let ((v (make-variable)))
    (assert! (integerpv v))
    (cond ((null n) v)
          ((numberp n)
           (assert! (=v v n)))
          ((listp n)
           (cond ((and (every #'listp n)
                       (every #'cdr n))
                  (assert! (memberv v (remove-duplicates (flat (mapcar #'(lambda (x) 
                                                                   (let ((s (sort x #'<)))
                                                                     (all-values (an-integer-between (car s) (cadr s))))) n))))))
                 (t (assert! (andv (>=v v (car n))
                                   (<=v v (cadr n)))))))
          (t nil))
    v))

(defun make-realv= (n)
  (let ((v (make-variable)))
    (assert! (realpv v))
    (assert! (=v v n))
    v))

(defun make-var-equalv (x)
  (let ((v (make-variable)))
    (assert! (equalv v x))
    v))

(defun list->numberv (l)
  (cond ((null l) nil)
        ((listp l) 
         (append (list (list->intv (car l)))
                 (list->intv (cdr l))))
        ((screamer::variable? l) l)
        (t (make-numberv= l))))

(defun list->intv (l)
  (cond ((null l) nil)
        ((listp l) 
         (append (list (list->intv (car l)))
                 (list->intv (cdr l))))
        ((screamer::variable? l) l)
        (t (make-intv= l))))

(defun list->realv (l)
  (cond ((null l) nil)
        ((listp l) 
         (append (list (list->intv (car l)))
                 (list->intv (cdr l))))
        ((screamer::variable? l) l)
        (t (make-realv= l))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; screams.lisp

(defun all-differentv (x &rest xs)
  (labels ((all-different (x xs)
             (if (null xs)
                 t
                 (andv (notv (=v x (car xs)))
                       (all-different x (cdr xs))
                       (all-different (car xs) (cdr xs))))))
    (all-different x xs)))

;  append([X|Y],Z,[X|W]) :- append(Y,Z,W).
;  append([],X,X).
(defun prolog-append (x y z)
  (either 
    (progn 
      (assert! (equalv x nil))
      (assert! (equalv y z)))
    (let ((x1 (make-variable))
          ;(y1 (make-variable))
          (z1 (make-variable))
          (a (make-variable)))
      (assert! (equalv x (cons a x1)))
      ;(assert! (equalv y y1))
      (assert! (equalv z (cons a z1)))
      (prolog-append x1 y z1))))

(defun prolog-reverse (x y)
  (prolog-reverse-append x nil y))

;  reverse([X|Y],Z,W) :- reverse(Y,[X|Z],W).
;  reverse([],X,X).
(defun prolog-reverse-append (x y z)
  (either 
    (progn 
      (assert! (equalv x nil))
      (assert! (equalv y z)))
    (let ((x1 (make-variable))
          (y1 (make-variable))
          ;(z1 (make-variable))
          (a (make-variable)))
      (assert! (equalv x (cons a x1)))
      (assert! (equalv y1 (cons a y)))
      ;(assert! (equalv z z1))
      (prolog-reverse-append x1 y1 z))))

(cl:defun make-var-sequence (len &optional pad)
  (let ((vars (mapcar #'make-variable (make-sequence 'list len))))
    (cond (pad
           (cond ((functionp pad)
                  (mapcar (lambda (x) 
                            (funcall pad))
                          vars))
                 (t 
                  (mapcar (lambda (x) 
                            (assert! (equalv x pad))
                            x)
                          vars))))
          (t vars))))

(defun cons-atomsv (l c)
  (prolog-maplist3 (lambda (x)
                     (cond ((funcallv #'consp x) x)
                           (t (cons x nil))))
                   l
                   c))

; flatten(List, Flattened):-
;  flatten(List, [], Flattened).
;

(defun prolog-flatten (l f)
  (let ((f1 (make-variable)))
    (prolog-flatten3 l nil f1)))

;flatten(Var, Tl, [Var|Tl]) :-
;	var(Var), !.
;flatten([], Tl, Tl) :- !.
;flatten([Hd|Tl], Tail, List) :- !,
;	flatten(Hd, FlatHeadTail, List),
;	flatten(Tl, Tail, FlatHeadTail).
;flatten(NonList, Tl, [NonList|Tl]).


;(defun prolog-flatten3 (v tail list)
;  (one-value
;   (progn ; ?
;     (assert! (bound? v))
;     (assert! (equalv list (cons v tail))))
;   (one-value 
;    (progn
;      (assert! (equalv nil v))
;      (assert! (equalv tail list)))
;    (let ((hd (make-variable))
;          (tl (make-variable)))
;      (either 
;        (progn 
;          (assert! (equalv v (cons hd tl)))
;          (let ((fht (make-variable)))
;            (prolog-flatten3 hd fht list)
;            (prolog-flatten3 tl tail fht)))
;        (progn
;          (prolog-flatten3 v tail (cons v tail))))))))

; flatten([], Flattened, Flattened).
; flatten([Item|Tail], L, Flattened):-
;  flatten(Item, L1, Flattened),
;  flatten(Tail, L, L1).
; flatten(Item, Flattened, [Item|Flattened]):-
;  \+ is_list(Item).

(defun prolog-flatten3 (i l f)
  (either 
    (progn 
      (assert! (equalv nil i))
      (assert! (equalv l f)))
    (let ((i1 (make-variable))
          (i2 (make-variable))
          (f1 (make-variable))
          (l1 (make-variable)))
      (assert! (equalv i (cons i1 i2)))
      (assert! (equalv f f1))
      (prolog-flatten3 i1 l1 f1)
      (prolog-flatten3 i2 l l1))
    (progn 
      (assert! (equalv f (cons i l))))))

(defun pad-listsv (l m &optional p pad-fn)
  (let ((lc (make-variable))
        (lens (make-variable))
        (lmax (make-variable)))    
    (cons-atomsv l lc)    
    (prolog-maplist3 #'lengthv 
                     lc
                     lens)   
    (maxv2 lens lmax)
    ;(progn 
    ;  (print (list 'pad-listsv 'lc (apply-substitution lc)))
    ;  (print (list 'pad-listsv 'lens (apply-substitution lens)))
    ;  (print (list 'pad-listsv 'lmax (apply-substitution lmax))))
    (prolog-maplist3 (lambda (x)
                       (either 
                         (progn 
                           ;(print (list 10 'x x))
                           (assert! (=v (lengthv x) lmax))
                           x)
                         (progn  
                           (assert! (notv (=v (lengthv x) lmax)))
                           ;(print (list 15 'x x))              
                           (let ((p (if p
                                        p
                                      (let ((last (make-variable)))
                                        (prolog-last x last)
                                        (if pad-fn 
                                            (funcallv pad-fn last)
                                          last)))))
                             (let ((y (funcallv #'make-var-sequence (-v lmax (lengthv x)) p))
                                   (z (make-variable)))
                               (prolog-append x y z)
                               z)))))
                     lc
                     m)))


(defun prolog-subseq (sequence f l subseq &optional prcs-excluded)
  (assert! (integerpv f))
  (assert! (integerpv l))
  (let ((seqc-length (lengthv sequence)))
    (assert! (>=v f 0))
    (assert! (<=v f l))
    (assert! (<=v l seqc-length))
    (assert! (>=v (-v l f) 0))
    (assert! (<=v l (lengthv sequence)))
    (either 
      (progn 
        (assert! (notv (equalv nil subseq)))
        (assert! (<v f l))
        (let ((lf (-v l f))
              (r (-v seqc-length l)))    
          (assert! (>=v lf 0))  
          (assert! (>=v r 0))
          (let ((a (funcallv #'make-var-sequence f))
                (b (funcallv #'make-var-sequence lf))
                (c (funcallv #'make-var-sequence r))
                (ab (make-variable)))
            (prolog-append a b ab)
            (prolog-append ab c sequence)
            (either 
              (progn 
                (assert! (not (null prcs-excluded)))
                (prolog-append a c subseq))
              (progn 
                (assert! (equalv subseq b)))))))
      (progn 
        (assert! (=v f l))
        (equalv subseq nil)))))
;;	list_to_set(+List, ?Set) is det.
;
;	True when Set has the same elements  as  List in the same order.
; The left-most copy of the duplicate  is retained. The complexity
;	of this operation is |List|^2.
;
;	@see sort/2.
(defun prolog-remove-duplicates (list set)
  (let ((set0 (make-variable)))
    (prolog-remove-duplicates-internal list set0)
    (assert! (equalv set set0))))
(defun prolog-remove-duplicates-internal (list set)
  (print (list 'prolog-remove-duplicates-internal 'list list 'set set))
  (either
    (progn
      (assert! (equalv list nil))
      (prolog-close-list set))
    (let ((a (make-variable))
          (b (make-variable))
          (c (a-booleanv)))
      (assert! (equalv list (cons a b)))
      (assert! (equalv c (one-value (memberv a set) nil)))
      (either
       (progn 
         (assert! (equalv c t))
         (prolog-remove-duplicates-internal b set))
       (let ((set1 (make-variable)))     
         (prolog-insert a set set)
         (prolog-remove-duplicates-internal b set))))))
(defun prolog-close-list (list)
  (one-value
   (assert! (equalv list nil))
    (let ((a (make-variable))
          (b (make-variable)))
      (assert! (equalv list (cons a b)))
      (prolog-close-list b))))

(defun prolog-subset (x y)
  (either 
    (progn 
      (assert! (equalv nil x))
      (assert! (equalv nil y)))
    (progn 
      (let ((x1 (make-variable))
            (x2 (make-variable))
            (y1 (make-variable))
            (y2 (make-variable)))
        (assert! (equalv x (cons x1 x2)))
        (assert! (equalv x1 y1))
        (prolog-subset x2 y2)
        (either 
          (assert! (equalv y (cons y1 y2)))
          (assert! (equalv y y2)))))))

;  subset([X|R],S) :- member(X,S), subset(R,S).
;  subset([],_).
(defun prolog-subset? (x s)
  (either
    (let ((a (make-variable))
          (x1 (make-variable))
          (s1 (make-variable)))
      (assert! (equalv x (cons a x1)))
      (assert! (memberv a s))
      (prolog-subset x1 s))
    (progn 
      (assert! (equalv nil x))
      t)))

;(defun prolog-rotate-list (x y n) ; iffy
;  (let ((l (make-variable))
;        (r (make-variable))
;        (len (lengthv x)))
;    (prolog-subseq x 0 n l)
;    (prolog-subseq x n len r)
;    (prolog-append l r x)
;    (prolog-append r l y)))

(defun prolog-rotate (l r)
  (let ((a (make-variable))
        (b (make-variable)))
    (assert! (notv (equalv nil b)))
    (prolog-append b a l)
    (prolog-append a b r)))

; rotate(List, [H|R]):- rotate(List, R, H).
; rotate([H], [], H).
; rotate([H|T], [H|T1], R) :- rotate(T, T1, R). 
(defun prolog-rotate-list (l r)
  (let ((h (make-variable))
        (r1 (make-variable)))
    (assert! (equalv r (cons h r1)))
    (prolog-rotate-list3 l r1 h)))
(defun prolog-rotate-list3 (l r h)
  (either 
    (progn 
      (assert! (equalv r nil))
      (assert! (equalv l (cons h nil))))
    (let ((a  (make-variable))
          (l1 (make-variable))
          (r1 (make-variable)))
      (assert! (equalv l (cons a l1)))
      (assert! (equalv r (cons a r1)))
      (prolog-rotate-list3 l1 r1 h))))
  


(defun prolog-member? (e x s)
  (either
    (progn 
      (assert! (equalv nil x))
      (assert! (equalv s (equalv nil e))))
    (let ((x1 (make-variable))
          (x2 (make-variable)))
      (assert! (equalv x (cons x1 x2)))
      (one-value 
        (progn
          (assert! (equalv e x1))
          (assert! (equalv s t)))
        (prolog-member? e x2 s)))))

;  takeout(X,[X|R],R).
;  takeout(X,[F|R],[F|S]) :- takeout(X,R,S).
(defun prolog-takeout (x y z)
  (either 
    (progn 
      (assert! (equalv y (cons x z))))
    (let (;(x1 (make-variable))
          (y1 (make-variable))
          (z1 (make-variable))
          (a (make-variable)))
      ;(assert! (equalv x x1))
      (assert! (equalv y (cons a y1)))
      (assert! (equalv z (cons a z1)))
      (prolog-takeout x y1 z1))))

;  perm([X|Y],Z) :- perm(Y,W), takeout(X,Z,W).   
;  perm([],[]).
(defun prolog-perm (y z)
  (either 
    (progn 
      (assert! (equalv y nil))
      (assert! (equalv z nil)))
    (let ((w (make-variable))
          (x (make-variable))
          (y1 (make-variable)))
          ;(z1 (make-variable)))
      (assert! (equalv y (cons x y1)))
      ;(assert! (equalv z z1))
      (prolog-perm y1 w)
      (prolog-takeout x z w))))

(defun prolog-nperm (n y z &optional debug)
  (if (>= *mess* 30) (print (list 'prolog-nperm 'n n 'y (apply-substitution y) 'z (apply-substitution z))))
  (assert! (orv (equalv t debug)
                (<=v n (funcallv #'n! (lengthv (funcallv #'remove-duplicates (apply-substitution y)))))))
  (let ((tmp (funcallv #'make-sequence 'list (value-of n)))
        (a (make-variable)))
    (prolog-maplist3 (lambda (x)
                       (make-variable))
                     tmp
                     a)
    (prolog-maplist3 (lambda (x)
                       (progn
                         (prolog-perm y x)
                         x))
                     a
                     z)
    (prolog-all-distinctv? z t)))

(defun prolog-nperms-an-iteration-idx-list (n y)
  (let* ((s (prime-facts 0 (1- n) 1))
         (o (a-member-of (prime-facts 2 (1- n) 1)))
         (s1 (mapcar #'(lambda (x) 
                         (mod x n))
                     (prime-facts 0 (* n o) o))))
    (if (>= *mess* 20) (print (list 's s 's1 s1)))
   ; (if (and (> (length s) 5) (list-eq s s1)) (fail))
    (unless (or (< (length s) 5)
              (null (set-difference s s1))) (fail))
    s1))
    
    

(defun prolog-nperms (n y z &optional debug fail-form)
  (prolog-nperms4 n y z (an-integer-between 0 512) debug fail-form))

(defun prolog-nperms4 (n y z offset &optional debug fail-form)
  (assert! (orv (notv (equalv nil debug))
                (<=v n (funcallv #'n! (minv 10 (lengthv y))))))
  (let ((tmp (prolog-nperms-an-iteration-idx-list n y))
        (tmp1 (make-variable)))
    ;(print (list 'tmp tmp))
    (prolog+v3 tmp tmp1 offset)
    (prolog-maplist3 (lambda (x)
                       (ith-value x 
                                  (let ((a (make-variable)))
                                    (prolog-perm y a)
                                    (solution a (static-ordering #'divide-and-conquer-force)))
                                  fail-form))
                     tmp1
                     z)))


(defun prolog-insert (elem list1 list2)
  (either
    (progn
      (assert! (equalv list1 nil))
      (assert! (equalv list2 (cons elem nil))))
    (let ((h (make-variable))
          (l (make-variable))
          (r (make-variable)))
      (assert! (equalv list1 (cons h l)))
      (assert! (equalv list2 (cons h r)))
      (prolog-insert elem l r))))
                         
(defun prolog-select (elem list1 list2)
  (either
    (assert! (equalv list1 (cons elem list2)))
    (let ((h (make-variable))
          (l (make-variable))
          (r (make-variable)))
      (assert! (equalv list1 (cons h l)))
      (assert! (equalv list2 (cons h r)))
      (prolog-select elem l r))))

(defun prolog-perm2 (l hp)
  (either 
    (progn 
      (assert! (equalv l nil))
      (assert! (equalv hp nil)))
    (let ((h (make-variable))
          (p (make-variable))
          (nl (make-variable)))
      (assert! (equalv hp (cons h p)))
      (prolog-select h l nl)
      (prolog-perm3 nl h p))))

(defun prolog-perm3 (l h ip)
  (either 
    (progn
      (assert! (equalv l nil))
      (assert! (equalv ip nil)))
    (let ((i (make-variable))
          (p (make-variable))
          (nl (make-variable)))
      (assert! (equalv ip (cons i p)))
      (prolog-select i l nl)
      (prolog-perm3 nl i p))))                         

(defun all-distinctv? (x)
  (let ((var (make-variable)))
    (prolog-all-distinctv? x var)
    var))

(defun prolog-all-distinctv? (x s)
  (either 
    (progn 
      (assert! (funcallv #'atom x))
      (assert! (equalv s t)))    
    (prolog-all-distinctv?3 nil nil x s)))
  

(defun prolog-all-distinctv?3 (x y z s)  
  (if (>= *mess* 31) (print (list 'prolog-all-distinctv?3 
                                  'x (apply-substitution x)
                                  'y (apply-substitution y)
                                  'z (apply-substitution z)
                                  's (value-of s))))
  (either 
    (progn 
      (assert! (equalv y nil))
      (assert! (equalv z nil))
      (assert! (equalv s t))) 
    (progn 
      (assert! (equalv z nil))
      (assert! (equalv s (notv (memberv y x)))))
    (let ((x1 (make-variable))
          (y1 (make-variable))
          (z1 (make-variable))
          (s1 (make-variable)))
      (assert! (equalv z (cons y1 z1)))
      (assert! (equalv x1 (cons y x)))
      (prolog-all-distinctv?3 x1 y1 z1 s1)
      (assert! (equalv s (andv s1
                               (orv (equalv nil y)
                                    (andv (notv (memberv y x)) 
                                          (notv (memberv y z))))))))))

(defun prolog-maplist (fn list &rest args)
  (prolog-maplist-internal fn list args))
(defun prolog-maplist-internal (fn list args)
  (either 
    (progn 
      (assert! (equalv nil args))
      (assert! (equalv nil list)))
    (let ((a (make-variable))
          (b (make-variable))
          (c (make-variable))
          (list1 (make-variable)))
      (prolog-lists-firsts-rests args a b)
      (assert! (equalv c (funcall-nondeterministic fn a)))
      (prolog-append list1 c list)
      (prolog-maplist-internal fn list1 b))))

;(defun prolog-mapn (fn lists)
;  (either 
;    (let ((f (make-variable))
;          (r (make-variable)))
;      (prolog-lists-firsts-rests lists f r)
;      (funcall-nondeterministic fn f)
;      (prolog-mapn fn r))
;    nil))

; transpose(Ms, Ts) :- 
; must_be(list(list), Ms), 
;  ( Ms = [] -> Ts = [] 
;  ; Ms = [F|_], 
;    transpose(F, Ms, Ts)
;  ).
(defun prolog-mapn (fn ms)
  (either 
    (progn 
      (assert! (equalv ms nil))
      (assert! (equalv ts nil)))
    (let ((f (make-variable))
          (m1 (make-variable))
          (ts (make-variable)))
      (assert! (equalv ms (cons f m1)))
      (prolog-transpose ts ms)
      (prolog-mapnx fn f ms ts))))

;  transpose([], _, []). 
;  transpose([_|Rs], Ms, [Ts|Tss]) 
;    :-  lists_firsts_rests(Ms, Ts, Ms1), transpose(Rs, Ms1, Tss).
(defun prolog-mapnx (fn rs ms ts)
  (either 
    (progn 
      (assert! (equalv nil rs))
      (assert! (equalv nil ts)))
    (let ((r1 (make-variable))
          (r (make-variable))
          (m1 (make-variable))
          (t1 (make-variable))
          (tss (make-variable)))
      (assert! (equalv rs (cons r r1)))
      (assert! (equalv ts (cons t1 tss)))
      (prolog-lists-firsts-rests ms t1 m1)
      (funcall-nondeterministic fn t1)
      (prolog-mapnx fn r1 m1 tss))))

(defun prolog-map (fn list)
  (either 
    (assert! (equalv list nil))
    (let ((a (make-variable))
          (b (make-variable)))
      (assert! (equalv list (cons a b)))
      (funcall-nondeterministic fn a)
      (prolog-map fn b))))

(defun prolog-map2 (fn list1 list2)
  (either 
    (progn 
      (assert! (equalv list1 nil))
      (assert! (equalv list2 nil)))
    (let ((a (make-variable))
          (b (make-variable))
          (c (make-variable))
          (d (make-variable)))
      (assert! (equalv list1 (cons a b)))
      (assert! (equalv list2 (cons c d)))
      (funcall-nondeterministic fn a c)
      (prolog-map2 fn b d))))

(defun prolog-map3 (fn list1 list2 list3)
  (either 
    (progn 
      (assert! (equalv list1 nil))
      (assert! (equalv list2 nil))
      (assert! (equalv list3 nil)))
    (let ((a (make-variable))
          (b (make-variable))
          (c (make-variable))
          (d (make-variable))
          (e (make-variable))
          (f (make-variable)))
      (assert! (equalv list1 (cons a b)))
      (assert! (equalv list2 (cons c d)))
      (assert! (equalv list2 (cons e f)))
      (funcall-nondeterministic fn a c e)
      (prolog-map3 fn b d f))))
;  maplist(_C, [], []).
;  maplist( C, [X|Xs], [Y|Ys]) :-
;     call(C, X, Y),
;     maplist( C, Xs, Ys).
(defun prolog-maplist3 (fn x y)
  (either 
    (progn 
      (assert! (equalv nil x))
      (assert! (equalv nil y)))
    (let ((a (make-variable))
          (b (make-variable))
          (xs (make-variable))
          (ys (make-variable)))
      (assert! (equalv x (cons a xs)))
      (assert! (equalv y (cons b ys)))
      (assert! (equalv b (funcall-nondeterministic fn a)))
      (prolog-maplist3 fn xs ys))))

; heads_and_tails(0, [], [], []).
; heads_and_tails(N, [[H|T]|L1], [H|L2], [T|L3]) :-
; 	N2 is N - 1,
;	heads_and_tails(N2, L1, L2, L3).
(defun prolog-heads-and-tails (n l1 l2 l3)
  (either
    (progn 
      (assert! (equalv n 0))
      (assert! (equalv l1 nil))
      (assert! (equalv l2 nil))
      (assert! (equalv l3 nil)))
    (let ((n1 (-v n 1))
          (l1t (make-variable))
          (l2t (make-variable))
          (l3t (make-variable))
          (head (make-variable))
          (tail (make-variable)))
      (assert! (equalv l1 (cons (cons head tail) l1t)))
      (assert! (equalv l2 (cons head l2t)))
      (assert! (equalv l3 (cons tail l3t)))
      (prolog-heads-and-tails n1 l1t l2t l3t))))

(defun prolog-nth (n hr h r)
  (either
    (progn
      (assert! (=v n 0))
      (assert! (equalv hr (cons h r))))
    (let ((n1 (-v n 1))
          (a  (make-variable))
          (r0 (make-variable))
          (r1 (make-variable)))
      (assert! (equalv hr (cons a r0)))
      (assert! (equalv r  (cons a r1)))
      (prolog-nth n1 r0 h r1))))
(defun dolistv (fn l)
  (either 
    (assert! (equalv nil l))
    (let ((a (make-variable))
          (l1 (make-variable)))
      (assert! (equalv l (cons a l1)))
      (dolistv fn l1)      
      (funcall-nondeterministic fn a))))

;  maplist(_C, [], []).
;  maplist( C, [X|Xs], [Y|Ys]) :-
;     call(C, X, Y),
;     maplist( C, Xs, Ys).
(defun prolog-maplist3a (fn x y)
  (either 
    (progn 
      (assert! (equalv nil x))
      (assert! (equalv nil y)))
    (let ((a (make-variable))
          (b (make-variable))
          (xs (make-variable))
          (ys (make-variable)))
      (assert! (equalv x (cons a xs)))
      (assert! (equalv y (cons b ys)))
      (assert! (equalv b (funcallv fn a)))
      (prolog-maplist3a fn xs ys))))


(defun prolog-first (a b)  
  (let ((a1 (make-variable))
        (a2 (make-variable)))
    (one-value 
     (progn
       (assert! (notv (equalv a (cons a1 a2))))
       (assert! (equalv a b)))
     (progn 
       (assert! (equalv a (cons a1 a2)))
       (prolog-first a1 b)))))

(defun prolog-last (a b)
  (let* ((c (make-variable))
         (d (make-variable))
         (e (make-variable)))
    (prolog-reverse a e)
    (assert! (equalv e (cons c d)))
    (either 
      (progn
        (assert! (funcallv #'consp c))
        (prolog-last c b))
      (progn 
        (assert! (funcallv #'atom c))
        (assert! (equalv b c))))))

;  lists_firsts_rests([], [], []). 
;  lists_firsts_rests([[F|Os]|Rest], [F|Fs], [Os|Oss]) 
;    :- lists_firsts_rests(Rest, Fs, Oss).
(defun prolog-lists-firsts-rests (r f o)

  ; (if (= *mess* 31) (print (list 'prolog-lists-firsts-rests 'r r 'f f 'o o)))
  (either 
    (progn 
      (assert! (equalv r nil))
      (assert! (equalv f nil))
      (assert! (equalv o nil)))
    (let ((a (make-variable))
          (b (make-variable))
          (r1 (make-variable))
          (f1 (make-variable))
          (o1 (make-variable)))
      (assert! (equalv f (cons a f1)))
      (assert! (equalv o (cons b o1)))
      (assert! (equalv r (cons (cons a b) r1)))
      (prolog-lists-firsts-rests r1 f1 o1))))

; transpose(Ms, Ts) :- 
; must_be(list(list), Ms), 
;  ( Ms = [] -> Ts = [] 
;  ; Ms = [F|_], 
;    transpose(F, Ms, Ts)
;  ).
(defun prolog-transpose (ms ts)
  (either 
    (progn 
      (assert! (equalv ms nil))
      (assert! (equalv ts nil)))
    (let ((f (make-variable))
          (m1 (make-variable)))
      (assert! (equalv ms (cons f m1)))
      (prolog-transpose3 f ms ts))))
    
;  transpose([], _, []). 
;  transpose([_|Rs], Ms, [Ts|Tss]) 
;    :-  lists_firsts_rests(Ms, Ts, Ms1), transpose(Rs, Ms1, Tss).
(defun prolog-transpose3 (rs ms ts)
  (either 
    (progn 
      (assert! (equalv nil rs))
      (assert! (equalv nil ts)))
    (let ((r (make-variable))
          (r1 (make-variable))
          (m1 (make-variable))
          (t1 (make-variable))
          (tss (make-variable)))
      (assert! (equalv rs (cons r r1)))
      (assert! (equalv ts (cons t1 tss)))
      (prolog-lists-firsts-rests ms t1 m1)
      (prolog-transpose3 r1 m1 tss))))

(defun prolog-flatten-once (l f)
  (let ((f1 (make-variable)))
    (prolog-maplist3 (lambda (x)
                       (cond ((funcallv #'consp x) x)
                             (t (cons x nil))))
                     l
                     f1)
    (prolog-flatten-once-internal f1 f)))

(defun prolog-flatten-once-internal (l f)
  (either 
    (progn 
      (assert! (equalv l nil))
      (assert! (equalv f nil)))
    (let ((l1 (make-variable))
          (l2 (make-variable))
          (f1 (make-variable))
          (f2 (make-variable)))
      (assert! (equalv l (cons l1 l2)))
      (assert! (equalv l1 f1))    
      (prolog-append f1 f2 f)
      (prolog-flatten-once-internal l2 f2))))


(defun prolog-ordered? (m s &key key (order 'asc))
  (either 
    (progn 
      (assert! (equalv m nil))
      (assert! (equalv s nil)))
    (let ((l (make-variable))
          (r (make-variable))
          (l1 (make-variable))
          (r1 (make-variable))
          (m1 (make-variable))
          (s1 (make-variable))
          (s2 (make-variable)))
      (assert! (equalv m (cons l (cons r m1))))
      (cond (key 
             (assert! (equalv l1 (funcallv key l)))
             (assert! (equalv r1 (funcallv key r))))
            (t 
             (assert! (equalv l1 l))
             (assert! (equalv r1 r))))                
      (assert! (realpv l1))
      (assert! (realpv r1))
      (cond ((eq order 'asc) 
             (assert! (equalv s1 (<=v l1 r1))))
            (t 
             (assert! (equalv s1 (>=v l1 r1)))))
      (either 
        (progn 
          (assert! (notv (equalv m1 nil)))
          (prolog-ordered? (cons r m1) s2 :key key :order order))
        (progn 
          (assert! (equalv m1 nil))
          (assert! (equalv s2 t))))
      (assert! (equalv s (andv s1 s2))))))

(defun prolog-quicksort (l s &key key)
  ;(if (>= *mess* 20) (print (list 'prolog-quicksort 'l l 's s)))
  (either 
    (progn 
      (assert! (equalv l nil))
      (assert! (equalv s nil)))
    (let ((a (make-variable))
          (b (make-variable))
          (sl  (make-variable))
          (sl1 (make-variable))
          (bl  (make-variable))
          (bl1 (make-variable))
          (ab1 (make-variable)))
      (assert! (equalv l (cons a b)))
      (assert! (equalv ab1 (cons a bl1)))
      (prolog-split a b sl bl :key key)
      (prolog-quicksort sl sl1 :key key)
      (prolog-quicksort bl bl1 :key key)
      (prolog-concatenate sl1 ab1 s))))

;(defun prolog-split (i ht sl bl &key key)
  ;(if (>= *mess* 20) (print (list 'prolog-split 'i i 'ht ht 'sl sl 'bl bl)))
;  (either 
;    (progn 
;      (assert! (equalv ht nil))
;      (assert! (equalv sl nil))
;      (assert! (equalv bl nil)))
;    (let ((h1  (make-variable))
;          (t1  (make-variable))
;          (sl1 (make-variable)))
;      (assert! (equalv ht (cons h1 t1))) 
;      (assert! (equalv sl (cons h1 sl1)))
;      (one-value 
;       (cond (key
;              (assert! (>v (funcallv key i) 
;                           (funcallv key h1))))
;             (t
;              (assert! (>v i h1))))
;       (prolog-split i t1 sl1 bl :key key)))
;    (let ((h1  (make-variable))
;          (t1  (make-variable))
;          (bl1 (make-variable)))
;      (assert! (equalv ht (cons h1 t1))) 
;      (assert! (equalv bl (cons h1 bl1)))
;      (prolog-split i t1 sl1 bl :key key))))
(defun prolog-split (i ht sl bl &key key)
  ;(if (>= *mess* 20) (print (list 'prolog-split 'i i 'ht ht 'sl sl 'bl bl)))
  (either 
    (progn 
      (assert! (equalv ht nil))
      (assert! (equalv sl nil))
      (assert! (equalv bl nil)))
    (let ((h1  (make-variable))
          (t1  (make-variable))
          (sl1 (make-variable)))
      (assert! (equalv ht (cons h1 t1))) 
      (either 
        (let ((sl1 (make-variable)))
          (assert! (equalv sl (cons h1 sl1)))
          (cond (key
                 (assert! (>=v (funcallv key i) 
                               (funcallv key h1))))
                (t
                 (assert! (>=v i h1))))
          (prolog-split i t1 sl1 bl :key key))
        (let ((bl1 (make-variable)))
          (assert! (equalv bl (cons h1 bl1)))
          (cond (key
                 (assert! (<v (funcallv key i) 
                              (funcallv key h1))))
                (t
                 (assert! (<v i h1))))
          (prolog-split i t1 sl bl1 :key key))))))

(defun prolog-concatenate (x y z)
  ;(if (>= *mess* 20) (print (list 'prolog-concatenate 'x x 'y y 'z z)))
  (either 
    (progn 
      (assert! (equalv x nil))
      (assert! (equalv y z)))
    (let ((a (make-variable))
          (x1 (make-variable))
          ;(y1 (make-variable))
          (z1 (make-variable)))
      (assert! (equalv x (cons a x1)))
      ;(assert! (equalv y y1))
      (assert! (equalv z (cons a z1)))
      (prolog-concatenate x1 y z1))))


(defun eltv (sequence index seqc2) ;iiffy
  (either 
    (progn 
      (assert! (equalv index nil))
      (assert! (equalv seqc2 nil))
      nil)
    (progn
      (assert! (=v index 0))
      (prolog-first sequence seqc2)
      t)
    (let ((a (make-variable))
          (seq1 (make-variable)))
      (assert! (equalv sequence (cons a seq1)))
      (eltv seq1 (-v index 1) seqc2))))

(defun countv (obj &optional (nil-equals-zero t))
  (let ((n (an-integerv)))
    (countv2 obj n nil-equals-zero)
    n))

(defun countv2 (obj n &optional (nil-equals-zero t))
  (cond ((funcallv #'null obj)
         (assert! (=v n (if nil-equals-zero 0 1))))
        ((funcallv #'consp obj)
         (let ((n1 (an-integerv))
               (n2 (an-integerv)))
           (countv2 (funcallv #'car obj) n1 nil-equals-zero)
           (countv2 (funcallv #'cdr obj) n2 nil-equals-zero)
           (assert! (=v n (+v n1 n2)))))
        (t (assert! (=v n 1)))))

(defun lengthv2 (obj n)
  (assert! (integerpv n))
  (cond ((funcallv #'null obj)
         (assert! (=v n 0)))
        ((funcallv #'consp obj)
         (let ((n1 (an-integerv)))
           (lengthv2 (funcallv #'cdr obj) n1)
           (assert! (=v n (+v n1 1)))))
        (t (assert! (=v n 1)))))

(defun has-consv (sequence)
  (let ((var (make-variable)))
    (prolog-has-consv sequence var)
    var))

(defun prolog-has-consv (sequence has-cons)
  (assert! (memberv has-cons (list t nil)))
  (either
    (progn 
      (assert! (equalv nil sequence))
      (assert! (equalv nil has-cons)))
    (progn
      (let ((s1 (make-variable))
            (s2 (make-variable)))
        (either 
          (progn 
            (assert! (equalv sequence (cons s1 s2)))
            (either 
              (progn 
                (assert! (funcallv #'consp s1))
                (assert! (equalv has-cons t)))
              (let ((h1 (make-variable)))
                (assert! (funcallv #'atom s1))
                (prolog-has-consv s2 h1)
                (assert! (equalv has-cons h1)))))          
          (progn 
            (assert! (funcallv #'atom sequence))
            (assert! (equalv has-cons nil))))))))

(defun list-eltv (sequence index-list list) ; iffy
  (let* ((a (make-variable))
         (b (prolog-reverse index-list a)))
    (list-eltv-internal sequence a list)))

(defun list-eltv-internal (sequence index-list list)
  (either 
    (progn 
      (assert! (equalv index-list nil))
      nil)
    (let ((index-list1 (make-variable))
          (index (make-variable))
          (elem (make-variable))
          (list1 (make-variable)))
      (let ((a (eltv sequence index elem)))
        (assert! (equalv index-list (cons index index-list1)))
        (let ((b (prolog-append list1 (list elem) list)))
          (assert! (notv (equalv elem nil)))
          (list-eltv-internal sequence index-list1 list1))))))


(defun a-subset-of (x)
  (if (null x)
      nil
      (let ((y (a-subset-of (rest x)))) 
        (either (cons (first x) y) y))))

(defun a-subset-size= (x size)
  (let ((r (a-subset-of x)))
    (if (or (null r)
            (not (= (length r) size)))
        (fail)
      r)))

(defun a-permutation-of (list)
  (if (null list)
      nil
    (let ((i (an-integer-between 0 (1- (length list)))))
      (append (list (elt list i))
              (a-permutation-of 
               (append (subseq list 0 i)
                       (subseq list (1+ i) (length list))))))))

(defun a-permutation-ofv (list &key symbol-mode)
  (let ((vars (mapcar #'(lambda (x) 
                          (let ((v (an-integerv)))
                            (assert! (memberv v list))
                            v))
                      list))
        (perms (all-values (a-permutation-of list))))
    (assert! (reduce-chunks 
              #'orv                            
              (mapcar #'(lambda (p) (lists=v p vars))
                      perms)))
    vars))

(defun takeout (x y &key (test #'list-eq))
  (cond ((not (position x y :test test)) y)
        (t 
         (let ((p (a-partition-of y)))
           (unless (= (length p) 2) (fail))
           (either 
             (progn 
               (unless (funcall test x (caadr p)) (fail))
               (append (print (car p)) (print (cdadr p))))
             (progn
               (unless (funcall test x (car (reverse (car p)))) (fail))
               (append (reverse (cdr (reverse (car p))))
                       (cadr p))))))))
  
(defun a-partition-of (x)
  (if (null x)
      x
    (let ((y (a-partition-of (rest x))))
      (either
        (cons (list (first x)) y)
        (let ((z (a-member-of y)))
          (cons (cons (first x) z) (remove z y :test #'eq :count 1)))))))

(defun an-ordered-partition-of (x)
  (cond ((null x) nil)
        ((null (cdr x)) (list x))
        (t 
         (let ((y (an-ordered-partition-of (rest x))))
           (either
             (cons (list (first x)) y)
             (cons (cons (first x) (first y)) (rest y)))))))

(defun a-partition-having (x &optional partition-fn element-fn)
  (let ((a (a-partition-of x)))
    (unless (evaluate a partition-fn) (fail))   
    (unless 
        (dolist (y a) 
          (if (null y) (return t))
          (if (null (evaluate y element-fn)) (return nil)))
      (fail))
    a))

(defun list-random-members-of (list templates)
  (cond
   ((null list) nil)
   (t
    (append
     (list (a-random-member-of templates))
     (list-random-members-of (cdr list) templates)))))


(defun a-powerset-member-of (s sets)
  (let ((p (a-member-of sets)))
    (if (or (null p)
            (null (set-difference s (set-difference s p))))
        (fail)
      p)))

(defun powerset-members-of (s sets)
  (let* ((ps (a-subset-of (all-values (a-powerset-member-of s sets)))))
    (if (or (null ps)
            (not (null (set-difference s (flat ps)))))
        (fail)
      ps)))
           
(cl:defun print-warnings-level (level)
  (setf *mess* level))

(cl:defun split-sublists (ll)
  (mapcar 't2l::split ll))

(cl:defun split (ll) 
  (cond ((> (length ll) 1)
         (append (list (reverse (cdr (reverse ll))))
                 (list (list (car (reverse ll))))))
        ((> (length ll) 0)
         (list ll))
        (t ll)))


(defun apply-cps (fn vars)
  (cond ((null fn) vars)
        ((listp fn) (apply-fns (cdr fn) 
                               (apply-fns (car fn) vars)))
        (t (funcall fn vars))))

(defmacro macro1 (sym &rest args)
  `(print (list ,@args)))

(defun evaluate (input r)
  (cond ((null r) t)
        ((consp r)
         (and (evaluate input (car r))
              (evaluate input (cdr r))))
        ((functionp r)
         (funcall r input))
        (t nil)))

(defun an-expanded-list (templates rules &key randomize-choices)
  (let ((r (solution (an-expanded-list-rec 1 templates :randomize-choices randomize-choices)
                     (static-ordering #'linear-force))))
    (unless (evaluate r rules) (fail))
    r))

(defun an-expanded-list-rec (len templates &key randomize-choices)
  (either    
    (mapcar #'(lambda (x) (if randomize-choices (a-random-member-ofv templates) (a-member-ofv templates))) (make-sequence 'list len))
    (an-expanded-list-rec (1+ len) templates :randomize-choices randomize-choices)))

#|(defun embed-internal (input templates level levels)
  (cond
   ((< level levels)
    (cond
     ((null input) nil)
     ((atom input) (embed-internal (a-random-member-of templates)
                                   templates
                                   (1+ level)
                                   levels))
     (t (append
         (list (embed-internal (car input)
                               templates
                               level
                               levels))
         (embed-internal (cdr input)
                         templates
                         level
                         levels)))))
   (t input)))|#

(defun embed-internal (input templates level levels)
  (cond
   ((< level levels)
    (embed-internal (cond
                     ((null input) (a-random-member-of templates))
                     ((atom input) (a-random-member-of templates))
                     (t (funcall-nondeterministic-rec #'(lambda (x) (a-random-member-of templates)) input)))
                    templates
                    (1+ level)
                    levels))
   (t input)))

(defun embed (input templates &key (levels 2) test)
  (let ((list (embed-internal input templates 0 levels)))
    (unless (cond
             ((null test) t)
             ((listp test) (funcall (a-member-of test) list))
             (t (funcall test list)))
      (fail))
    list))
                

(defun lsubs1-members-of (lists)
  (if (null lists)
      nil
    (append (list (a-member-of (car lists)))
            (lsubs1-members-of (cdr lists)))))           

(defun lsubs1 (lists predicate &optional (r 0.5))
  (let ((is (mapcar
             #'(lambda (x) (arithm-ser x (floor (* r x)) -1))
             (mapcar #'length lists))))
    (let* ((cards (permut-random 
                    (all-values (lsubs1-members-of is))))
           (c (a-member-of cards))
           (l (mapcar #'(lambda (i x) (subseq x 0 i)) c lists)))
      (if predicate (funcall predicate l))
      l)))

(defun print-divide-and-conquer-force (x)
  "print messages when t2l::*mess* >= 30"
  (if (>= *mess* 30) (print (format nil "divide-and-conquer-force IN: ~A" x)))
  (let ((y (linear-force x)))
    (if (>= *mess* 30) (print (format nil "divide-and-conquer-force OUT: ~A~%" y)))
    y))

(defun print-linear-force (x)
  "print messages when t2l::*mess* >= 30"
  (if (>= *mess* 30) (print (format nil "linear-force IN: ~A" x)))
  (linear-force x)
  (if (>= *mess* 30) (print (format nil "linear-force OUT: ~A ~%" x)))
  x)

(defun print-screamer-info (arg)
  (lprint 'screamer-version *screamer-version*)
  (lprint "  " 'screamer? screamer::*screamer?* 'nondeterministic-context? screamer::*nondeterministic-context?* 'local? screamer::*local?* 'dynamic-extent? *dynamic-extent?* 'iscream? screamer::*iscream?*)
  (lprint "  " 'function-record-table (hash-table-count screamer::*function-record-table*))
  (lprint "  " 'trail (length screamer::*trail*))
  arg)