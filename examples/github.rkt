#lang racket

(require marionette)

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

   (define search-bar
     (page-query-selector! p "[name=q]"))

   (element-type! search-bar "Bogdanp/marionette")
   (page-execute-async! p "arguments[0].closest(\"form\").submit()" (element-handle search-bar))
   (page-wait-for! p ".repo-list")

   (call-with-page-screenshot! p save&open)
   (call-with-element-screenshot! (page-query-selector! p "[name=q]") save&open)))
