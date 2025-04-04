;; farm-registration.clar
;; Records details of agricultural operations

;; Define data variables
(define-data-var contract-owner principal tx-sender)
(define-map farms
  { owner: principal }
  {
    farm-id: (string-utf8 32),
    location: {
      latitude: int,
      longitude: int
    },
    size-hectares: uint,
    registered-at: uint,
    active: bool
  }
)

(define-map crops
  { farm-id: (string-utf8 32), crop-id: (string-utf8 32) }
  {
    name: (string-utf8 32),
    variety: (string-utf8 32),
    planting-date: uint,
    expected-harvest-date: uint,
    hectares: uint
  }
)

;; Error codes
(define-constant err-unauthorized u1)
(define-constant err-farm-exists u2)
(define-constant err-farm-not-found u3)
(define-constant err-crop-exists u4)
(define-constant err-crop-not-found u5)

;; Read-only functions
(define-read-only (get-farm-details (owner principal))
  (map-get? farms { owner: owner })
)

(define-read-only (get-crop-details (farm-id (string-utf8 32)) (crop-id (string-utf8 32)))
  (map-get? crops { farm-id: farm-id, crop-id: crop-id })
)

;; Public functions
(define-public (register-farm
    (farm-id (string-utf8 32))
    (latitude int)
    (longitude int)
    (size-hectares uint)
  )
  (let
    ((caller tx-sender))
    (asserts! (is-none (map-get? farms { owner: caller })) (err err-farm-exists))

    (ok (map-set farms
      { owner: caller }
      {
        farm-id: farm-id,
        location: {
          latitude: latitude,
          longitude: longitude
        },
        size-hectares: size-hectares,
        registered-at: block-height,
        active: true
      }
    ))
  )
)

(define-public (add-crop
    (farm-id (string-utf8 32))
    (crop-id (string-utf8 32))
    (name (string-utf8 32))
    (variety (string-utf8 32))
    (planting-date uint)
    (expected-harvest-date uint)
    (hectares uint)
  )
  (let
    ((caller tx-sender)
     (farm-data (map-get? farms { owner: caller })))

    ;; Check if farm exists and belongs to caller
    (asserts! (is-some farm-data) (err err-farm-not-found))

    ;; Check if crop already exists
    (asserts! (is-none (map-get? crops { farm-id: farm-id, crop-id: crop-id })) (err err-crop-exists))

    ;; Add crop
    (ok (map-set crops
      { farm-id: farm-id, crop-id: crop-id }
      {
        name: name,
        variety: variety,
        planting-date: planting-date,
        expected-harvest-date: expected-harvest-date,
        hectares: hectares
      }
    ))
  )
)

(define-public (deactivate-farm)
  (let
    ((caller tx-sender)
     (farm-data (map-get? farms { owner: caller })))

    ;; Check if farm exists
    (asserts! (is-some farm-data) (err err-farm-not-found))

    ;; Update farm status
    (ok (map-set farms
      { owner: caller }
      (merge (unwrap-panic farm-data) { active: false })
    ))
  )
)
