;; Gym Membership Guilt Accumulation Calculator
;; Computes the mounting psychological weight of unused January fitness commitments by December

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u200))
(define-constant ERR_MEMBERSHIP_NOT_FOUND (err u201))
(define-constant ERR_INVALID_DATA (err u202))
(define-constant ERR_ALREADY_EXISTS (err u203))
(define-constant ERR_MEMBERSHIP_EXPIRED (err u204))
(define-constant SECONDS_IN_DAY u86400)
(define-constant DAYS_IN_MONTH u30)
(define-constant GUILT_MULTIPLIER u10)
(define-constant MAX_GUILT_SCORE u10000)

;; Data Variables
(define-data-var membership-counter uint u0)
(define-data-var total-memberships uint u0)
(define-data-var total-visits uint u0)
(define-data-var total-guilt-accumulated uint u0)

;; Data Maps
(define-map gym-memberships
  { membership-id: uint }
  {
    member: principal,
    gym-name: (string-ascii 100),
    membership-type: (string-ascii 50),
    monthly-fee: uint,
    start-date: uint,
    end-date: uint,
    total-visits: uint,
    last-visit: (optional uint),
    guilt-score: uint,
    is-active: bool,
    new-year-commitment: bool
  }
)

(define-map gym-visits
  { membership-id: uint, visit-id: uint }
  {
    visit-date: uint,
    duration-minutes: uint,
    workout-type: (string-ascii 100),
    intensity-level: uint,
    satisfaction-rating: uint
  }
)

(define-map member-stats
  { member: principal }
  {
    membership-ids: (list 20 uint),
    total-memberships: uint,
    total-fees-paid: uint,
    total-visits: uint,
    average-guilt-score: uint,
    january-commitments: uint,
    commitment-success-rate: uint
  }
)

(define-map guilt-analysis
  { membership-id: uint }
  {
    days-since-last-visit: uint,
    money-wasted: uint,
    psychological-pressure: uint,
    regret-level: uint,
    excuses-made: (list 10 (string-ascii 100))
  }
)

(define-map monthly-usage
  { membership-id: uint, month: uint }
  {
    visits-count: uint,
    total-duration: uint,
    monthly-guilt: uint,
    usage-percentage: uint
  }
)

;; Private Functions
(define-private (calculate-guilt-score (membership-id uint))
  (match (map-get? gym-memberships { membership-id: membership-id })
    membership (let (
      (current-time stacks-block-height)
      (start-date (get start-date membership))
      (days-active (/ (- current-time start-date) SECONDS_IN_DAY))
      (member-visits (get total-visits membership))
      (expected-visits (/ days-active u3))
      (visit-deficit (if (> expected-visits member-visits) (- expected-visits member-visits) u0))
      (guilt-base (* visit-deficit GUILT_MULTIPLIER))
      (monthly-fee (get monthly-fee membership))
      (money-guilt (/ (* monthly-fee visit-deficit) u10))
    )
      (if (> (+ guilt-base money-guilt) MAX_GUILT_SCORE)
        MAX_GUILT_SCORE
        (+ guilt-base money-guilt)
      )
    )
    u0
  )
)

(define-private (calculate-money-wasted (membership-id uint))
  (match (map-get? gym-memberships { membership-id: membership-id })
    membership (let (
      (current-time stacks-block-height)
      (start-date (get start-date membership))
      (months-active (/ (/ (- current-time start-date) SECONDS_IN_DAY) DAYS_IN_MONTH))
      (monthly-fee (get monthly-fee membership))
      (total-paid (* months-active monthly-fee))
      (member-visits (get total-visits membership))
      (cost-per-visit (if (> member-visits u0) (/ total-paid member-visits) total-paid))
    )
      {
        total-paid: total-paid,
        cost-per-visit: cost-per-visit,
        wasted-amount: (if (< member-visits u5) (/ (* total-paid u80) u100) u0)
      }
    )
    { total-paid: u0, cost-per-visit: u0, wasted-amount: u0 }
  )
)

