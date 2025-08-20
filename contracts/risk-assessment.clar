;; DeFi Risk Assessment Contract
;; Manages protocol risk evaluation and scoring

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-INPUT (err u101))
(define-constant ERR-NOT-FOUND (err u102))
(define-constant ERR-ALREADY-EXISTS (err u103))

;; Data Variables
(define-data-var next-protocol-id uint u1)
(define-data-var risk-threshold uint u70) ;; Default risk threshold

;; Data Maps
(define-map protocols
  { protocol-id: uint }
  {
    name: (string-ascii 50),
    owner: principal,
    created-at: uint,
    active: bool
  }
)

(define-map risk-assessments
  { protocol-id: uint }
  {
    risk-score: uint,        ;; Overall risk score (1-100)
    liquidity-risk: uint,    ;; Liquidity risk factor (1-100)
    volatility-risk: uint,   ;; Volatility risk factor (1-100)
    security-risk: uint,     ;; Security risk factor (1-100)
    last-updated: uint,      ;; Block height of last update
    assessor: principal      ;; Who performed the assessment
  }
)

(define-map risk-history
  { protocol-id: uint, timestamp: uint }
  {
    risk-score: uint,
    liquidity-risk: uint,
    volatility-risk: uint,
    security-risk: uint,
    assessor: principal
  }
)

(define-map authorized-assessors
  { assessor: principal }
  { authorized: bool, reputation: uint }
)

;; Private Functions

(define-private (is-authorized-assessor (assessor principal))
  ;; Fixed default-to function call - removed extra 'bool' argument
  (default-to false (get authorized (map-get? authorized-assessors { assessor: assessor })))
)

(define-private (calculate-overall-risk (liquidity uint) (volatility uint) (security uint))
  (let (
    (weighted-score (+ (* liquidity u3) (* volatility u2) (* security u5)))
    (total-weight u10)
  )
    (/ weighted-score total-weight)
  )
)

(define-private (is-valid-risk-score (score uint))
  (and (>= score u1) (<= score u100))
)

;; Public Functions

;; Register a new protocol for risk assessment
(define-public (register-protocol (name (string-ascii 50)))
  (let (
    (protocol-id (var-get next-protocol-id))
  )
    (asserts! (> (len name) u0) ERR-INVALID-INPUT)
    (asserts! (is-none (map-get? protocols { protocol-id: protocol-id })) ERR-ALREADY-EXISTS)

    (map-set protocols
      { protocol-id: protocol-id }
      {
        name: name,
        owner: tx-sender,
        created-at: block-height,
        active: true
      }
    )

    (var-set next-protocol-id (+ protocol-id u1))
    (ok protocol-id)
  )
)

