;; Energy Efficiency Contract
;; Optimizes heating and cooling performance

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-OWNER-ONLY (err u300))
(define-constant ERR-NOT-FOUND (err u301))
(define-constant ERR-INVALID-INPUT (err u302))
(define-constant ERR-UNAUTHORIZED (err u303))

;; Data Variables
(define-data-var contract-active bool true)
(define-data-var total-optimizations uint u0)
(define-data-var total-energy-saved uint u0)

;; Data Maps
(define-map efficiency-systems
  { system-id: uint }
  {
    owner: principal,
    system-capacity: uint,
    baseline-consumption: uint,
    current-consumption: uint,
    efficiency-rating: uint,
    last-optimization: uint,
    total-savings: uint,
    active: bool
  }
)

(define-map energy-readings
  { system-id: uint, reading-date: uint }
  {
    power-consumption: uint,
    temperature-differential: uint,
    runtime-hours: uint,
    efficiency-score: uint,
    cost-per-hour: uint,
    outdoor-temp: uint,
    indoor-temp: uint
  }
)

(define-map optimization-records
  { system-id: uint, optimization-id: uint }
  {
    optimization-type: (string-ascii 100),
    implementation-date: uint,
    energy-savings: uint,
    cost-savings: uint,
    efficiency-improvement: uint,
    status: (string-ascii 50)
  }
)

(define-map user-balances
  { user: principal }
  { efficiency-tokens: uint }
)

;; Token Functions
(define-private (mint-efficiency-tokens (recipient principal) (amount uint))
  (let ((current-balance (default-to u0 (get efficiency-tokens (map-get? user-balances { user: recipient })))))
    (map-set user-balances
      { user: recipient }
      { efficiency-tokens: (+ current-balance amount) }
    )
  )
)

;; Public Functions
(define-public (register-efficiency-system (system-id uint) (system-capacity uint) (baseline-consumption uint))
  (begin
    (asserts! (var-get contract-active) (err u304))
    (asserts! (> system-capacity u0) ERR-INVALID-INPUT)
    (asserts! (> baseline-consumption u0) ERR-INVALID-INPUT)
    (asserts! (is-none (map-get? efficiency-systems { system-id: system-id })) (err u305))

    (map-set efficiency-systems
      { system-id: system-id }
      {
        owner: tx-sender,
        system-capacity: system-capacity,
        baseline-consumption: baseline-consumption,
        current-consumption: baseline-consumption,
        efficiency-rating: u100,
        last-optimization: block-height,
        total-savings: u0,
        active: true
      }
    )

    (ok system-id)
  )
)

(define-public (record-energy-reading (system-id uint) (power-consumption uint) (temp-diff uint) (runtime-hours uint) (outdoor-temp uint) (indoor-temp uint))
  (let ((system-data (unwrap! (map-get? efficiency-systems { system-id: system-id }) ERR-NOT-FOUND)))
    (asserts! (var-get contract-active) (err u304))
    (asserts! (is-eq (get owner system-data) tx-sender) ERR-UNAUTHORIZED)
    (asserts! (get active system-data) (err u306))

    (let ((efficiency-score (calculate-efficiency-score power-consumption temp-diff runtime-hours (get system-capacity system-data)))
          (cost-per-hour (calculate-cost-per-hour power-consumption)))

      ;; Record energy reading
      (map-set energy-readings
        { system-id: system-id, reading-date: block-height }
        {
          power-consumption: power-consumption,
          temperature-differential: temp-diff,
          runtime-hours: runtime-hours,
          efficiency-score: efficiency-score,
          cost-per-hour: cost-per-hour,
          outdoor-temp: outdoor-temp,
          indoor-temp: indoor-temp
        }
      )

      ;; Update system consumption
      (map-set efficiency-systems
        { system-id: system-id }
        (merge system-data {
          current-consumption: power-consumption,
          efficiency-rating: efficiency-score
        })
      )

      ;; Mint tokens for recording data
      (mint-efficiency-tokens tx-sender u3)

      ;; Bonus tokens for high efficiency
      (if (> efficiency-score u90)
        (mint-efficiency-tokens tx-sender u5)
        true
      )

      (ok efficiency-score)
    )
  )
)

