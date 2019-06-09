#lang racket/base

(require racket/contract
         racket/function
         racket/list
         racket/match
         racket/string
         "capabilities.rkt"
         "page.rkt"
         "private/marionette.rkt"
         "timeouts.rkt")

(provide
 browser?
 browser-connect!
 browser-disconnect!

 browser-timeouts
 set-browser-timeouts!

 browser-viewport-size
 set-browser-viewport-size!

 make-browser-page!
 browser-pages
 browser-focus!)

(struct browser (marionette))

(define/contract (browser-connect! #:host [host "127.0.0.1"]
                                   #:port [port 2828]
                                   #:capabilities [capabilities (make-capabilities)])
  (->* ()
       (#:host non-empty-string?
        #:port (integer-in 1 65535)
        #:capabilities capabilities?)
       browser?)

  (define marionette (make-marionette host port))
  (marionette-connect! marionette (capabilities->jsexpr capabilities))
  (browser marionette))

(define/contract (browser-disconnect! b)
  (-> browser? void?)
  (marionette-disconnect! (browser-marionette b)))

(define (call-with-browser-script! b s [p identity])
  (sync
   (handle-evt
    (marionette-execute-script! (browser-marionette b) s)
    (match-lambda
      [(hash-table ('value value))
       (p value)]))))

(define/contract (browser-timeouts b)
  (-> browser? timeouts?)
  (sync
   (handle-evt
    (marionette-get-timeouts! (browser-marionette b))
    (match-lambda
      [(hash-table ('script script)
                   ('pageLoad page-load)
                   ('implicit implicit))
       (timeouts script page-load implicit)]))))

(define/contract (set-browser-timeouts! b timeouts)
  (-> browser? timeouts? void?)
  (void
   (sync
    (marionette-set-timeouts! (browser-marionette b)
                              (timeouts-script timeouts)
                              (timeouts-page-load timeouts)
                              (timeouts-implicit timeouts)))))

(define/contract (browser-viewport-size b)
  (-> browser? (values exact-nonnegative-integer?
                       exact-nonnegative-integer?))
  (call-with-browser-script! b
    "return [window.innerWidth, window.innerHeight]"
    (curry apply values)))

(define/contract (set-browser-viewport-size! b width height)
  (-> browser? exact-nonnegative-integer? exact-nonnegative-integer? void?)

  (define-values (dx dy)
    (call-with-browser-script! b
      "return [window.outerWidth - window.innerWidth, window.outerHeight - window.innerHeight]"
      (curry apply values)))

  (void
   (sync
    (marionette-set-window-rect! (browser-marionette b)
                                 (+ width dx)
                                 (+ height dy)))))

(define/contract (make-browser-page! b)
  (-> browser? page?)
  (call-with-browser-script! b "window.open()")
  (define p (last (browser-pages b)))
  (begin0 p
    (browser-focus! b p)))

(define/contract (browser-pages b)
  (-> browser? (listof page?))
  (define ids
    (sync
     (marionette-get-window-handles! (browser-marionette b))))

  (for/list ([id (in-list ids)])
    (make-page id (browser-marionette b))))

(define/contract (browser-focus! b p)
  (-> browser? page? void?)
  (void (sync (marionette-switch-to-window! (browser-marionette b) (page-id p)))))
