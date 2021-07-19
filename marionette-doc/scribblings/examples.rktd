;; This file was created by make-log-based-eval
((require marionette racket/file)
 ((3) 0 () 0 () () (c values c (void)))
 #""
 #"")
((define data
   (call-with-marionette/browser/page!
    (lambda (p)
      (page-goto! p "https://racket-lang.org")
      (call-with-page-screenshot! p values))))
 ((3) 0 () 0 () () (c values c (void)))
 #""
 #"")
((define filename (make-temporary-file "~a.png"))
 ((3) 0 () 0 () () (c values c (void)))
 #""
 #"")
((with-output-to-file
  filename
  #:exists
  'truncate/replace
  (lambda () (write-bytes data)))
 ((3) 0 () 0 () () (q values 791931))
 #""
 #"")
((printf "filename of page screenshot: ~v\n" (path->string filename))
 ((3) 0 () 0 () () (c values c (void)))
 #"filename of page screenshot: \"/var/folders/6s/8kt06x656dddy8z5y0jmf_fc0000gn/T/16266838661626683866996.png\"\n"
 #"")
