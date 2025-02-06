#lang racket

(require marionette)

(call-with-marionette/browser/page!
 #:headless? #f
 (lambda (p)
   (page-goto! p "https://example.com")
   (call-with-page-pdf! p
     (lambda (data)
       (define filename (make-temporary-file "~a.pdf"))
       (with-output-to-file filename
         #:exists 'truncate/replace
         (lambda ()
           (write-bytes data)))
       (system* (find-executable-path "open") filename)))))
