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
        (map-set contributors tx-sender (+ current-contribution amount))
        (var-set total-raised (+ (var-get total-raised) amount))
        (ok true)
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

            (let ((new-vote-count (+ (get vote-count milestone) contribution)))
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
                            })
                        )
                        (ok {
                            approved: false,
                            vote-count: new-vote-count,
                        })
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

            (let ((new-vote-count (+ (get vote-count extension) contribution)))
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
                            })
                        )
                        (ok {
                            approved: false,
                            vote-count: new-vote-count,
                            new-deadline: (get new-deadline extension),
                        })
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
