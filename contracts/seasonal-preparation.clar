;; Seasonal Preparation Contract
;; Coordinates system winterization and summer readiness

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-OWNER-ONLY (err u400))
(define-constant ERR-NOT-FOUND (err u401))
(define-constant ERR-INVALID-INPUT (err u402))
(define-constant ERR-UNAUTHORIZED (err u403))

;; Data Variables
(define-data-var contract-active bool true)
(define-data-var total-preparations uint u0)
(define-data-var current-season (string-ascii 20) "spring")

;; Data Maps
(define-map seasonal-systems
  { system-id: uint }
  {
    owner: principal,
    system-type: (string-ascii 50),
    last-winter-prep: uint,
    last-summer-prep: uint,
    winter-ready: bool,
    summer-ready: bool,
    prep-history-count: uint,
    active: bool
  }
)

(define-map preparation-checklists
  { system-id: uint, season: (string-ascii 20), prep-date: uint }
  {
    checklist-items: (list 10 (string-ascii 100)),
    completed-items: uint,
    total-items: uint,
    completion-percentage: uint,
    technician: (optional principal),
    completion-date: uint,
    notes: (string-ascii 200)
  }
)

(define-map seasonal-tasks
  { task-id: uint }
  {
    task-name: (string-ascii 100),
    season: (string-ascii 20),
    priority: uint,
    estimated-time: uint,
    required-tools: (string-ascii 200),
    safety-requirements: (string-ascii 200)
  }
)

(define-map user-balances
  { user: principal }
  { seasonal-tokens: uint }
)

;; Token Functions
(define-private (mint-seasonal-tokens (recipient principal) (amount uint))
  (let ((current-balance (default-to u0 (get seasonal-tokens (map-get? user-balances { user: recipient })))))
    (map-set user-balances
      { user: recipient }
      { seasonal-tokens: (+ current-balance amount) }
    )
  )
)

;; Public Functions
(define-public (register-seasonal-system (system-id uint) (system-type (string-ascii 50)))
  (begin
    (asserts! (var-get contract-active) (err u404))
    (asserts! (is-none (map-get? seasonal-systems { system-id: system-id })) (err u405))

    (map-set seasonal-systems
      { system-id: system-id }
      {
        owner: tx-sender,
        system-type: system-type,
        last-winter-prep: u0,
        last-summer-prep: u0,
        winter-ready: false,
        summer-ready: false,
        prep-history-count: u0,
        active: true
      }
    )

    (ok system-id)
  )
)

(define-public (create-preparation-checklist (system-id uint) (season (string-ascii 20)) (checklist-items (list 10 (string-ascii 100))))
  (let ((system-data (unwrap! (map-get? seasonal-systems { system-id: system-id }) ERR-NOT-FOUND)))
    (asserts! (var-get contract-active) (err u404))
    (asserts! (is-eq (get owner system-data) tx-sender) ERR-UNAUTHORIZED)
    (asserts! (get active system-data) (err u406))

    (let ((total-items (len checklist-items)))
      (map-set preparation-checklists
        { system-id: system-id, season: season, prep-date: block-height }
        {
          checklist-items: checklist-items,
          completed-items: u0,
          total-items: total-items,
          completion-percentage: u0,
          technician: none,
          completion-date: u0,
          notes: ""
        }
      )

      ;; Mint tokens for creating checklist
      (mint-seasonal-tokens tx-sender u5)

      (ok block-height)
    )
  )
)

(define-public (complete-preparation-task (system-id uint) (season (string-ascii 20)) (prep-date uint) (completed-count uint))
  (let ((system-data (unwrap! (map-get? seasonal-systems { system-id: system-id }) ERR-NOT-FOUND))
        (checklist-data (unwrap! (map-get? preparation-checklists { system-id: system-id, season: season, prep-date: prep-date }) ERR-NOT-FOUND)))

    (asserts! (var-get contract-active) (err u404))
    (asserts! (is-eq (get owner system-data) tx-sender) ERR-UNAUTHORIZED)
    (asserts! (<= completed-count (get total-items checklist-data)) ERR-INVALID-INPUT)

    (let ((completion-percentage (/ (* completed-count u100) (get total-items checklist-data))))

      (map-set preparation-checklists
        { system-id: system-id, season: season, prep-date: prep-date }
        (merge checklist-data {
          completed-items: completed-count,
          completion-percentage: completion-percentage,
          completion-date: (if (is-eq completed-count (get total-items checklist-data)) block-height u0)
        })
      )

      ;; Mint tokens based on completion percentage
      (mint-seasonal-tokens tx-sender (/ completion-percentage u10))

      ;; Update system readiness if fully completed
      (if (is-eq completed-count (get total-items checklist-data))
        (begin
          (if (is-eq season "winter")
            (map-set seasonal-systems
              { system-id: system-id }
              (merge system-data {
                last-winter-prep: block-height,
                winter-ready: true,
                prep-history-count: (+ (get prep-history-count system-data) u1)
              })
            )
            (map-set seasonal-systems
              { system-id: system-id }
              (merge system-data {
                last-summer-prep: block-height,
                summer-ready: true,
                prep-history-count: (+ (get prep-history-count system-data) u1)
              })
            )
          )
          (mint-seasonal-tokens tx-sender u15)
          (var-set total-preparations (+ (var-get total-preparations) u1))
        )
        true
      )

      (ok completion-percentage)
    )
  )
)

