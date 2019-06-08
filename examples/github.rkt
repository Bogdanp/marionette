#lang racket

(require marionette)

(call-with-browser!
 (lambda (b)
   (call-with-page! b
     (lambda (p)
       (page-goto! p "https://github.com")

       (define search-bar
         (page-query-selector! p "[name=q]"))

       (element-type! search-bar "Bogdanp/marionette")
       (page-execute-async! p "arguments[0].closest(\"form\").submit()" (element-handle search-bar))
       (sleep 1) ;; TODO: add a wait to wait for page loads.

       (call-with-page-screenshot! p
         (lambda (data)
           (define filename (make-temporary-file "~a.png"))
           (with-output-to-file filename
             #:exists 'truncate/replace
             (lambda _
               (write-bytes data)))

           (system* (find-executable-path "open") filename)))))))