(define-public (implement-optimization (system-id uint) (optimization-id uint) (optimization-type (string-ascii 100)) (expected-savings uint))
  (let ((system-data (unwrap! (map-get? efficiency-systems { system-id: system-id }) ERR-NOT-FOUND)))
    (asserts! (var-get contract-active) (err u304))
    (asserts! (is-eq (get owner system-data) tx-sender) ERR-UNAUTHORIZED)
    (asserts! (> expected-savings u0) ERR-INVALID-INPUT)

    (let ((efficiency-improvement (calculate-efficiency-improvement expected-savings (get baseline-consumption system-data))))

      (map-set optimization-records
        { system-id: system-id, optimization-id: optimization-id }
        {
          optimization-type: optimization-type,
          implementation-date: block-height,
          energy-savings: expected-savings,
          cost-savings: (/ (* expected-savings u15) u100),
          efficiency-improvement: efficiency-improvement,
          status: "implemented"
        }
      )

      ;; Update system totals
      (map-set efficiency-systems
        { system-id: system-id }
        (merge system-data {
          last-optimization: block-height,
          total-savings: (+ (get total-savings system-data) expected-savings)
        })
      )

      ;; Mint tokens based on savings
      (mint-efficiency-tokens tx-sender (/ expected-savings u10))

      (var-set total-optimizations (+ (var-get total-optimizations) u1))
      (var-set total-energy-saved (+ (var-get total-energy-saved) expected-savings))

      (ok optimization-id)
    )
  )
)

(define-public (verify-optimization-results (system-id uint) (optimization-id uint) (actual-savings uint))
  (let ((system-data (unwrap! (map-get? efficiency-systems { system-id: system-id }) ERR-NOT-FOUND))
        (optimization-data (unwrap! (map-get? optimization-records { system-id: system-id, optimization-id: optimization-id }) ERR-NOT-FOUND)))

    (asserts! (var-get contract-active) (err u304))
    (asserts! (is-eq (get owner system-data) tx-sender) ERR-UNAUTHORIZED)
    (asserts! (is-eq (get status optimization-data) "implemented") (err u307))

    (let ((expected-savings (get energy-savings optimization-data))
          (performance-ratio (/ (* actual-savings u100) expected-savings)))

      (map-set optimization-records
        { system-id: system-id, optimization-id: optimization-id }
        (merge optimization-data {
          energy-savings: actual-savings,
          cost-savings: (/ (* actual-savings u15) u100),
          status: "verified"
        })
      )

      ;; Bonus tokens for exceeding expectations
      (if (> performance-ratio u100)
        (mint-efficiency-tokens tx-sender u10)
        true
      )

      ;; Penalty for underperformance (no additional tokens)
      (ok performance-ratio)
    )
  )
)

;; Private Helper Functions
(define-private (calculate-efficiency-score (power uint) (temp-diff uint) (runtime uint) (capacity uint))
  (let ((base-efficiency (/ (* capacity u100) power)))
    (if (> temp-diff u20)
      (- base-efficiency u10)
      (if (< temp-diff u5)
        (+ base-efficiency u5)
        base-efficiency
      )
    )
  )
)

(define-private (calculate-cost-per-hour (power-consumption uint))
  (/ (* power-consumption u15) u1000)
)

(define-private (calculate-efficiency-improvement (savings uint) (baseline uint))
  (/ (* savings u100) baseline)
)

;; Read-only Functions
(define-read-only (get-system-info (system-id uint))
  (map-get? efficiency-systems { system-id: system-id })
)

(define-read-only (get-energy-reading (system-id uint) (reading-date uint))
  (map-get? energy-readings { system-id: system-id, reading-date: reading-date })
)

(define-read-only (get-optimization-record (system-id uint) (optimization-id uint))
  (map-get? optimization-records { system-id: system-id, optimization-id: optimization-id })
)

(define-read-only (get-user-tokens (user principal))
  (default-to u0 (get efficiency-tokens (map-get? user-balances { user: user })))
)

(define-read-only (get-contract-stats)
  {
    total-optimizations: (var-get total-optimizations),
    total-energy-saved: (var-get total-energy-saved),
    contract-active: (var-get contract-active)
  }
)

(define-read-only (calculate-potential-savings (system-id uint) (target-efficiency uint))
  (match (map-get? efficiency-systems { system-id: system-id })
    system-data
    (let ((current-consumption (get current-consumption system-data))
          (current-efficiency (get efficiency-rating system-data)))
      (if (> target-efficiency current-efficiency)
        (/ (* current-consumption (- target-efficiency current-efficiency)) u100)
        u0
      )
    )
    u0
  )
)

(define-read-only (get-efficiency-recommendations (system-id uint))
  (match (map-get? efficiency-systems { system-id: system-id })
    system-data
    (let ((efficiency-rating (get efficiency-rating system-data)))
      (if (< efficiency-rating u70)
        "Consider system upgrade or major maintenance"
        (if (< efficiency-rating u85)
          "Schedule tune-up and filter replacement"
          "System operating efficiently"
        )
      )
    )
    "System not found"
  )
)
