#lang racket/base

(require json
         racket/contract/base
         "timeouts.rkt")

(provide
 page-load-strategy/c
 unhandled-prompt-behavior/c

 (contract-out
  [struct capabilities ([timeouts timeouts?]
                        [page-load-strategy page-load-strategy/c]
                        [unhandled-prompt-behavior unhandled-prompt-behavior/c]
                        [accept-insecure-certs? boolean?])]
  [make-capabilities (->* []
                          [#:timeouts timeouts?
                           #:page-load-strategy page-load-strategy/c
                           #:unhandled-prompt-behavior unhandled-prompt-behavior/c
                           #:accept-insecure-certs? boolean?]
                          capabilities?)]
  [jsexpr->capabilities (-> jsexpr? capabilities?)]))

(define page-load-strategy/c
  (or/c 'none 'eager 'normal "none" "eager" "normal"))

(define unhandled-prompt-behavior/c
  (or/c 'dismiss
        'dimsiss-and-notify
        'accept
        'accept-and-notify
        'ignore
        "dismiss"
        "dismiss and notify"
        "accept"
        "accept and notify"
        "ignore"))

(struct capabilities
  (timeouts
   page-load-strategy
   unhandled-prompt-behavior
   accept-insecure-certs?)
  #:transparent)

(define (make-capabilities #:timeouts [timeouts (make-timeouts)]
                           #:page-load-strategy [page-load-strategy 'normal]
                           #:unhandled-prompt-behavior [unhandled-prompt-behavior 'dismiss-and-notify]
                           #:accept-insecure-certs? [accept-insecure-certs? #f])
  (capabilities timeouts
                (pls->string page-load-strategy)
                (upb->string unhandled-prompt-behavior)
                accept-insecure-certs?))

(define (jsexpr->capabilities data)
  (define timeouts-data (hash-ref data 'timeouts))
  (make-capabilities #:timeouts (make-timeouts #:script (hash-ref timeouts-data 'script)
                                               #:page-load (hash-ref timeouts-data 'pageLoad)
                                               #:implicit (hash-ref timeouts-data 'implicit))
                     #:page-load-strategy (hash-ref data 'pageLoadStrategy)
                     #:unhandled-prompt-behavior (hash-ref data 'unhandledPromptBehavior)
                     #:accept-insecure-certs? (hash-ref data 'acceptInsecureCerts)))

(define (pls->string s)
  (if (symbol? s) (symbol->string s) s))

(define (upb->string s)
  (case s
    [(dismiss accept ignore) (symbol->string s)]
    [(dismiss-and-notify) "dismiss and notify"]
    [(accept-and-notify) "accept and notify"]
    [else s]))
