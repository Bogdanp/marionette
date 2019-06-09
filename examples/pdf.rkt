#lang racket

;; This module demonstrates how you could potentially generate a PDF
;; from a web page, though jsPDF still needs to be further improved
;; before this is viable.

(require net/base64
         marionette)

(define (call-with-page-pdf! page p)
  (define data-url
    (page-execute-async! page #<<SCRIPT
function addScript(uri) {
  return new Promise((resolve) => {
    const script = document.createElement("script");
    script.src = uri;
    script.addEventListener("load", resolve);
    document.body.appendChild(script);
  });
}

function makePDF() {
  return new Promise((resolve) => {
    const doc = new jsPDF();
    doc.html(document.body, {callback: resolve});
  });
}

return (
  addScript("https://cdn.jsdelivr.net/npm/html2canvas@1.0.0-rc.1/dist/html2canvas.min.js").
    then(() => addScript("https://unpkg.com/jspdf@latest/dist/jspdf.min.js")).
    then(() => makePDF()).
    then((doc) => doc.output("dataurl")));
SCRIPT
                         ))

  (p (base64-decode (string->bytes/utf-8
                     (cadr (string-split data-url "," #:repeat? #f))))))

(call-with-browser!
  (lambda (b)
    (set-browser-viewport-size! b 1920 1080)
    (call-with-page! b
      (lambda (p)
        (page-goto! p "https://example.com")
        (call-with-page-pdf! p
                             (lambda (data)
                               (define filename (make-temporary-file "~a.pdf"))
                               (with-output-to-file filename
                                 #:exists 'truncate/replace
                                 (lambda ()
                                   (write-bytes data)))

                               (system* (find-executable-path "open") filename)))))))
