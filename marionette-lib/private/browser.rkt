#lang racket/base

(provide
 (struct-out browser)
 browser-current-page=?)

(struct browser (marionette [current-page #:mutable] capabilities))

(define (browser-current-page=? b p)
  (eq? (browser-current-page b) p))