(define-private (determine-regret-level (guilt-score uint))
  (if (<= guilt-score u100) 
    "mild-disappointment"
    (if (<= guilt-score u500) 
      "moderate-regret"
      (if (<= guilt-score u1000) 
        "significant-shame"
        (if (<= guilt-score u3000) 
          "crushing-guilt"
          (if (<= guilt-score u5000) 
            "existential-crisis"
            "complete-self-loathing"
          )
        )
      )
    )
  )
)

(define-private (update-member-stats (member principal) (membership-id uint) (monthly-fee uint))
  (let (
    (current-data (default-to 
      { membership-ids: (list), total-memberships: u0, total-fees-paid: u0, 
        total-visits: u0, average-guilt-score: u0, january-commitments: u0, commitment-success-rate: u0 }
      (map-get? member-stats { member: member })
    ))
    (updated-ids (unwrap! (as-max-len? 
      (append (get membership-ids current-data) membership-id) u20) (err ERR_INVALID_DATA)))
    (new-memberships (+ (get total-memberships current-data) u1))
    (new-fees-paid (+ (get total-fees-paid current-data) monthly-fee))
  )
    (map-set member-stats 
      { member: member }
      {
        membership-ids: updated-ids,
        total-memberships: new-memberships,
        total-fees-paid: new-fees-paid,
        total-visits: (get total-visits current-data),
        average-guilt-score: (get average-guilt-score current-data),
        january-commitments: (get january-commitments current-data),
        commitment-success-rate: (get commitment-success-rate current-data)
      }
    )
    (ok true)
  )
)

;; Public Functions

;; Register new gym membership
(define-public (register-membership
  (gym-name (string-ascii 100))
  (membership-type (string-ascii 50))
  (monthly-fee uint)
  (end-date uint)
  (is-new-year-commitment bool)
)
  (let (
    (membership-id (+ (var-get membership-counter) u1))
    (current-time stacks-block-height)
  )
    (asserts! (> (len gym-name) u0) ERR_INVALID_DATA)
    (asserts! (> end-date current-time) ERR_INVALID_DATA)
    (asserts! (> monthly-fee u0) ERR_INVALID_DATA)
    
    (map-set gym-memberships
      { membership-id: membership-id }
      {
        member: tx-sender,
        gym-name: gym-name,
        membership-type: membership-type,
        monthly-fee: monthly-fee,
        start-date: current-time,
        end-date: end-date,
        total-visits: u0,
        last-visit: none,
        guilt-score: u0,
        is-active: true,
        new-year-commitment: is-new-year-commitment
      }
    )
    
    (var-set membership-counter membership-id)
    (var-set total-memberships (+ (var-get total-memberships) u1))
    (unwrap! (update-member-stats tx-sender membership-id monthly-fee) ERR_INVALID_DATA)
    
    (ok membership-id)
  )
)

