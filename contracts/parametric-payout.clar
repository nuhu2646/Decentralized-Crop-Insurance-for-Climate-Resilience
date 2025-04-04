;; parametric-payout.clar
;; Triggers compensation based on climate events

;; Define data variables
(define-data-var contract-owner principal tx-sender)
(define-data-var oracle-contract principal tx-sender)
(define-data-var risk-contract principal tx-sender)

(define-map insurance-policies
  { policy-id: (string-utf8 32) }
  {
    farm-id: (string-utf8 32),
    crop-id: (string-utf8 32),
    owner: principal,
    premium-paid: uint,
    coverage-amount: uint,
    start-block: uint,
    end-block: uint,
    is-active: bool
  }
)

(define-map policy-triggers
  { policy-id: (string-utf8 32), trigger-id: (string-utf8 32) }
  {
    event-type: (string-utf8 32),      ;; drought, flood, frost, etc.
    threshold-value: int,              ;; threshold value for the event
    payout-percentage: uint,           ;; percentage of coverage to pay * 100 (for 2 decimal places)
    days-consecutive: uint             ;; number of consecutive days for the event to trigger
  }
)

(define-map payouts
  { payout-id: (string-utf8 32) }
  {
    policy-id: (string-utf8 32),
    trigger-id: (string-utf8 32),
    event-id: (string-utf8 32),
    amount: uint,
    paid-at: uint,
    recipient: principal
  }
)

;; Error codes
(define-constant err-unauthorized u1)
(define-constant err-policy-exists u2)
(define-constant err-policy-not-found u3)
(define-constant err-trigger-exists u4)
(define-constant err-trigger-not-found u5)
(define-constant err-payout-exists u6)
(define-constant err-policy-inactive u7)
(define-constant err-invalid-parameters u8)

;; Read-only functions
(define-read-only (get-policy (policy-id (string-utf8 32)))
  (map-get? insurance-policies { policy-id: policy-id })
)

(define-read-only (get-policy-trigger (policy-id (string-utf8 32)) (trigger-id (string-utf8 32)))
  (map-get? policy-triggers { policy-id: policy-id, trigger-id: trigger-id })
)

(define-read-only (get-payout (payout-id (string-utf8 32)))
  (map-get? payouts { payout-id: payout-id })
)

;; Public functions
(define-public (set-contract-references (oracle principal) (risk principal))
  (begin
    ;; Only contract owner can set references
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err err-unauthorized))

    ;; Set contract references
    (var-set oracle-contract oracle)
    (var-set risk-contract risk)
    (ok true)
  )
)

(define-public (create-policy
    (policy-id (string-utf8 32))
    (farm-id (string-utf8 32))
    (crop-id (string-utf8 32))
    (premium uint)
    (coverage-amount uint)
    (duration-blocks uint)
  )
  (let
    ((caller tx-sender))

    ;; Check policy doesn't already exist
    (asserts! (is-none (map-get? insurance-policies { policy-id: policy-id })) (err err-policy-exists))

    ;; Validate parameters
    (asserts! (and (> premium u0) (> coverage-amount u0) (> duration-blocks u0)) (err err-invalid-parameters))

    ;; Create policy
    (ok (map-set insurance-policies
      { policy-id: policy-id }
      {
        farm-id: farm-id,
        crop-id: crop-id,
        owner: caller,
        premium-paid: premium,
        coverage-amount: coverage-amount,
        start-block: block-height,
        end-block: (+ block-height duration-blocks),
        is-active: true
      }
    ))
  )
)

(define-public (add-policy-trigger
    (policy-id (string-utf8 32))
    (trigger-id (string-utf8 32))
    (event-type (string-utf8 32))
    (threshold-value int)
    (payout-percentage uint)
    (days-consecutive uint)
  )
  (let
    ((caller tx-sender)
     (policy-data (map-get? insurance-policies { policy-id: policy-id })))

    ;; Check policy exists and caller is owner
    (asserts! (is-some policy-data) (err err-policy-not-found))
    (asserts! (is-eq caller (get owner (unwrap-panic policy-data))) (err err-unauthorized))

    ;; Check trigger doesn't already exist
    (asserts! (is-none (map-get? policy-triggers { policy-id: policy-id, trigger-id: trigger-id })) (err err-trigger-exists))

    ;; Add trigger
    (ok (map-set policy-triggers
      { policy-id: policy-id, trigger-id: trigger-id }
      {
        event-type: event-type,
        threshold-value: threshold-value,
        payout-percentage: payout-percentage,
        days-consecutive: days-consecutive
      }
    ))
  )
)

(define-public (process-payout
    (payout-id (string-utf8 32))
    (policy-id (string-utf8 32))
    (trigger-id (string-utf8 32))
    (event-id (string-utf8 32))
  )
  (let
    ((policy-data (map-get? insurance-policies { policy-id: policy-id }))
     (trigger-data (map-get? policy-triggers { policy-id: policy-id, trigger-id: trigger-id })))

    ;; Check policy and trigger exist
    (asserts! (is-some policy-data) (err err-policy-not-found))
    (asserts! (is-some trigger-data) (err err-trigger-not-found))

    ;; Check payout doesn't already exist
    (asserts! (is-none (map-get? payouts { payout-id: payout-id })) (err err-payout-exists))

    ;; Check policy is active
    (asserts! (get is-active (unwrap-panic policy-data)) (err err-policy-inactive))

    ;; Calculate payout amount
    (let
      ((policy (unwrap-panic policy-data))
       (trigger (unwrap-panic trigger-data))
       (coverage (get coverage-amount policy))
       (percentage (get payout-percentage trigger))
       (payout-amount (/ (* coverage percentage) u10000)))

      ;; Create payout record
      (ok (map-set payouts
        { payout-id: payout-id }
        {
          policy-id: policy-id,
          trigger-id: trigger-id,
          event-id: event-id,
          amount: payout-amount,
          paid-at: block-height,
          recipient: (get owner policy)
        }
      ))
    )
  )
)

(define-public (deactivate-policy (policy-id (string-utf8 32)))
  (let
    ((caller tx-sender)
     (policy-data (map-get? insurance-policies { policy-id: policy-id })))

    ;; Check policy exists
    (asserts! (is-some policy-data) (err err-policy-not-found))

    ;; Check caller is owner or contract owner
    (asserts! (or
      (is-eq caller (get owner (unwrap-panic policy-data)))
      (is-eq caller (var-get contract-owner))
    ) (err err-unauthorized))

    ;; Deactivate policy
    (ok (map-set insurance-policies
      { policy-id: policy-id }
      (merge (unwrap-panic policy-data) { is-active: false })
    ))
  )
)

