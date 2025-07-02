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

(define-data-var campaign-active bool false)
(define-data-var campaign-deadline uint u0)
(define-data-var campaign-target uint u0)
(define-data-var total-raised uint u0)
(define-data-var beneficiary principal contract-owner)

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

(define-read-only (get-campaign-status)
    (ok {
        active: (var-get campaign-active),
        deadline: (var-get campaign-deadline),
        target: (var-get campaign-target),
        raised: (var-get total-raised),
        beneficiary: (var-get beneficiary),
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
