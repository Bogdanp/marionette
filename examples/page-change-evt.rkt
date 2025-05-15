#lang racket/base

(require marionette
         web-server/servlet
         (only-in xml current-unescaped-tags html-unescaped-tags))

(current-unescaped-tags html-unescaped-tags)

(define ((app n) _req)
  (send/suspend/dispatch
   (lambda (embed/url)
     (sleep 1)
     (response/xexpr
      #:preamble #"<!DOCTYPE html>"
      `(html
        (head
         (script ([src "https://cdn.jsdelivr.net/npm/unpoly@3.10.2/unpoly.min.js"])))
        (body
         (div.content
          (p ,(format "Counter: ~a" n))
          (a
           ([class "continue-button"]
            [href ,(embed/url (app (add1 n)))]
            [up-target ".content"])
           "Continue"))))))))

(define (run-marionette port)
  (call-with-marionette/browser/page!
   #:headless? #f
   (lambda (p)
     (page-goto! p (format "http://127.0.0.1:~a" port))
     (define e (page-change-evt p))
     (element-click! (page-wait-for! p ".continue-button"))
     (println (page-url p))
     (println `(sync-result ,(sync e)))
     (println (page-url p))
     (println `(sync-result ,(sync e)))
     (define e2 (page-change-evt p))
     (abandon-page-change-evt e2)
     (println `(timeout-result ,(sync/timeout 1 e2))))))

(module+ main
  (require racket/async-channel
           web-server/servlet-dispatch
           web-server/web-server)

  (define port-or-exn-ch
    (make-async-channel))
  (define stop
    (serve
     #:confirmation-channel port-or-exn-ch
     #:dispatch (dispatch/servlet (app 1))
     #:port 0))
  (define port-or-exn
    (sync port-or-exn-ch))
  (when (exn:fail? port-or-exn)
    (raise port-or-exn))
  (define marionette-thd
    (thread
     (lambda ()
       (run-marionette port-or-exn))))
  (with-handlers ([exn:break? void])
    (sync/enable-break marionette-thd))
  (stop))
