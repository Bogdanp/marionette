#lang racket/base

(require racket/contract)

(provide
 (contract-out
  [struct rect ([x exact-integer?]
                [y exact-integer?]
                [w real?]
                [h real?])]))

(struct rect (x y w h)
  #:transparent)
