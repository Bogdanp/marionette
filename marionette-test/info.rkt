#lang info

(define collection 'multi)

(define deps '())
(define build-deps '("base"
                     "marionette-lib"
                     "rackunit-lib"))

(define update-implies '("marionette-lib"))
