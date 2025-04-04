;; risk-assessment.clar
;; Calculates premiums based on location and crops

;; Define data variables
(define-data-var contract-owner principal tx-sender)

(define-map risk-factors
  { region: (string-utf8 32), crop-type: (string-utf8 32) }
  {
    base-premium-rate: uint,  ;; Base premium rate * 10000 (for 4 decimal places)
    drought-factor: uint,     ;; Risk multiplier * 10000 (for 4 decimal places)
    flood-factor: uint,       ;; Risk multiplier * 10000 (for 4 decimal places)
    frost-factor: uint,       ;; Risk multiplier * 10000 (for 4 decimal places)
    pest-factor: uint,        ;; Risk multiplier * 10000 (for 4 decimal places)
    last-updated: uint
  }
)

(define-map premium-calculations
  { farm-id: (string-utf8 32), crop-id: (string-utf8 32) }
  {
    premium-amount: uint,
    coverage-amount: uint,
    calculated-at: uint,
    valid-until: uint
  }
)

;; Error codes
(define-constant err-unauthorized u1)
(define-constant err-risk-factor-exists u2)
(define-constant err-risk-factor-not-found u3)
(define-constant err-invalid-parameters u4)

;; Utility constants
(define-constant precision-factor u10000)  ;; For 4 decimal places in calculations

;; Read-only functions
(define-read-only (get-risk-factors (region (string-utf8 32)) (crop-type (string-utf8 32)))
  (map-get? risk-factors { region: region, crop-type: crop-type })
)

(define-read-only (get-premium-calculation (farm-id (string-utf8 32)) (crop-id (string-utf8 32)))
  (map-get? premium-calculations { farm-id: farm-id, crop-id: crop-id })
)

;; Helper function for premium calculation
(define-read-only (calculate-premium
    (region (string-utf8 32))
    (crop-type (string-utf8 32))
    (hectares uint)
    (value-per-hectare uint)
  )
  (let
    ((risk-data (map-get? risk-factors { region: region, crop-type: crop-type })))

    (if (is-some risk-data)
      (let
        ((factors (unwrap-panic risk-data))
         (base-rate (get base-premium-rate factors))
         (total-value (* hectares value-per-hectare))
         ;; Calculate premium by multiplying total value by base rate
         (premium-amount (/ (* total-value base-rate) precision-factor)))

        (some {
          premium-amount: premium-amount,
          coverage-amount: total-value
        })
      )
      none
    )
  )
)

;; Public functions
(define-public (set-risk-factors
    (region (string-utf8 32))
    (crop-type (string-utf8 32))
    (base-premium-rate uint)
    (drought-factor uint)
    (flood-factor uint)
    (frost-factor uint)
    (pest-factor uint)
  )
  (begin
    ;; Only contract owner can set risk factors
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err err-unauthorized))

    ;; Validate parameters
    (asserts! (and (> base-premium-rate u0) (<= base-premium-rate precision-factor)) (err err-invalid-parameters))

    ;; Set risk factors
    (ok (map-set risk-factors
      { region: region, crop-type: crop-type }
      {
        base-premium-rate: base-premium-rate,
        drought-factor: drought-factor,
        flood-factor: flood-factor,
        frost-factor: frost-factor,
        pest-factor: pest-factor,
        last-updated: block-height
      }
    ))
  )
)

(define-public (calculate-and-store-premium
    (farm-id (string-utf8 32))
    (crop-id (string-utf8 32))
    (region (string-utf8 32))
    (crop-type (string-utf8 32))
    (hectares uint)
    (value-per-hectare uint)
    (valid-days uint)
  )
  (let
    ((calculation (calculate-premium region crop-type hectares value-per-hectare)))

    ;; Check if risk factors exist for this region and crop
    (asserts! (is-some calculation) (err err-risk-factor-not-found))

    ;; Store premium calculation
    (ok (map-set premium-calculations
      { farm-id: farm-id, crop-id: crop-id }
      {
        premium-amount: (get premium-amount (unwrap-panic calculation)),
        coverage-amount: (get coverage-amount (unwrap-panic calculation)),
        calculated-at: block-height,
        valid-until: (+ block-height (* valid-days u144))  ;; Assuming ~144 blocks per day
      }
    ))
  )
)
