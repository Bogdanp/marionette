#lang racket/base

(require json
         net/base64
         net/url
         racket/contract
         racket/match
         racket/string
         "element.rkt"
         "private/json.rkt"
         "private/marionette.rkt")

(provide
 exn:fail:marionette:page?
 exn:fail:marionette:page:script?
 exn:fail:marionette:page:script-cause

 (contract-out
  [make-page (-> string? marionette? page?)]
  [page? (-> any/c boolean?)]
  [page=? (-> page? page? boolean?)]
  [page-id (-> page? string?)]
  [page-select! (-> page? void?)]
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

(define (page-select! p)
  (syncv (marionette-switch-to-window! (page-marionette p) (page-id p))))

(define (page-close! p)
  (with-page p
    (syncv (marionette-close-window! (page-marionette p)))))

(define (page-refresh! p)
  (with-page p
    (syncv (marionette-refresh! (page-marionette p)))))

(define (page-goto! p url)
  (with-page p
    (syncv (marionette-navigate!
            (page-marionette p)
            (cond
              [(url? url) (url->string url)]
              [else url])))))

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

                              [else
                               (raise e)]))])
           (with-page p
             (page-execute-async! p wait-for-element-script selector (* timeout 1000) visible?))))

       (channel-put res-ch (and handle (page-query-selector! p selector))))))

  (sync/timeout timeout res-ch))

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
        (λ (res)
          (make-element
           (hash-ref res 'value)
           (page-marionette p))))))))

(define (page-query-selector-all! p selector)
  (with-page p
    (sync
     (handle-evt
      (marionette-find-elements! (page-marionette p) selector)
      (λ (ids)
        (for/list ([id (in-list ids)])
          (make-element id (page-marionette p))))))))

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
         (λ (res)
           (base64-decode (string->bytes/utf-8 (hash-ref res 'value)))))))))

(define syncv
  (compose1 void sync))

(define (res-value res)
  (hash-ref res 'value))
