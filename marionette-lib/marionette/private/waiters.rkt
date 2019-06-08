#lang racket/base

(require racket/contract)

(provide
 make-waiter-set
 waiter-set?
 waiter-set-emit
 waiter-set-ref)

(struct waiter-set
  (seq events))

(define/contract (make-waiter-set)
  (-> waiter-set?)
  (waiter-set 0 (hasheq)))

(define/contract (waiter-set-emit ws)
  (-> waiter-set? (values exact-nonnegative-integer? evt? waiter-set?))
  (define chan (make-channel))
  (define next-id (add1 (waiter-set-seq ws)))
  (define next-events (hash-set (waiter-set-events ws) next-id chan))
  (values next-id chan (waiter-set next-id next-events)))

(define/contract (waiter-set-ref ws command-id)
  (-> waiter-set? exact-nonnegative-integer? (or/c false/c evt?))
  (hash-ref (waiter-set-events ws) command-id #f))
