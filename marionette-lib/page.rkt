#lang racket/base

(require json
         net/base64
         net/url
         racket/contract
         racket/match
         racket/string
         "private/json.rkt"
         "private/marionette.rkt"
         "rect.rkt")


;; page ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(provide
 exn:fail:marionette:page?
 exn:fail:marionette:page:script?
 exn:fail:marionette:page:script-cause

 (contract-out
  [make-page (-> string? marionette? page?)]
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
  [page-wait-for! (->* (page? string?)
                       (#:timeout (and/c real? (not/c negative?))
                        #:visible? boolean?)
                       (or/c #f element?))]
  [page-query-selector! (-> page? string? (or/c #f element?))]
  [page-query-selector-all! (-> page? string? (listof element?))]
  [page-interactive? (-> page? boolean?)]
  [page-loaded? (-> page? boolean?)]
  [page-title (-> page? string?)]
  [page-url (-> page? url?)]
  [page-content (-> page? string?)]
  [set-page-content! (-> page? string? void?)]
  [page-alert-text (-> page? string?)]
  [page-alert-accept! (-> page? void?)]
  [page-alert-dismiss! (-> page? void?)]
  [page-alert-type! (-> page? string? void?)]
  [call-with-page-screenshot! (->* (page? (-> bytes? any))
                                   (#:full? boolean?)
                                   any)]))

(struct exn:fail:marionette:page exn:fail:marionette ())
(struct exn:fail:marionette:page:script exn:fail:marionette:page (cause))

(define (page=? page-1 page-2)
  (and (eq? (page-marionette page-1)
            (page-marionette page-2))
       (equal? (page-id page-1)
               (page-id page-2))))

(struct page (id marionette))

(define (make-page id marionette)
  (page id marionette))

(define (call-with-page p f)
  (dynamic-wind
    (λ () (sync/enable-break (marionette-switch-to-window! (page-marionette p) (page-id p))))
    (λ () (f))
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

(define (page-execute-async! p s . args)
  (with-page p
    (sync
     (handle-evt
      (marionette-execute-async-script! (page-marionette p) (wrap-async-script s) args)
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

(define wait-for-element-script #<<SCRIPT
const [selector, timeout, mustBeVisible] = arguments;

let node;
let resolve;
let observer;
const res = new Promise(r => resolve = function(res) {
  observer && observer.disconnect();
  return r(res);
});

window.setTimeout(function() {
  return resolve(false);
}, timeout);

bootstrap();
return res;

function bootstrap() {
  if (node = findNode()) {
    return resolve(node);
  }

  observer = new MutationObserver(() => {
    if (node = findNode()) {
      return resolve(node);
    }
  });

  observer.observe(document.body, {
    subtree: true,
    childList: true,
    attributes: true,
  });

  return res;
}

function isVisible(node) {
  const { visibility } = window.getComputedStyle(node) || {};
  const { top, bottom, width, height } = node.getBoundingClientRect();
  return visibility !== "hidden" && top && bottom && width && height;
}

function findNode() {
  const node = document.querySelector(selector);
  if (node && (mustBeVisible && isVisible(node) || !mustBeVisible)) {
    return node;
  }

  return null;
}
SCRIPT
  )

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
          (element (page-marionette p) p (res-value r))))))))

(define (page-query-selector-all! p selector)
  (with-page p
    (sync
     (handle-evt
      (marionette-find-elements! (page-marionette p) selector)
      (λ (ids)
        (for/list ([id (in-list ids)])
          (element (page-marionette p) p id)))))))

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

(define (call-with-page-screenshot! p f #:full? [full? #t])
  (with-page p
    (f (sync
        (handle-evt
         (marionette-take-screenshot! (page-marionette p) full?)
         res-value/decode)))))


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

(define (element=? element-1 element-2)
  (and (eq? (element-page element-1)
            (element-page element-2))
       (equal? (element-handle element-1)
               (element-handle element-2))))

(struct element (marionette page handle))

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
           (element-marionette e)
           (element-page e)
           (res-value r))))))))

(define (element-query-selector-all! e selector)
  (with-page (element-page e)
    (sync
     (handle-evt
      (marionette-find-elements! (element-marionette e) selector (element-id e))
      (lambda (ids)
        (for/list ([id (in-list ids)])
          (element id (element-marionette e))))))))

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

(define (call-with-element-screenshot! e p)
  (with-page (element-page e)
    (sync
     (handle-evt
      (marionette-take-screenshot! (element-marionette e) #f (element-id e))
      (lambda (res)
        (p (base64-decode (string->bytes/utf-8 (hash-ref res 'value)))))))))


;; common ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define syncv
  (compose1 void sync))

(define (res-value r)
  (hash-ref r 'value))

(define res-value/decode
  (compose1 base64-decode string->bytes/utf-8 res-value))