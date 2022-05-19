;;; corfu-terminal.el --- Corfu popup on terminal -*- lexical-binding: t -*-

;; Copyright (C) 2022 Akib Azmain Turja.

;; Author: Akib Azmain Turja <akib@disroot.org>
;; Created: 2022-04-11
;; Version: 0.1
;; Package-Requires: ((emacs "26.1") (corfu "0.23") (popon "0"))
;; Keywords: convenience
;; Homepage: https://codeberg.org/akib/emacs-corfu-terminal

;; This file is not part of GNU Emacs.

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; For a full copy of the GNU General Public License
;; see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Corfu uses child frames to display candidates.  This makes Corfu
;; unusable on terminal.  This package replaces that with popup/popon,
;; which works everywhere.  Use M-x corfu-terminal-mode to enable.  You'll
;; probably want to enable it only on terminal.  In that case, put the
;; following in your init file:

;;   (unless (display-graphic-p)
;;     (corfu-terminal-mode +1))

;;; Code:

(require 'subr-x)
(require 'corfu)
(require 'popon)
(require 'cl-lib)

(defgroup corfu-terminal nil
  "Corfu popup on terminal."
  :group 'convenience
  :link '(url-link "https://codeberg.org/akib/emacs-corfu-terminal")
  :prefix "corfu-terminal-")

(defcustom corfu-terminal-position-right-margin 0
  "Number of columns of margin at the right of window.

Always keep the popup this many columns away from the right edge of the
window.

Note: If the popup breaks or crosses the right edge of window, you may set
this variable to warkaround it.  But remember, that's a *bug*, so if that
ever happens to you please report the issue at
https://codeberg.org/akib/emacs-corfu-terminal/issues."
  :type 'integer)

(declare-function corfu--auto-tick "corfu") ;; OK, byte-compiler?

(defvar corfu-terminal--popon nil
  "Popon object.")

(defvar corfu-terminal--last-position nil
  "Position of last popon, and some data is to make sure that's valid.")

(defun corfu-terminal--popup-hide ()
  "Hide popup."
  (when corfu-terminal--popon
    (setq corfu-terminal--popon (popon-kill corfu-terminal--popon))))

(defun corfu-terminal--popup-show (pos off width lines &optional curr lo
                                       bar)
  "Show popup at OFF columns before POS.

Show LINES, a list of lines.  Highlight CURRth line as current selection.
Show a vertical scroll bar of size BAR + 1 from LOth line."
  (corfu-terminal--popup-hide)  ; Hide the popup first.
  (let* ((bar-width (if (display-graphic-p)
                        (ceiling (* (default-font-width) corfu-bar-width))
                      (ceiling corfu-bar-width)))
         (margin-left-width (if (display-graphic-p)
                                (ceiling (* (default-font-width)
                                            corfu-left-margin-width))
                              (ceiling corfu-left-margin-width)))
         (margin-right-width (max (if (display-graphic-p)
                                      (ceiling
                                       (* (default-font-width)
                                          corfu-right-margin-width))
                                    (ceiling corfu-right-margin-width))
                                  bar-width))
         (scroll-bar (when (< 0 bar-width)
                       (if (display-graphic-p)
                           (concat
                            (propertize " " 'display
                                        `(space
                                          :width (,(- margin-right-width
                                                      bar-width))))
                            (propertize " " 'display
                                        `(space :width (,bar-width))
                                        'face 'corfu-bar))
                         (concat
                          (make-string (- margin-right-width bar-width) ? )
                          (propertize (make-string bar-width ? ) 'face
                                      'corfu-bar)))))
         (margin-left (when (< 0 margin-left-width)
                        (if (display-graphic-p)
                            (propertize " " 'display
                                        `(space
                                          :width (,margin-left-width)))
                          (make-string margin-left-width ? ))))
         (margin-right (when (< 0 margin-right-width)
                         (if (display-graphic-p)
                             (propertize " " 'display
                                         `(space
                                           :width (,margin-right-width)))
                           (make-string margin-right-width ? ))))
         (popon-width (if (display-graphic-p)
                          (+ width (round (/ (+ margin-left-width
                                                margin-right-width)
                                             (frame-char-width))))
                        (+ width margin-left-width margin-right-width)))
         (popon-pos (if (equal (cdr corfu-terminal--last-position)
                               (list pos popon-width (window-start)
                                     (buffer-modified-tick)))
                        (car corfu-terminal--last-position)
                      (let ((pos (popon-x-y-at-pos pos)))
                        (cons
                         (max
                          (min (- (car pos) off)
                               (- (window-width)
                                  (line-number-display-width)
                                  (if (display-graphic-p)
                                      (let ((fringes (window-fringes)))
                                        (+ (/ (+ (car fringes)
                                                 (cadr fringes))
                                              (frame-char-width))
                                           (if (zerop (cadr fringes))
                                               1
                                             0)))
                                    (1+ (if (zerop (window-hscroll)) 0 1)))
                                  corfu-terminal-position-right-margin
                                  popon-width))
                          0)
                         (if (and (< (floor (window-screen-lines))
                                     (+ (cdr pos) (length lines)))
                                  (>= (cdr pos) (length lines)))
                             (- (cdr pos) (length lines))
                           (1+ (cdr pos))))))))
    (setq corfu-terminal--last-position
          (list popon-pos pos popon-width (window-start)
                (buffer-modified-tick)))
    (setq corfu-terminal--popon
          (popon-create
           (cons
            (string-join
             (seq-map-indexed
              (lambda (line line-number)
                (let ((str (concat
                            margin-left line
                            (make-string (- width (string-width line)) ? )
                            (if (and lo (<= lo line-number (+ lo bar)))
                                scroll-bar
                              margin-right))))
                  (add-face-text-property 0 (length str)
                                          (if (eq line-number curr)
                                              'corfu-current
                                            'corfu-default)
                                          t str)
                  str))
              lines)
             "\n")
            popon-width)
           popon-pos))
    nil))

(defmacro corfu-terminal--patch-out-display-graphic-p (fn name)
  "Patch out `display-graphic-p' in FN and define NAME to that definition."
  (let* ((vc-follow-symlinks t)
         (definition (let ((position (find-function-noselect fn)))
                       (with-current-buffer (car position)
                         (save-excursion
                           (goto-char (cdr position))
                           (read (current-buffer)))))))
    (setf (nth 1 definition) name)
    (cl-labels ((patch-out
                 (form)
                 (cond
                  ((equal form '(display-graphic-p))
                   t)
                  ((proper-list-p form)
                   (mapcar #'patch-out form))
                  (t
                   form))))
      (patch-out definition))))

(corfu-terminal--patch-out-display-graphic-p
 corfu--auto-post-command corfu-terminal--auto-post-command)
(corfu-terminal--patch-out-display-graphic-p
 corfu--in-region corfu-terminal--in-region)

;;;###autoload
(define-minor-mode corfu-terminal-mode
  "Corfu popup on terminal."
  :global t
  :group 'corfu-terminal
  (if corfu-terminal-mode
      (progn
        (advice-add #'corfu--popup-show :override
                    #'corfu-terminal--popup-show)
        (advice-add #'corfu--popup-hide :override
                    #'corfu-terminal--popup-hide)
        (advice-add #'corfu--auto-post-command :override
                    #'corfu-terminal--auto-post-command)
        (advice-add #'corfu--in-region :override
                    #'corfu-terminal--in-region))
    (advice-remove #'corfu--popup-show #'corfu-terminal--popup-show)
    (advice-remove #'corfu--popup-hide #'corfu-terminal--popup-hide)
    (advice-remove #'corfu--auto-post-command
                   #'corfu-terminal--auto-post-command)
    (advice-remove #'corfu--in-region #'corfu-terminal--in-region)))

(provide 'corfu-terminal)
;;; corfu-terminal.el ends here