(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-active (err u101))
(define-constant err-already-active (err u102))
(define-constant err-amount-too-small (err u103))
(define-constant err-deadline-passed (err u104))
(define-constant err-target-not-reached (err u105))
(define-constant err-already-claimed (err u106))
(define-constant err-no-contribution (err u107))
(define-constant err-not-deadline (err u108))
(define-constant err-milestone-not-found (err u109))
(define-constant err-milestone-already-approved (err u110))
(define-constant err-milestone-not-approved (err u111))
(define-constant err-insufficient-votes (err u112))
(define-constant err-extension-already-requested (err u113))
(define-constant err-extension-limit-reached (err u114))
(define-constant err-insufficient-momentum (err u115))
(define-constant err-extension-not-found (err u116))
(define-constant err-insufficient-tier (err u117))
(define-constant err-invalid-analytics-id (err u118))
(define-constant err-analytics-not-found (err u119))

(define-data-var campaign-active bool false)
(define-data-var campaign-deadline uint u0)
(define-data-var campaign-target uint u0)
(define-data-var total-raised uint u0)
(define-data-var beneficiary principal contract-owner)
(define-data-var milestone-count uint u0)
(define-data-var required-approval-percentage uint u60)
(define-data-var extension-count uint u0)
(define-data-var max-extensions uint u3)
(define-data-var extension-duration uint u144)
(define-data-var minimum-momentum-threshold uint u25)
(define-data-var bronze-tier-threshold uint u1000000)
(define-data-var silver-tier-threshold uint u5000000)
(define-data-var gold-tier-threshold uint u10000000)
(define-data-var platinum-tier-threshold uint u25000000)
(define-data-var analytics-snapshot-count uint u0)
(define-data-var total-unique-contributors uint u0)

(define-map milestones
    uint
    {
        description: (string-ascii 256),
        amount: uint,
        approved: bool,
        vote-count: uint,
        released: bool,
    }
)

(define-map milestone-votes
    {
        milestone-id: uint,
        voter: principal,
    }
    bool
)

(define-map contributors
    principal
    uint
)
(define-map refunded
    principal
    bool
)
(define-map claimed
    bool
    bool
)

(define-map extension-requests
    uint
    {
        requested-at: uint,
        new-deadline: uint,
        vote-count: uint,
        approved: bool,
        momentum-score: uint,
    }
)

(define-map extension-votes
    {
        extension-id: uint,
        voter: principal,
    }
    bool
)

(define-map contributor-tiers
    principal
    {
        tier-name: (string-ascii 16),
        tier-level: uint,
        voting-multiplier: uint,
        early-access: bool,
    }
)

(define-map tier-early-access
    {
        milestone-id: uint,
        user: principal,
    }
    uint
)

;; ===== CAMPAIGN ANALYTICS SYSTEM =====

(define-map campaign-analytics
    uint
    {
        timestamp: uint,
        total-raised: uint,
        contributor-count: uint,
        campaign-health-score: uint,
        momentum-score: uint,
        target-progress-percentage: uint,
        time-remaining: uint,
    }
)

(define-map contribution-patterns
    {
        period-start: uint,
        period-end: uint,
    }
    {
        total-contributions: uint,
        avg-contribution-size: uint,
        largest-contribution: uint,
        smallest-contribution: uint,
        new-contributors: uint,
    }
)

(define-map milestone-metrics
    uint
    {
        total-milestones: uint,
        approved-milestones: uint,
        released-milestones: uint,
        approval-rate: uint,
        completion-rate: uint,
        avg-approval-time: uint,
    }
)

(define-map tier-distribution
    uint
    {
        bronze-count: uint,
        silver-count: uint,
        gold-count: uint,
        platinum-count: uint,
        standard-count: uint,
    }
)

(define-map contributor-activity
    principal
    {
        first-contribution-block: uint,
        last-contribution-block: uint,
        total-contributions: uint,
        milestone-votes: uint,
        extension-votes: uint,
        engagement-score: uint,
    }
)

(define-read-only (get-campaign-status)
    (ok {
        active: (var-get campaign-active),
        deadline: (var-get campaign-deadline),
        target: (var-get campaign-target),
        raised: (var-get total-raised),
        beneficiary: (var-get beneficiary),
        extensions-used: (var-get extension-count),
        max-extensions: (var-get max-extensions),
    })
)