;; Authorize an assessor to perform risk evaluations
(define-public (authorize-assessor (assessor principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (map-set authorized-assessors
      { assessor: assessor }
      { authorized: true, reputation: u50 }
    )
    (ok true)
  )
)

;; Assess protocol risk with individual risk factors
(define-public (assess-protocol-risk
  (protocol-id uint)
  (liquidity-risk uint)
  (volatility-risk uint)
  (security-risk uint))
  (let (
    (protocol (map-get? protocols { protocol-id: protocol-id }))
    (overall-risk (calculate-overall-risk liquidity-risk volatility-risk security-risk))
  )
    (asserts! (is-some protocol) ERR-NOT-FOUND)
    (asserts! (get active (unwrap-panic protocol)) ERR-INVALID-INPUT)
    (asserts! (is-authorized-assessor tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-valid-risk-score liquidity-risk) ERR-INVALID-INPUT)
    (asserts! (is-valid-risk-score volatility-risk) ERR-INVALID-INPUT)
    (asserts! (is-valid-risk-score security-risk) ERR-INVALID-INPUT)

    ;; Store current assessment
    (map-set risk-assessments
      { protocol-id: protocol-id }
      {
        risk-score: overall-risk,
        liquidity-risk: liquidity-risk,
        volatility-risk: volatility-risk,
        security-risk: security-risk,
        last-updated: block-height,
        assessor: tx-sender
      }
    )

    ;; Store in history
    (map-set risk-history
      { protocol-id: protocol-id, timestamp: block-height }
      {
        risk-score: overall-risk,
        liquidity-risk: liquidity-risk,
        volatility-risk: volatility-risk,
        security-risk: security-risk,
        assessor: tx-sender
      }
    )

    (ok overall-risk)
  )
)

;; Update individual risk factors
(define-public (update-risk-factor
  (protocol-id uint)
  (factor (string-ascii 20))
  (new-value uint))
  (let (
    (current-assessment (map-get? risk-assessments { protocol-id: protocol-id }))
  )
    (asserts! (is-some current-assessment) ERR-NOT-FOUND)
    (asserts! (is-authorized-assessor tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-valid-risk-score new-value) ERR-INVALID-INPUT)

    (let (
      (assessment (unwrap-panic current-assessment))
      (updated-assessment
        (if (is-eq factor "liquidity")
          (merge assessment { liquidity-risk: new-value, last-updated: block-height, assessor: tx-sender })
          (if (is-eq factor "volatility")
            (merge assessment { volatility-risk: new-value, last-updated: block-height, assessor: tx-sender })
            (if (is-eq factor "security")
              (merge assessment { security-risk: new-value, last-updated: block-height, assessor: tx-sender })
              assessment
            )
          )
        )
      )
      (new-overall-risk (calculate-overall-risk
        (get liquidity-risk updated-assessment)
        (get volatility-risk updated-assessment)
        (get security-risk updated-assessment)
      ))
    )
      (map-set risk-assessments
        { protocol-id: protocol-id }
        (merge updated-assessment { risk-score: new-overall-risk })
      )

      (ok new-overall-risk)
    )
  )
)

;; Set risk threshold for alerts
(define-public (set-risk-threshold (threshold uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (is-valid-risk-score threshold) ERR-INVALID-INPUT)
    (var-set risk-threshold threshold)
    (ok true)
  )
)

;; Deactivate a protocol
(define-public (deactivate-protocol (protocol-id uint))
  (let (
    (protocol (map-get? protocols { protocol-id: protocol-id }))
  )
    (asserts! (is-some protocol) ERR-NOT-FOUND)
    (asserts! (or
      (is-eq tx-sender CONTRACT-OWNER)
      (is-eq tx-sender (get owner (unwrap-panic protocol)))
    ) ERR-NOT-AUTHORIZED)

    (map-set protocols
      { protocol-id: protocol-id }
      (merge (unwrap-panic protocol) { active: false })
    )
    (ok true)
  )
)

;; Read-only Functions

;; Get protocol information
(define-read-only (get-protocol (protocol-id uint))
  (map-get? protocols { protocol-id: protocol-id })
)

;; Get current risk assessment
(define-read-only (get-risk-assessment (protocol-id uint))
  (map-get? risk-assessments { protocol-id: protocol-id })
)

;; Get risk score only
(define-read-only (get-risk-score (protocol-id uint))
  (match (map-get? risk-assessments { protocol-id: protocol-id })
    assessment (some (get risk-score assessment))
    none
  )
)

;; Check if protocol exceeds risk threshold
(define-read-only (is-high-risk (protocol-id uint))
  (match (get-risk-score protocol-id)
    score (> score (var-get risk-threshold))
    false
  )
)

;; Get risk history for a protocol at specific timestamp
(define-read-only (get-risk-history (protocol-id uint) (timestamp uint))
  (map-get? risk-history { protocol-id: protocol-id, timestamp: timestamp })
)

;; Get assessor information
(define-read-only (get-assessor-info (assessor principal))
  (map-get? authorized-assessors { assessor: assessor })
)

;; Get current risk threshold
(define-read-only (get-risk-threshold)
  (var-get risk-threshold)
)

;; Get next protocol ID
(define-read-only (get-next-protocol-id)
  (var-get next-protocol-id)
)

;; Check if assessor is authorized
(define-read-only (is-assessor-authorized (assessor principal))
  (is-authorized-assessor assessor)
)

;; Get protocol count
(define-read-only (get-protocol-count)
  (- (var-get next-protocol-id) u1)
)
