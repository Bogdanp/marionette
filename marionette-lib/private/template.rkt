#lang racket/base

(require racket/port
         scribble/text)

(provide
 template)

(define-syntax-rule (template path)
  (with-output-to-string
    (lambda ()
      (output (include/text path)))))
