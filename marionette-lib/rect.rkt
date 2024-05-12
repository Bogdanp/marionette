#lang racket/base

(require racket/contract/base)

(provide
 (contract-out
  [struct rect ([x real?]
                [y real?]
                [w real?]
                [h real?])]))

(struct rect (x y w h)
  #:transparent)
