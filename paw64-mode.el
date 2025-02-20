
(require 'cl-lib)

(defcustom paw64-indent-level 16
  "Default level of indentation for assembly instructions(opcodes)"
  :type 'integer)

(defcustom paw64-comment-indent-level 30
  "Default level of comment/documentation column"
  :type 'integer)



(defconst paw64-6502-opcode-list '("adc" "anc" "and" "ane" "arr" "asl" "asr" "bcc" "bcs" "beq" "bit" "bmi" "bne"
                                   "bpl" "brk" "bvc" "bvs" "clc" "cld" "cli" "clv" "cmp" "cpx" "cpy" "dcp" "dec"
                                   "dex" "dey" "eor" "inc" "inx" "iny" "isb" "jam" "jmp" "jsr" "lax" "lda" "lds"
                                   "ldx" "ldy" "lsr" "nop" "ora" "pha" "php" "pla" "plp" "rla" "rol" "ror" "rra"
                                   "rti" "rts" "sax" "sbc" "sbx" "sec" "sed" "sei" "sha" "shs" "shx" "shy" "slo"
                                   "sre" "sta" "stx" "sty" "tax" "tay" "tsx" "txa" "txs" "tya"))

(defconst paw64-6502-opcode-regex (concat "\\<" (regexp-opt paw64-6502-opcode-list) "\\>"))

(defconst paw64-symbol-regex "[a-zA-Z_][a-zA-Z0-9_]+")

(defconst paw64-constant-decl-regex "^" (concat paw64-symbol-regex "\s*="))
(defconst paw64-assembly-address-regex "^\\(\\*=\\)")
(defconst paw64-instruction-regex paw64-6502-opcode-regex)
(defconst paw64-banner-label-regex (concat "^" paw64-symbol-regex ":"))



(defconst paw64-font-lock-keywords
  `(;; Preprocessor
    ("\\.[[:alpha:]]+" . font-lock-keyword-face)

    ;; Assembly address
    ("^\\(\\*=\\)\\(\\$[0-9a-fA-F]+\\)"
     (1 font-lock-constant-face)
     (2 font-lock-function-name-face))

    ;; Constant declaration
    (,(concat "^\\(" paw64-symbol-regex "\\)[[:blank:]]*=") 1 font-lock-function-name-face)

    ;; Label declaration
    (,(concat "^\\(" paw64-symbol-regex "\\)\\(:?\\)\\>")
     (1 font-lock-type-face)
     (2 'bold))

    ;; Hi/Lo ref
    (,(concat "\\#[\\>\\<]" paw64-symbol-regex) . font-lock-function-name-face)

    ;; Constant hex value
    ("=" "\\$[0-9a-fA-F]+" nil nil (0 'bold))

    ;; Opcode argument value
    (,paw64-6502-opcode-regex "\\#[\\$\\%]\\(?:[0-9a-fA-F]+\\)" nil nil (0 'bold))

    ;; Opcode argument address
    (,paw64-6502-opcode-regex "\\$\\(?:[0-9a-fA-F]+\\)" nil nil (0 'font-lock-variable-name-face))

    ;; Opcode argument label/constant
    (,paw64-6502-opcode-regex ,(concat "[[:blank:]]+\\(" paw64-symbol-regex "\\)") nil nil (0 'font-lock-preprocessor-face))

    ;; Opcode register arg
    (,(concat "\\(" paw64-6502-opcode-regex "\\).*\\,[[:space:]]?\\([xy]\\)")
     (2 'bold))

    ;; Highlight opcodes with optimized regexp for all valid 6502/6510 opcodes, including illegal/undocumented opcodes
    (,paw64-6502-opcode-regex 0 font-lock-keyword-face)))



(defun paw64-resolve-instr-indent ()
  "Resolve indentation level for instruction/opcode column by looking at previous lines, otherwise use ‘paw64-indent-level’"
  (save-excursion
    (beginning-of-line)
    (let ((col (re-search-backward paw64-6502-opcode-regex nil t)))
      (if (and (integerp col)
               (not (= col 0)))
          (progn
            (goto-char col)
            (current-column))
      paw64-indent-level))))

(defun paw64-resolve-comment-indent()
  "Resolve indentation level for comment column by looking at previous lines, otherwise use ‘paw64-indent-level’"
  (let ((instr-col (paw64-resolve-instr-indent)))
    (save-excursion
      ;; Find comment start that is right of instruction column
      (let ((col (re-search-backward (concat "^\\(?:[^;]\\{" (int-to-string instr-col) ",\\}\\);") (beginning-of-line) t)))
        (if (integerp col)
            (progn
              ;; Find comment start character column
              (goto-char col)
              (beginning-of-line)
              (forward-char instr-col)
              (goto-char (re-search-forward ";"))
              (backward-char)
              (current-column))
          paw64-comment-indent-level)))))

(defun paw64-previous-statement ()
  (save-excursion
    (if (bobp)
        'nothing
      (progn
        (previous-line)
        (beginning-of-line)
        (let ((line (buffer-substring-no-properties (line-beginning-position) (line-end-position))))
          (cond
           ((string-match "^\s*$" line)
            (paw64-previous-statement))

           ((string-match paw64-instruction-regex line)
            'instruction)

           ((string-match paw64-assembly-address-regex line)
            'assembly-address)

           ((string-match paw64-banner-label-regex line)
            'banner-label)

           ((string-match paw64-constant-decl-regex line)
            'constant-declaration)))))))

(defun paw64-eat-ws ()
  "Removes all whitespace immediately before and after the current cursor-position"
  (save-restriction
    (save-match-data
      (progn
        (skip-chars-backward "[[:blank:]]*")
        (re-search-forward "[[:blank:]]*")
        (replace-match "" nil nil)))))

(defun paw64-indent ()
  "The ‘indent-line-function’ of paw64-mode. Delegates to either ‘paw64-indent-line’, ‘paw64-indent-at-cursor’ or 'paw64-indent-by-previous' depending on context."
  (interactive)
  (cond
   ((and (bolp) (eolp))
    (paw64-indent-by-previous))

   ((bolp)
    (paw64-indent-line))

   (t
    (paw64-indent-at-cursor))))

(defun paw64-indent-at-cursor ()
  "Indents the remainder of the line from the current cursor column"
  (let* ((instr-col (paw64-resolve-instr-indent))
         (comment-col (paw64-resolve-comment-indent)))
    (cond
     ((and
       (looking-back "^[[:blank:]]*")
       (eolp))
      (paw64-eat-ws))

     ((looking-back (concat "^" paw64-6502-opcode-regex))
      (save-excursion
        (beginning-of-line)
        (indent-to (paw64-resolve-instr-indent))))

     ((looking-back "^\\(?:[[:alnum:]]\\|_\\)+[[:blank:]]*")
      (progn
        (paw64-eat-ws)
        (indent-to (paw64-resolve-instr-indent))))

     ((and (looking-at ";") (= (current-column) comment-col))
      (progn
        (paw64-eat-ws)
        (indent-to (+ (if (bolp) 0 1) (current-column)))))

     ((or (eolp)
          (and (looking-at "[[:blank:]]*;")
               (> (current-column) instr-col)))
      (progn
        (paw64-eat-ws)
        (indent-to comment-col))))))

(defun paw64-indent-by-previous ()
  (when (member (paw64-previous-statement)
                '(instruction assembly-address banner-label))
    (indent-to  (paw64-resolve-instr-indent))))

(defun paw64-indent-line ()
  "Indent current line"
  (interactive)
  (save-excursion
    (beginning-of-line)
    (paw64-eat-ws))
  (paw64-eat-ws)
  (cond

   ((looking-at ";")
    (indent-to (paw64-resolve-comment-indent)))

   ((or (looking-at paw64-6502-opcode-regex)
        (and (bolp) (eolp)))
    (indent-to (paw64-resolve-instr-indent)))))

(defun paw64-post-command-hook ()
  (let* ((line (buffer-substring-no-properties (line-beginning-position) (line-end-position)))
         (instr-pos (string-match paw64-6502-opcode-regex line))
         (col (- (point) (line-beginning-position))))
    (when (and instr-pos
               (< col instr-pos))
      (save-excursion
        (goto-char (+ (line-beginning-position) instr-pos))
        (paw64-indent-at-cursor)))))

(defun paw64-indent-for-tab (&optional arg)
  (interactive)
  (if (and (bolp) (eolp))
      (indent-to (paw64-resolve-instr-indent))
    (indent-for-tab-command arg)))



(defun paw64-to-decimal-string (input)
  "Converts string representation of hexadecimal number to a string containing its corresponding integer value."
  (let ((hex (string-match "\\$[[:digit:]]+" input))
        (dec (string-match "[[:digit:]]+" input)))
    (if (= dec 0)
        input
      (number-to-string (string-to-number (substring input 1) 16)))))

(defun paw64-insert-basic-header ()
  "Inserts a basic program to bootstrap machine language program at cursor."
  (interactive)
  (let ((prog-addr (paw64-to-decimal-string (string-trim (read-string "Enter program start address: ")))))
    (beginning-of-line)
    (insert "*=$0801")
    (newline)
    (insert ".byte $0c, $08, $0a, $00, $9e, $20")
    (newline)
    (insert (concat ".byte " (let ((nums ()))
                               (dotimes (i (length prog-addr))
                                 (push (concat "$3" (substring prog-addr i (+ i 1))) nums))
                               (dotimes (i (- 7 (length prog-addr)))
                                 (push "$00" nums))
                               (string-join (nreverse nums) ", "))))
    (newline)
    (newline)))



(defun paw64-target-name (&optional ext file-name)
  (or ext (setq ext "prg"))
  (concat (car (split-string (or file-name buffer-file-name) "\\.")) "." ext))

(defun paw64-compile-64tass ()
  "Compile/Assemble current buffer using 64tass. Result will be stored in a file named after the buffer, with the file extension .prg"
  (interactive)
  (call-process "64tass" nil "*64tass compilation log*" nil buffer-file-name "-o" (paw64-target-name)))

(defun paw64-compile-and-run-64tass ()
  "Assembles current buffer using ‘paw64-compile-64tass’ and runs the resulting binary in VICE/x64"
  (interactive)
  (paw64-compile-64tass)
  (call-process "x64" nil 0 nil (paw64-target-name)))



(defvar paw64-mode-syntax-table
  (let ((st (make-syntax-table)))
    (modify-syntax-entry ?\; "< b" st)
    (modify-syntax-entry ?\n "> b" st)
    st))

(defvar paw64-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") 'paw64-compile-64tass)
    (define-key map (kbd "C-c C-x") 'paw64-compile-and-run-64tass)
    (define-key map (kbd "C-c C-b") 'paw64-insert-basic-header)
    (define-key map (kbd "TAB") 'paw64-indent-for-tab)

    map))

;;;###autoload
(define-derived-mode paw64-mode
  fundamental-mode
  "Paw64"
  "Major mode for 6502/6510 assembly with 64tass and/or paw64"
  (set-syntax-table (make-syntax-table paw64-mode-syntax-table))
  (set (make-local-variable 'font-lock-defaults) '(paw64-font-lock-keywords))
  (set (make-local-variable 'indent-line-function) 'paw64-indent)

  (add-hook 'post-command-hook #'paw64-post-command-hook nil t)
  (electric-indent-local-mode -1))


(provide 'paw64-mode)
