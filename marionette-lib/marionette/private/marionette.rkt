#lang racket/base

(require (for-syntax racket/base
                     racket/format
                     racket/syntax
                     syntax/parse)
         json
         racket/contract
         racket/format
         racket/list
         racket/match
         racket/port
         racket/string
         racket/tcp
         "../capabilities.rkt"
         "../timeouts.rkt"
         "json.rkt")

(provide
 exn:fail:marionette?
 exn:fail:marionette

 exn:fail:marionette:command?
 exn:fail:marionette:command
 exn:fail:marionette:command-stacktrace

 (contract-out
  [make-marionette (-> non-empty-string? (integer-in 1 65535) marionette?)]
  [marionette? (-> any/c boolean?)]
  [marionette-connect! (-> marionette? capabilities? jsexpr?)]
  [marionette-disconnect! (-> marionette? void?)]
  [marionette-send! (-> marionette? non-empty-string? jsexpr? (evt/c jsexpr?))]))


;; errors ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(struct exn:fail:marionette exn:fail ())
(struct exn:fail:marionette:command exn:fail:marionette (stacktrace))

(define (oops who fmt . args)
  (exn:fail:marionette
   (~a who ": " (apply format fmt args))
   (current-continuation-marks)))


;; impl ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-logger marionette)

(struct marionette (mgr))

(define (make-marionette host port)
  (marionette (make-manager host port)))

(define (marionette-connect! m c)
  (sync (send (marionette-mgr m) connect))
  (sync (marionette-new-session! m
                                 (timeouts->jsexpr (capabilities-timeouts c))
                                 (capabilities-page-load-strategy c)
                                 (capabilities-unhandled-prompt-behavior c)
                                 (capabilities-accept-insecure-certs? c))))

(define (marionette-disconnect! m)
  (sync (marionette-delete-session! m))
  (sync (send (marionette-mgr m) disconnect)))

(define (marionette-send! m command parameters)
  (handle-evt
   (send (marionette-mgr m) send command parameters)
   (lambda (res)
     (begin0 res
       (when (exn:fail? res)
         (raise res))))))

(struct Waiter (nack-evt res-ch))
(struct Cmd (nack-evt res-ch))
(struct Connect Cmd (host port))
(struct Disconnect Cmd ())
(struct Reply Cmd (id))

