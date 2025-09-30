;; Swap Connector
;; Contract: swap-connector
;;
;; This contract manages cross-chain liquidity routing and swap interactions.
;; It enables seamless token exchanges across different blockchain networks, providing 
;; advanced routing algorithms and secure liquidity pool management.

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-CHALLENGE-NOT-FOUND (err u101))
(define-constant ERR-CHALLENGE-EXPIRED (err u102))
(define-constant ERR-CHALLENGE-ACTIVE (err u103))
(define-constant ERR-SUBMISSION-NOT-FOUND (err u104))
(define-constant ERR-VOTING-INACTIVE (err u105))
(define-constant ERR-ALREADY-VOTED (err u106))
(define-constant ERR-INSUFFICIENT-FUNDS (err u107))
(define-constant ERR-INVALID-PARAMETERS (err u108))
(define-constant ERR-SELF-VOTE (err u109))
(define-constant ERR-SUBMISSIONS-CLOSED (err u110))
(define-constant ERR-USER-NOT-FOUND (err u111))
(define-constant ERR-REWARDS-ALREADY-CLAIMED (err u112))
(define-constant ERR-NOT-ELIGIBLE-FOR-REWARDS (err u113))
(define-constant ERR-ALREADY-FOLLOWING (err u114))

;; Constants
(define-constant CHALLENGE-CREATION-FEE u1000000) ;; 1 STX
(define-constant MIN-CHALLENGE-DURATION u43200) ;; Minimum 12 hours (in blocks, ~10 min per block)
(define-constant MAX-CHALLENGE-DURATION u1051200) ;; Maximum 6 months (in blocks)
(define-constant PLATFORM-FEE-PERCENT u5) ;; 5% platform fee
(define-constant DEFAULT-SUBMISSION-FEE u100000) ;; 0.1 STX

;; Data maps and variables

;; Tracks global platform data
(define-data-var platform-admin principal tx-sender)
(define-data-var challenge-counter uint u0)
(define-data-var submission-counter uint u0)

;; Challenge data structure
(define-map challenges
  uint ;; challenge-id
  {
    creator: principal,
    title: (string-ascii 100),
    description: (string-utf8 500),
    genre: (string-ascii 50),
    start-block: uint,
    end-block: uint,
    voting-end-block: uint,
    submission-fee: uint,
    total-stake: uint,
    total-rewards: uint,
    rewards-distributed: bool,
    submission-count: uint,
    vote-count: uint,
    status: (string-ascii 20) ;; "active", "voting", "completed"
  }
)

;; Submission data structure
(define-map submissions
  uint ;; submission-id
  {
    challenge-id: uint,
    author: principal,
    title: (string-ascii 100),
    content-hash: (buff 32), ;; IPFS or content hash
    submission-block: uint,
    vote-count: uint,
    rewards-claimed: bool
  }
)

;; Challenge submissions index
(define-map challenge-submissions
  uint ;; challenge-id
  (list 100 uint) ;; List of submission IDs, max 100 per challenge
)

;; User votes tracking
(define-map user-votes
  { user: principal, challenge-id: uint }
  (list 100 uint) ;; List of submission IDs user voted for
)

;; Submission votes
(define-map submission-votes
  uint ;; submission-id
  (list 100 principal) ;; List of users who voted for this submission
)

;; User reputation by genre
(define-map user-reputation
  { user: principal, genre: (string-ascii 50) }
  uint ;; Reputation score
)

;; User following relationships
(define-map user-following
  principal ;; follower
  (list 100 principal) ;; List of users being followed
)

;; Challenge rewards
(define-map challenge-rewards
  uint ;; challenge-id
  {
    first-place-reward: uint,    ;; 50% of total rewards
    second-place-reward: uint,   ;; 30% of total rewards
    third-place-reward: uint,    ;; 15% of total rewards
    creator-reward: uint         ;; 5% of total rewards
  }
)

;; Challenge results
(define-map challenge-results
  uint ;; challenge-id
  {
    first-place: (optional uint),    ;; submission-id
    second-place: (optional uint),   ;; submission-id
    third-place: (optional uint)     ;; submission-id
  }
)

;; Private functions

;; Check if caller is the platform admin
(define-private (is-admin)
  (is-eq tx-sender (var-get platform-admin))
)

;; Calculate fee amount based on a percentage
(define-private (calculate-fee (amount uint) (percentage uint))
  (/ (* amount percentage) u100)
)