;; Record gym visit
(define-public (record-visit
  (membership-id uint)
  (duration-minutes uint)
  (workout-type (string-ascii 100))
  (intensity-level uint)
  (satisfaction-rating uint)
)
  (let (
    (membership (unwrap! (map-get? gym-memberships { membership-id: membership-id }) ERR_MEMBERSHIP_NOT_FOUND))
    (current-time stacks-block-height)
    (visit-id (+ (get total-visits membership) u1))
  )
    (asserts! (is-eq (get member membership) tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (get is-active membership) ERR_MEMBERSHIP_EXPIRED)
    (asserts! (<= intensity-level u10) ERR_INVALID_DATA)
    (asserts! (<= satisfaction-rating u10) ERR_INVALID_DATA)
    
    (map-set gym-visits
      { membership-id: membership-id, visit-id: visit-id }
      {
        visit-date: current-time,
        duration-minutes: duration-minutes,
        workout-type: workout-type,
        intensity-level: intensity-level,
        satisfaction-rating: satisfaction-rating
      }
    )
    
    (map-set gym-memberships
      { membership-id: membership-id }
      (merge membership {
        total-visits: visit-id,
        last-visit: (some current-time)
      })
    )
    
    (var-set total-visits (+ (var-get total-visits) u1))
    
    (ok visit-id)
  )
)

;; Calculate current guilt analysis
(define-public (calculate-guilt-analysis (membership-id uint))
  (let (
    (membership (unwrap! (map-get? gym-memberships { membership-id: membership-id }) ERR_MEMBERSHIP_NOT_FOUND))
    (current-time stacks-block-height)
    (last-visit (default-to (get start-date membership) (get last-visit membership)))
    (days-since-visit (/ (- current-time last-visit) SECONDS_IN_DAY))
    (guilt-score (calculate-guilt-score membership-id))
    (money-data (calculate-money-wasted membership-id))
    (regret-level (determine-regret-level guilt-score))
    (psychological-pressure (* days-since-visit u5))
  )
    (asserts! (is-eq (get member membership) tx-sender) ERR_NOT_AUTHORIZED)
    
    (map-set guilt-analysis
      { membership-id: membership-id }
      {
        days-since-last-visit: days-since-visit,
        money-wasted: (get wasted-amount money-data),
        psychological-pressure: psychological-pressure,
        regret-level: guilt-score,
        excuses-made: (list "too-busy" "will-go-tomorrow" "gym-too-crowded")
      }
    )
    
    (map-set gym-memberships
      { membership-id: membership-id }
      (merge membership {
        guilt-score: guilt-score
      })
    )
    
    (var-set total-guilt-accumulated (+ (var-get total-guilt-accumulated) guilt-score))
    
    (ok {
      guilt-score: guilt-score,
      regret-category: regret-level,
      money-wasted: (get wasted-amount money-data),
      days-since-visit: days-since-visit
    })
  )
)

;; Cancel membership (guilt-inducing action)
(define-public (cancel-membership (membership-id uint) (cancellation-reason (string-ascii 200)))
  (let (
    (membership (unwrap! (map-get? gym-memberships { membership-id: membership-id }) ERR_MEMBERSHIP_NOT_FOUND))
    (final-guilt (calculate-guilt-score membership-id))
  )
    (asserts! (is-eq (get member membership) tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (get is-active membership) ERR_MEMBERSHIP_EXPIRED)
    
    (map-set gym-memberships
      { membership-id: membership-id }
      (merge membership {
        is-active: false,
        guilt-score: final-guilt
      })
    )
    
    (ok {
      final-guilt-score: final-guilt,
      membership-cancelled: true,
      regret-level: (determine-regret-level final-guilt)
    })
  )
)

;; Read-only functions

(define-read-only (get-membership (membership-id uint))
  (map-get? gym-memberships { membership-id: membership-id })
)

(define-read-only (get-guilt-analysis (membership-id uint))
  (map-get? guilt-analysis { membership-id: membership-id })
)

(define-read-only (get-member-stats (member principal))
  (map-get? member-stats { member: member })
)

(define-read-only (get-visit (membership-id uint) (visit-id uint))
  (map-get? gym-visits { membership-id: membership-id, visit-id: visit-id })
)

(define-read-only (get-global-gym-stats)
  {
    total-memberships: (var-get total-memberships),
    total-visits: (var-get total-visits),
    total-guilt-accumulated: (var-get total-guilt-accumulated),
    average-visits-per-membership: (if (> (var-get total-memberships) u0)
      (/ (var-get total-visits) (var-get total-memberships))
      u0
    )
  }
)

(define-read-only (calculate-shame-level (membership-id uint))
  (let (
    (membership (unwrap! (map-get? gym-memberships { membership-id: membership-id }) (err "not-found")))
    (guilt-score (get guilt-score membership))
  )
    (ok (determine-regret-level guilt-score))
  )
)
