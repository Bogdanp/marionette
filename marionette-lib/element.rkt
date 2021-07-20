#lang racket

;; For backwards-compatibility in case anyone was requring the module directly.

(require racket/provide
         "page.rkt")

(provide
 (filtered-out
  (λ (name)
    (and (or (regexp-match? #rx"^element" name)
             (regexp-match? #rx"^call-with-element" name))
         name))
  (all-from-out "page.rkt")))
