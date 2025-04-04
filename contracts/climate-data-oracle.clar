;; climate-data-oracle.clar
;; Provides verified weather information

;; Define data variables
(define-data-var contract-owner principal tx-sender)
(define-map authorized-data-providers
  { provider: principal }
  { active: bool }
)

(define-map weather-data
  { location-id: (string-utf8 32), timestamp: uint }
  {
    temperature: int,     ;; Temperature in Celsius * 100 (for 2 decimal places)
    precipitation: uint,  ;; Precipitation in mm * 100 (for 2 decimal places)
    humidity: uint,       ;; Humidity percentage * 100 (for 2 decimal places)
    wind-speed: uint,     ;; Wind speed in km/h * 100 (for 2 decimal places)
    reported-by: principal,
    is-extreme-event: bool
  }
)

(define-map extreme-weather-events
  { event-id: (string-utf8 32) }
  {
    location-id: (string-utf8 32),
    event-type: (string-utf8 32), ;; drought, flood, frost, etc.
    start-time: uint,
    end-time: uint,
    severity: uint,        ;; 1-10 scale
    confirmed: bool
  }
)

;; Error codes
(define-constant err-unauthorized u1)
(define-constant err-provider-exists u2)
(define-constant err-provider-not-found u3)
(define-constant err-data-exists u4)
(define-constant err-event-exists u5)

;; Read-only functions
(define-read-only (get-weather-data (location-id (string-utf8 32)) (timestamp uint))
  (map-get? weather-data { location-id: location-id, timestamp: timestamp })
)

(define-read-only (get-extreme-event (event-id (string-utf8 32)))
  (map-get? extreme-weather-events { event-id: event-id })
)

(define-read-only (is-authorized-provider (provider principal))
  (default-to false (get active (map-get? authorized-data-providers { provider: provider })))
)

;; Public functions
(define-public (register-data-provider (provider principal))
  (begin
    ;; Only contract owner can register providers
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err err-unauthorized))

    ;; Check if provider already exists
    (asserts! (is-none (map-get? authorized-data-providers { provider: provider })) (err err-provider-exists))

    ;; Add provider
    (ok (map-set authorized-data-providers
      { provider: provider }
      { active: true }
    ))
  )
)

(define-public (report-weather-data
    (location-id (string-utf8 32))
    (timestamp uint)
    (temperature int)
    (precipitation uint)
    (humidity uint)
    (wind-speed uint)
    (is-extreme-event bool)
  )
  (let
    ((caller tx-sender))

    ;; Ensure caller is authorized
    (asserts! (is-authorized-provider caller) (err err-unauthorized))

    ;; Add weather data
    (ok (map-set weather-data
      { location-id: location-id, timestamp: timestamp }
      {
        temperature: temperature,
        precipitation: precipitation,
        humidity: humidity,
        wind-speed: wind-speed,
        reported-by: caller,
        is-extreme-event: is-extreme-event
      }
    ))
  )
)

(define-public (report-extreme-event
    (event-id (string-utf8 32))
    (location-id (string-utf8 32))
    (event-type (string-utf8 32))
    (start-time uint)
    (end-time uint)
    (severity uint)
  )
  (let
    ((caller tx-sender))

    ;; Ensure caller is authorized
    (asserts! (is-authorized-provider caller) (err err-unauthorized))

    ;; Check event doesn't already exist
    (asserts! (is-none (map-get? extreme-weather-events { event-id: event-id })) (err err-event-exists))

    ;; Add extreme event report
    (ok (map-set extreme-weather-events
      { event-id: event-id }
      {
        location-id: location-id,
        event-type: event-type,
        start-time: start-time,
        end-time: end-time,
        severity: severity,
        confirmed: false
      }
    ))
  )
)

(define-public (confirm-extreme-event (event-id (string-utf8 32)))
  (let
    ((caller tx-sender)
     (event-data (map-get? extreme-weather-events { event-id: event-id })))

    ;; Ensure caller is authorized and event exists
    (asserts! (is-authorized-provider caller) (err err-unauthorized))
    (asserts! (is-some event-data) (err err-provider-not-found))

    ;; Update event confirmation
    (ok (map-set extreme-weather-events
      { event-id: event-id }
      (merge (unwrap-panic event-data) { confirmed: true })
    ))
  )
)
