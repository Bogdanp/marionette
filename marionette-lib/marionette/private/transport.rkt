#lang racket/base

(require json
         racket/async-channel
         racket/contract
         racket/match
         racket/string
         racket/tcp)

(provide
 current-transport-buffer-size
 make-transport
 transport?
 transport-connect!
 transport-disconnect!
 transport-live?
 transport-send!)

(define-logger marionette-transport)

(define/contract current-transport-buffer-size
  (parameter/c exact-positive-integer?)
  (make-parameter 65535))

(struct connection-opts (host port))
(struct transport
  (opts
   chan->
   [in #:auto #:mutable]
   [out #:auto #:mutable]
   [receiver #:auto #:mutable])
  #:auto-value #f)

(define/contract (make-transport #:host host
                                 #:port port
                                 #:chan chan)
  (-> #:host non-empty-string?
      #:port (integer-in 1 65535)
      #:chan (async-channel/c jsexpr?)
      transport?)
  (transport (connection-opts host port) chan))

(define/contract (transport-connect! t)
  (-> transport? void?)
  (define-values (in out)
    (tcp-connect (connection-opts-host (transport-opts t))
                 (connection-opts-port (transport-opts t))))

  (define preamble (bytes->jsexpr (read-data in)))
  (unless (and (equal? (hash-ref preamble 'applicationType #f) "gecko")
               (equal? (hash-ref preamble 'marionetteProtocol #f) 3))
    (raise-user-error 'transport-connect! "the other end doesn't implement the v3 marionette protocol"))

  (set-transport-in! t in)
  (set-transport-out! t out)
  (set-transport-receiver! t (make-receiver t)))

(define/contract (transport-disconnect! t)
  (-> transport? void?)
  (kill-thread (transport-receiver t))
  (close-input-port (transport-in t))
  (close-output-port (transport-out t)))

(define/contract (transport-live? t)
  (-> transport? boolean?)
  (not (or (thread-dead? (transport-receiver t))
           (port-closed? (transport-in       t))
           (port-closed? (transport-out      t)))))

(define/contract (transport-send! t data)
  (-> transport? jsexpr? void?)
  (void
   (parameterize ([current-output-port (transport-out t)])
     (define data:str (jsexpr->bytes data))

     (write-string (number->string (bytes-length data:str)))
     (write-bytes #":")
     (write-bytes data:str)
     (flush-output))))

(define prefix-re
  #rx"([1-9][0-9]*):")

(define (read-data in)
  (match-define (list _ nbytes:str)
    (regexp-match prefix-re in))

  (read-bytes (string->number (bytes->string/utf-8 nbytes:str)) in))

(define (make-receiver t)
  (thread
   (lambda _
     (define in (transport-in t))
     (define chan-> (transport-chan-> t))

     (let loop ()
       (match (read-data in)
         [(? eof-object?)
          (log-marionette-transport-warning "unexpected eof from the remote end")]

         [data
          (with-handlers ([exn:fail?
                           (lambda (e)
                             (log-marionette-transport-warning (format "failed to parse payload: ~v" (exn-message e)))
                             (loop))])
            (log-marionette-transport-debug (format "received payload: ~v" data))
            (async-channel-put chan-> (bytes->jsexpr data)))

          (loop)])))))

(module+ test
  (require rackunit
           rackunit/text-ui)

  (define (call-with-receiver-tester p)
    (define-values (in out) (make-pipe))
    (define c (make-async-channel))
    (define t (transport #f c))
    (set-transport-in! t in)

    (dynamic-wind
      (lambda _
        (set-transport-receiver! t (make-receiver t)))
      (lambda _
        (p c (lambda (bs)
               (write-bytes bs out))))
      (lambda _
        (kill-thread (transport-receiver t)))))

  (run-tests
   (test-suite
    "transport"

    (test-suite
     "make-receiver"

     (test-case "received messages are sent over a channel"
       (call-with-receiver-tester
        (lambda (c send!)
          (send! #"2:{}")
          (check-equal? (async-channel-get c) (hasheq))

          (send! #"50:{\"applicationType\":\"gecko\",\"marionetteProtocol\":3}")
          (check-equal? (async-channel-get c) (hasheq 'applicationType "gecko"
                                                      'marionetteProtocol 3)))))

     (test-case "invalid prefixes are ignored"
       (call-with-receiver-tester
        (lambda (c send!)
          (send! #"a2:{}")
          (check-equal? (async-channel-get c) (hasheq))

          (send! #"2:{}")
          (check-equal? (async-channel-get c) (hasheq)))))

     (test-case "invalid json payloads are ignored"
       (call-with-receiver-tester
        (lambda (c send!)
          (send! #"2:xx")
          (check-false (async-channel-try-get c))

          (send! #"2:{}")
          (check-equal? (async-channel-get c) (hasheq)))))))))
