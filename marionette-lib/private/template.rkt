#lang racket/base

(require racket/port
         scribble/text)

(provide
 template in)

(define-syntax-rule (template path)
  (with-output-to-string
    (lambda ()
      (output (include/text path)))))

(define-syntax in
  (syntax-rules ()
    [(_ x xs e ...)
     (add-newlines
      (for/list ([x xs])
        (begin/text e ...)))]))
