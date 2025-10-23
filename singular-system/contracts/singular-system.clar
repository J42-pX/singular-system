;; SingularSystem - Liquid Democracy DAO Governance
;; A modular governance system with expertise-based delegation and dynamic voting

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-already-voted (err u103))
(define-constant err-proposal-closed (err u104))
(define-constant err-invalid-delegation (err u105))
(define-constant err-circular-delegation (err u106))
(define-constant err-invalid-expertise (err u107))

;; Data Variables
(define-data-var proposal-count uint u0)
(define-data-var min-voting-period uint u1440) ;; ~10 days in blocks

;; Expertise Domains
(define-constant DOMAIN-TECHNICAL u1)
(define-constant DOMAIN-FINANCIAL u2)
(define-constant DOMAIN-GOVERNANCE u3)
(define-constant DOMAIN-COMMUNITY u4)
(define-constant DOMAIN-OPERATIONS u5)

;; Data Maps

;; Member reputation scores by expertise domain
(define-map member-reputation
    { member: principal, domain: uint }
    { score: uint, last-updated: uint }
)

;; Delegation relationships: delegator -> delegate by domain
(define-map delegations
    { delegator: principal, domain: uint }
    { delegate: principal, delegated-at: uint, active: bool }
)

;; Proposals
(define-map proposals
    { proposal-id: uint }
    {
        proposer: principal,
        title: (string-ascii 256),
        description: (string-ascii 1024),
        domain: uint,
        start-block: uint,
        end-block: uint,
        votes-for: uint,
        votes-against: uint,
        executed: bool,
        passed: bool
    }
)

;; Vote records
(define-map votes
    { proposal-id: uint, voter: principal }
    { 
        vote-for: bool, 
        voting-power: uint,
        voted-at: uint,
        is-delegated: bool
    }
)

;; Member voting power (base power from tokens/participation)
(define-map member-power
    { member: principal }
    { power: uint, last-activity: uint }
)

;; Read-only functions

(define-read-only (get-proposal (proposal-id uint))
    (map-get? proposals { proposal-id: proposal-id })
)

(define-read-only (get-member-reputation (member principal) (domain uint))
    (default-to 
        { score: u0, last-updated: u0 }
        (map-get? member-reputation { member: member, domain: domain })
    )
)

(define-read-only (get-delegation (delegator principal) (domain uint))
    (map-get? delegations { delegator: delegator, domain: domain })
)

(define-read-only (get-member-power (member principal))
    (default-to 
        { power: u1, last-activity: u0 }
        (map-get? member-power { member: member })
    )
)

(define-read-only (get-vote (proposal-id uint) (voter principal))
    (map-get? votes { proposal-id: proposal-id, voter: voter })
)

(define-read-only (get-proposal-count)
    (var-get proposal-count)
)

;; Read-only helper to check if a delegation would create a direct circular reference
;; This only checks one level to avoid circular dependency issues
(define-read-only (would-create-circular-delegation (delegator principal) (delegate principal) (domain uint))
    (match (map-get? delegations { delegator: delegate, domain: domain })
        delegation-info
            (and (get active delegation-info) (is-eq (get delegate delegation-info) delegator))
        false
    )
)

(define-read-only (calculate-voting-power (member principal) (domain uint))
    (let
        (
            (base-power (get power (get-member-power member)))
            (reputation (get score (get-member-reputation member domain)))
        )
        ;; Combine base power with domain expertise (weighted average)
        (/ (+ (* base-power u70) (* reputation u30)) u100)
    )
)

;; Public functions

;; Initialize or update member power
(define-public (register-member (initial-power uint))
    (begin
        (asserts! (> initial-power u0) (err u108))
        (ok (map-set member-power
            { member: tx-sender }
            { power: initial-power, last-activity: block-height }
        ))
    )
)

;; Update reputation score (would be called by oracle in production)
(define-public (update-reputation (member principal) (domain uint) (new-score uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (<= domain DOMAIN-OPERATIONS) err-invalid-expertise)
        (ok (map-set member-reputation
            { member: member, domain: domain }
            { score: new-score, last-updated: block-height }
        ))
    )
)

