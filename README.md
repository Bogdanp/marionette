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

* [ ] ~~Alerts~~
* [ ] Cookies
* [ ] Frames

## Notes

### Alerts

The commands for alerts are all there, but there doesn't appear to be
a way to set a global alert handler so all alerts are immediately
dismissed.

Reading the Web Driver protocol section on [prompts], it's not clear
to me how prompt handlers are supposed to be set and the marionette
server doesn't appear to expose a way to do it either.

[prompts]: https://w3c.github.io/webdriver/#dfn-user-prompt-handler


[Marionette Protocol]: https://firefox-source-docs.mozilla.org/testing/marionette/marionette/Protocol.html
