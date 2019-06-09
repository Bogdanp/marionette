#lang racket/base

(require marionette
         rackunit
         "common.rkt")

(provide
 browser-tests)

(define browser-tests
  (test-suite
   "browser"

   (test-suite
    "browser-{dis,}connect!"

    (test-case "can successfully connect and disconnect from a browser"
      (define b (browser-connect!))
      (browser-disconnect! b)))

   (test-suite
    "{set-,}browser-timeouts"

    (test-case "can set and retrieve timeouts"
      (call-with-browser!
       (lambda (b)
         (set-browser-timeouts! b (make-timeouts #:script 30000
                                                 #:page-load 300000))

         (define t (browser-timeouts b))
         (check-eq? (timeouts-script t) 30000)
         (check-eq? (timeouts-page-load t) 300000)
         (check-eq? (timeouts-implicit t) 0)))))

   (test-suite
    "browser-viewport-size"

    (test-case "can retrieve the viewport size"
      (call-with-browser!
       (lambda (b)
         (define-values (w h)
           (browser-viewport-size b))

         (check-true (> w 0))
         (check-true (> h 0))))))

   (test-suite
    "set-browser-viewport-size!"

    (test-case "can set the viewport size"
      (call-with-browser!
       (lambda (b)
         (set-browser-viewport-size! b 1400 900)
         (let-values ([(w h) (browser-viewport-size b)])
           (check-eq? w 1400)
           (check-eq? h 900))

         (set-browser-viewport-size! b 1920 1080)
         (let-values ([(w h) (browser-viewport-size b)])
           (check-eq? w 1920)
           (check-eq? h 1080))))))

   (test-suite
    "browser-capabilities"

    (test-case "can set and get capabilities"
      (define caps (make-capabilities #:page-load-strategy "none"
                                      #:unhandled-prompt-behavior "ignore"))
      (call-with-browser!
        #:capabilities caps
        (lambda (b)
          (check-equal? (browser-capabilities b) caps)))))

   (test-suite
    "browser-pages"

    (test-case "can list existing pages"
      (call-with-browser!
        (lambda (b)
          (check-true (> (length (browser-pages b)) 0))))))

   (test-suite
    "make-browser-page!"

    (test-case "can create new pages"
      (call-with-browser!
       (lambda (b)
         (check-not-false (make-browser-page! b))))))))

(module+ test
  (run-integration-tests browser-tests))
