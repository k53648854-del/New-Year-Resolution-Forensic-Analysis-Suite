;; Resolution Autopsy Timeline Reconstructor
;; Pinpoints the exact moment when 'this year will be different' 
;; transformed into 'maybe next year will be different'

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_RESOLUTION_NOT_FOUND (err u101))
(define-constant ERR_INVALID_DATA (err u102))
(define-constant ERR_ALREADY_FAILED (err u103))
(define-constant MAX_DESCRIPTION_LENGTH u500)
(define-constant SECONDS_IN_DAY u86400)

;; Data Variables
(define-data-var resolution-counter uint u0)
(define-data-var total-resolutions uint u0)
(define-data-var failed-resolutions uint u0)

;; Data Maps
(define-map resolutions
  { resolution-id: uint }
  {
    creator: principal,
    description: (string-ascii 500),
    category: (string-ascii 100),
    created-at: uint,
    target-date: uint,
    failed-at: (optional uint),
    failure-reason: (optional (string-ascii 300)),
    milestone-count: uint,
    last-check-in: uint,
    confidence-level: uint,
    is-active: bool
  }
)

(define-map milestones
  { resolution-id: uint, milestone-id: uint }
  {
    description: (string-ascii 200),
    target-date: uint,
    completed-at: (optional uint),
    is-completed: bool
  }
)

(define-map user-resolutions
  { user: principal }
  {
    resolution-ids: (list 50 uint),
    total-created: uint,
    total-failed: uint,
    success-rate: uint
  }
)

(define-map resolution-timeline
  { resolution-id: uint }
  {
    creation-block: uint,
    failure-block: (optional uint),
    days-survived: uint,
    failure-pattern: (optional (string-ascii 100))
  }
)

;; Private Functions
(define-private (is-valid-description (desc (string-ascii 500)))
  (and 
    (> (len desc) u0)
    (<= (len desc) MAX_DESCRIPTION_LENGTH)
  )
)

(define-private (calculate-days-survived (created-at uint) (failed-at uint))
  (/ (- failed-at created-at) SECONDS_IN_DAY)
)

(define-private (determine-failure-pattern (days-survived uint))
  (if (<= days-survived u3) 
    "immediate-abandonment"
    (if (<= days-survived u7) 
      "week-one-dropout"
      (if (<= days-survived u30) 
        "january-fade"
        (if (<= days-survived u60) 
          "february-failure"
          (if (<= days-survived u90) 
            "quarter-one-quit"
            "long-term-decline"
          )
        )
      )
    )
  )
)

(define-private (update-user-stats (user principal) (resolution-id uint) (is-failure bool))
  (let (
    (current-data (default-to 
      { resolution-ids: (list), total-created: u0, total-failed: u0, success-rate: u0 }
      (map-get? user-resolutions { user: user })
    ))
    (updated-ids (unwrap! (as-max-len? 
      (append (get resolution-ids current-data) resolution-id) u50) (err ERR_INVALID_DATA)))
    (new-created (+ (get total-created current-data) u1))
    (new-failed (if is-failure (+ (get total-failed current-data) u1) (get total-failed current-data)))
    (new-success-rate (if (> new-created u0) 
      (* (/ (- new-created new-failed) new-created) u100) u0))
  )
    (map-set user-resolutions 
      { user: user }
      {
        resolution-ids: updated-ids,
        total-created: new-created,
        total-failed: new-failed,
        success-rate: new-success-rate
      }
    )
    (ok true)
  )
)

;; Public Functions

;; Create a new resolution
(define-public (create-resolution 
  (description (string-ascii 500))
  (category (string-ascii 100))
  (target-date uint)
  (confidence-level uint)
)
  (let (
    (resolution-id (+ (var-get resolution-counter) u1))
    (current-time stacks-block-height)
  )
    (asserts! (is-valid-description description) ERR_INVALID_DATA)
    (asserts! (> target-date current-time) ERR_INVALID_DATA)
    (asserts! (<= confidence-level u100) ERR_INVALID_DATA)
    
    (map-set resolutions
      { resolution-id: resolution-id }
      {
        creator: tx-sender,
        description: description,
        category: category,
        created-at: current-time,
        target-date: target-date,
        failed-at: none,
        failure-reason: none,
        milestone-count: u0,
        last-check-in: current-time,
        confidence-level: confidence-level,
        is-active: true
      }
    )
    
    (map-set resolution-timeline
      { resolution-id: resolution-id }
      {
        creation-block: stacks-block-height,
        failure-block: none,
        days-survived: u0,
        failure-pattern: none
      }
    )
    
    (var-set resolution-counter resolution-id)
    (var-set total-resolutions (+ (var-get total-resolutions) u1))
    (unwrap! (update-user-stats tx-sender resolution-id false) ERR_INVALID_DATA)
    
    (ok resolution-id)
  )
)