(define-read-only (get-contribution (contributor principal))
    (default-to u0 (map-get? contributors contributor))
)

(define-read-only (is-refunded (contributor principal))
    (default-to false (map-get? refunded contributor))
)

(define-read-only (is-claimed)
    (default-to false (map-get? claimed true))
)

(define-read-only (is-deadline-reached)
    (>= burn-block-height (var-get campaign-deadline))
)

(define-read-only (is-target-reached)
    (>= (var-get total-raised) (var-get campaign-target))
)

(define-public (initialize
        (target uint)
        (deadline uint)
        (new-beneficiary principal)
    )
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (not (var-get campaign-active)) err-already-active)
        (asserts! (> target u0) err-amount-too-small)
        (asserts! (> deadline burn-block-height) err-deadline-passed)
        (var-set campaign-active true)
        (var-set campaign-target target)
        (var-set campaign-deadline deadline)
        (var-set beneficiary new-beneficiary)
        (var-set total-raised u0)
        (ok true)
    )
)

(define-public (contribute)
    (let (
            (amount (stx-get-balance tx-sender))
            (current-contribution (get-contribution tx-sender))
        )
        (asserts! (var-get campaign-active) err-not-active)
        (asserts! (not (is-deadline-reached)) err-deadline-passed)
        (asserts! (> amount u0) err-amount-too-small)
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (let ((new-total-contribution (+ current-contribution amount)))
            (map-set contributors tx-sender new-total-contribution)
            (let ((new-tier (calculate-contributor-tier new-total-contribution)))
                (map-set contributor-tiers tx-sender new-tier)
            )
            
            ;; Update analytics tracking
            (if (is-eq current-contribution u0)
                ;; New contributor
                (begin
                    (var-set total-unique-contributors (+ (var-get total-unique-contributors) u1))
                    (map-set contributor-activity tx-sender {
                        first-contribution-block: burn-block-height,
                        last-contribution-block: burn-block-height,
                        total-contributions: u1,
                        milestone-votes: u0,
                        extension-votes: u0,
                        engagement-score: u1,
                    })
                )
                ;; Existing contributor
                (let ((current-activity (unwrap-panic (map-get? contributor-activity tx-sender))))
                    (map-set contributor-activity tx-sender (merge current-activity {
                        last-contribution-block: burn-block-height,
                        total-contributions: (+ (get total-contributions current-activity) u1),
                    }))
                )
            )
            
            (var-set total-raised (+ (var-get total-raised) amount))
            (ok true)
        )
    )
)

(define-public (claim-funds)
    (begin
        (asserts! (is-eq tx-sender (var-get beneficiary)) err-owner-only)
        (asserts! (is-deadline-reached) err-not-deadline)
        (asserts! (is-target-reached) err-target-not-reached)
        (asserts! (not (is-claimed)) err-already-claimed)
        (map-set claimed true true)
        (as-contract (stx-transfer? (var-get total-raised) tx-sender (var-get beneficiary)))
    )
)

(define-public (request-refund)
    (let ((contribution (get-contribution tx-sender)))
        (asserts! (is-deadline-reached) err-not-deadline)
        (asserts! (not (is-target-reached)) err-target-not-reached)
        (asserts! (> contribution u0) err-no-contribution)
        (asserts! (not (is-refunded tx-sender)) err-already-claimed)
        (map-set refunded tx-sender true)
        (as-contract (stx-transfer? contribution tx-sender tx-sender))
    )
)

(define-public (emergency-shutdown)
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set campaign-active false)
        (ok true)
    )
)

(define-read-only (get-contract-balance)
    (stx-get-balance (as-contract tx-sender))
)

(define-public (update-beneficiary (new-beneficiary principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set beneficiary new-beneficiary)
        (ok true)
    )
)

(define-read-only (can-refund (user principal))
    (and
        (is-deadline-reached)
        (not (is-target-reached))
        (> (get-contribution user) u0)
        (not (is-refunded user))
    )
)

(define-read-only (time-remaining)
    (if (is-deadline-reached)
        u0
        (- (var-get campaign-deadline) burn-block-height)
    )
)

(define-read-only (get-milestone (milestone-id uint))
    (map-get? milestones milestone-id)
)

(define-read-only (get-milestone-count)
    (var-get milestone-count)
)

