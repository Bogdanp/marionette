#lang racket/base

(require file/sha1
         json
         net/base64
         net/url
         racket/contract/base
         racket/match
         racket/random
         racket/string
         "private/browser.rkt"
         "private/executor.rkt"
         "private/json.rkt"
         "private/marionette.rkt"
         "private/template.rkt"
         "rect.rkt")


;; page ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(provide
 cookie/c

 exn:fail:marionette:page?
 exn:fail:marionette:page:script?
 exn:fail:marionette:page:script-cause

 (contract-out
  [make-page (-> browser? string? page?)]
  [page? (-> any/c boolean?)]
  [page=? (-> page? page? boolean?)]
  [page-id (-> page? string?)]
  [page-close! (-> page? void?)]
  [page-refresh! (-> page? void?)]
  [page-goto! (-> page? (or/c url? string?) void?)]
  [page-go-back! (-> page? void?)]
  [page-go-forward! (-> page? void?)]
  [page-execute! (-> page? string? jsexpr? ... any/c)]
  [page-execute-async! (-> page? string? jsexpr? ... any/c)]
  [page-wait-for! (->* [page? string?]
                       [#:timeout (and/c real? (not/c negative?))
                        #:visible? boolean?]
                       (or/c #f element?))]
  [page-query-selector! (-> page? string? (or/c #f element?))]
  [page-query-selector-all! (-> page? string? (listof element?))]
  [page-interactive? (-> page? boolean?)]
  [page-loaded? (-> page? boolean?)]
  [page-title (-> page? string?)]
  [page-url (-> page? url?)]
  [page-content (-> page? string?)]
  [set-page-content! (-> page? string? void?)]
  [page-cookies (-> page? (listof cookie/c))]
  [page-add-cookie! (-> page? cookie/c void?)]
  [page-delete-all-cookies! (-> page? void?)]
  [page-delete-cookie! (-> page? string? void?)]
  [page-alert-text (-> page? string?)]
  [page-alert-accept! (-> page? void?)]
  [page-alert-dismiss! (-> page? void?)]
  [page-alert-type! (-> page? string? void?)]
  [page-switch-to-frame! (->* [page? element?]
                              [boolean?]
                              void?)]
  [page-switch-to-parent-frame! (-> page? void?)]
  [call-with-page-pdf! (-> page? (-> bytes? any) any)]
  [call-with-page-screenshot! (->* [page? (-> bytes? any)]
                                   [#:full? boolean?]
                                   any)]))

(struct exn:fail:marionette:page exn:fail:marionette ())
(struct exn:fail:marionette:page:script exn:fail:marionette:page (cause))

(struct page (browser id))

(define (make-page b id)
  (page b id))

(define (page=? page-1 page-2)
  (and (eq? (page-browser page-1)
            (page-browser page-2))
       (equal? (page-id page-1)
               (page-id page-2))))

(define (page-marionette p)
  (browser-marionette (page-browser p)))

(define (page-focused? p)
  (browser-current-page=? (page-browser p) p))

(define (call-with-page p proc) ;; noqa
  (dynamic-wind
    (λ () (unless (page-focused? p)
            (sync/enable-break (marionette-switch-to-window! (page-marionette p) (page-id p)))
            (set-browser-current-page! (page-browser p) p)))
    (λ () (proc))
    (λ () (void))))

(define-syntax-rule (with-page p e0 e ...)
  (call-with-page p (λ () e0 e ...)))

(define (page-close! p)
  (with-page p
    (syncv (marionette-close-window! (page-marionette p)))))

(define (page-refresh! p)
  (with-page p
    (syncv (marionette-refresh! (page-marionette p)))))

(define (page-goto! p u)
  (with-page p
    (syncv (marionette-navigate!
            (page-marionette p)
            (if (url? u) (url->string u) u)))))

(define (page-go-back! p)
  (with-page p
    (syncv (marionette-back! (page-marionette p)))))

(define (page-go-forward! p)
  (with-page p
    (syncv (marionette-forward! (page-marionette p)))))

(define (page-execute! p s . args)
  (with-page p
    (sync
     (handle-evt
      (marionette-execute-script! (page-marionette p) s args)
      res-value))))

(define (wrap-async-script body) ;; noqa
  (template "support/wrap-async-script.js"))

(define (page-execute-async! p s . args)
  (with-page p
    (sync
     (handle-evt
      (marionette-execute-async-script!
       (page-marionette p)
       (wrap-async-script s)
       args)
      (λ (res)
        (match (hash-ref res 'value)
          [(hash-table ('error (js-null))
                       ('value value   ))
           value]

          [(hash-table ('error err))
           (raise (exn:fail:marionette:page:script
                   (format "async script execution failed: ~a" err)
                   (current-continuation-marks)
                   err))]

          [(js-null)
           (raise (exn:fail:marionette:page:script
                   "async script execution aborted"
                   (current-continuation-marks)
                   #f))]))))))

(define (page-title p)
  (with-page p
    (sync
     (handle-evt
      (marionette-get-title! (page-marionette p))
      res-value))))

(define (page-url p)
  (with-page p
    (sync
     (handle-evt
      (marionette-get-current-url! (page-marionette p))
      (compose1 string->url res-value)))))

(define (page-content p)
  (with-page p
    (sync
     (handle-evt
      (marionette-get-page-source! (page-marionette p))
      res-value))))

(define (set-page-content! p c)
  (void (page-execute! p "document.documentElement.innerHTML = arguments[0]" c)))

(define (page-readystate p)
  (page-execute! p "return document.readyState"))

(define (page-interactive? p)
  (and (member (page-readystate p) '("interactive" "complete")) #t))

(define (page-loaded? p)
  (and (member (page-readystate p) '("complete")) #t))

(define cookie/c jsexpr?)

(define (page-cookies p)
  (with-page p
    (sync (marionette-get-cookies! (page-marionette p)))))

(define (page-add-cookie! p c)
  (with-page p
    (syncv (marionette-add-cookie! (page-marionette p) c))))

(define (page-delete-all-cookies! p)
  (with-page p
    (syncv (marionette-delete-all-cookies! (page-marionette p)))))

(define (page-delete-cookie! p name)
  (with-page p
    (syncv (marionette-delete-cookie! (page-marionette p) name))))

(define wait-for-element-script
  (template "support/wait-for-element.js"))

(define (page-wait-for! p selector
                        #:timeout [timeout 30]
                        #:visible? [visible? #t])
  (define res-ch
    (make-channel))

  (thread
   (λ ()
     (let loop ()
       (define handle
         (with-handlers ([exn:fail:marionette?
                          (λ (e)
                            (cond
                              [(or (string-contains? (exn-message e) "unloaded")
                                   (string-contains? (exn-message e) "async script execution failed")
                                   (string-contains? (exn-message e) "async script execution aborted")
                                   (string-contains? (exn-message e) "context has been discarded"))
                               (loop)]

                              [else e]))])
           (with-page p
             (page-execute-async! p wait-for-element-script selector (* timeout 1000) visible?))))

       (if (exn:fail? handle)
           (channel-put res-ch handle)
           (channel-put
            res-ch
            (and handle (with-page p (page-query-selector! p selector))))))))

  (sync/timeout
   timeout
   (handle-evt
    res-ch
    (λ (res)
      (begin0 res
        (when (exn:fail? res)
          (raise res)))))))

(define (page-query-selector! p selector)
  (with-handlers ([exn:fail:marionette:command?
                   (λ (e)
                     (cond
                       [(string-contains? (exn-message e) "Unable to locate element") #f]
                       [else (raise e)]))])
    (with-page p
      (sync
       (handle-evt
        (marionette-find-element! (page-marionette p) selector)
        (λ (r)
          (element p (res-value r))))))))

(define (page-query-selector-all! p selector)
  (with-page p
    (sync
     (handle-evt
      (marionette-find-elements! (page-marionette p) selector)
      (λ (ids)
        (for/list ([id (in-list ids)])
          (element p id)))))))

(define (page-alert-text p)
  (sync
   (handle-evt
    (marionette-get-alert-text! (page-marionette p))
    res-value)))

(define (page-alert-accept! p)
  (with-page p
    (syncv (marionette-accept-alert! (page-marionette p)))))

(define (page-alert-dismiss! p)
  (with-page p
    (syncv (marionette-dismiss-alert! (page-marionette p)))))

(define (page-alert-type! p text)
  (syncv (marionette-send-alert-text! (page-marionette p) text)))

(define (page-switch-to-frame! p e [focus? #t])
  (syncv (marionette-switch-to-frame! (page-marionette p) (element-handle e) focus?)))

(define (page-switch-to-parent-frame! p)
  (syncv (marionette-switch-to-parent-frame! (page-marionette p))))

(define (call-with-page-pdf! p proc)
  (with-page p
    (proc
     (sync
      (handle-evt
       (marionette-print! (page-marionette p))
       res-value/decode)))))

(define (call-with-page-screenshot! p proc #:full? [full? #t])
  (with-page p
    (proc
     (sync
      (handle-evt
       (marionette-take-screenshot! (page-marionette p) full?)
       res-value/decode)))))


;; page-change-evt ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(provide
 page-change-evt?
 page-change-evt
 abandon-page-change-evt
 call-with-page-change-evt)

(struct page-change-evt (p token [abandoned? #:mutable])
  #:name -page-change-evt
  #:constructor-name -page-change-evt
  #:property prop:evt
  (lambda (e)
    (match-define (-page-change-evt p token _) e)
    (guard-evt
     (lambda ()
       (unless (page-change-evt-abandoned? e)
         (thread
          (lambda ()
            (let loop ()
              (unless (page-change-evt-abandoned? e)
                (define current (page-execute! p (template "support/get-page-change-token.js")))
                (log-marionette-debug "get PageChangeToken=~a" current)
                (when (equal? current token)
                  (sleep 0.05)
                  (loop)))))))))))

(define (page-change-evt p)
  (define token (bytes->hex-string (crypto-random-bytes 32)))
  (page-execute! p (template "support/set-page-change-token.js") token)
  (log-marionette-debug "set PageChangeToken=~s" token)
  (define evt (-page-change-evt p token #f))
  (will-register executor evt abandon-page-change-evt)
  evt)

(define (abandon-page-change-evt e)
  (set-page-change-evt-abandoned?! e #t)
  (sync/enable-break e))

(define (call-with-page-change-evt p proc)
  (define e #f)
  (dynamic-wind
    (lambda ()
      (set! e (page-change-evt p)))
    (lambda ()
      (proc e))
    (lambda ()
      (abandon-page-change-evt e))))

;; element ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(provide
 (contract-out
  [element? (-> any/c boolean?)]
  [element=? (-> element? element? boolean?)]
  [element-click! (-> element? void?)]
  [element-clear! (-> element? void?)]
  [element-type! (-> element? string? void?)]
  [element-query-selector! (-> element? string? (or/c #f element?))]
  [element-query-selector-all! (-> element? string? (listof element?))]
  [element-enabled? (-> element? boolean?)]
  [element-selected? (-> element? boolean?)]
  [element-visible? (-> element? boolean?)]
  [element-handle (-> element? any/c)]
  [element-tag (-> element? string?)]
  [element-text (-> element? string?)]
  [element-rect (-> element? rect?)]
  [element-attribute (-> element? string? (or/c #f string?))]
  [element-property (-> element? string? (or/c #f string?))]
  [call-with-element-screenshot! (-> element? (-> bytes? any) any)]))

(struct element (page handle))

(define (element=? element-1 element-2)
  (and (eq? (element-page element-1)
            (element-page element-2))
       (equal? (element-handle element-1)
               (element-handle element-2))))

(define (element-marionette e)
  (page-marionette (element-page e)))

(define (element-id e)
  (for/first ([(_ v) (in-hash (element-handle e))])
    v))

(define (element-click! e)
  (with-page (element-page e)
    (syncv (marionette-element-click! (element-marionette e) (element-id e)))))

(define (element-clear! e)
  (with-page (element-page e)
    (syncv (marionette-element-clear! (element-marionette e) (element-id e)))))

(define (element-type! e text)
  (with-page (element-page e)
    (syncv (marionette-element-send-keys! (element-marionette e) (element-id e) text))))

(define (element-query-selector! e selector)
  (with-handlers ([exn:fail:marionette:command?
                   (lambda (ex)
                     (cond
                       [(regexp-match? #rx"Unable to locate element" (exn-message ex)) #f]
                       [else (raise ex)]))])
    (with-page (element-page e)
      (sync
       (handle-evt
        (marionette-find-element! (element-marionette e) selector (element-id e))
        (lambda (r)
          (element
           (element-page e)
           (res-value r))))))))

(define (element-query-selector-all! e selector)
  (define p (element-page e))
  (with-page p
    (sync
     (handle-evt
      (marionette-find-elements! (element-marionette e) selector (element-id e))
      (lambda (ids)
        (for/list ([id (in-list ids)])
          (element p id)))))))

(define (element-enabled? e)
  (with-page (element-page e)
    (sync
     (handle-evt
      (marionette-is-element-enabled! (element-marionette e) (element-id e))
      res-value))))

(define (element-selected? e)
  (with-page (element-page e)
    (sync
     (handle-evt
      (marionette-is-element-selected! (element-marionette e) (element-id e))
      res-value))))

(define (element-visible? e)
  (with-page (element-page e)
    (sync
     (handle-evt
      (marionette-is-element-displayed! (element-marionette e) (element-id e))
      res-value))))

(define (element-tag e)
  (with-page (element-page e)
    (sync
     (handle-evt
      (marionette-get-element-tag-name! (element-marionette e) (element-id e))
      res-value))))

(define (element-text e)
  (with-page (element-page e)
    (sync
     (handle-evt
      (marionette-get-element-text! (element-marionette e) (element-id e))
      res-value))))

(define (element-rect e)
  (with-page (element-page e)
    (sync
     (handle-evt
      (marionette-get-element-rect! (element-marionette e) (element-id e))
      (match-lambda
        [(hash-table ('x x)
                     ('y y)
                     ('width w)
                     ('height h))
         (rect x y w h)])))))

(define (element-attribute e name)
  (with-page (element-page e)
    (sync
     (handle-evt
      (marionette-get-element-attribute! (element-marionette e) (element-id e) name)
      (match-lambda
        [(hash-table ('value (js-null))) #f   ]
        [(hash-table ('value value    )) value])))))

(define (element-property e name)
  (with-page (element-page e)
    (sync
     (handle-evt
      (marionette-get-element-property! (element-marionette e) (element-id e) name)
      (match-lambda
        [(hash-table ('value (js-null))) #f]
        [(hash-table ('value value    )) value])))))

(define (call-with-element-screenshot! e proc)
  (with-page (element-page e)
    (proc
     (sync
      (handle-evt
       (marionette-take-screenshot! (element-marionette e) #f (element-id e))
       res-value/decode)))))


;; common ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define syncv
  (compose1 void sync))

(define (res-value r)
  (hash-ref r 'value))

(define res-value/decode
  (compose1 base64-decode string->bytes/utf-8 res-value))
