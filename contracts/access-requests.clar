;; Public Access Request Management Contract
;; Streamlines access to government records for citizens

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-REQUEST-NOT-FOUND (err u201))
(define-constant ERR-INVALID-STATUS (err u202))
(define-constant ERR-INVALID-INPUT (err u203))
(define-constant ERR-REQUEST-EXPIRED (err u204))

;; Request Status Constants
(define-constant STATUS-PENDING u1)
(define-constant STATUS-UNDER-REVIEW u2)
(define-constant STATUS-APPROVED u3)
(define-constant STATUS-DENIED u4)
(define-constant STATUS-FULFILLED u5)

;; Data Variables
(define-data-var next-request-id uint u1)
(define-data-var processing-fee uint u1000000) ;; 1 STX in microSTX

;; Data Maps
(define-map access-requests
  { request-id: uint }
  {
    requester: principal,
    document-description: (string-ascii 512),
    request-type: (string-ascii 64),
    status: uint,
    submitted-at: uint,
    processed-at: (optional uint),
    processor: (optional principal),
    denial-reason: (optional (string-ascii 256))
  }
)

(define-map request-documents
  { request-id: uint }
  { document-hashes: (list 10 (buff 32)) }
)

(define-map authorized-processors principal bool)

(define-map requester-stats
  { requester: principal }
  {
    total-requests: uint,
    approved-requests: uint,
    denied-requests: uint
  }
)

;; Authorization Functions
(define-public (add-authorized-processor (processor principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (ok (map-set authorized-processors processor true))
  )
)

(define-public (remove-authorized-processor (processor principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (ok (map-delete authorized-processors processor))
  )
)

(define-public (set-processing-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (ok (var-set processing-fee new-fee))
  )
)

;; Request Submission Functions
(define-public (submit-access-request
  (document-description (string-ascii 512))
  (request-type (string-ascii 64)))
  (let
    (
      (request-id (var-get next-request-id))
      (current-stats (default-to
        { total-requests: u0, approved-requests: u0, denied-requests: u0 }
        (map-get? requester-stats { requester: tx-sender })
      ))
    )
    (asserts! (> (len document-description) u0) ERR-INVALID-INPUT)
    (asserts! (> (len request-type) u0) ERR-INVALID-INPUT)

    ;; Pay processing fee
    (try! (stx-transfer? (var-get processing-fee) tx-sender CONTRACT-OWNER))

    (map-set access-requests
      { request-id: request-id }
      {
        requester: tx-sender,
        document-description: document-description,
        request-type: request-type,
        status: STATUS-PENDING,
        submitted-at: block-height,
        processed-at: none,
        processor: none,
        denial-reason: none
      }
    )

    ;; Update requester stats
    (map-set requester-stats
      { requester: tx-sender }
      (merge current-stats { total-requests: (+ (get total-requests current-stats) u1) })
    )

    (var-set next-request-id (+ request-id u1))
    (ok request-id)
  )
)

;; Request Processing Functions
(define-public (update-request-status
  (request-id uint)
  (new-status uint)
  (denial-reason (optional (string-ascii 256))))
  (let
    (
      (request-info (unwrap! (map-get? access-requests { request-id: request-id }) ERR-REQUEST-NOT-FOUND))
      (is-authorized (default-to false (map-get? authorized-processors tx-sender)))
      (requester (get requester request-info))
      (current-stats (default-to
        { total-requests: u0, approved-requests: u0, denied-requests: u0 }
        (map-get? requester-stats { requester: requester })
      ))
    )
    (asserts! (or is-authorized (is-eq tx-sender CONTRACT-OWNER)) ERR-NOT-AUTHORIZED)
    (asserts! (and (>= new-status u1) (<= new-status u5)) ERR-INVALID-STATUS)

    (map-set access-requests
      { request-id: request-id }
      (merge request-info {
        status: new-status,
        processed-at: (some block-height),
        processor: (some tx-sender),
        denial-reason: denial-reason
      })
    )

    ;; Update requester stats based on status
    (if (is-eq new-status STATUS-APPROVED)
      (map-set requester-stats
        { requester: requester }
        (merge current-stats { approved-requests: (+ (get approved-requests current-stats) u1) })
      )
      (if (is-eq new-status STATUS-DENIED)
        (map-set requester-stats
          { requester: requester }
          (merge current-stats { denied-requests: (+ (get denied-requests current-stats) u1) })
        )
        true
      )
    )

    (ok true)
  )
)

(define-public (attach-documents-to-request
  (request-id uint)
  (document-hashes (list 10 (buff 32))))
  (let
    (
      (request-info (unwrap! (map-get? access-requests { request-id: request-id }) ERR-REQUEST-NOT-FOUND))
      (is-authorized (default-to false (map-get? authorized-processors tx-sender)))
    )
    (asserts! (or is-authorized (is-eq tx-sender CONTRACT-OWNER)) ERR-NOT-AUTHORIZED)
    (asserts! (> (len document-hashes) u0) ERR-INVALID-INPUT)

    (map-set request-documents
      { request-id: request-id }
      { document-hashes: document-hashes }
    )
    (ok true)
  )
)

;; Read-only Functions
(define-read-only (get-request-info (request-id uint))
  (map-get? access-requests { request-id: request-id })
)

(define-read-only (get-request-documents (request-id uint))
  (map-get? request-documents { request-id: request-id })
)

(define-read-only (get-requester-stats (requester principal))
  (map-get? requester-stats { requester: requester })
)

(define-read-only (is-authorized-processor (processor principal))
  (default-to false (map-get? authorized-processors processor))
)

(define-read-only (get-processing-fee)
  (var-get processing-fee)
)

(define-read-only (get-next-request-id)
  (var-get next-request-id)
)
