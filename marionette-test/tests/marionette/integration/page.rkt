#lang racket/base

(require marionette
         net/url
         racket/string
         rackunit
         "common.rkt")

(provide
 page-tests)

(define page-tests
  (test-suite
   "page"

   (test-suite
    "page-close!"

    (test-case "can close pages"
      (call-with-browser!
       (lambda (b)
         (define p (make-browser-page! b))
         (check-not-false (member p (browser-pages b)))
         (page-close! p)
         (check-false (member p (browser-pages b)))))))

   (test-suite
    "page-refresh!"

    (test-case "can refresh the current page"
      (call-with-browser!
        (lambda (b)
          (call-with-page! b
            (lambda (p)
              (page-refresh! p)))))))

   (test-suite
    "page-goto!"

    (test-case "can navigate to urls"
      (call-with-browser!
        (lambda (b)
          (call-with-page! b
           (lambda (p)
             (page-goto! p "https://example.com")
             (check-equal? (page-title p) "Example Domain")
             (check-equal? (page-url p) (string->url "https://example.com/"))))))))

   (test-suite
    "page-execute-async!"

    (test-case "can execute asynchronous scripts"
      (call-with-browser!
        (lambda (b)
          (call-with-page! b
           (lambda (p)
             (define val
               (page-execute-async! p #<<SCRIPT
return new Promise((resolve) => {
  window.setTimeout(function() {
    resolve(42);
  }, 1000);
});
SCRIPT
                                    ))

             (check-equal? val 42))))))

    (test-case "can capture script execution errors"
      (call-with-browser!
        (lambda (b)
          (call-with-page! b
           (lambda (p)
             (check-exn
              exn:fail:marionette:page:script?
              (lambda _
                (page-execute-async! p #<<SCRIPT
throw new Error("an error!");
SCRIPT
                                     )))))))))

   (test-suite
    "page-query-selector!"

    (test-case "can fail to retrieve nonexistent elements"
      (call-with-browser!
       (lambda (b)
         (call-with-page! b
           (lambda (p)
             (check-false (page-query-selector! p ".idontexist")))))))

    (test-case "can retrieve elements"
      (call-with-browser!
        (lambda (b)
          (call-with-page! b
            (lambda (p)
              (page-goto! p "https://example.com")
              (check-not-false (page-query-selector! p "h1"))))))))

   (test-suite
    "page-query-selector-all!"

    (test-case "can retrieve lists of elements"
      (call-with-browser!
        (lambda (b)
          (call-with-page! b
            (lambda (p)
              (page-goto! p "https://example.com")
              (check-true (> (length (page-query-selector-all! p "h1")) 0))))))))

   (test-suite
    "page-content"

    (test-case "can retrieve a page's content"
      (call-with-browser!
        (lambda (b)
          (call-with-page! b
            (lambda (p)
              (page-goto! p "https://example.com")
              (check-true (string-contains? (page-content p) "Example Domain"))))))))

   (test-suite
    "set-page-content!"

    (test-case "can update a page's content"
      (call-with-browser!
        (lambda (b)
          (call-with-page! b
           (lambda (p)
             (define c "<h1>Hello!</h1>")
             (set-page-content! p c)
             (check-true (string-contains? (page-content p) c))))))))

   (test-suite
    "call-with-page-screenshot!"

    (test-case "can screenshot an entire page"
      (call-with-browser!
        (lambda (b)
          (call-with-page! b
           (lambda (p)
             (page-goto! p "https://example.com")
             (call-with-page-screenshot! p
               (lambda (data)
                 (check-not-false data)))))))))))

(module+ test
  (run-integration-tests page-tests))
