#lang racket/base

(require rackunit/text-ui)

(provide
 run-integration-tests)

(define (run-integration-tests . args)
  (when (equal? (getenv "MARIONETTE_INTEGRATION_TESTS") "x")
    (apply run-tests args)))