;; Record resolution failure with forensic details
(define-public (record-failure 
  (resolution-id uint)
  (failure-reason (string-ascii 300))
)
  (let (
    (resolution (unwrap! (map-get? resolutions { resolution-id: resolution-id }) ERR_RESOLUTION_NOT_FOUND))
    (current-time stacks-block-height)
    (created-at (get created-at resolution))
    (days-survived (calculate-days-survived created-at current-time))
    (failure-pattern (determine-failure-pattern days-survived))
  )
    (asserts! (is-eq (get creator resolution) tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (get is-active resolution) ERR_ALREADY_FAILED)
    
    (map-set resolutions
      { resolution-id: resolution-id }
      (merge resolution {
        failed-at: (some current-time),
        failure-reason: (some failure-reason),
        last-check-in: current-time,
        is-active: false
      })
    )
    
    (map-set resolution-timeline
      { resolution-id: resolution-id }
      {
        creation-block: (get creation-block (unwrap! 
          (map-get? resolution-timeline { resolution-id: resolution-id }) ERR_RESOLUTION_NOT_FOUND)),
        failure-block: (some stacks-block-height),
        days-survived: days-survived,
        failure-pattern: (some failure-pattern)
      }
    )
    
    (var-set failed-resolutions (+ (var-get failed-resolutions) u1))
    (unwrap! (update-user-stats tx-sender resolution-id true) ERR_INVALID_DATA)
    
    (ok true)
  )
)

;; Add milestone to resolution
(define-public (add-milestone
  (resolution-id uint)
  (milestone-description (string-ascii 200))
  (milestone-target-date uint)
)
  (let (
    (resolution (unwrap! (map-get? resolutions { resolution-id: resolution-id }) ERR_RESOLUTION_NOT_FOUND))
    (milestone-id (+ (get milestone-count resolution) u1))
  )
    (asserts! (is-eq (get creator resolution) tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (get is-active resolution) ERR_ALREADY_FAILED)
    (asserts! (> (len milestone-description) u0) ERR_INVALID_DATA)
    
    (map-set milestones
      { resolution-id: resolution-id, milestone-id: milestone-id }
      {
        description: milestone-description,
        target-date: milestone-target-date,
        completed-at: none,
        is-completed: false
      }
    )
    
    (map-set resolutions
      { resolution-id: resolution-id }
      (merge resolution {
        milestone-count: milestone-id
      })
    )
    
    (ok milestone-id)
  )
)

;; Complete milestone
(define-public (complete-milestone
  (resolution-id uint)
  (milestone-id uint)
)
  (let (
    (resolution (unwrap! (map-get? resolutions { resolution-id: resolution-id }) ERR_RESOLUTION_NOT_FOUND))
    (milestone (unwrap! (map-get? milestones { resolution-id: resolution-id, milestone-id: milestone-id }) ERR_RESOLUTION_NOT_FOUND))
    (current-time stacks-block-height)
  )
    (asserts! (is-eq (get creator resolution) tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (get is-active resolution) ERR_ALREADY_FAILED)
    (asserts! (not (get is-completed milestone)) ERR_INVALID_DATA)
    
    (map-set milestones
      { resolution-id: resolution-id, milestone-id: milestone-id }
      (merge milestone {
        completed-at: (some current-time),
        is-completed: true
      })
    )
    
    (map-set resolutions
      { resolution-id: resolution-id }
      (merge resolution {
        last-check-in: current-time
      })
    )
    
    (ok true)
  )
)

;; Read-only functions

(define-read-only (get-resolution (resolution-id uint))
  (map-get? resolutions { resolution-id: resolution-id })
)

(define-read-only (get-resolution-timeline (resolution-id uint))
  (map-get? resolution-timeline { resolution-id: resolution-id })
)

(define-read-only (get-user-stats (user principal))
  (map-get? user-resolutions { user: user })
)

(define-read-only (get-global-stats)
  {
    total-resolutions: (var-get total-resolutions),
    failed-resolutions: (var-get failed-resolutions),
    failure-rate: (if (> (var-get total-resolutions) u0)
      (* (/ (var-get failed-resolutions) (var-get total-resolutions)) u100)
      u0
    )
  }
)

(define-read-only (get-milestone (resolution-id uint) (milestone-id uint))
  (map-get? milestones { resolution-id: resolution-id, milestone-id: milestone-id })
)
