#lang racket/base

(require racket/contract)

(provide
 (contract-out
  [struct rect ([x real?]
                [y real?]
                [w real?]
                [h real?])]))

(struct rect (x y w h)
  #:transparent)
