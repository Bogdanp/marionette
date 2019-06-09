#lang racket/base

(require json
         racket/contract
         "timeouts.rkt")

(provide
 make-capabilities
 capabilities?
 capabilities->jsexpr)

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

(define/contract (capabilities->jsexpr c)
  (-> capabilities? jsexpr?)
  (hasheq 'timeouts (hasheq 'script (timeouts-script (capabilities-timeouts c))
                            'pageLoad (timeouts-page-load (capabilities-timeouts c))
                            'implicit (timeouts-implicit (capabilities-timeouts c)))
          'pageLoadStrategy (capabilities-page-load-strategy c)
          'unhandledPromptBehavior (capabilities-unhandled-prompt-behavior c)
          'acceptInsecureCerts (capabilities-accept-insecure-certs? c)))