(define-read-only (has-voted-for-milestone
        (milestone-id uint)
        (voter principal)
    )
    (default-to false
        (map-get? milestone-votes {
            milestone-id: milestone-id,
            voter: voter,
        })
    )
)

(define-read-only (calculate-campaign-momentum)
    (let (
            (current-raised (var-get total-raised))
            (target (var-get campaign-target))
            (time-left (time-remaining))
        )
        (if (and (> current-raised u0) (> time-left u0))
            (/ (* current-raised u100) target)
            u0
        )
    )
)

(define-read-only (get-extension-request (extension-id uint))
    (map-get? extension-requests extension-id)
)

(define-read-only (has-voted-for-extension
        (extension-id uint)
        (voter principal)
    )
    (default-to false
        (map-get? extension-votes {
            extension-id: extension-id,
            voter: voter,
        })
    )
)

(define-read-only (can-request-extension)
    (and
        (var-get campaign-active)
        (< (time-remaining) u72)
        (< (var-get extension-count) (var-get max-extensions))
        (>= (calculate-campaign-momentum) (var-get minimum-momentum-threshold))
    )
)

(define-read-only (calculate-contributor-tier (contribution uint))
    (if (>= contribution (var-get platinum-tier-threshold))
        { tier-name: "Platinum", tier-level: u4, voting-multiplier: u4, early-access: true }
        (if (>= contribution (var-get gold-tier-threshold))
            { tier-name: "Gold", tier-level: u3, voting-multiplier: u3, early-access: true }
            (if (>= contribution (var-get silver-tier-threshold))
                { tier-name: "Silver", tier-level: u2, voting-multiplier: u2, early-access: true }
                (if (>= contribution (var-get bronze-tier-threshold))
                    { tier-name: "Bronze", tier-level: u1, voting-multiplier: u1, early-access: false }
                    { tier-name: "Standard", tier-level: u0, voting-multiplier: u1, early-access: false }
                )
            )
        )
    )
)

(define-read-only (get-contributor-tier (contributor principal))
    (let ((contribution (get-contribution contributor)))
        (calculate-contributor-tier contribution)
    )
)

(define-read-only (get-contributor-tier-info (contributor principal))
    (default-to
        { tier-name: "Standard", tier-level: u0, voting-multiplier: u1, early-access: false }
        (map-get? contributor-tiers contributor)
    )
)

(define-read-only (has-early-access (contributor principal))
    (let ((tier-info (get-contributor-tier contributor)))
        (get early-access tier-info)
    )
)

(define-public (create-milestone
        (description (string-ascii 256))
        (amount uint)
    )
    (let ((milestone-id (+ (var-get milestone-count) u1)))
        (asserts! (is-eq tx-sender (var-get beneficiary)) err-owner-only)
        (asserts! (var-get campaign-active) err-not-active)
        (asserts! (> amount u0) err-amount-too-small)
        (map-set milestones milestone-id {
            description: description,
            amount: amount,
            approved: false,
            vote-count: u0,
            released: false,
        })
        (var-set milestone-count milestone-id)
        (ok milestone-id)
    )
)

(define-public (vote-for-milestone (milestone-id uint))
    (let (
            (milestone-opt (get-milestone milestone-id))
            (contribution (get-contribution tx-sender))
            (total-contributors (var-get total-raised))
            (tier-info (get-contributor-tier tx-sender))
        )
        (asserts! (is-some milestone-opt) err-milestone-not-found)
        (asserts! (> contribution u0) err-no-contribution)
        (asserts! (not (has-voted-for-milestone milestone-id tx-sender))
            err-already-claimed
        )

        (let ((milestone (unwrap-panic milestone-opt)))
            (asserts! (not (get approved milestone))
                err-milestone-already-approved
            )
            (map-set milestone-votes {
                milestone-id: milestone-id,
                voter: tx-sender,
            }
                true
            )
            
            ;; Update contributor analytics
            (let ((current-activity (unwrap-panic (map-get? contributor-activity tx-sender))))
                (map-set contributor-activity tx-sender (merge current-activity {
                    milestone-votes: (+ (get milestone-votes current-activity) u1),
                }))
            )

            (let ((weighted-vote (* contribution (get voting-multiplier tier-info))))
                (let ((new-vote-count (+ (get vote-count milestone) weighted-vote)))
                    (map-set milestones milestone-id
                        (merge milestone { vote-count: new-vote-count })
                    )

                    (let ((approval-threshold (/
                            (* total-contributors
                                (var-get required-approval-percentage)
                            )
                            u100
                        )))
                        (if (>= new-vote-count approval-threshold)
                            (begin
                                (map-set milestones milestone-id
                                    (merge milestone {
                                        approved: true,
                                        vote-count: new-vote-count,
                                    })
                                )
                                (ok {
                                    approved: true,
                                    vote-count: new-vote-count,
                                    weighted-vote: weighted-vote,
                                })
                            )
                            (ok {
                                approved: false,
                                vote-count: new-vote-count,
                                weighted-vote: weighted-vote,
                            })
                        )
                    )
                )
            )
        )
    )
)

