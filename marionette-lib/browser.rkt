#lang racket/base

(require racket/contract/base
         racket/match
         racket/string
         "capabilities.rkt"
         "page.rkt"
         "private/browser.rkt"
         "private/marionette.rkt"
         "timeouts.rkt")

(provide
 (contract-out
  [browser? (-> any/c boolean?)] ;; noqa
  [browser-connect! (->* []
                         [#:host non-empty-string?
                          #:port (integer-in 1 65535)
                          #:capabilities capabilities?]
                         browser?)]
  [browser-disconnect! (-> browser? void?)]
  [browser-timeouts (-> browser? timeouts?)]
  [set-browser-timeouts! (-> browser? timeouts? void?)]
  [browser-viewport-size (-> browser? (values exact-nonnegative-integer?
                                              exact-nonnegative-integer?))]
  [set-browser-viewport-size! (-> browser? exact-nonnegative-integer? exact-nonnegative-integer? void?)]
  [make-browser-page! (-> browser? page?)]
  [browser-capabilities (-> browser? capabilities?)]
  [browser-pages (-> browser? (listof page?))]
  [browser-focus! (-> browser? page? void?)]))

(define (browser-connect! #:host [host "127.0.0.1"]
                          #:port [port 2828]
                          #:capabilities [caps (make-capabilities)])
  (define m (make-marionette host port))
  (marionette-connect! m caps)
  (browser m #f))

(define (browser-disconnect! b)
  (marionette-disconnect! (browser-marionette b)))

(define (call-with-browser-script! b s [p values])
  (sync
   (handle-evt
    (marionette-execute-script! (browser-marionette b) s)
    (match-lambda
      [(hash-table ('value value))
       (p value)]))))

(define (browser-timeouts b)
  (sync
   (handle-evt
    (marionette-get-timeouts! (browser-marionette b))
    (match-lambda
      [(hash-table ('script script)
                   ('pageLoad page-load)
                   ('implicit implicit))
       (timeouts script page-load implicit)]))))

(define (set-browser-timeouts! b timeouts)
  (void
   (sync
    (marionette-set-timeouts! (browser-marionette b)
                              (timeouts-script timeouts)
                              (timeouts-page-load timeouts)
                              (timeouts-implicit timeouts)))))

(define (browser-viewport-size b)
  (call-with-browser-script! b
    "return [window.innerWidth, window.innerHeight]"
    (λ (size)
      (apply values size))))

(define (set-browser-viewport-size! b width height)
  (define-values (dx dy)
    (call-with-browser-script! b
      "return [window.outerWidth - window.innerWidth, window.outerHeight - window.innerHeight]"
      (λ (size)
        (apply values size))))

  (void
   (sync
    (marionette-set-window-rect! (browser-marionette b)
                                 (+ width dx)
                                 (+ height dy)))))

(define (make-browser-page! b)
  (sync
   (handle-evt
    (marionette-new-window! (browser-marionette b))
    (lambda (res)
      (define p (make-page b (hash-ref res 'handle)))
      (begin0 p
        (browser-focus! b p))))))

(define (browser-capabilities b)
  (sync
   (handle-evt
    (marionette-get-capabilities! (browser-marionette b))
    (match-lambda
      [(or (hash-table ['capabilities caps])
           (hash-table ['value (hash-table ['capabilities caps])]))
       (jsexpr->capabilities caps)]))))

(define (browser-pages b)
  (for/list ([id (in-list (sync (marionette-get-window-handles! (browser-marionette b))))])
    (make-page b id)))

(define (browser-focus! b p)
  (void (sync (marionette-switch-to-window! (browser-marionette b) (page-id p))))
  (set-browser-current-page! b p))
