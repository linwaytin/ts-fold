;;; ts-fold-indicators.el --- Display indicators for folding range  -*- lexical-binding: t; -*-

;; Copyright (C) 2021-2023  Shen, Jen-Chieh
;; Created date 2021-10-04 20:03:12

;; This file is NOT part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; Display indicators for folding range
;;

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(require 'fringe-helper)

(require 'ts-fold-util)
(require 'ts-fold)

(defcustom ts-fold-indicators-fringe 'left-fringe
  "Display indicators on the left/right fringe."
  :type '(choice (const :tag "On the right fringe" right-fringe)
                 (const :tag "On the left fringe" left-fringe))
  :group 'ts-fold)

(defcustom ts-fold-indicators-priority 30
  "Indicators fringe priority."
  :type 'integer
  :group 'ts-fold)

(defcustom ts-fold-indicators-face-function nil
  "Function call when apply to indicators face."
  :type 'function
  :group 'ts-fold)

;; TODO: We eventually want to remove this. Therefore, we get fast and
;; accurate results!
(defcustom ts-fold-indicators-render-method 'partial
  "Method used to display indicators."
  :type '(choice (const :tag "Accurate rendering but cost more performance" full)
                 (const :tag "Inaccurate rendering but fast" partial))
  :group 'ts-fold)

(fringe-helper-define 'ts-fold-indicators-fr-plus nil
  "XXXXXXX"
  "X.....X"
  "X..X..X"
  "X.XXX.X"
  "X..X..X"
  "X.....X"
  "XXXXXXX")

(fringe-helper-define 'ts-fold-indicators-fr-minus-tail nil
  "........" "........" "........" "........" "........"
  "........" "........" "........" "........" "........"
  "XXXXXXX"
  "X.....X"
  "X.....X"
  "X.XXX.X"
  "X.....X"
  "X.....X"
  "XXXXXXX"
  "...XX..." "...XX..." "...XX..." "...XX..." "...XX..."
  "...XX..." "...XX..." "...XX..." "...XX..." "...XX...")

(fringe-helper-define 'ts-fold-indicators-fr-center nil
  "...XX..." "...XX..." "...XX..." "...XX..." "...XX..."
  "...XX..." "...XX..." "...XX..." "...XX..." "...XX..."
  "...XX..." "...XX..." "...XX..." "...XX..." "...XX..."
  "...XX..." "...XX..." "...XX..." "...XX..." "...XX..."
  "...XX..." "...XX..." "...XX...")

(fringe-helper-define 'ts-fold-indicators-fr-end-left nil
  "...XX..." "...XX..." "...XX..." "...XX..." "...XX..."
  "...XX..." "...XX..." "...XX..." "...XX..." "...XX..."
  "...XX..." "...XXXXX" "...XXXXX"
  "........" "........" "........" "........" "........"
  "........" "........" "........" "........" "........")

(fringe-helper-define 'ts-fold-indicators-fr-end-right nil
  "...XX..." "...XX..." "...XX..." "...XX..." "...XX..."
  "...XX..." "...XX..." "...XX..." "...XX..." "...XX..."
  "...XX..." "XXXXX..." "XXXXX..."
  "........" "........" "........" "........" "........"
  "........" "........" "........" "........" "........")

;;
;; (@* "Entry" )
;;

(defvar ts-fold-indicators-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map [left-fringe mouse-1] #'ts-fold-indicators-click-fringe)
    (define-key map [right-fringe mouse-1] #'ts-fold-indicators-click-fringe)
    map)
  "Keymap for function `ts-fold-indicators-mode'.")

(defun ts-fold-indicators--enable ()
  "Enable `ts-fold-indicators' mode."
  (if (or ts-fold-mode (ts-fold-mode 1))  ; Enable `ts-fold-mode' automatically
      (progn
        (add-hook 'tree-sitter-after-change-functions #'ts-fold-indicators-refresh nil t)
        (add-hook 'after-save-hook #'ts-fold-indicators-refresh nil t)
        (add-hook 'window-size-change-functions #'ts-fold-indicators--size-change)
        (add-hook 'window-scroll-functions #'ts-fold-indicators--scroll)
        (ts-fold-indicators--render-buffer))
    (ts-fold-indicators-mode -1)))

(defun ts-fold-indicators--disable ()
  "Disable `ts-fold-indicators' mode."
  (remove-hook 'tree-sitter-after-change-functions #'ts-fold-indicators-refresh t)
  (remove-hook 'after-save-hook #'ts-fold-indicators-refresh t)
  (remove-hook 'window-size-change-functions #'ts-fold-indicators--size-change)
  (remove-hook 'window-scroll-functions #'ts-fold-indicators--scroll)
  (ts-fold-indicators--remove-ovs-buffer))

;;;###autoload
(define-minor-mode ts-fold-indicators-mode
  "Minor mode for indicators mode."
  :group 'ts-fold
  :lighter nil
  :keymap ts-fold-indicators-mode-map
  :init-value nil
  (if ts-fold-indicators-mode (ts-fold-indicators--enable)
    (ts-fold-indicators--disable)))

;;;###autoload
(define-minor-mode global-ts-fold-indicators-mode
  "Global minor mode for turning on ts-fold with indicators whenever avaliable."
  :group 'ts-fold
  :lighter nil
  :init-value nil
  :global t
  (cond (global-ts-fold-indicators-mode
         (add-hook 'ts-fold-mode-hook #'ts-fold-indicators-mode)
         (global-ts-fold-mode 1)  ; Must enabled!
         (dolist (buf (buffer-list))
           (with-current-buffer buf
             (when (and ts-fold-mode (not ts-fold-indicators-mode))
               (ts-fold-indicators-mode 1)))))
        (t
         (remove-hook 'ts-fold-mode-hook #'ts-fold-indicators-mode)
         (dolist (buf (buffer-list))
           (with-current-buffer buf
             (when (and ts-fold-mode ts-fold-indicators-mode)
               (ts-fold-indicators-mode -1)))))))

;;
;; (@* "Events" )
;;

(defun ts-fold-indicators-click-fringe (event)
  "EVENT click on fringe."
  (interactive "e")
  (let ((current-fringe (nth 1 (car (cdr event)))) ovs ov cur-ln)
    (when (eq current-fringe ts-fold-indicators-fringe)
      (mouse-set-point event)
      (beginning-of-line)
      (setq cur-ln (line-number-at-pos (point)))
      (setq ovs (append (ts-fold--overlays-in 'type 'ts-fold-indicators-fr-plus)
                        (ts-fold--overlays-in 'type 'ts-fold-indicators-fr-minus-tail)))
      (when ovs
        (setq ov (cl-some
                  (lambda (ov) (= cur-ln (line-number-at-pos (overlay-start ov))))
                  ovs))
        (when ov
          (or (save-excursion
                (end-of-line)
                (when (nth 4 (syntax-ppss)) (back-to-indentation))
                (ts-fold-toggle))
              (ts-fold-toggle)))))))

;;
;; (@* "Core" )
;;

(defun ts-fold-indicators--create-overlay-at-point ()
  "Create indicator overlay at current point."
  (let* ((pos (line-beginning-position))
         (ov (make-overlay pos (1+ pos)))
         (window (selected-window)))
    (overlay-put ov 'ts-fold-indicators-window window)
    (overlay-put ov 'window window)
    ov))

(defun ts-fold-indicators--create-overlays (beg end folded)
  "Create indicators overlays in range of BEG to END.

If argument FOLDED is non-nil, means the region is close/hidden (overlay
is created); this is used to determie what indicators' bitmap to use."
  (let (ov-lst)
    (save-excursion
      (goto-char beg)
      (while (and (<= (line-beginning-position) end) (not (eobp)))
        (push (ts-fold-indicators--create-overlay-at-point) ov-lst)
        (forward-line 1)))
    (ts-fold-indicators--update-overlays (reverse ov-lst) folded)))

(defun ts-fold-indicators--get-priority (bitmap)
  "Return the priority integer depends on the type of the BITMAP.

This is a static/constant method."
  (let ((prior ts-fold-indicators-priority))
    (cl-case bitmap
      (ts-fold-indicators-fr-plus (+ prior 2))
      (ts-fold-indicators-fr-minus-tail (+ prior 2))
      (ts-fold-indicators-fr-end-left (+ prior 1))
      (ts-fold-indicators-fr-end-right (+ prior 1))
      (t prior))))

(defun ts-fold-indicators--get-string (folded ov bitmap)
  "Return a string or nil for indicators overlay (OV).

If argument FOLDED is nil, it must return a string so all indicators are shown
in range.  Otherwise, we should only return string only when BITMAP is the
head (first line) of the region."
  (let* ((face (or (and (functionp ts-fold-indicators-face-function)
                        (funcall ts-fold-indicators-face-function (overlay-start ov)))
                   'ts-fold-fringe-face))
         (str (propertize "." 'display `(,ts-fold-indicators-fringe ,bitmap ,face))))
    (if (not folded) str
      (cl-case bitmap
        (ts-fold-indicators-fr-plus str)  ; return string only in head
        (ts-fold-indicators-fr-minus-tail nil)
        (ts-fold-indicators-fr-end-left nil)
        (ts-fold-indicators-fr-end-right nil)
        (t nil)))))

(defun ts-fold-indicators--active-ov (folded ov bitmap)
  "SHOW the indicator OV with BITMAP.

Argument FOLDED holds folding state; it's a boolean."
  (when (overlayp ov)
    (overlay-put ov 'ts-fold-indicators-active folded)
    (overlay-put ov 'type bitmap)
    (overlay-put ov 'priority (ts-fold-indicators--get-priority bitmap))
    (overlay-put ov 'before-string (ts-fold-indicators--get-string folded ov bitmap))))

(defun ts-fold-indicators--get-end-fringe ()
  "Return end fringe bitmap according to variable `ts-fold-indicators-fringe'."
  (cl-case ts-fold-indicators-fringe
    (left-fringe 'ts-fold-indicators-fr-end-left)
    (right-fringe 'ts-fold-indicators-fr-end-right)
    (t (user-error "Invalid indicators fringe type: %s" ts-fold-indicators-fringe))))

(defun ts-fold-indicators--update-overlays (ov-lst folded)
  "SHOW indicators overlays OV-LST depends on FOLDED."
  (when-let* ((len (length ov-lst))
              ((> len 1))
              (len-1 (1- len))
              (first-ov (nth 0 ov-lst))
              (last-ov (nth len-1 ov-lst))
              (index 1))
    ;; Head
    (ts-fold-indicators--active-ov
     folded first-ov
     (if folded 'ts-fold-indicators-fr-plus
       'ts-fold-indicators-fr-minus-tail))
    ;; Last
    (ts-fold-indicators--active-ov folded last-ov (ts-fold-indicators--get-end-fringe))
    ;; In between `head' and `last'
    (while (< index len-1)
      (ts-fold-indicators--active-ov folded (nth index ov-lst) 'ts-fold-indicators-fr-center)
      (cl-incf index)))
  ov-lst)

;;
;; (@* "Update" )
;;

(defun ts-fold-indicators--create (node)
  "Create indicators using NODE."
  (when-let* ((range (ts-fold--get-fold-range node))
              (beg (car range)) (end (cdr range)))
    (let ((folded (ts-fold-overlay-at node)))
      (ts-fold-indicators--create-overlays beg end folded))))

(defun ts-fold-indicators--size-change (&optional frame &rest _)
  "Render indicators for all visible windows from FRAME."
  (ts-fold--with-no-redisplay
    (dolist (win (window-list frame)) (ts-fold-indicators--render-window win))))

(defun ts-fold-indicators--scroll (&optional window &rest _)
  "Render indicators on WINDOW."
  (ts-fold--with-no-redisplay
    (ts-fold-indicators--render-window window)))

(defun ts-fold-indicators--render-buffer ()
  "Render indicators for current buffer."
  (dolist (window (get-buffer-window-list nil nil t))
    (ts-fold-indicators--render-window window)))

(defun ts-fold-indicators--render-window (window)
  "Render indicators for WINDOW."
  (ts-fold--with-selected-window window
    (ignore-errors (ts-fold-indicators-refresh))))

(defun ts-fold-indicators--within-window (node &optional wend wstart)
  "Return nil if NODE is not within the current window display range.

Optional arguments WEND and WSTART are the range for caching."
  (when-let*
      ((wend (or wend (window-end nil t)))
       (wstart (or wstart (window-start)))
       (range (cl-case ts-fold-indicators-render-method
                (`full
                 (ignore-errors (ts-fold--get-fold-range node)))
                (`partial (cons (tsc-node-start-position node)
                                (tsc-node-end-position node)))
                (t
                 (user-error "Invalid render method: %s" ts-fold-indicators-render-method))))
       (start (car range))
       (end (cdr range))
       ((or (and (<= wstart start) (<= end wend))    ; with in range
            (and (<= wstart end) (<= start wstart))  ; just one above
            (and (<= wend end) (<= start wend)))))   ; just one below
    node))

;;;###autoload
(defun ts-fold-indicators-refresh (&rest _)
  "Refresh indicators for all folding range."
  (when (and tree-sitter-mode ts-fold-indicators-mode)
    (ts-fold--ensure-ts
      (when-let*
          ((node (ignore-errors (tsc-root-node tree-sitter-tree)))
           (patterns (seq-mapcat (lambda (fold-range) `((,(car fold-range)) @name))
                                 (alist-get major-mode ts-fold-range-alist)
                                 'vector))
           (query (ignore-errors
                    (tsc-make-query tree-sitter-language patterns)))
           (nodes-to-fold (tsc-query-captures query node #'ignore))
           (wend (window-end nil t))
           (wstart (window-start))
           (nodes-to-fold
            (cl-remove-if-not (lambda (node)
                                (ts-fold-indicators--within-window (cdr node) wend wstart))
                              nodes-to-fold))
           (mode-ranges (alist-get major-mode ts-fold-range-alist))
           (nodes-to-fold
            (cl-remove-if (lambda (node)
                            (ts-fold--non-foldable-node-p (cdr node) mode-ranges))
                          nodes-to-fold)))
        (ts-fold-indicators--remove-ovs)
        (thread-last nodes-to-fold
                     (mapcar #'cdr)
                     (mapc #'ts-fold-indicators--create))))))

(defun ts-fold-indicators--remove-ovs (&optional window)
  "Remove all indicators overlays in this WINDOW."
  (remove-overlays (point-min) (point-max) 'ts-fold-indicators-window
                   (or window (selected-window))))

(defun ts-fold-indicators--remove-ovs-buffer ()
  "Remove all indicators overlays for this buffer."
  (dolist (window (get-buffer-window-list nil nil t))
    (ts-fold-indicators--remove-ovs window)))

(provide 'ts-fold-indicators)
;;; ts-fold-indicators.el ends here