(define-public (request-campaign-extension)
    (let (
            (extension-id (+ (var-get extension-count) u1))
            (momentum (calculate-campaign-momentum))
            (new-deadline (+ (var-get campaign-deadline) (var-get extension-duration)))
        )
        (asserts! (can-request-extension) err-extension-limit-reached)
        (asserts! (>= momentum (var-get minimum-momentum-threshold))
            err-insufficient-momentum
        )

        (map-set extension-requests extension-id {
            requested-at: burn-block-height,
            new-deadline: new-deadline,
            vote-count: u0,
            approved: false,
            momentum-score: momentum,
        })

        (var-set extension-count extension-id)
        (ok extension-id)
    )
)

(define-public (vote-for-extension (extension-id uint))
    (let (
            (extension-opt (get-extension-request extension-id))
            (contribution (get-contribution tx-sender))
            (campaign-total (var-get total-raised))
            (tier-info (get-contributor-tier tx-sender))
        )
        (asserts! (is-some extension-opt) err-extension-not-found)
        (asserts! (> contribution u0) err-no-contribution)
        (asserts! (not (has-voted-for-extension extension-id tx-sender))
            err-already-claimed
        )

        (let ((extension (unwrap-panic extension-opt)))
            (asserts! (not (get approved extension))
                err-extension-already-requested
            )

            (map-set extension-votes {
                extension-id: extension-id,
                voter: tx-sender,
            }
                true
            )
            
            ;; Update contributor analytics
            (let ((current-activity (unwrap-panic (map-get? contributor-activity tx-sender))))
                (map-set contributor-activity tx-sender (merge current-activity {
                    extension-votes: (+ (get extension-votes current-activity) u1),
                }))
            )

            (let ((weighted-vote (* contribution (get voting-multiplier tier-info))))
                (let ((new-vote-count (+ (get vote-count extension) weighted-vote)))
                    (map-set extension-requests extension-id
                        (merge extension { vote-count: new-vote-count })
                    )

                    (let ((approval-threshold (/ (* campaign-total u51) u100)))
                        (if (>= new-vote-count approval-threshold)
                            (begin
                                (map-set extension-requests extension-id
                                    (merge extension {
                                        approved: true,
                                        vote-count: new-vote-count,
                                    })
                                )
                                (var-set campaign-deadline
                                    (get new-deadline extension)
                                )
                                (ok {
                                    approved: true,
                                    vote-count: new-vote-count,
                                    new-deadline: (get new-deadline extension),
                                    weighted-vote: weighted-vote,
                                })
                            )
                            (ok {
                                approved: false,
                                vote-count: new-vote-count,
                                new-deadline: (get new-deadline extension),
                                weighted-vote: weighted-vote,
                            })
                        )
                    )
                )
            )
        )
    )
)

(define-public (release-milestone-funds (milestone-id uint))
    (let ((milestone-opt (get-milestone milestone-id)))
        (asserts! (is-some milestone-opt) err-milestone-not-found)
        (asserts! (is-eq tx-sender (var-get beneficiary)) err-owner-only)

        (let ((milestone (unwrap-panic milestone-opt)))
            (asserts! (get approved milestone) err-milestone-not-approved)
            (asserts! (not (get released milestone)) err-already-claimed)
            (asserts! (>= (get-contract-balance) (get amount milestone))
                err-amount-too-small
            )

            (map-set milestones milestone-id (merge milestone { released: true }))
            (as-contract (stx-transfer? (get amount milestone) tx-sender (var-get beneficiary)))
        )
    )
)

