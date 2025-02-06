#lang racket

(require marionette
         marionette/key)

(define (save&open data)
  (define filename (make-temporary-file "~a.png"))
  (with-output-to-file filename
    #:exists 'truncate/replace
    (lambda ()
      (write-bytes data)))
  (system* (find-executable-path "open") filename))

(call-with-marionette/browser/page!
 (lambda (p)
   (page-goto! p "https://github.com")
   (element-click! (page-wait-for! p "button.header-search-button"))

   (define search-bar
     (page-query-selector! p "[name=query-builder-test]"))

   (element-type! search-bar "Bogdanp/marionette")
   (element-type! search-bar (string key:return))

   (define results-list
     (page-wait-for! p "[data-test-id=results-list]"))

   (call-with-page-screenshot! p save&open)
   (call-with-element-screenshot! results-list save&open)))
