#lang racket/base

(require marionette
         rackunit/text-ui)

(provide
 run-integration-tests)

(define (run-integration-tests . args)
  (when (equal? (getenv "MARIONETTE_INTEGRATION_TESTS") "x")
    (call-with-marionette!
     (lambda _
       (apply run-tests args)))))