(define-public (grant-early-access (milestone-id uint))
    (let (
            (milestone-opt (get-milestone milestone-id))
            (tier-info (get-contributor-tier tx-sender))
        )
        (asserts! (is-some milestone-opt) err-milestone-not-found)
        (asserts! (get early-access tier-info) err-insufficient-tier)
        (asserts! (> (get-contribution tx-sender) u0) err-no-contribution)
        
        (map-set tier-early-access {
            milestone-id: milestone-id,
            user: tx-sender,
        } burn-block-height)
        
        (ok true)
    )
)

(define-read-only (get-early-access-timestamp (milestone-id uint) (user principal))
    (map-get? tier-early-access {
        milestone-id: milestone-id,
        user: user,
    })
)

(define-read-only (list-contributor-privileges (contributor principal))
    (let ((tier-info (get-contributor-tier contributor)))
        (ok {
            tier-name: (get tier-name tier-info),
            tier-level: (get tier-level tier-info),
            voting-multiplier: (get voting-multiplier tier-info),
            early-access: (get early-access tier-info),
            contribution-amount: (get-contribution contributor),
        })
    )
)

(define-public (update-tier-thresholds 
        (bronze uint) 
        (silver uint) 
        (gold uint) 
        (platinum uint)
    )
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (< bronze silver) err-amount-too-small)
        (asserts! (< silver gold) err-amount-too-small)
        (asserts! (< gold platinum) err-amount-too-small)
        
        (var-set bronze-tier-threshold bronze)
        (var-set silver-tier-threshold silver)
        (var-set gold-tier-threshold gold)
        (var-set platinum-tier-threshold platinum)
        
        (ok true)
    )
)

(define-read-only (get-tier-thresholds)
    (ok {
        bronze: (var-get bronze-tier-threshold),
        silver: (var-get silver-tier-threshold),
        gold: (var-get gold-tier-threshold),
        platinum: (var-get platinum-tier-threshold),
    })
)

;; ===== ANALYTICS READ-ONLY FUNCTIONS =====

(define-read-only (get-campaign-performance-score)
    (let (
            (target-amount (var-get campaign-target))
            (raised-amount (var-get total-raised))
            (time-left (time-remaining))
            (deadline-block (var-get campaign-deadline))
        )
        (if (and (> target-amount u0) (> deadline-block burn-block-height))
            (let (
                    (total-time (- deadline-block burn-block-height))
                    (progress-score (/ (* raised-amount u100) target-amount))
                    (time-efficiency-score (if (and (> time-left u0) (> total-time u0))
                        (/ (* (- total-time time-left) u100) total-time)
                        (if (is-eq time-left u0) u100 u0)
                    ))
                    (momentum-value (calculate-campaign-momentum))
                )
                ;; Weighted score: 40% progress, 30% time efficiency, 30% momentum
                (ok (/ (+ (* progress-score u40) (* time-efficiency-score u30) (* momentum-value u30)) u100))
            )
            (ok u0)
        )
    )
)

(define-read-only (get-contribution-statistics)
    (let (
            (raised-amount (var-get total-raised))
            (unique-contributors (var-get total-unique-contributors))
        )
        (ok {
            total-raised: raised-amount,
            unique-contributors: unique-contributors,
            avg-contribution: (if (> unique-contributors u0)
                (/ raised-amount unique-contributors)
                u0
            ),
            campaign-target: (var-get campaign-target),
            target-progress-percentage: (if (> (var-get campaign-target) u0)
                (/ (* raised-amount u100) (var-get campaign-target))
                u0
            ),
        })
    )
)

(define-read-only (get-milestone-completion-rate)
    (let ((total-milestones (var-get milestone-count)))
        (if (> total-milestones u0)
            (let (
                    (approved-count (fold calculate-approved-milestones (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10) u0))
                    (completed-count (fold calculate-completed-milestones (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10) u0))
                )
                (ok {
                    total-milestones: total-milestones,
                    approved-milestones: approved-count,
                    completed-milestones: completed-count,
                    approval-rate: (/ (* approved-count u100) total-milestones),
                    completion-rate: (/ (* completed-count u100) total-milestones),
                })
            )
            (ok {
                total-milestones: u0,
                approved-milestones: u0,
                completed-milestones: u0,
                approval-rate: u0,
                completion-rate: u0,
            })
        )
    )
)

