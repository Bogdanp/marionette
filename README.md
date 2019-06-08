# marionette

A Racket library that lets you control Firefox via the [Marionette
Protocol].

## Quickstart

Install marionette:

    $ raco pkg install marionette

Run `Firefox` with the `-marionette` flag:

    $ /path/to/firefox -headless -marionette -safe-mode

Run this script:

``` racket
#lang racket

(require marionette)

(call-with-browser!
  (lambda (b)
    (call-with-page! b
      (lambda (p)
        (page-goto! p "https://racket-lang.org")
        (call-with-page-screenshot! p
          (lambda (data)
            (define filename (make-temporary-file))
            (with-output-to-file filename
              #:exists 'truncate/replace
              (lambda _
                (write-bytes data)))

            (system* (find-executable-path "open") filename)))))))
```

## Todos

* [ ] Alerts
* [ ] Cookies
* [ ] Downloads
* [ ] Frames


[Marionette Protocol]: https://firefox-source-docs.mozilla.org/testing/marionette/marionette/Protocol.html