(define (make-manager host port)
  (thread/suspend-to-kill
   (lambda ()
     (let loop ([in #f]
                [out #f]
                [cmds null]
                [waiters (hasheqv)]
                [next-id 0])
       (define connected?
         (and in out
              (not (port-closed? in))
              (not (port-closed? out))))

       (apply
        sync
        (handle-evt
         (thread-receive-evt)
         (lambda (_)
           (match (thread-receive)
             [`(connect ,nack-evt ,res-ch)
              (cond
                [connected?
                 (loop in out cmds waiters next-id)]

                [else
                 (define cmd (Connect nack-evt res-ch host port))
                 (loop in out (cons cmd cmds) waiters next-id)])]

             [`(disconnect ,nack-evt ,res-ch)
              (define cmd (Disconnect nack-evt res-ch))
              (loop in out (cons cmd cmds) waiters next-id)]

             [`(send ,name ,params ,nack-evt ,res-ch)
              (cond
                [connected?
                 (with-handlers ([exn:fail?
                                  (lambda (e)
                                    (log-marionette-error "failed to send command ~s with params ~.s~n  error: ~a" name params (exn-message e))
                                    (define cmd (Reply nack-evt res-ch e))
                                    (loop in out (cons cmd cmds) waiters next-id))])
                   (define id next-id)
                   (log-marionette-debug "sending command ~s with params ~.s and id ~s" name params id)
                   (write-data (list 0 id name params) out)
                   (loop in out cmds (hash-set waiters id (Waiter nack-evt res-ch)) (add1 id)))]

                [else
                 (log-marionette-debug "failed to send command ~s with params ~.s~n  error: not connected" name params)
                 (define cmd (Reply nack-evt res-ch (oops 'command "not connected")))
                 (loop in out (cons cmd cmds) waiters next-id)])]

             [message
              (log-marionette-warning "invalid message: ~.s" message)
              (loop in out cmds waiters next-id)])))

        (handle-evt
         (or (and connected? in) never-evt)
         (lambda (p)
           (match (read-data p)
             [(? eof-object?)
              (log-marionette-warning "connection closed by remote")
              (loop #f #f cmds waiters next-id)]

             [`(1 ,id ,data ,(js-null))
              (log-marionette-debug "received error response to command ~s with data ~.s" id data)
              (cond
                [(hash-ref waiters id #f)
                 => (match-lambda
                      [(Waiter nack-evt res-ch)
                       (define err
                         (exn:fail:marionette:command
                          (hash-ref data 'message "")
                          (current-continuation-marks)
                          (hash-ref data 'stacktrace "")))
                       (define cmd (Reply nack-evt res-ch err))
                       (loop in out (cons cmd cmds) (hash-remove waiters id) next-id)])]

                [else
                 (log-marionette-warning "received error response to unkown waiter (~s): ~.s" id data)
                 (loop in out cmds waiters next-id)])]

             [`(1 ,id ,(js-null) ,data)
              (log-marionette-debug "received response to command ~s with data ~.s" id data)
              (cond
                [(hash-ref waiters id #f)
                 => (match-lambda
                      [(Waiter nack-evt res-ch)
                       (define cmd (Reply nack-evt res-ch data))
                       (loop in out (cons cmd cmds) (hash-remove waiters id) next-id)])]

                [else
                 (log-marionette-warning "received response to unknown waiter (~s): ~.s" id data)
                 (loop in out cmds waiters next-id)])]

             [data
              (log-marionette-warning "received unexpected data: ~.s" data)
              (loop in out cmds waiters next-id)])))

        (append
         (for/list ([cmd (in-list cmds)])
           (match cmd
             [(Connect _ res-ch host port)
              (cond
                [connected?
                 (handle-evt
                  (channel-put-evt res-ch (oops 'connect "already connected"))
                  (lambda (_)
                    (loop in out (remq cmd cmds) waiters next-id)))]

                [else
                 (with-handlers ([exn:fail?
                                  (lambda (e)
                                    (handle-evt
                                     (channel-put-evt res-ch e)
                                     (lambda (_)
                                       (loop #f #f (remq cmd cmds) waiters next-id))))])
                   (let-values ([(in out) (tcp-connect host port)])
                     (log-marionette-debug "connected to ~a:~a" host port)
                     (define preamble (read-data in))
                     (cond
                       [(and (equal? (hash-ref preamble 'applicationType #f) "gecko")
                             (equal? (hash-ref preamble 'marionetteProtocol #f) 3))
                        (sync/timeout 0 (channel-put-evt res-ch (void)))
                        (loop in out (remq cmd cmds) waiters next-id)]

                       [else
                        (close-input-port in)
                        (close-output-port out)
                        (define err (oops 'connect "the other end doesn't implement the v3 marionette protocol"))
                        (sync/timeout 0 (channel-put-evt res-ch err))
                        (loop #f #f (remq cmd cmds) waiters next-id)])))])]

             [(Disconnect _ res-ch)
              (handle-evt
               (channel-put-evt res-ch (void))
               (lambda (_)
                 (when connected?
                   (close-input-port in)
                   (close-output-port out))
                 (loop #f #f (remq cmd cmds) waiters next-id)))]

             [(Reply _ res-ch rep)
              (handle-evt
               (channel-put-evt res-ch rep)
               (lambda (_)
                 (loop in out (remq cmd cmds) waiters next-id)))]))
         (for/list ([cmd (in-list cmds)])
           (handle-evt
            (Cmd-nack-evt cmd)
            (lambda (_)
              (loop in out (remq cmd cmds) waiters next-id))))))))))

(define (send* mgr cmd . args)
  (handle-evt
   (nack-guard-evt
    (lambda (nack-evt)
      (define res-ch (make-channel))
      (begin0 res-ch
        (thread-resume mgr (current-thread))
        (thread-send mgr `(,cmd ,@args ,nack-evt ,res-ch)))))
   (lambda (msg)
     (begin0 msg
       (when (exn:fail? msg)
         (raise msg))))))

(define-syntax-rule (send who cmd arg ...)
  (send* who 'cmd arg ...))

(define (read-data in)
  (match (regexp-match #rx"([1-9][0-9]*):" in)
    [`(,_ ,len-str)
     (define len (string->number (bytes->string/utf-8 len-str)))
     (read-json (make-limited-input-port in len #f))]

    [#f eof]))

(define (write-data data out)
  (define data-bs (jsexpr->bytes data))
  (write-string (number->string (bytes-length data-bs)) out)
  (write-bytes #":" out)
  (write-bytes data-bs out)
  (flush-output out))


;; commands ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define missing (gensym 'missing))
(define (missing? v)
  (eq? missing v))

(define-syntax (define-marionette-command stx)
  (define (make-command-name stx name)
    (define name:str (symbol->string name))
    (define normalized-name
      (string-downcase
       (regexp-replace* #rx"[A-Z]+" name:str (λ (s) (~a "-" s)))))

    (format-id stx "marionette~a!" (regexp-replace #rx"[^:]*:" normalized-name "")))

  (define-syntax-class param
    (pattern  name:id               #:with spec #'name)
    (pattern [name:id]              #:with spec #'(name missing))
    (pattern [name:id default:expr] #:with spec #'(name default)))

  (syntax-parse stx
    [(_ (command-name:id param:param ...))
     (with-syntax ([name (make-command-name #'command-name (syntax-e #'command-name))]
                   [command-name:str (symbol->string (syntax-e #'command-name))]
                   [(command-param ...) (map
                                         (lambda (key name)
                                           #`(cons #,key #,name))
                                         (syntax-e #'('param.name ...))
                                         (syntax-e #'(param.name ...)))])
       #'(begin
           (define (name m param.spec ...)
             (marionette-send! m
                               command-name:str
                               (make-immutable-hasheq
                                (filter-map
                                 (lambda (pair)
                                   (cond
                                     [(missing? (cdr pair)) #f]
                                     [else pair]))
                                 (list command-param ...)))))
           (provide name)))]))

;; Supported commands can be found here:
;; https://searchfox.org/mozilla-central/source/testing/marionette/driver.js#3570
(define-marionette-command (WebDriver:AcceptAlert))
(define-marionette-command (WebDriver:AddCookie cookie))
(define-marionette-command (WebDriver:Back))
(define-marionette-command (WebDriver:CloseChromeWindow))
(define-marionette-command (WebDriver:CloseWindow))
(define-marionette-command (WebDriver:DeleteAllCookies))
(define-marionette-command (WebDriver:DeleteCookie name))
(define-marionette-command (WebDriver:DeleteSession))
(define-marionette-command (WebDriver:DismissAlert))
(define-marionette-command (WebDriver:ElementClear id))
(define-marionette-command (WebDriver:ElementClick id))
(define-marionette-command (WebDriver:ElementSendKeys id text))
(define-marionette-command (WebDriver:ExecuteAsyncScript script [args null]))
(define-marionette-command (WebDriver:ExecuteScript script [args null]))
(define-marionette-command (WebDriver:FindElement value [element] [using "css selector"]))
(define-marionette-command (WebDriver:FindElements value [element] [using "css selector"]))
(define-marionette-command (WebDriver:Forward))
(define-marionette-command (WebDriver:FullscreenWindow))
(define-marionette-command (WebDriver:GetActiveElement))
(define-marionette-command (WebDriver:GetAlertText))
(define-marionette-command (WebDriver:GetCapabilities))
(define-marionette-command (WebDriver:GetChromeWindowHandle))
(define-marionette-command (WebDriver:GetChromeWindowHandles))
(define-marionette-command (WebDriver:GetCookies))
(define-marionette-command (WebDriver:GetCurrentChromeWindowHandle))
(define-marionette-command (WebDriver:GetCurrentURL))
(define-marionette-command (WebDriver:GetElementAttribute id name))
(define-marionette-command (WebDriver:GetElementCSSValue id propertyName))
(define-marionette-command (WebDriver:GetElementProperty id name))
(define-marionette-command (WebDriver:GetElementRect id))
(define-marionette-command (WebDriver:GetElementTagName id))
(define-marionette-command (WebDriver:GetElementText id))
(define-marionette-command (WebDriver:GetPageSource))
(define-marionette-command (WebDriver:GetTimeouts))
(define-marionette-command (WebDriver:GetTitle))
(define-marionette-command (WebDriver:GetWindowHandle))
(define-marionette-command (WebDriver:GetWindowHandles))
(define-marionette-command (WebDriver:GetWindowRect))
(define-marionette-command (WebDriver:IsElementDisplayed id))
(define-marionette-command (WebDriver:IsElementEnabled id))
(define-marionette-command (WebDriver:IsElementSelected id))
(define-marionette-command (WebDriver:MaximizeWindow))
(define-marionette-command (WebDriver:MinimizeWindow))
(define-marionette-command (WebDriver:Navigate url))
(define-marionette-command (WebDriver:NewSession [timeouts] [pageLoadStrategy] [unhandledPromptBehavior] [acceptInsecureCerts]))
(define-marionette-command (WebDriver:NewWindow [focus #t] [private #f] [type "tab"]))
(define-marionette-command (WebDriver:PerformActions actions))
(define-marionette-command (WebDriver:Refresh))
(define-marionette-command (WebDriver:ReleaseActions))
(define-marionette-command (WebDriver:SendAlertText text))
(define-marionette-command (WebDriver:SetTimeouts script pageLoad implicit))
(define-marionette-command (WebDriver:SetWindowRect width height))
(define-marionette-command (WebDriver:Status))
(define-marionette-command (WebDriver:SwitchToFrame id [focus #t]))
(define-marionette-command (WebDriver:SwitchToParentFrame))
(define-marionette-command (WebDriver:SwitchToShadowRoot id))
(define-marionette-command (WebDriver:SwitchToWindow handle [focus #t]))
(define-marionette-command (WebDriver:TakeScreenshot full [id] [hash #f]))