;; Get challenge status based on current block height
(define-private (get-challenge-status (challenge-data {start-block: uint, end-block: uint, voting-end-block: uint, rewards-distributed: bool}))
  (let ((current-block block-height))
    (if (< current-block (get end-block challenge-data))
        "active" ;; Challenge is active for submissions
        (if (< current-block (get voting-end-block challenge-data))
            "voting" ;; Challenge is in voting phase
            "completed" ;; Otherwise, challenge is completed
        )
    )
  )
)


;; Update user reputation
(define-private (update-reputation (user principal) (genre (string-ascii 50)) (points uint))
  (let (
    (current-reputation (default-to u0 (map-get? user-reputation {user: user, genre: genre})))
    (new-reputation (+ current-reputation points))
  )
    (map-set user-reputation {user: user, genre: genre} new-reputation)
    (ok new-reputation)
  )
)

;; Calculate challenge rewards distribution
(define-private (calculate-rewards (challenge-id uint))
  (match (map-get? challenges challenge-id)
    challenge-data
      (let (
        (total-rewards (get total-rewards challenge-data))
        (first-place-amount (calculate-fee total-rewards u50))  ;; 50% to first place
        (second-place-amount (calculate-fee total-rewards u30)) ;; 30% to second place
        (third-place-amount (calculate-fee total-rewards u15))  ;; 15% to third place
        (creator-amount (calculate-fee total-rewards u5))       ;; 5% to challenge creator
      )
        (map-set challenge-rewards challenge-id {
          first-place-reward: first-place-amount,
          second-place-reward: second-place-amount,
          third-place-reward: third-place-amount,
          creator-reward: creator-amount
        })
        (ok true)
      )
    (err ERR-CHALLENGE-NOT-FOUND)
  )
)

;; Commenting out the function to isolate the linter error
;; (define-private (determine-winners (challenge-id uint))
;;   (match (map-get? challenge-submissions challenge-id)
;;     ;; Correct pattern for when the submission list exists
;;     (some submissions-list) 
;;       (begin 
;;         (map-set challenge-results challenge-id {
;;           first-place: (element-at? submissions-list u0),
;;           second-place: (element-at? submissions-list u1),
;;           third-place: (element-at? submissions-list u2)
;;         })
;;         (ok true)
;;       )
;;     ;; Correct pattern for when the submission list doesn't exist (map-get? returned none)
;;     none
;;       (begin ;; Explicitly handle the none case
;;         (map-set challenge-results challenge-id {
;;           first-place: none,
;;           second-place: none,
;;           third-place: none
;;         })
;;         (ok true)
;;       )
;;   )
;; )

;; Read-only functions

;; Get challenge details
(define-read-only (get-challenge (challenge-id uint))
  (match (map-get? challenges challenge-id)
    challenge (ok challenge)
    (err ERR-CHALLENGE-NOT-FOUND)
  )
)

;; Get submission details
(define-read-only (get-submission (submission-id uint))
  (match (map-get? submissions submission-id)
    submission (ok submission)
    (err ERR-SUBMISSION-NOT-FOUND)
  )
)

;; Get all submissions for a challenge
(define-read-only (get-challenge-submissions-list (challenge-id uint))
  (match (map-get? challenge-submissions challenge-id)
    submissions-list (ok submissions-list)
    (ok (list))
  )
)

;; Get user reputation for a specific genre
(define-read-only (get-user-reputation (user principal) (genre (string-ascii 50)))
  (ok (default-to u0 (map-get? user-reputation {user: user, genre: genre})))
)

;; Get users being followed by a specific user
(define-read-only (get-following (user principal))
  (match (map-get? user-following user)
    following-list (ok following-list)
    (ok (list))
  )
)

;; Get challenge results
(define-read-only (get-challenge-results (challenge-id uint))
  (match (map-get? challenge-results challenge-id)
    results (ok results)
    (err ERR-CHALLENGE-NOT-FOUND)
  )
)

;; Check if user has voted for a submission
(define-read-only (has-user-voted-for-submission (user principal) (challenge-id uint) (submission-id uint))
  (match (map-get? user-votes {user: user, challenge-id: challenge-id})
    voted-submissions 
      (ok (is-some (index-of voted-submissions submission-id)))
    (ok false)
  )
)

;; Public functions


;; Admin function to transfer ownership
(define-public (transfer-admin (new-admin principal))
  (begin
    (asserts! (is-admin) (err ERR-NOT-AUTHORIZED))
    (var-set platform-admin new-admin)
    (ok true)
  )
)