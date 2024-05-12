#lang racket/base

(require json
         racket/contract/base)

(provide
 (contract-out
  [struct timeouts ([script exact-nonnegative-integer?]
                    [page-load exact-nonnegative-integer?]
                    [implicit exact-nonnegative-integer?])]
  [make-timeouts (->* []
                      [#:script exact-nonnegative-integer?
                       #:page-load exact-nonnegative-integer?
                       #:implicit exact-nonnegative-integer?]
                      timeouts?)]
  [timeouts->jsexpr (-> timeouts? jsexpr?)]))

(struct timeouts (script page-load implicit)
  #:transparent)

(define (make-timeouts #:script [script 30000]
                       #:page-load [page-load 300000]
                       #:implicit [implicit 0])
  (timeouts script page-load implicit))

(define (timeouts->jsexpr t)
  (hasheq 'script (timeouts-script t)
          'pageLoad (timeouts-page-load t)
          'implicit (timeouts-implicit t)))
