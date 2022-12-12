#lang info

(define license 'BSD-3-Clause)
(define collection "marionette")
(define scribblings '(("scribblings/marionette.scrbl" ())))

(define deps '("base"))
(define build-deps '("marionette-lib"
                     "sandbox-lib"
                     "scribble-lib"

                     "net-doc"
                     "racket-doc"))
(define update-implies '("marionette-lib"))
