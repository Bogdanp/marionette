#lang racket/base

(require racket/contract
         racket/string
         "browser.rkt"
         "element.rkt"
         "page.rkt"
         "rect.rkt"
         "timeouts.rkt"

         "private/marionette.rkt")
(provide
 (all-from-out "browser.rkt"
               "element.rkt"
               "page.rkt"
               "rect.rkt"
               "timeouts.rkt")

 exn:fail:marionette?
 exn:fail:marionette:command?
 exn:fail:marionette:command-stacktrace

 call-with-browser!
 call-with-page!)

(define/contract (call-with-browser! p
                   #:host [host "127.0.0.1"]
                   #:port [port 28282])
  (->* ((-> browser? any/c))
       (#:host non-empty-string?
        #:port (integer-in 1 65535))
       any/c)

  (define b #f)
  (dynamic-wind
    (lambda _
      (set! b (browser-connect!)))
    (lambda _
      (p b))
    (lambda _
      (browser-disconnect! b))))

(define/contract (call-with-page! b p)
  (-> browser? (-> page? any/c) any/c)
  (define page #f)
  (dynamic-wind
    (lambda _
      (set! page (make-browser-page! b)))
    (lambda _
      (p page))
    (lambda _
      (page-close! page))))
