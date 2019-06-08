#lang racket/base

(provide box-swap!)

(define (box-swap! b p)
  (let loop ([value (unbox b)])
    (unless (box-cas! b value (p value))
      (loop (unbox b)))))
