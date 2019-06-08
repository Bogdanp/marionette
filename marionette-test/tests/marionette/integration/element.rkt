#lang racket/base

(require marionette
         net/url
         racket/string
         rackunit
         "common.rkt")

(provide
 element-tests)

(define element-tests
  (test-suite
   "element"

   (test-suite
    "element-click!"

    (test-case "can click on an element"
      (call-with-browser!
        (lambda (b)
          (call-with-page! b
            (lambda (p)
              (set-page-content! p "<a href=\"https://example.com\">click me</a>")
              (define e (page-query-selector! p "a"))
              (element-click! e)
              (check-equal? (page-url p) (string->url "https://example.com/"))))))))

   (test-suite
    "element-type!"

    (test-case "can type inside an element"
      (call-with-browser!
        (lambda (b)
          (call-with-page! b
            (lambda (p)
              (set-page-content! p "<input>")
              (define e (page-query-selector! p "input"))
              (element-type! e "hello")
              (check-equal? (element-property e "value") "hello")))))))

   (test-suite
    "element-query-selector!"

    (test-case "can fail to retrieve nonexistent elements"
      (call-with-browser!
        (lambda (b)
          (call-with-page! b
            (lambda (p)
              (set-page-content! p "<h1>Hello!")
              (define e (page-query-selector! p "h1"))
              (check-false (element-query-selector! e ".idontexist")))))))

    (test-case "can retrieve elements' children"
      (call-with-browser!
        (lambda (b)
          (call-with-page! b
            (lambda (p)
              (set-page-content! p "<h1>An anchor: <a>example")
              (define e (page-query-selector! p "h1"))
              (check-not-false (element-query-selector! e "a"))))))))

   (test-suite
    "element-enabled?"

    (test-case "returns #f if an element is disabled"
      (call-with-browser!
        (lambda (b)
          (call-with-page! b
            (lambda (p)
              (set-page-content! p "<input disabled>")
              (define e (page-query-selector! p "input"))
              (check-false (element-enabled? e)))))))

    (test-case "returns #t if an element is enabled"
      (call-with-browser!
        (lambda (b)
          (call-with-page! b
            (lambda (p)
              (set-page-content! p "<h1>Hello")
              (define e (page-query-selector! p "h1"))
              (check-true (element-enabled? e))))))))

   (test-suite
    "element-selected?"

    (test-case "returns #f if an element is not selected"
      (call-with-browser!
        (lambda (b)
          (call-with-page! b
            (lambda (p)
              (set-page-content! p "<input>")
              (define e (page-query-selector! p "input"))
              (check-false (element-selected? e)))))))

    #;
    (test-case "returns #t if an element is selected"
      (call-with-browser!
        (lambda (b)
          (call-with-page! b
            (lambda (p)
              (set-page-content! p "<input type=\"text\">")
              (define e (page-query-selector! p "input"))
              (element-click! e)
              (check-true (element-selected? e))))))))

   (test-suite
    "element-visible?"

    (test-case "returns #f if an element is invisible"
      (call-with-browser!
        (lambda (b)
          (call-with-page! b
            (lambda (p)
              (set-page-content! p "<h1 style=\"display: none\">Hello!")
              (define e (page-query-selector! p "h1"))
              (check-false (element-visible? e)))))))

    (test-case "returns #t if an element is visible"
      (call-with-browser!
        (lambda (b)
          (call-with-page! b
            (lambda (p)
              (set-page-content! p "<h1>Hello")
              (define e (page-query-selector! p "h1"))
              (check-true (element-visible? e))))))))

   (test-suite
    "element-tag"

    (test-case "can retrieve an element's tag"
      (call-with-browser!
        (lambda (b)
          (call-with-page! b
            (lambda (p)
              (set-page-content! p "<h1>Hello")
              (define e (page-query-selector! p "h1"))
              (check-equal? (element-tag e) "h1")))))))

   (test-suite
    "element-attribute"

    (test-case "can fail to retrieve nonexistent attributes"
      (call-with-browser!
        (lambda (b)
          (call-with-page! b
            (lambda (p)
              (set-page-content! p "<a>a link</a>")
              (define e (page-query-selector! p "a"))
              (check-false (element-attribute e "href")))))))

   (test-suite
    "element-text"

    (test-case "can retrieve an element's inner text"
      (call-with-browser!
        (lambda (b)
          (call-with-page! b
            (lambda (p)
              (set-page-content! p "<h1>Hello")
              (define e (page-query-selector! p "h1"))
              (check-equal? (element-text e) "Hello")))))))

    (test-case "can retrieve an existing attribute"
      (call-with-browser!
        (lambda (b)
          (call-with-page! b
            (lambda (p)
              (set-page-content! p "<a href=\"https://example.com\">a link</a>")
              (define e (page-query-selector! p "a"))
              (check-equal? (element-attribute e "href") "https://example.com")))))))

   (test-suite
    "element-rect"

    (test-case "can retrieve an element's bounding rect"
      (call-with-browser!
        (lambda (b)
          (call-with-page! b
            (lambda (p)
              (set-page-content! p "<h1>Hello")
              (define e (page-query-selector! p "h1"))
              (check-true (rect? (element-rect e)))))))))

   (test-suite
    "call-with-element-screenshot!"

    (test-case "can screenshot elements on a page"
      (call-with-browser!
        (lambda (b)
          (call-with-page! b
            (lambda (p)
              (page-goto! p "https://example.com")
              (define e (page-query-selector! p "h1"))
              (call-with-element-screenshot! e
                (lambda (data)
                  (check-true (> (bytes-length data) 0))))))))))))

(module+ test
  (run-integration-tests element-tests))
