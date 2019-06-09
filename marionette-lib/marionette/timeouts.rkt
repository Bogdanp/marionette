#lang racket/base

(require json
         racket/contract)

(provide
 (contract-out
  [struct timeouts ([script exact-nonnegative-integer?]
                    [page-load exact-nonnegative-integer?]
                    [implicit exact-nonnegative-integer?])])

 make-timeouts
 timeouts->jsexpr)

(struct timeouts (script page-load implicit)
  #:transparent)

(define/contract (make-timeouts #:script [script 30000]
                                #:page-load [page-load 300000]
                                #:implicit [implicit 0])
  (->* ()
       (#:script exact-nonnegative-integer?
        #:page-load exact-nonnegative-integer?
        #:implicit exact-nonnegative-integer?)
       timeouts?)
  (timeouts script page-load implicit))

(define/contract (timeouts->jsexpr t)
  (-> timeouts? jsexpr?)
  (hasheq 'script (timeouts-script t)
          'pageLoad (timeouts-page-load t)
          'implicit (timeouts-implicit t)))
