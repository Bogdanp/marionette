#lang racket/base

(require racket/contract
         racket/file
         racket/list
         racket/match
         racket/string
         racket/format
         racket/system
         racket/tcp
         "browser.rkt"
         "capabilities.rkt"
         "page.rkt"
         "private/marionette.rkt"
         "private/template.rkt"
         "rect.rkt"
         "timeouts.rkt")

(provide
 exn:fail:marionette?
 exn:fail:marionette:command?
 exn:fail:marionette:command-stacktrace

 (contract-out
  [start-marionette! (->* ()
                          (#:command absolute-path?
                           #:profile (or/c #f absolute-path?)
                           #:port (or/c #f (integer-in 1 65535))
                           #:safe-mode? boolean?
                           #:headless? boolean?
                           #:timeout exact-nonnegative-integer?)
                          (-> void?))]
  [call-with-browser! (->* ((-> browser? any))
                           (#:host non-empty-string?
                            #:port (integer-in 1 65535)
                            #:capabilities capabilities?)
                           any)]
  [call-with-page! (-> browser? (-> page? any) any)])

 call-with-marionette!
 call-with-marionette/browser!
 call-with-marionette/browser/page!

 (all-from-out
  "browser.rkt"
  "capabilities.rkt"
  "page.rkt"
  "rect.rkt"
  "timeouts.rkt"))

(define firefox
  (or (find-executable-path "firefox")
      (find-executable-path "firefox-bin")
      (for/first ([path '("/Applications/Firefox Developer Edition.app/Contents/MacOS/firefox"
                          "/Applications/Firefox.app/Contents/MacOS/firefox")]
                  #:when (file-exists? path))
        path)))

(define (start-marionette!
         #:command [command firefox]
         #:profile [profile #f]
         #:user.js [user.js #f]
         #:port [port #f]
         #:safe-mode? [safe-mode? #t]
         #:headless? [headless? #t]
         #:timeout [timeout 30])
  (unless command
    (raise-user-error
     'start-marionette!
     "could not determine path to Firefox executable~n  please provide one via #:command"))

  (define deadline (+ (current-seconds) timeout))
  (define delete-profile? (not profile))
  (define profile-path (or profile (make-temporary-file "marionette~a" 'directory)))

  (when port
    (unless (directory-exists? profile-path)
      (make-fresh-profile! command profile-path))

    (with-output-to-file (build-path profile-path "user.js")
      #:exists 'truncate/replace
      (lambda ()
        (display (template "support/user.js")))))

  (when (hash? user.js)
    (with-output-to-file (build-path profile-path "user.js")
      #:exists (if port 'append 'truncate/replace)
      (lambda ()
        (define (user-prefs k v)
          (display
           (string-append "user_prefs("
                          (~s (if (symbol? k) (symbol->string k) k))
                          ","
                          (~s (cond
                                [(symbol? v) (symbol->string v)]
                                [(eq? v #f)  "false"]
                                [(eq? v #t)  "true"]
                                [else        v]))
                          ");"))
          (newline))
        (hash-for-each user.js user-prefs))))

  (define command-args
    (for/list ([arg      (list "--safe-mode" "--headless")]
               [enabled? (list    safe-mode?    headless?)]
               #:when enabled?)
      arg))

  (match-define (list _stdout _stdin _pid _stderr control)
    (apply process*
           command
           "--profile" profile-path
           "--no-remote"
           "--marionette"
           command-args))

  (wait-for-marionette "127.0.0.1" (or port 2828) deadline)
  (lambda ()
    (sync
     (thread
      (lambda ()
        (control 'interrupt)
        (control 'wait)))
     (handle-evt
      (alarm-evt (+ (current-inexact-milliseconds) 5000))
      (lambda (_)
        (control 'kill)
        (control 'wait))))
    (when delete-profile?
      (delete-directory/files profile-path))))

(define call-with-marionette!
  (make-keyword-procedure
   (lambda (kws kw-args p . args)
     (define stop-marionette! void)
     (dynamic-wind
       (lambda ()
         (set! stop-marionette! (keyword-apply start-marionette! kws kw-args args)))
       (lambda ()
         (p))
       (lambda ()
         (stop-marionette!))))))

(define (call-with-browser! p
          #:host [host "127.0.0.1"]
          #:port [port 2828]
          #:capabilities [capabilities (make-capabilities)])
  (define b #f)
  (dynamic-wind
    (lambda ()
      (parameterize-break #t
        (set! b (browser-connect! #:host host
                                  #:port port
                                  #:capabilities capabilities))))
    (lambda ()
      (p b))
    (lambda ()
      (browser-disconnect! b))))

(define (call-with-page! b p)
  (define page #f)
  (dynamic-wind
    (lambda ()
      (set! page (make-browser-page! b)))
    (lambda ()
      (p page))
    (lambda ()
      (page-close! page))))


;; shortcuts ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (kws-ref kws kw-args kw)
  (define idx (index-of kws kw))
  (and idx (list-ref kw-args idx)))

(define call-with-marionette/browser!
  (make-keyword-procedure
   (lambda (kws kw-args p)
     (define host (or (kws-ref kws kw-args '#:host) "127.0.0.1"))
     (define port (or (kws-ref kws kw-args '#:port) 2828))
     (define p*
       (lambda ()
         (call-with-browser! #:host host #:port port p)))

     (keyword-apply call-with-marionette! kws kw-args (list p*)))))

(define call-with-marionette/browser/page!
  (make-keyword-procedure
   (lambda (kws kw-args p)
     (define host (or (kws-ref kws kw-args '#:host) "127.0.0.1"))
     (define port (or (kws-ref kws kw-args '#:port) 2828))
     (define p*
       (lambda ()
         (call-with-browser!
           #:host host
           #:port port
           (lambda (b)
             (call-with-page! b p)))))

     (keyword-apply call-with-marionette! kws kw-args (list p*)))))


;; help ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (make-fresh-profile! command path [timeout 5000])
  (define custodian (make-custodian))
  (parameterize ([current-custodian custodian])
    (define evt (filesystem-change-evt path))
    (match-define (list _stdout _stdin _pid _stderr control)
      (process* command
                "--headless"
                "--profile" path
                "--no-remote"))

    (define deadline
      (+ (current-inexact-milliseconds) timeout))

    (let loop ([evt evt])
      (sync
       (handle-evt (alarm-evt deadline) void)
       (handle-evt
        (nack-guard-evt
         (λ (nack-evt)
           (begin0 evt
             (thread
              (λ ()
                (sync nack-evt)
                (filesystem-change-evt-cancel evt))))))
        (lambda (_)
          (define evt* (filesystem-change-evt path))
          (unless (file-exists? (build-path path "prefs.js"))
            (loop evt*))))))

    (control 'interrupt)
    (control 'wait))
  (custodian-shutdown-all custodian))

(define (wait-for-marionette host port deadline)
  (define st (current-milliseconds))
  (let loop ([attempts 0])
    (with-handlers ([exn:fail:network?
                     (λ (e)
                       (cond
                         [(< (current-seconds) deadline)
                          (define duration (min 0.5 (* 0.05 (expt 2 attempts))))
                          (log-marionette-debug "wait-for-marionette: retrying connect after ~s seconds" duration)
                          (sleep duration)
                          (loop (add1 attempts))]

                         [else
                          (raise e)]))])
      (define-values (in out)
        (tcp-connect host port))
      (close-input-port in)
      (close-output-port out)
      (log-marionette-debug "wait-for-marionette: connected after ~sms" (- (current-milliseconds) st)))))
