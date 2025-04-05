;; Impact Assessment Contract
;; Monitors and limits environmental effects

;; Define impact data structure
(define-map location-impact
  { location-id: uint }
  {
    total-bookings: uint,
    total-days-used: uint,
    last-assessment-time: uint,
    environmental-score: uint,  ;; 0-100, higher is better
    usage-limit-per-month: uint,  ;; in days
    current-month-usage: uint,
    is-restricted: bool,
    owner: principal
  }
)

;; Define booking impact data
(define-map booking-impact
  { booking-id: uint }
  {
    location-id: uint,
    days-used: uint,
    impact-score: uint,  ;; 0-100, higher means more impact
    notes: (string-ascii 500)
  }
)

;; Initialize a location's impact tracking
(define-public (initialize-impact-tracking
    (location-id uint)
    (usage-limit-per-month uint))
  (let
    (
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
    )

    ;; Initialize the impact data
    (map-set location-impact
      { location-id: location-id }
      {
        total-bookings: u0,
        total-days-used: u0,
        last-assessment-time: current-time,
        environmental-score: u100,  ;; Start with perfect score
        usage-limit-per-month: usage-limit-per-month,
        current-month-usage: u0,
        is-restricted: false,
        owner: tx-sender
      }
    )

    (ok true)
  )
)

;; Record the impact of a completed booking
(define-public (record-booking-impact
    (booking-id uint)
    (location-id uint)
    (start-time uint)
    (end-time uint))
  (let
    (
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
      (days-used (/ (- end-time start-time) u86400))
      (impact-data (unwrap! (map-get? location-impact { location-id: location-id }) (err u3)))
    )

    ;; Check that the sender is the owner of the impact data
    (asserts! (is-eq tx-sender (get owner impact-data)) (err u4))

    ;; Record the booking impact
    (map-set booking-impact
      { booking-id: booking-id }
      {
        location-id: location-id,
        days-used: days-used,
        impact-score: u50,  ;; Default medium impact
        notes: ""
      }
    )

    ;; Update the location impact data
    (map-set location-impact
      { location-id: location-id }
      {
        total-bookings: (+ (get total-bookings impact-data) u1),
        total-days-used: (+ (get total-days-used impact-data) days-used),
        last-assessment-time: current-time,
        environmental-score: (calculate-new-score (get environmental-score impact-data) days-used),
        usage-limit-per-month: (get usage-limit-per-month impact-data),
        current-month-usage: (+ (get current-month-usage impact-data) days-used),
        is-restricted: (get is-restricted impact-data),
        owner: (get owner impact-data)
      }
    )

    ;; Check if we need to restrict the location due to overuse
    (if (> (+ (get current-month-usage impact-data) days-used) (get usage-limit-per-month impact-data))
      (restrict-location location-id)
      (ok true)
    )
  )
)

;; Helper function to calculate a new environmental score
(define-private (calculate-new-score (current-score uint) (days-used uint))
  (let
    (
      (impact-factor (/ days-used u10))  ;; Each 10 days reduces score by 1 point
    )
    (if (> impact-factor current-score)
      u0
      (- current-score impact-factor)
    )
  )
)

;; Restrict a location due to overuse
(define-private (restrict-location (location-id uint))
  (let
    (
      (impact-data (unwrap! (map-get? location-impact { location-id: location-id }) (err u1)))
    )

    ;; Update the location impact data to restricted
    (map-set location-impact
      { location-id: location-id }
      (merge impact-data { is-restricted: true })
    )

    (ok true)
  )
)

;; Reset monthly usage counter
(define-public (reset-monthly-usage (location-id uint))
  (let
    (
      (impact-data (unwrap! (map-get? location-impact { location-id: location-id }) (err u2)))
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
    )

    ;; Check that the sender is the owner
    (asserts! (is-eq tx-sender (get owner impact-data)) (err u3))

    ;; Check that at least 30 days have passed since the last assessment
    (asserts! (>= (- current-time (get last-assessment-time impact-data)) u2592000) (err u4))

    ;; Reset the monthly usage and unrestrict if needed
    (map-set location-impact
      { location-id: location-id }
      (merge impact-data
        {
          current-month-usage: u0,
          is-restricted: false,
          last-assessment-time: current-time
        }
      )
    )

    (ok true)
  )
)

;; Update the environmental score manually (by an admin or auditor)
(define-public (update-environmental-score (location-id uint) (new-score uint))
  (let
    (
      (impact-data (unwrap! (map-get? location-impact { location-id: location-id }) (err u2)))
    )

    ;; Check that the sender is the owner
    (asserts! (is-eq tx-sender (get owner impact-data)) (err u3))

    ;; Check that the score is valid (0-100)
    (asserts! (<= new-score u100) (err u4))

    ;; Update the environmental score
    (map-set location-impact
      { location-id: location-id }
      (merge impact-data { environmental-score: new-score })
    )

    (ok true)
  )
)

;; Get impact data for a location
(define-read-only (get-location-impact (location-id uint))
  (map-get? location-impact { location-id: location-id })
)

;; Get impact data for a booking
(define-read-only (get-booking-impact (booking-id uint))
  (map-get? booking-impact { booking-id: booking-id })
)

;; Update the usage limit for a location
(define-public (update-usage-limit (location-id uint) (new-limit uint))
  (let
    (
      (impact-data (unwrap! (map-get? location-impact { location-id: location-id }) (err u2)))
    )

    ;; Check that the sender is the owner
    (asserts! (is-eq tx-sender (get owner impact-data)) (err u3))

    ;; Update the usage limit
    (map-set location-impact
      { location-id: location-id }
      (merge impact-data { usage-limit-per-month: new-limit })
    )

    (ok true)
  )
)

;; Check if a location is restricted due to overuse
(define-read-only (is-location-restricted (location-id uint))
  (let
    (
      (impact-data (map-get? location-impact { location-id: location-id }))
    )
    (if (is-some impact-data)
      (get is-restricted (unwrap-panic impact-data))
      false
    )
  )
)