;; Delegate voting power to another member for specific domain
(define-public (delegate-vote (delegate principal) (domain uint))
    (let
        (
            ;; Check if delegate has delegated back to us (one level check)
            (delegate-info (map-get? delegations { delegator: delegate, domain: domain }))
            (has-circular (match delegate-info
                info (and (get active info) (is-eq (get delegate info) tx-sender))
                false
            ))
        )
        (asserts! (not (is-eq tx-sender delegate)) err-invalid-delegation)
        (asserts! (<= domain DOMAIN-OPERATIONS) err-invalid-expertise)
        (asserts! (not has-circular) err-circular-delegation)
        
        (ok (map-set delegations
            { delegator: tx-sender, domain: domain }
            { 
                delegate: delegate, 
                delegated-at: block-height,
                active: true 
            }
        ))
    )
)

;; Revoke delegation for a specific domain
(define-public (revoke-delegation (domain uint))
    (begin
        (asserts! (<= domain DOMAIN-OPERATIONS) err-invalid-expertise)
        (match (get-delegation tx-sender domain)
            delegation-info
                (ok (map-set delegations
                    { delegator: tx-sender, domain: domain }
                    (merge delegation-info { active: false })
                ))
            err-not-found
        )
    )
)

;; Create a new proposal
(define-public (create-proposal 
    (title (string-ascii 256))
    (description (string-ascii 1024))
    (domain uint)
    (voting-period uint))
    (let
        (
            (new-proposal-id (+ (var-get proposal-count) u1))
            (end-block (+ block-height voting-period))
        )
        (asserts! (<= domain DOMAIN-OPERATIONS) err-invalid-expertise)
        (asserts! (>= voting-period (var-get min-voting-period)) (err u109))
        
        (map-set proposals
            { proposal-id: new-proposal-id }
            {
                proposer: tx-sender,
                title: title,
                description: description,
                domain: domain,
                start-block: block-height,
                end-block: end-block,
                votes-for: u0,
                votes-against: u0,
                executed: false,
                passed: false
            }
        )
        (var-set proposal-count new-proposal-id)
        (ok new-proposal-id)
    )
)

;; Vote on a proposal (direct vote or as delegate)
(define-public (vote (proposal-id uint) (vote-for bool))
    (let
        (
            (proposal (unwrap! (get-proposal proposal-id) err-not-found))
            (voter-power (calculate-voting-power tx-sender (get domain proposal)))
        )
        ;; Check proposal is active
        (asserts! (< block-height (get end-block proposal)) err-proposal-closed)
        (asserts! (>= block-height (get start-block proposal)) err-proposal-closed)
        
        ;; Check hasn't voted already
        (asserts! (is-none (get-vote proposal-id tx-sender)) err-already-voted)
        
        ;; Record vote
        (map-set votes
            { proposal-id: proposal-id, voter: tx-sender }
            { 
                vote-for: vote-for, 
                voting-power: voter-power,
                voted-at: block-height,
                is-delegated: false
            }
        )
        
        ;; Update proposal vote counts
        (if vote-for
            (map-set proposals
                { proposal-id: proposal-id }
                (merge proposal { 
                    votes-for: (+ (get votes-for proposal) voter-power) 
                })
            )
            (map-set proposals
                { proposal-id: proposal-id }
                (merge proposal { 
                    votes-against: (+ (get votes-against proposal) voter-power) 
                })
            )
        )
        
        (ok true)
    )
)

;; Execute proposal (after voting period ends)
(define-public (finalize-proposal (proposal-id uint))
    (let
        (
            (proposal (unwrap! (get-proposal proposal-id) err-not-found))
        )
        (asserts! (>= block-height (get end-block proposal)) (err u110))
        (asserts! (not (get executed proposal)) (err u111))
        
        (let
            (
                (passed (> (get votes-for proposal) (get votes-against proposal)))
            )
            (map-set proposals
                { proposal-id: proposal-id }
                (merge proposal { 
                    executed: true,
                    passed: passed
                })
            )
            (ok passed)
        )
    )
)

;; Admin function to update minimum voting period
(define-public (set-min-voting-period (new-period uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set min-voting-period new-period)
        (ok true)
    )
)
