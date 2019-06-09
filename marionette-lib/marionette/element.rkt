#lang racket/base

(require net/base64
         racket/contract
         racket/function
         racket/match
         racket/string
         "private/marionette.rkt"
         "private/util.rkt"
         "rect.rkt")

(provide
 make-element
 element?
 element=?

 element-click!
 element-clear!
 element-type!
 element-query-selector!
 element-query-selector-all!

 element-enabled?
 element-selected?
 element-visible?

 element-handle
 element-tag
 element-text
 element-rect

 element-attribute
 element-property

 call-with-element-screenshot!)

(define element-handle/c
  (hash/c symbol? string?))

(define (element=? element-1 element-2 [recursive? #f])
  (equal? (element-handle element-1)
          (element-handle element-2)))

(define (hash-element e r)
  (r (element-handle e)))

(struct element (handle marionette)
  #:methods gen:equal+hash
  [(define equal-proc element=?)
   (define hash-proc  hash-element)
   (define hash2-proc hash-element)])

(define/contract (make-element handle m)
  (-> element-handle/c marionette? element?)
  (element handle m))

(define/contract (element-id e)
  (-> element? non-empty-string?)
  (for/first ([(_ v) (in-hash (element-handle e))])
    v))

(define/contract (element-click! e)
  (-> element? void?)
  (void
   (sync
    (marionette-element-click! (element-marionette e) (element-id e)))))

(define/contract (element-clear! e)
  (-> element? void?)
  (void
   (sync
    (marionette-element-clear! (element-marionette e) (element-id e)))))

(define/contract (element-type! e text)
  (-> element? string? void?)
  (void
   (sync
    (marionette-element-send-keys! (element-marionette e) (element-id e) text))))

(define/contract (element-query-selector! e selector)
  (-> element? non-empty-string? (or/c false/c element?))
  (with-handlers ([exn:fail:marionette:command?
                   (lambda (e)
                     (cond
                       [(string-contains? (exn-message e) "Unable to locate element") #f]
                       [else (raise e)]))])
    (sync
     (handle-evt
      (marionette-find-element! (element-marionette e) selector (element-id e))
      (lambda (res)
        (make-element
         (hash-ref res 'value)
         (element-marionette e)))))))

(define/contract (element-query-selector-all! e selector)
  (-> element? non-empty-string? (listof element?))
  (sync
   (handle-evt
    (marionette-find-elements! (element-marionette e) selector)
    (lambda (ids)
      (for/list ([id (in-list ids)])
        (make-element id (element-marionette e)))))))

(define/contract (element-enabled? e)
  (-> element? boolean?)
  (sync
   (handle-evt
    (marionette-is-element-enabled! (element-marionette e) (element-id e))
    (curryr hash-ref 'value))))

(define/contract (element-selected? e)
  (-> element? boolean?)
  (sync
   (handle-evt
    (marionette-is-element-selected! (element-marionette e) (element-id e))
    (curryr hash-ref 'value))))

(define/contract (element-visible? e)
  (-> element? boolean?)
  (sync
   (handle-evt
    (marionette-is-element-displayed! (element-marionette e) (element-id e))
    (curryr hash-ref 'value))))

(define/contract (element-tag e)
  (-> element? non-empty-string?)
  (sync
   (handle-evt
    (marionette-get-element-tag-name! (element-marionette e) (element-id e))
    (curryr hash-ref 'value))))

(define/contract (element-text e)
  (-> element? string?)
  (sync
   (handle-evt
    (marionette-get-element-text! (element-marionette e) (element-id e))
    (curryr hash-ref 'value))))

(define/contract (element-rect e)
  (-> element? rect?)
  (sync
   (handle-evt
    (marionette-get-element-rect! (element-marionette e) (element-id e))
    (match-lambda
      [(hash-table ('x x)
                   ('y y)
                   ('width w)
                   ('height h))
       (rect x y w h)]))))

(define/contract (element-attribute e name)
  (-> element? non-empty-string? (or/c false/c string?))
  (sync
   (handle-evt
    (marionette-get-element-attribute! (element-marionette e) (element-id e) name)
    (match-lambda
      [(hash-table ('value (js-null))) #f   ]
      [(hash-table ('value value    )) value]))))

(define/contract (element-property e name)
  (-> element? non-empty-string? (or/c false/c string?))
  (sync
   (handle-evt
    (marionette-get-element-property! (element-marionette e) (element-id e) name)
    (match-lambda
      [(hash-table ('value (js-null))) #f]
      [(hash-table ('value value    )) value]))))

(define/contract (call-with-element-screenshot! e p)
  (-> element? (-> bytes? any) any)
  (sync
   (handle-evt
    (marionette-take-screenshot! (element-marionette e) #f (element-id e))
    (lambda (res)
      (p (base64-decode (string->bytes/utf-8 (hash-ref res 'value))))))))
