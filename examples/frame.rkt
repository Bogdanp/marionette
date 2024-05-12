#lang racket/base

(require marionette
         racket/runtime-path)

(define-runtime-path frame.html
  "frame.html")

(call-with-marionette/browser/page!
 (lambda (p)
   (page-goto! p (format "file:///~a" frame.html))
   (page-switch-to-frame! p (page-query-selector! p "iframe"))
   (eprintf "frame h1: ~s~n" (element-text (page-query-selector! p "h1")))
   (page-switch-to-parent-frame! p)
   (eprintf "outer h1: ~s~n" (page-query-selector! p "h1"))))
