;; Data Privacy Protection Contract
;; Redacts sensitive information from public records to protect privacy

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-RULE-NOT-FOUND (err u301))
(define-constant ERR-INVALID-CLASSIFICATION (err u302))
(define-constant ERR-INVALID-INPUT (err u303))

;; Classification Levels
(define-constant CLASSIFICATION-PUBLIC u0)
(define-constant CLASSIFICATION-INTERNAL u1)
(define-constant CLASSIFICATION-CONFIDENTIAL u2)
(define-constant CLASSIFICATION-RESTRICTED u3)
(define-constant CLASSIFICATION-SECRET u4)
(define-constant CLASSIFICATION-TOP-SECRET u5)

;; Data Variables
(define-data-var next-rule-id uint u1)

;; Data Maps
(define-map privacy-rules
  { rule-id: uint }
  {
    rule-name: (string-ascii 128),
    pattern-type: (string-ascii 64),
    classification-level: uint,
    redaction-method: (string-ascii 32),
    active: bool,
    created-by: principal,
    created-at: uint
  }
)

(define-map document-privacy-status
  { document-hash: (buff 32) }
  {
    original-classification: uint,
    public-classification: uint,
    redaction-applied: bool,
    redacted-sections: (list 20 (string-ascii 64)),
    processed-at: uint,
    processed-by: principal
  }
)

(define-map clearance-levels
  { user: principal }
  { clearance-level: uint }
)

(define-map authorized-privacy-officers principal bool)

;; Authorization Functions
(define-public (add-privacy-officer (officer principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (ok (map-set authorized-privacy-officers officer true))
  )
)

(define-public (remove-privacy-officer (officer principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (ok (map-delete authorized-privacy-officers officer))
  )
)

(define-public (set-user-clearance (user principal) (clearance-level uint))
  (let
    (
      (is-authorized (default-to false (map-get? authorized-privacy-officers tx-sender)))
    )
    (asserts! (or is-authorized (is-eq tx-sender CONTRACT-OWNER)) ERR-NOT-AUTHORIZED)
    (asserts! (<= clearance-level u5) ERR-INVALID-CLASSIFICATION)

    (map-set clearance-levels
      { user: user }
      { clearance-level: clearance-level }
    )
    (ok true)
  )
)

;; Privacy Rule Management
(define-public (create-privacy-rule
  (rule-name (string-ascii 128))
  (pattern-type (string-ascii 64))
  (classification-level uint)
  (redaction-method (string-ascii 32)))
  (let
    (
      (rule-id (var-get next-rule-id))
      (is-authorized (default-to false (map-get? authorized-privacy-officers tx-sender)))
    )
    (asserts! (or is-authorized (is-eq tx-sender CONTRACT-OWNER)) ERR-NOT-AUTHORIZED)
    (asserts! (> (len rule-name) u0) ERR-INVALID-INPUT)
    (asserts! (<= classification-level u5) ERR-INVALID-CLASSIFICATION)

    (map-set privacy-rules
      { rule-id: rule-id }
      {
        rule-name: rule-name,
        pattern-type: pattern-type,
        classification-level: classification-level,
        redaction-method: redaction-method,
        active: true,
        created-by: tx-sender,
        created-at: block-height
      }
    )

    (var-set next-rule-id (+ rule-id u1))
    (ok rule-id)
  )
)

(define-public (toggle-privacy-rule (rule-id uint) (active bool))
  (let
    (
      (rule-info (unwrap! (map-get? privacy-rules { rule-id: rule-id }) ERR-RULE-NOT-FOUND))
      (is-authorized (default-to false (map-get? authorized-privacy-officers tx-sender)))
    )
    (asserts! (or is-authorized (is-eq tx-sender CONTRACT-OWNER)) ERR-NOT-AUTHORIZED)

    (map-set privacy-rules
      { rule-id: rule-id }
      (merge rule-info { active: active })
    )
    (ok true)
  )
)

;; Document Privacy Processing
(define-public (process-document-privacy
  (document-hash (buff 32))
  (original-classification uint)
  (public-classification uint)
  (redacted-sections (list 20 (string-ascii 64))))
  (let
    (
      (is-authorized (default-to false (map-get? authorized-privacy-officers tx-sender)))
    )
    (asserts! (or is-authorized (is-eq tx-sender CONTRACT-OWNER)) ERR-NOT-AUTHORIZED)
    (asserts! (<= original-classification u5) ERR-INVALID-CLASSIFICATION)
    (asserts! (<= public-classification u5) ERR-INVALID-CLASSIFICATION)
    (asserts! (<= public-classification original-classification) ERR-INVALID-CLASSIFICATION)

    (map-set document-privacy-status
      { document-hash: document-hash }
      {
        original-classification: original-classification,
        public-classification: public-classification,
        redaction-applied: (> (len redacted-sections) u0),
        redacted-sections: redacted-sections,
        processed-at: block-height,
        processed-by: tx-sender
      }
    )
    (ok true)
  )
)

;; Access Control Functions
(define-public (can-access-document (user principal) (document-hash (buff 32)))
  (let
    (
      (user-clearance (default-to { clearance-level: CLASSIFICATION-PUBLIC }
        (map-get? clearance-levels { user: user })))
      (privacy-status (map-get? document-privacy-status { document-hash: document-hash }))
    )
    (match privacy-status
      status (ok (<= (get public-classification status) (get clearance-level user-clearance)))
      (ok true) ;; If no privacy status set, assume public
    )
  )
)

;; Read-only Functions
(define-read-only (get-privacy-rule (rule-id uint))
  (map-get? privacy-rules { rule-id: rule-id })
)

(define-read-only (get-document-privacy-status (document-hash (buff 32)))
  (map-get? document-privacy-status { document-hash: document-hash })
)

(define-read-only (get-user-clearance (user principal))
  (map-get? clearance-levels { user: user })
)

(define-read-only (is-privacy-officer (officer principal))
  (default-to false (map-get? authorized-privacy-officers officer))
)

(define-read-only (get-next-rule-id)
  (var-get next-rule-id)
)

(define-read-only (classify-for-public-access (original-classification uint))
  (if (<= original-classification CLASSIFICATION-INTERNAL)
    original-classification
    CLASSIFICATION-PUBLIC
  )
)
