#lang scribble/manual

@(require (for-label net/url
                     racket/base
                     racket/contract
                     racket/math
                     racket/string
                     marionette))

@title{Marionette}
@author[(author+email "Bogdan Popa" "bogdan@defn.io")]

@section[#:tag "intro"]{Introduction}

@(define protocol-link "https://firefox-source-docs.mozilla.org/testing/marionette/marionette/Protocol.html")

Marionette lets you control the Firefox web browser via the
@hyperlink[protocol-link]{Marionette Protocol}.

To use this library, you need to have a running Firefox instance with
the marionette protocol enabled.  To do this, all you have to do is
run the firefox binary with the @literal{-marionette} flag.

@section[#:tag "limitations"]{Limitations}

The protocol doesn't (seem to) support operating on more than one page
concurrently within one browser session.  To get around this, simply
initiate multiple browser sessions via @racket[call-with-browser!].

@section[#:tag "reference"]{Reference}
@defmodule[marionette]

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
@defmodule[marionette/browser]

@defproc[(browser? [b any/c]) boolean?]{
  Returns @racket[#t] when @racket[b] is a browser.
}

@defproc[(browser-connect! [#:host host non-empty-string? "127.0.0.1"]
                           [#:port port (integer-in 1 65535) 2828]
                           [#:capabilities capabilities capabilities? (make-capabilities)]) browser?]{
  Connects to the marionette server at @racket[host] and @racket[port]
  and returns a @racket[browser?] session.
}

@defproc[(browser-disconnect! [b browser?]) void?]{
  Disconnects @racket[b] from its server.
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
@defmodule[marionette/page]

@defproc[(page? [p any/c]) boolean?]{
  Returns @racket[#t] when @racket[p] is a page.
}

@defproc[(page=? [p1 page?]
                 [p2 page?]) boolean?]{
  Returns @racket[#t] when @racket[p1] and @racket[p2] represent the
  same page (i.e. they have the same id but are not necessarily the
  same object in memory).
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
  Ascertain the current "ready state" of @racket[p].
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
  Waits for an element matching the given CSS @racket[selector] to appear on
  @racket[p] or @racket[timeout] milliseconds to pass.  If
  @racket[visible?] is @racket[#t], then the element must be visible
  on the page for it to match.
}

@deftogether[
  (@defproc[(page-query-selector! [p page?]
                                  [selector non-empty-string?]) (or/c false/c element?)]
   @defproc[(page-query-selector-all! [p page?]
                                      [selector non-empty-string?]) (listof element?)])]{
  Query @racket[p] for either the first or all @racket[element?]s that
  match the given CSS selector.
}

@deftogether[
  (@defproc[(page-alert-text [p page?]) string?]
   @defproc[(page-alert-accept! [p page?]) void?]
   @defproc[(page-alert-dismiss! [p page?]) void?]
   @defproc[(page-alert-type! [p page?]
                              [text string?]) void?])]{
  Interact with the current prompt on @racket[p].  By default, all
  prompts are automatically dismissed, so you won't have anything to
  interact with.  To change this, specify a different unhandled prompt
  behavior in your @racket[capabilities?].
}

@defproc[(call-with-page-screenshot! [page page?]
                                     [proc (-> bytes? any)]
                                     [#:full? full? boolean? #t]) any]{
  Take a screenshot of @racket[page] and call @racket[proc] with the
  resulting @racket[bytes?].  @racket[full?] determines whether or not
  the entire page is captured.
}


@subsection[#:tag "reference/element"]{Element}
@defmodule[marionette/element]

@defproc[(element? [e any/c]) boolean?]{
  Returns @racket[#t] when @racket[e] is a element.
}

@defproc[(element=? [e1 element?]
                    [e2 element?]) boolean?]{
  Returns @racket[#t] when @racket[e1] and @racket[e2] represent the
  same element (i.e. they have the same handle but are not necessarily
  the same object in memory).
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
  Query @racket[e] for either the first or all @racket[element?]s
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
  (@defproc[(element-handle [e element?]) handle/c]
   @defproc[(element-tag [e element?]) string?]
   @defproc[(element-text [e element?]) string?]
   @defproc[(element-rect [e element?]) rect?])]{
  Access various @racket[e] fields.
}

@deftogether[
  (@defproc[(element-attribute [e element?]
                               [name string?]) (or/c false/c string?)]
   @defproc[(element-property [e element?]
                              [name string?]) (or/c false/c string?)])]{
  Retrieve @racket[e]'s attribute named @racket[name] statically and
  dynamically, respectively.
}

@defproc[(call-with-element-screenshot! [e element?]
                                        [p (-> bytes? any)]) any]{
  Take a screenshot of @racket[e] and call @racket[proc] with the
  resulting @racket[bytes?].
}


@subsection[#:tag "reference/capabilities"]{Capabilities}
@defmodule[marionette/capabilities]

@deftogether[
  (@defthing[page-load-strategy/c (or/c "none" "eager" "normal")]
   @defthing[unhandled-prompt-behavior/c (or/c "dismiss"
                                               "dismiss and notify"
                                               "accept"
                                               "accept and notify"
                                               "ignore")])]{

  Contracts used by the functions in this module.
}

@defstruct[capabilities ([timeouts timeouts?]
                         [page-load-strategy page-load-strategy/c]
                         [unhandled-prompt-behavior unhandled-prompt-behavior/c]
                         [accept-insecure-certs? boolean?])]{

  This struct is used to represent a session's capabilities.  Think of
  these as settings/behaviors that you can tweak when you create a new
  session via @racket[browser-connect!].
}

@defproc[(make-capabilities [#:timeouts timeouts timeouts? (make-timeouts)]
                            [#:page-load-strategy page-load-strategy page-load-strategy/c "normal"]
                            [#:unhandled-prompt-behavior unhandled-prompt-behavior unhandled-prompt-behavior/c "dismiss and notify"]
                            [#:accept-insecure-certs? accept-insecure-certs? boolean? #f]) capabilities?]{

  A convenience constructor for @racket[capabilities].
}


@subsection[#:tag "reference/timeouts"]{Timeouts}
@defmodule[marionette/timeouts]

@defstruct[timeouts ([script exact-nonnegative-integer?]
                     [page-load exact-nonnegative-integer?]
                     [implicit exact-nonnegative-integer?])]{

  This struct is used to represent the browser's timeout settings.
}

@defproc[(make-timeouts [#:script script exact-nonnegative-integer? 30000]
                        [#:page-load page-load exact-nonnegative-integer? 300000]
                        [#:implicit implicit exact-nonnegative-integer? 0]) timeouts?]{

  A convenience constructor for @racket[timeouts].
}


@subsection[#:tag "reference/rect"]{Rect}
@defmodule[marionette/rect]

@defstruct[rect ([x exact-integer?]
                 [y exact-integer?]
                 [w natural?]
                 [h natural?])]{

  This struct is used to represent an element's bounding client rect.
}
