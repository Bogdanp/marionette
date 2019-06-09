#lang racket/base

(require json
         racket/contract
         "timeouts.rkt")

(provide
 (contract-out
  [struct capabilities ([timeouts timeouts?]
                        [page-load-strategy page-load-strategy/c]
                        [unhandled-prompt-behavior unhandled-prompt-behavior/c]
                        [accept-insecure-certs? boolean?])])

 make-capabilities
 jsexpr->capabilities)

(define page-load-strategy/c
  (or/c "none" "eager" "normal"))

(define unhandled-prompt-behavior/c
  (or/c "dismiss"
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

(define/contract (make-capabilities #:timeouts [timeouts (make-timeouts)]
                                    #:page-load-strategy [page-load-strategy "normal"]
                                    #:unhandled-prompt-behavior [unhandled-prompt-behavior "dismiss and notify"]
                                    #:accept-insecure-certs? [accept-insecure-certs? #f])
  (->* ()
       (#:timeouts timeouts?
        #:page-load-strategy page-load-strategy/c
        #:unhandled-prompt-behavior unhandled-prompt-behavior/c
        #:accept-insecure-certs? boolean?)
       capabilities?)
  (capabilities timeouts
                page-load-strategy
                unhandled-prompt-behavior
                accept-insecure-certs?))

(define/contract (jsexpr->capabilities data)
  (-> jsexpr? capabilities?)
  (define timeouts-data (hash-ref data 'timeouts))
  (make-capabilities #:timeouts (make-timeouts #:script (hash-ref timeouts-data 'script)
                                               #:page-load (hash-ref timeouts-data 'pageLoad)
                                               #:implicit (hash-ref timeouts-data 'implicit))
                     #:page-load-strategy (hash-ref data 'pageLoadStrategy)
                     #:unhandled-prompt-behavior (hash-ref data 'unhandledPromptBehavior)
                     #:accept-insecure-certs? (hash-ref data 'acceptInsecureCerts)))
