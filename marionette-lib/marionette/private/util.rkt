#lang racket/base

(require (for-syntax racket/base)
         json
         racket/match)

(provide
 box-swap!
 json-null?
 js-null)

(define (box-swap! b p)
  (let loop ([value (unbox b)])
    (unless (box-cas! b value (p value))
      (loop (unbox b)))))

(define (json-null? v)
  (eq? v (json-null)))

(define-match-expander js-null
  (lambda (stx)
    (syntax-case stx ()
      [(_)
       #'(? json-null?)])))
