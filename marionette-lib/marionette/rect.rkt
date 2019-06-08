#lang racket/base

(require racket/contract)

(provide
 (contract-out
  [struct rect ([x exact-integer?]
                [y exact-integer?]
                [w exact-nonnegative-integer?]
                [h exact-nonnegative-integer?])]))

(struct rect (x y w h)
  #:transparent)
