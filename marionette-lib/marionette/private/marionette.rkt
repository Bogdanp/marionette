#lang racket/base

(require (for-syntax racket/base
                     racket/format
                     syntax/parse)
         json
         racket/async-channel
         racket/contract
         racket/function
         racket/list
         racket/match
         racket/string
         "transport.rkt"
         "util.rkt"
         "waiters.rkt")

(provide
 exn:fail:marionette?
 exn:fail:marionette

 exn:fail:marionette:command?
 exn:fail:marionette:command
 exn:fail:marionette:command-stacktrace

 make-marionette
 marionette?
 marionette-connect!
 marionette-disconnect!
 marionette-send!)

(define-logger marionette)

(struct exn:fail:marionette exn:fail ())
(struct exn:fail:marionette:command exn:fail:marionette (stacktrace))

(struct marionette
  (transport
   dispatcher
   waiters))

(define/contract (make-marionette host port)
  (-> non-empty-string? (integer-in 1 65535) marionette?)

  (define chan (make-async-channel))
  (define transport (make-transport #:host host
                                    #:port port
                                    #:chan chan))
  (define waiters (box (make-waiter-set)))
  (define dispatcher (make-dispatcher waiters chan))
  (marionette transport dispatcher waiters))

(define/contract (marionette-connect! m)
  (-> marionette? jsexpr?)
  (transport-connect! (marionette-transport m))
  (sync (marionette-send! m "WebDriver:NewSession" (hasheq 'capabilities (hasheq)))))

(define/contract (marionette-disconnect! m)
  (-> marionette? void?)
  (sync (marionette-send! m "WebDriver:DeleteSession"))
  (transport-disconnect! (marionette-transport m)))

(define/contract (marionette-send! m command [parameters (hasheq)])
  (->* (marionette? non-empty-string?) (jsexpr?) (evt/c jsexpr?))
  (define t (marionette-transport m))
  (unless (transport-live? t)
    (raise (exn:fail:marionette "not connected" (current-continuation-marks)) ))

  (let ([command-id #f]
        [command-chan #f])
    (box-swap! (marionette-waiters m) (lambda (ws)
                                        (define-values (command-id* command-chan* ws*)
                                          (waiter-set-emit ws))

                                        (begin0 ws*
                                          (set! command-id command-id*)
                                          (set! command-chan command-chan*))))
    (transport-send! t (list 0 command-id command parameters))
    (handle-evt command-chan (lambda (res)
                               (match res
                                 [(cons 'ok data) data]
                                 [(cons 'err data)
                                  (raise (exn:fail:marionette:command
                                          (hash-ref data 'message "")
                                          (current-continuation-marks)
                                          (hash-ref data 'stacktrace "")))])))))

(define (make-dispatcher waiters ->chan)
  (thread
   (lambda _
     (let loop ()
       (with-handlers ([exn:fail?
                        (lambda (e)
                          (log-marionette-warning (format "encountered unhandled exception: ~a" (exn-message e))))])
         (match (sync ->chan)
           [(list 1 command-id error-data 'null)
            (cond
              [(waiter-set-ref (unbox waiters) command-id)
               => (lambda (command-chan)
                    (log-marionette-debug (format "sending error to channel for command ~v" command-id))
                    (channel-put command-chan (cons 'err error-data)))]

              [else
               (log-marionette-warning (format "received error for unknown command ~v: ~a" command-id error-data))])]

           [(list 1 command-id 'null data)
            (cond
              [(waiter-set-ref (unbox waiters) command-id)
               => (lambda (command-chan)
                    (log-marionette-debug (format "sending data to channel for command ~v" command-id))
                    (channel-put command-chan (cons 'ok data)))]

              [else
               (log-marionette-warning (format "received data for unknown command ~v: ~a" command-id data))])]

           [payload
            (log-marionette-warning (format "received invalid data: ~a" payload))]))

       (loop)))))

(define-syntax (define-marionette-command stx)
  (define (make-command-name stx name)
    (define name:str (symbol->string name))
    (define normalized-name
      (string-downcase
       (regexp-replace* #rx"[A-Z]+" name:str (lambda (s)
                                               (~a "-" s)))))

    (datum->syntax stx
                   (string->symbol
                    (~a "marionette" (regexp-replace #rx"[^:]*:" normalized-name "") "!"))))

  (define-syntax-class param
    (pattern  name:id               #:with spec #'name)
    (pattern [name:id]              #:with spec #'(name 'missing))
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
                                     [(eq? (cdr pair) 'missing) #f]
                                     [else pair]))
                                 (list command-param ...)))))
           (provide name)))]))

;; Supported commands can be found here:
;; https://searchfox.org/mozilla-central/source/testing/geckodriver/src/marionette.rs
(define-marionette-command (WebDriver:Back))
(define-marionette-command (WebDriver:ElementClear id))
(define-marionette-command (WebDriver:ElementClick id))
(define-marionette-command (WebDriver:ElementSendKeys id text))
(define-marionette-command (WebDriver:ExecuteAsyncScript script [args null]))
(define-marionette-command (WebDriver:ExecuteScript script [args null]))
(define-marionette-command (WebDriver:FindElement value [element] [using "css selector"]))
(define-marionette-command (WebDriver:FindElements value [element] [using "css selector"]))
(define-marionette-command (WebDriver:Forward))
(define-marionette-command (WebDriver:GetCurrentURL))
(define-marionette-command (WebDriver:GetElementAttribute id name))
(define-marionette-command (WebDriver:GetElementProperty id name))
(define-marionette-command (WebDriver:GetElementRect id))
(define-marionette-command (WebDriver:GetElementTagName id))
(define-marionette-command (WebDriver:GetElementText id))
(define-marionette-command (WebDriver:GetPageSource))
(define-marionette-command (WebDriver:GetTimeouts))
(define-marionette-command (WebDriver:GetTitle))
(define-marionette-command (WebDriver:GetWindowHandles))
(define-marionette-command (WebDriver:IsElementDisplayed id))
(define-marionette-command (WebDriver:IsElementEnabled id))
(define-marionette-command (WebDriver:IsElementSelected id))
(define-marionette-command (WebDriver:Navigate url))
(define-marionette-command (WebDriver:Refresh))
(define-marionette-command (WebDriver:SetTimeouts script pageLoad implicit))
(define-marionette-command (WebDriver:SetWindowRect width height))
(define-marionette-command (WebDriver:Status))
(define-marionette-command (WebDriver:SwitchToWindow name [focus #t]))
(define-marionette-command (WebDriver:TakeScreenshot full [id] [hash #f]))
