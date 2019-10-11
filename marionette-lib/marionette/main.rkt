#lang racket/base

(require racket/contract
         racket/file
         racket/match
         racket/string
         racket/system
         "browser.rkt"
         "capabilities.rkt"
         "element.rkt"
         "page.rkt"
         "private/marionette.rkt"
         "rect.rkt"
         "timeouts.rkt")

(provide
 (all-from-out "browser.rkt"
               "capabilities.rkt"
               "element.rkt"
               "page.rkt"
               "rect.rkt"
               "timeouts.rkt")

 exn:fail:marionette?
 exn:fail:marionette:command?
 exn:fail:marionette:command-stacktrace

 start-marionette!
 call-with-marionette!

 call-with-browser!
 call-with-page!

 call-with-marionette/browser!
 call-with-marionette/browser/page!)

(define FIREFOX-BIN-PATH
  (or (find-executable-path "firefox")
      (find-executable-path "firefox-bin")
      (for/first ([path '("/Applications/Firefox Developer Edition.app/Contents/MacOS/firefox"
                          "/Applications/Firefox.app/Contents/MacOS/firefox")]
                  #:when (file-exists? path))
        path)))

(define/contract (start-marionette! #:command [command FIREFOX-BIN-PATH]
                                    #:profile [profile #f]
                                    #:safe-mode? [safe-mode? #t]
                                    #:headless? [headless? #t]
                                    #:timeout [timeout 5])
  (->* ()
       (#:command absolute-path?
        #:profile (or/c false/c absolute-path?)
        #:safe-mode? boolean?
        #:headless? boolean?
        #:timeout exact-nonnegative-integer?)
       (-> void?))

  (define deadline
    (+ (current-seconds) timeout))

  (define delete-profile?
    (not profile))

  (define profile-path
    (or profile (make-temporary-file "marionette~a" 'directory)))

  (define command-args
    (for/list ([arg      (list "--safe-mode" "--headless")]
               [enabled? (list    safe-mode?    headless?)]
               #:when enabled?)
      arg))

  (match-define (list stdout stdin pid stderr control)
    (apply process*
           command
           "--profile" profile-path
           "--no-remote"
           "--marionette"
           command-args))

  (let loop ()
    (with-handlers ([exn:fail?
                     (lambda (e)
                       (cond
                         [(< (current-seconds) deadline)
                          (sleep 0.1)
                          (loop)]

                         [else
                          (raise e)]))])
      (call-with-browser! void)))

  (lambda _
    (control 'interrupt)
    (control 'wait)

    (when delete-profile?
      (delete-directory/files profile-path))))

(define call-with-marionette!
  (make-keyword-procedure
   (lambda (kws kw-args p . args)
     (define stop-marionette! void)

     (dynamic-wind
       (lambda _
         (set! stop-marionette! (keyword-apply start-marionette! kws kw-args args)))
       (lambda _
         (p))
       (lambda _
         (stop-marionette!))))))

(define/contract (call-with-browser! p
                   #:host [host "127.0.0.1"]
                   #:port [port 2828]
                   #:capabilities [capabilities (make-capabilities)])
  (->* ((-> browser? any))
       (#:host non-empty-string?
        #:port (integer-in 1 65535)
        #:capabilities capabilities?)
       any)

  (define b #f)
  (dynamic-wind
    (lambda _
      (set! b (browser-connect! #:host host
                                #:port port
                                #:capabilities capabilities)))
    (lambda _
      (p b))
    (lambda _
      (browser-disconnect! b))))

(define/contract (call-with-page! b p)
  (-> browser? (-> page? any) any)
  (define page #f)
  (dynamic-wind
    (lambda _
      (set! page (make-browser-page! b)))
    (lambda _
      (p page))
    (lambda _
      (page-close! page))))


;; shortcuts ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define call-with-marionette/browser!
  (make-keyword-procedure
   (lambda (kws kw-args p)
     (define p*
       (lambda _
         (call-with-browser! p)))

     (keyword-apply call-with-marionette! kws kw-args (list p*)))))

(define call-with-marionette/browser/page!
  (make-keyword-procedure
   (lambda (kws kw-args p)
     (define p*
       (lambda _
         (call-with-browser!
           (lambda (b)
             (call-with-page! b p)))))

     (keyword-apply call-with-marionette! kws kw-args (list p*)))))
