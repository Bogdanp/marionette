#lang racket/base

(require json
         net/base64
         net/url
         racket/contract
         racket/function
         racket/match
         racket/string
         "element.rkt"
         "private/marionette.rkt")

(provide
 exn:fail:marionette:page?
 exn:fail:marionette:page:script?
 exn:fail:marionette:page:script-cause

 make-page
 page?
 page=?
 page-id
 page-close!
 page-refresh!
 page-goto!
 page-go-back!
 page-go-forward!

 page-execute!
 page-execute-async!

 page-query-selector!
 page-query-selector-all!

 page-title
 page-url
 page-content
 set-page-content!

 call-with-page-screenshot!)

(struct exn:fail:marionette:page exn:fail:marionette ())
(struct exn:fail:marionette:page:script exn:fail:marionette:page (cause))

(define (page=? page-1 page-2 [recursive? #f])
  (equal? (page-id page-1)
          (page-id page-2)))

(define (hash-page p r)
  (r (page-id p)))

(struct page (id marionette)
  #:methods gen:equal+hash
  [(define equal-proc page=?)
   (define hash-proc  hash-page)
   (define hash2-proc hash-page)])

(define/contract (make-page id marionette)
  (-> non-empty-string? marionette? page?)
  (page id marionette))

(define/contract (page-close! p)
  (-> page? void?)
  (void (page-execute! p "window.close()")))

(define/contract (page-refresh! p)
  (-> page? void?)
  (void (sync (marionette-refresh! (page-marionette p)))))

(define/contract (page-goto! p url)
  (-> page? (or/c url? string?) void?)
  (void (sync (marionette-navigate! (page-marionette p)
                                    (cond
                                      [(url? url) (url->string url)]
                                      [else url])))))

(define/contract (page-go-back! p)
  (-> page? void?)
  (void (sync (marionette-back! (page-marionette p)))))

(define/contract (page-go-forward! p)
  (-> page? void?)
  (void (sync (marionette-forward! (page-marionette p)))))

(define/contract (page-execute! p s . args)
  (-> page? string? jsexpr? ... any/c)
  (sync
   (handle-evt
    (marionette-execute-script! (page-marionette p) s args)
    (curryr hash-ref 'value))))

(define (wrap-async-script s)
  (define template
    #<<SCRIPT
const args = Array.prototype.slice.call(arguments, 0, arguments.length - 1);
const resolve = arguments[arguments.length - 1];

Promise
  .resolve()
  .then(() => (function() { ~a })(...args))
  .then((value) => resolve({ error: null, value }))
  .catch((error) => resolve({ error: error instanceof Error ? error.message : error, value: null }));
SCRIPT
    )

  (format template s))

(define/contract (page-execute-async! p s . args)
  (-> page? string? jsexpr? ... any/c)
  (sync
   (handle-evt
    (marionette-execute-async-script! (page-marionette p) (wrap-async-script s) args)
    (lambda (res)
      (match (hash-ref res 'value)
        [(hash-table ('error 'null)
                     ('value value)) value]

        [(hash-table ('error err))
         (raise (exn:fail:marionette:page:script "async script execution failed"
                                                 (current-continuation-marks)
                                                 err))])))))

(define/contract (page-title p)
  (-> page? string?)
  (sync
   (handle-evt
    (marionette-get-title! (page-marionette p))
    (curryr hash-ref 'value))))

(define/contract (page-url p)
  (-> page? url?)
  (string->url
   (sync
    (handle-evt
     (marionette-get-current-url! (page-marionette p))
     (curryr hash-ref 'value)))))

(define/contract (page-content p)
  (-> page? string?)
  (sync
   (handle-evt
    (marionette-get-page-source! (page-marionette p))
    (curryr hash-ref 'value))))

(define/contract (set-page-content! p c)
  (-> page? string? void?)
  (void
   (page-execute! p "document.documentElement.innerHTML = arguments[0]" c)))

(define/contract (page-query-selector! p selector)
  (-> page? non-empty-string? (or/c false/c element?))
  (with-handlers ([exn:fail:marionette:command?
                   (lambda (e)
                     (cond
                       [(string-contains? (exn-message e) "Unable to locate element") #f]
                       [else (raise e)]))])
    (sync
     (handle-evt
      (marionette-find-element! (page-marionette p) selector)
      (lambda (res)
        (make-element
         (hash-ref res 'value)
         (page-marionette p)))))))

(define/contract (page-query-selector-all! p selector)
  (-> page? non-empty-string? (listof element?))
  (sync
   (handle-evt
    (marionette-find-elements! (page-marionette p) selector)
    (lambda (ids)
      (for/list ([id (in-list ids)])
        (make-element id (page-marionette p)))))))

(define/contract (call-with-page-screenshot! page p
                   #:full? [full? #t])
  (->* (page? (-> bytes? any))
       (#:full? boolean?) any)
  (sync
   (handle-evt
    (marionette-take-screenshot! (page-marionette page) full?)
    (lambda (res)
      (p (base64-decode (string->bytes/utf-8 (hash-ref res 'value))))))))
