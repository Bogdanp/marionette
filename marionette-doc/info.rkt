#lang info

(define collection "marionette")
(define scribblings '(("scribblings/marionette.scrbl" ())))

(define deps '("base"))
(define build-deps '("marionette-lib"
                     "sandbox-lib"
                     "scribble-lib"

                     "net-doc"
                     "racket-doc"))
(define update-implies '("marionette-lib"))
