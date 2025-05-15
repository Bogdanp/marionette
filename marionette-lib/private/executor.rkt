#lang racket/base

(require "marionette.rkt")

(provide
 executor)

(define executor
  (make-will-executor))

(void
 (parameterize ([current-namespace (make-base-empty-namespace)])
   (thread/suspend-to-kill
    (lambda ()
      (let loop ()
        (with-handlers ([exn:fail?
                         (lambda (e)
                           (log-marionette-error "will executor: ~a" (exn-message e)))])
          (will-execute executor))
        (loop))))))