(define-read-only (get-campaign-analytics (snapshot-id uint))
    (match (map-get? campaign-analytics snapshot-id)
        analytics-data (ok analytics-data)
        (err err-analytics-not-found)
    )
)

(define-read-only (get-tier-distribution-stats)
    (let (
            (bronze-count (fold count-tier-members (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10) { tier: u1, count: u0 }))
            (silver-count (fold count-tier-members (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10) { tier: u2, count: u0 }))
            (gold-count (fold count-tier-members (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10) { tier: u3, count: u0 }))
            (platinum-count (fold count-tier-members (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10) { tier: u4, count: u0 }))
            (standard-count (- (var-get total-unique-contributors) 
                (+ (+ (+ (get count bronze-count) (get count silver-count)) 
                      (get count gold-count)) 
                   (get count platinum-count))))
        )
        (ok {
            bronze: (get count bronze-count),
            silver: (get count silver-count),
            gold: (get count gold-count),
            platinum: (get count platinum-count),
            standard: standard-count,
            total-contributors: (var-get total-unique-contributors),
        })
    )
)

(define-read-only (get-contributor-engagement (contributor principal))
    (match (map-get? contributor-activity contributor)
        activity-data (ok activity-data)
        (ok {
            first-contribution-block: u0,
            last-contribution-block: u0,
            total-contributions: u0,
            milestone-votes: u0,
            extension-votes: u0,
            engagement-score: u0,
        })
    )
)

(define-read-only (calculate-engagement-score (contributor principal))
    (let (
            (contribution-amount (get-contribution contributor))
            (activity-data (unwrap! (get-contributor-engagement contributor) (ok u0)))
            (milestone-vote-count (get milestone-votes activity-data))
            (extension-vote-count (get extension-votes activity-data))
            (contribution-count (get total-contributions activity-data))
        )
        (ok (+ (/ contribution-amount u1000000) (* milestone-vote-count u5) (* extension-vote-count u3) contribution-count))
    )
)

;; Helper functions for fold operations
(define-private (calculate-approved-milestones (milestone-id uint) (count uint))
    (let ((milestone-opt (get-milestone milestone-id)))
        (if (is-some milestone-opt)
            (let ((milestone (unwrap-panic milestone-opt)))
                (if (get approved milestone)
                    (+ count u1)
                    count
                )
            )
            count
        )
    )
)

(define-private (calculate-completed-milestones (milestone-id uint) (count uint))
    (let ((milestone-opt (get-milestone milestone-id)))
        (if (is-some milestone-opt)
            (let ((milestone (unwrap-panic milestone-opt)))
                (if (get released milestone)
                    (+ count u1)
                    count
                )
            )
            count
        )
    )
)

(define-private (count-tier-members (item uint) (tier-data { tier: uint, count: uint }))
    ;; This is a simplified implementation - in practice would iterate through contributors
    ;; For demo purposes, returning the same tier-data
    tier-data
)

;; ===== ANALYTICS MANAGEMENT FUNCTIONS =====

(define-public (create-analytics-snapshot)
    (let (
            (snapshot-id (+ (var-get analytics-snapshot-count) u1))
            (performance-score-result (get-campaign-performance-score))
            (momentum (calculate-campaign-momentum))
            (target-amount (var-get campaign-target))
            (raised-amount (var-get total-raised))
        )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (let ((performance-score (unwrap! performance-score-result (ok u0))))
            (map-set campaign-analytics snapshot-id {
                timestamp: burn-block-height,
                total-raised: raised-amount,
                contributor-count: (var-get total-unique-contributors),
                campaign-health-score: performance-score,
                momentum-score: momentum,
                target-progress-percentage: (if (> target-amount u0)
                    (/ (* raised-amount u100) target-amount)
                    u0
                ),
                time-remaining: (time-remaining),
            })
            (var-set analytics-snapshot-count snapshot-id)
            (ok snapshot-id)
        )
    )
)

(define-read-only (get-analytics-snapshot-count)
    (var-get analytics-snapshot-count)
)

(define-read-only (get-latest-analytics-snapshot)
    (let ((latest-id (var-get analytics-snapshot-count)))
        (if (> latest-id u0)
            (get-campaign-analytics latest-id)
            (err err-analytics-not-found)
        )
    )
)
