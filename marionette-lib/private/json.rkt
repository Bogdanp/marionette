#lang racket/base

(require (for-syntax racket/base)
         json
         racket/match)

(provide
 json-null?
 js-null)

(define (json-null? v)
  (eq? v (json-null)))

(define-match-expander js-null
  (lambda (stx)
    (syntax-case stx ()
      [(_) #'(? json-null?)])))
