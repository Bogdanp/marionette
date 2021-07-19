# marionette

[![CI](https://github.com/Bogdanp/marionette/actions/workflows/ci.yml/badge.svg)](https://github.com/Bogdanp/marionette/actions/workflows/ci.yml)

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
            (define filename (make-temporary-file "~a.png"))
            (with-output-to-file filename
              #:exists 'truncate/replace
              (lambda _
                (write-bytes data)))

            (system* (find-executable-path "open") filename)))))))
```

## Tips

To run a headless, marionette-enabled Firefox while you've got another
instance of the browser open, add the `-no-remote` flag:

    $ /path/to/firefox -no-remote -headless -marionette -safe-mode

It's advisable that you use a separate profile as well:

    $ /path/to/firefox -P marionette -no-remote -headless -marionette -safe-mode

You can create new profiles by visiting `about:profiles` in the
browser.

## Todos

* [ ] Cookies
* [ ] Frames

[Marionette Protocol]: https://firefox-source-docs.mozilla.org/testing/marionette/marionette/Protocol.html
