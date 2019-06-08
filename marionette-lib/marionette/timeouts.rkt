#lang racket/base

(require racket/contract)

(provide
 make-timeouts

 (contract-out
  [struct timeouts ([script exact-nonnegative-integer?]
                    [page-load exact-nonnegative-integer?]
                    [implicit exact-nonnegative-integer?])]))

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