(define-public (assign-technician (system-id uint) (season (string-ascii 20)) (prep-date uint) (technician principal))
  (let ((system-data (unwrap! (map-get? seasonal-systems { system-id: system-id }) ERR-NOT-FOUND))
        (checklist-data (unwrap! (map-get? preparation-checklists { system-id: system-id, season: season, prep-date: prep-date }) ERR-NOT-FOUND)))

    (asserts! (var-get contract-active) (err u404))
    (asserts! (is-eq (get owner system-data) tx-sender) ERR-UNAUTHORIZED)

    (map-set preparation-checklists
      { system-id: system-id, season: season, prep-date: prep-date }
      (merge checklist-data { technician: (some technician) })
    )

    (ok true)
  )
)

(define-public (add-preparation-notes (system-id uint) (season (string-ascii 20)) (prep-date uint) (notes (string-ascii 200)))
  (let ((system-data (unwrap! (map-get? seasonal-systems { system-id: system-id }) ERR-NOT-FOUND))
        (checklist-data (unwrap! (map-get? preparation-checklists { system-id: system-id, season: season, prep-date: prep-date }) ERR-NOT-FOUND)))

    (asserts! (var-get contract-active) (err u404))
    (asserts! (is-eq (get owner system-data) tx-sender) ERR-UNAUTHORIZED)

    (map-set preparation-checklists
      { system-id: system-id, season: season, prep-date: prep-date }
      (merge checklist-data { notes: notes })
    )

    (mint-seasonal-tokens tx-sender u2)
    (ok true)
  )
)

(define-public (update-current-season (new-season (string-ascii 20)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (var-set current-season new-season)
    (ok new-season)
  )
)

(define-public (create-seasonal-task (task-id uint) (task-name (string-ascii 100)) (season (string-ascii 20)) (priority uint) (estimated-time uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (and (>= priority u1) (<= priority u5)) ERR-INVALID-INPUT)

    (map-set seasonal-tasks
      { task-id: task-id }
      {
        task-name: task-name,
        season: season,
        priority: priority,
        estimated-time: estimated-time,
        required-tools: "",
        safety-requirements: ""
      }
    )

    (ok task-id)
  )
)

;; Read-only Functions
(define-read-only (get-system-info (system-id uint))
  (map-get? seasonal-systems { system-id: system-id })
)

(define-read-only (get-preparation-checklist (system-id uint) (season (string-ascii 20)) (prep-date uint))
  (map-get? preparation-checklists { system-id: system-id, season: season, prep-date: prep-date })
)

(define-read-only (get-seasonal-task (task-id uint))
  (map-get? seasonal-tasks { task-id: task-id })
)

(define-read-only (get-user-tokens (user principal))
  (default-to u0 (get seasonal-tokens (map-get? user-balances { user: user })))
)

(define-read-only (get-contract-stats)
  {
    total-preparations: (var-get total-preparations),
    current-season: (var-get current-season),
    contract-active: (var-get contract-active)
  }
)

(define-read-only (is-season-ready (system-id uint) (season (string-ascii 20)))
  (match (map-get? seasonal-systems { system-id: system-id })
    system-data
    (if (is-eq season "winter")
      (get winter-ready system-data)
      (if (is-eq season "summer")
        (get summer-ready system-data)
        false
      )
    )
    false
  )
)

(define-read-only (get-preparation-status (system-id uint))
  (match (map-get? seasonal-systems { system-id: system-id })
    system-data
    {
      winter-ready: (get winter-ready system-data),
      summer-ready: (get summer-ready system-data),
      last-winter-prep: (get last-winter-prep system-data),
      last-summer-prep: (get last-summer-prep system-data),
      prep-history-count: (get prep-history-count system-data)
    }
    {
      winter-ready: false,
      summer-ready: false,
      last-winter-prep: u0,
      last-summer-prep: u0,
      prep-history-count: u0
    }
  )
)

(define-read-only (needs-seasonal-preparation (system-id uint))
  (let ((current-season-var (var-get current-season)))
    (match (map-get? seasonal-systems { system-id: system-id })
      system-data
      (if (is-eq current-season-var "winter")
        (not (get winter-ready system-data))
        (if (is-eq current-season-var "summer")
          (not (get summer-ready system-data))
          true
        )
      )
      true
    )
  )
)
