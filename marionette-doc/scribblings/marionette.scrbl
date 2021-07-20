#lang scribble/manual

@(require racket/runtime-path
          racket/sandbox
          scribble/example
          (for-label json
                     marionette
                     net/url
                     racket/base
                     racket/contract
                     racket/file
                     racket/math
                     racket/string))

@title{Marionette}
@author[(author+email "Bogdan Popa" "bogdan@defn.io")]
@defmodule[marionette]

@section[#:tag "intro"]{Introduction}

@(define protocol-link "https://firefox-source-docs.mozilla.org/testing/marionette/marionette/Protocol.html")

Marionette lets you control the Firefox web browser via the
@hyperlink[protocol-link]{Marionette Protocol}. This is the same
interface used by Selenium, via geckodriver.

To use this library, you need to have a running Firefox instance with
the marionette protocol enabled.  To do this, all you have to do is
run the firefox binary with the @literal{-marionette} flag.


@section[#:tag "examples"]{Examples}

Here are some simple examples of using marionette. The first saves a PNG file
containing an image of the current racket-lang.org webpage:

@(begin
   (define-syntax-rule (interaction e ...) (examples #:label #f e ...))
   (define-runtime-path log-file "examples.rktd")
   (define log-mode (if (getenv "MARIONETTE_RECORD") 'record 'replay))
   (define (make-ex-eval log-file)
     (make-log-based-eval log-file log-mode))
   (define ex-eval (make-ex-eval log-file)))


@interaction[
#:eval ex-eval
(require marionette
         racket/file)

(code:line)
(define data
  (call-with-marionette/browser/page!
   (lambda (p)
     (page-goto! p "https://racket-lang.org")
     (call-with-page-screenshot! p values))))

(code:line)
(define filename
  (make-temporary-file "~a.png"))

(code:line)
(with-output-to-file filename
  #:exists 'truncate/replace
  (lambda ()
    (write-bytes data)))

(code:line)
(printf "filename of page screenshot: ~v\n" (path->string filename))
]

This next example dowloads the HTML content of a password-protected
web page:

@codeblock|{
#lang racket

(require marionette)

(define username "zipnarg")

(define nextcatalog-csc-minor-url
 "https://nextcatalog-admin.calpoly.edu/collegesandprograms/\
collegeofengineering/computersciencesoftwareengineering/\
computerscienceminor/")

(define profile-path
 (build-path "/Users/zipnarg/Library/Application Support/"
             "Firefox/Profiles/s9y75gtr.wazoo"))

(define content
 (call-with-marionette/browser/page!
  #:profile profile-path
  (λ (page)
    (page-goto! page nextcatalog-csc-minor-url)
    (printf "ready? ~v\n" (page-loaded? page))
    (printf "page title: ~v\n" (page-title page))
    (let ()
      (define username-elt (page-query-selector! page "#username"))
      (cond [username-elt
             (element-type! username-elt username)]
            [else
             (error 'login "couldn't find username field.")]))
    (let ()
      (define password-elt (page-query-selector! page "#password"))
      (cond [password-elt
             (printf "password: ")
             (define str (read-line))
             (element-type! password-elt str)]
            [else
             (error 'login "couldn't find password field.")]))
    (let ()
      (define form-button (page-query-selector! page ".form-button"))
      (cond [form-button
             (element-click! form-button)]
            [else
             (error 'login "couldn't find login button.")]))
    ;; wait until the page is ready and the title is no longer
    ;; that of the login page
    (let loop ()
      (define loaded? (page-loaded? page))
      (cond [loaded?
             (define title (page-title page))
             (cond [(equal? title "Cal Poly Web Login Service")
                    (printf "still login screen title, waiting...\n")
                    (sleep 1)
                    (loop)]
                   [else 'ok])]
            [else
             (printf "not ready, waiting...\n")
             (sleep 1)
             (loop)]))
    (printf "final page title: ~v\n" (page-title page))
    (page-content page))))
}|

@section[#:tag "reference"]{Reference}

@deftogether[
  (@defproc[(start-marionette! [#:command command absolute-path? "/usr/local/bin/firefox"]
                               [#:profile profile (or/c false/c absolute-path?) #f]
                               [#:port port (or/c false/c (integer-in 1 65535)) #f]
                               [#:safe-mode? safe-mode? boolean? #t]
                               [#:headless? headless? boolean? #t]
                               [#:timeout timeout exact-nonnegative-integer? 5]) (-> void?)]
   @defproc[(call-with-marionette! [p (-> any)]) any]
   @defproc[(call-with-marionette/browser! [p (-> browser? any)]) any]
   @defproc[(call-with-marionette/browser/page! [p (-> page? any)]) any])]{

  Start a marionette-enabled instance of the Firefox browser using
  @racket[profile].  The return value is a procedure that can be used
  to stop the browser.

  The @racket[command] argument controls the path to the firefox
  binary.  If not provided, the system @exec{PATH} is searched along
  with the @exec{/Applications} folder on macOS.

  If @racket[profile] is @racket[#f], then a temporary path si created
  for the profile and it it subsequently removed when the browser is
  stopped.

  If @racket[port] is provided, then the @racket[profile] will be
  modified to instruct the marionette server to listen on that port.

  @racket[call-with-marionette!] accepts the same keyword arguments
  that @racket[start-marionette!] does.  It starts the browser,
  applies its @racket[p] argument then immediately stops the browser.

  @racket[call-with-marionette/browser!] composes
  @racket[call-with-marionette!] and @racket[call-with-browser!]
  together.  Keyword arguments are passed through to
  @racket[start-marionette!].

  @racket[call-with-marionette/browser/page!] composes
  @racket[call-with-marionette/browser!] and @racket[call-with-page!]
  together.  Keyword arguments are passed through to
  @racket[start-marionette!].
}

@defproc[(call-with-browser! [p (-> browser? any)]
                             [#:host host non-empty-string? "127.0.0.1"]
                             [#:port port (integer-in 1 65535) 2828]
                             [#:capabilities capabilities capabilities? (make-capabilities)]) any]{
  Calls @racket[p] after initiating a new browser session and
  disconnects after @racket[p] finishes executing.
}

@defproc[(call-with-page! [b browser?]
                          [p (-> page? any)])
                          any]{
  Calls @racket[p] after creating a new page and closes said page
  after @racket[p] finishes executing.
}

@subsection[#:tag "reference/browser"]{Browser}

@deftech{Browsers} represent a connection to a marionette-driven
instance of Firefox.  Browsers are not thread-safe, nor is it safe to
interleave commands against the same marionette server.  If you need
concurrency, then create multiple marionettes and control them
separately.

@defproc[(browser? [b any/c]) boolean?]{
  Returns @racket[#t] when @racket[b] is a @tech{browser}.
}

@defproc[(browser-connect! [#:host host non-empty-string? "127.0.0.1"]
                           [#:port port (integer-in 1 65535) 2828]
                           [#:capabilities capabilities capabilities? (make-capabilities)]) browser?]{
  Connects to the marionette server at @racket[host] and @racket[port]
  and returns a @tech{browser} session.
}

@defproc[(browser-disconnect! [b browser?]) void?]{
  Disconnects @racket[b] from its marionette.
}

@deftogether[
  (@defproc[(browser-timeouts [b browser?]) timeouts?]
   @defproc[(set-browser-timeouts! [b browser?]
                                   [t timeouts?]) void?])]{
  Get or set the @racket[b]'s current timeout settings.
}

@deftogether[
  (@defproc[(browser-viewport-size [b browser?]) (values exact-nonnegative-integer?
                                                         exact-nonnegative-integer?)]
   @defproc[(set-browser-viewport-size! [b browser?]
                                        [w exact-nonnegative-integer?]
                                        [h exact-nonnegative-integer?]) void?])]{
  Get or set @racket[b]'s current viewport size.
}

@defproc[(make-browser-page! [b browser?]) page?]{
  Open a new page in @racket[b] and return it.
}

@defproc[(browser-capabilities [b browser?]) capabilities?]{
  Retrieve the @racket[capabilities?] for @racket[b].
}

@defproc[(browser-pages [b browser?]) (listof page?)]{
  Lists all the pages belonging to @racket[b].
}

@defproc[(browser-focus! [b browser?]
                         [p page?]) void?]{
  Makes @racket[p] the currently active page.
}


@subsection[#:tag "reference/page"]{Page}

@defproc[(page? [p any/c]) boolean?]{
  Returns @racket[#t] when @racket[p] is a page.
}

@defproc[(page=? [p1 page?]
                 [p2 page?]) boolean?]{
  Returns @racket[#t] when @racket[p1] and @racket[p2] have the same
  handle and belong to the same marionette.
}

@defproc[(page-close! [p page?]) void?]{
  Tells the browser to close @racket[p].
}

@defproc[(page-refresh! [p page?]) void?]{
  Tells the browser to refresh @racket[p].
}

@defproc[(page-goto! [p page?]
                     [location (or/c string? url?)]) void?]{
  Navigates @racket[p] to @racket[location].
}

@deftogether[
  (@defproc[(page-go-back! [p page?]) void?]
   @defproc[(page-go-forward! [p page?]) void?])]{
  Moves @racket[p] backward and forward through its history.
}

@defproc[(page-execute-async! [p page?]
                              [s string?]
                              [arg any/c] ...) jsexpr?]{
  Executes the script @racket[s] on @racket[p] and returns its result.
}

@deftogether[
  (@defproc[(page-interactive? [p page?]) boolean?]
   @defproc[(page-loaded? [p page?]) boolean?])]{
  Ascertains the current "ready state" of @racket[p].
}

@deftogether[
  (@defproc[(page-title [p page?]) string?]
   @defproc[(page-url [p page?]) url?])]{
  Accessors for @racket[p]'s title and url, respectively.
}

@deftogether[
  (@defproc[(page-content [p page?]) string?]
   @defproc[(set-page-content! [p page?]
                               [s string?]) void?])]{
  Get or set @racket[p]'s HTML content.
}

@defproc[(page-wait-for! [p page?]
                         [selector non-empty-string?]
                         [#:timeout timeout (and/c real? (not/c negative?)) 30]
                         [#:visible? visible? boolean? #t]) (or/c false/c element?)]{
  Waits for an element matching the given CSS @racket[selector] to
  appear on @racket[p] or @racket[timeout] milliseconds to pass. If
  @racket[visible?] is @racket[#t], then the element must be visible on
  the page for it to match.
}

@deftogether[
  (@defproc[(page-query-selector! [p page?]
                                  [selector non-empty-string?]) (or/c false/c element?)]
   @defproc[(page-query-selector-all! [p page?]
                                      [selector non-empty-string?]) (listof element?)])]{
  Queries @racket[p] for either the first or all @racket[element?]s
  that match the given CSS selector.
}

@deftogether[
  (@defproc[(page-alert-text [p page?]) string?]
   @defproc[(page-alert-accept! [p page?]) void?]
   @defproc[(page-alert-dismiss! [p page?]) void?]
   @defproc[(page-alert-type! [p page?]
                              [text string?]) void?])]{
  Interacts with the current prompt on @racket[p].  By default, all
  prompts are automatically dismissed, so you won't have anything to
  interact with.  To change this, specify a different unhandled prompt
  behavior in your @tech{capabilities}.
}

@defproc[(call-with-page-pdf! [page page?]
                              [proc (-> bytes? any)]) any]{

  Converts the contents of @racket[page] to a PDF and passes the
  resulting bytes to @racket[proc].
}

@defproc[(call-with-page-screenshot! [page page?]
                                     [proc (-> bytes? any)]
                                     [#:full? full? boolean? #t]) any]{
  Takes a screenshot of @racket[page] and calls @racket[proc] with the
  resulting @racket[bytes?].  @racket[full?] determines whether or not
  the entire page is captured.
}


@subsection[#:tag "reference/element"]{Element}

@deftech{Elements} represent individual elements on a specific page.
They are only valid for as long as the page they were queried from
active. That is, if you query an element and then navigate off the page
you got it from, it becomes invalid.

@defproc[(element? [e any/c]) boolean?]{
  Returns @racket[#t] when @racket[e] is an @tech{element}.
}

@defproc[(element=? [e1 element?]
                    [e2 element?]) boolean?]{
  Returns @racket[#t] when @racket[e1] and @racket[e2] have the same
  handle and belong to the same page.
}

@defproc[(element-click! [e element?]) void?]{
  Clicks on @racket[e].
}

@defproc[(element-clear! [e element?]) void?]{
  Clears @racket[e]'s contents if it is an HTMLInputElement.
}

@defproc[(element-type! [e element?]
                        [text string?]) void]{
  Types @racket[text] into @racket[e].
}

@deftogether[
  (@defproc[(element-query-selector! [e element?]
                                     [selector non-empty-string?]) (or/c false/c element?)]
   @defproc[(element-query-selector-all! [e element?]
                                         [selector non-empty-string?]) (listof element?)])]{
  Queries @racket[e] for either the first or all @racket[element?]s
  belonging to it that match the given CSS selector.
}

@deftogether[
  (@defproc[(element-enabled? [e element?]) boolean?]
   @defproc[(element-selected? [e element?]) boolean?]
   @defproc[(element-visible? [e element?]) boolean?])]{
  Returns @racket[#t] if @racket[e] is enabled, selected or visible,
  respectively.
}

@deftogether[
  (@defproc[(element-tag [e element?]) string?]
   @defproc[(element-text [e element?]) string?]
   @defproc[(element-rect [e element?]) rect?])]{
  Accessors for various @racket[e] fields.
}

@deftogether[
  (@defproc[(element-attribute [e element?]
                               [name string?]) (or/c false/c string?)]
   @defproc[(element-property [e element?]
                              [name string?]) (or/c false/c string?)])]{
  Retrieves @racket[e]'s attribute named @racket[name] statically and
  dynamically, respectively.
}

@defproc[(call-with-element-screenshot! [e element?]
                                        [p (-> bytes? any)]) any]{
  Takes a screenshot of @racket[e] and calls @racket[proc] with the
  resulting @racket[bytes?].
}

@defstruct[rect ([x real?]
                 [y real?]
                 [w real?]
                 [h real?])]{

  Represents an @tech{element}'s bounding client rect.
}


@subsection[#:tag "reference/capabilities"]{Capabilities}

@deftogether[
  (@defthing[page-load-strategy/c (or/c 'none 'eager 'normal)]
   @defthing[unhandled-prompt-behavior/c (or/c 'dismiss
                                               'dismiss-and-notify
                                               'accept
                                               'accept-and-notify
                                               'ignore)])]{

  Contracts used by the functions in this module.
}

@deftogether[(
  @defstruct[capabilities ([timeouts timeouts?]
                           [page-load-strategy page-load-strategy/c]
                           [unhandled-prompt-behavior unhandled-prompt-behavior/c]
                           [accept-insecure-certs? boolean?])]
  @defproc[(make-capabilities [#:timeouts timeouts timeouts? (make-timeouts)]
                              [#:page-load-strategy page-load-strategy page-load-strategy/c 'normal]
                              [#:unhandled-prompt-behavior unhandled-prompt-behavior unhandled-prompt-behavior/c 'dismiss-and-notify]
                              [#:accept-insecure-certs? accept-insecure-certs? boolean? #f]) capabilities?]
)]{

  Represents a session's capabilities.  @deftech{Capabilities} control
  various settings and behaviors of the sessions created via
  @racket[browser-connect!].
}


@subsection[#:tag "reference/timeouts"]{Timeouts}

@deftogether[(
  @defstruct[timeouts ([script exact-nonnegative-integer?]
                       [page-load exact-nonnegative-integer?]
                       [implicit exact-nonnegative-integer?])]
  @defproc[(make-timeouts [#:script script exact-nonnegative-integer? 30000]
                          [#:page-load page-load exact-nonnegative-integer? 300000]
                          [#:implicit implicit exact-nonnegative-integer? 0]) timeouts?]
)]{

  @deftech{Timeouts} let you control how long the browser will wait
  for various operations to finish before raising an exception.
}
