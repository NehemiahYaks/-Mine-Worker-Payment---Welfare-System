(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INSUFFICIENT_FUNDS (err u101))
(define-constant ERR_WORKER_NOT_FOUND (err u102))
(define-constant ERR_INVALID_AMOUNT (err u103))
(define-constant ERR_PAYMENT_ALREADY_PROCESSED (err u104))
(define-constant ERR_INVALID_PERIOD (err u105))
(define-constant ERR_INSURANCE_NOT_ENABLED (err u106))

(define-data-var contract-owner principal tx-sender)
(define-data-var insurance-rate uint u3)
(define-data-var payment-period uint u144)
(define-data-var retirement-rate uint u5)

(define-map workers
    { worker: principal }
    {
        hourly-rate: uint,
        hours-worked: uint,
        insurance-enabled: bool,
        retirement-enabled: bool,
        last-payment-block: uint,
        total-earned: uint,
        insurance-balance: uint,
        retirement-balance: uint
    }
)

(define-map payment-receipts
    { worker: principal, period: uint }
    {
        gross-amount: uint,
        insurance-deduction: uint,
        retirement-deduction: uint,
        net-amount: uint,
        payment-block: uint,
        payment-hash: (buff 32)
    }
)

(define-map employer-balances
    { employer: principal }
    { balance: uint }
)

(define-read-only (get-contract-owner)
    (var-get contract-owner)
)

(define-read-only (get-worker-info (worker principal))
    (map-get? workers { worker: worker })
)

(define-read-only (get-payment-receipt (worker principal) (period uint))
    (map-get? payment-receipts { worker: worker, period: period })
)

(define-read-only (get-employer-balance (employer principal))
    (default-to u0 (get balance (map-get? employer-balances { employer: employer })))
)

(define-read-only (calculate-payment (worker principal))
    (match (map-get? workers { worker: worker })
        worker-data
        (let
            (
                (gross-pay (* (get hourly-rate worker-data) (get hours-worked worker-data)))
                (insurance-deduction (if (get insurance-enabled worker-data)
                    (/ (* gross-pay (var-get insurance-rate)) u100)
                    u0
                ))
                (retirement-deduction (if (get retirement-enabled worker-data)
                    (/ (* gross-pay (var-get retirement-rate)) u100)
                    u0
                ))
                (net-pay (- gross-pay (+ insurance-deduction retirement-deduction)))
            )
            (some {
                gross-amount: gross-pay,
                insurance-deduction: insurance-deduction,
                retirement-deduction: retirement-deduction,
                net-amount: net-pay
            })
        )
        none
    )
)

(define-read-only (is-payment-due (worker principal))
    (match (map-get? workers { worker: worker })
        worker-data
        (>= (- burn-block-height (get last-payment-block worker-data)) (var-get payment-period))
        false
    )
)

(define-public (register-worker (worker principal) (hourly-rate uint) (insurance-enabled bool) (retirement-enabled bool))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
        (asserts! (> hourly-rate u0) ERR_INVALID_AMOUNT)
        (ok (map-set workers
            { worker: worker }
            {
                hourly-rate: hourly-rate,
                hours-worked: u0,
                insurance-enabled: insurance-enabled,
                retirement-enabled: retirement-enabled,
                last-payment-block: burn-block-height,
                total-earned: u0,
                insurance-balance: u0,
                retirement-balance: u0
            }
        ))
    )
)

(define-public (update-worker-hours (worker principal) (hours uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
        (asserts! (is-some (map-get? workers { worker: worker })) ERR_WORKER_NOT_FOUND)
        (match (map-get? workers { worker: worker })
            worker-data
            (ok (map-set workers
                { worker: worker }
                (merge worker-data { hours-worked: hours })
            ))
            ERR_WORKER_NOT_FOUND
        )
    )
)

(define-public (deposit-funds (amount uint))
    (let
        (
            (current-balance (get-employer-balance tx-sender))
        )
        (begin
            (asserts! (> amount u0) ERR_INVALID_AMOUNT)
            (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
            (ok (map-set employer-balances
                { employer: tx-sender }
                { balance: (+ current-balance amount) }
            ))
        )
    )
)

(define-public (process-payment (worker principal))
    (let
        (
            (payment-calculation (unwrap! (calculate-payment worker) ERR_WORKER_NOT_FOUND))
            (worker-data (unwrap! (map-get? workers { worker: worker }) ERR_WORKER_NOT_FOUND))
            (current-period (/ burn-block-height (var-get payment-period)))
            (employer-balance (get-employer-balance tx-sender))
        )
        (begin
            (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
            (asserts! (is-payment-due worker) ERR_PAYMENT_ALREADY_PROCESSED)
            (asserts! (>= employer-balance (get net-amount payment-calculation)) ERR_INSUFFICIENT_FUNDS)
            (asserts! (is-none (map-get? payment-receipts { worker: worker, period: current-period })) ERR_PAYMENT_ALREADY_PROCESSED)
            
            (try! (as-contract (stx-transfer? (get net-amount payment-calculation) tx-sender worker)))
            
            (map-set employer-balances
                { employer: tx-sender }
                { balance: (- employer-balance (get net-amount payment-calculation)) }
            )
            
            (map-set workers
                { worker: worker }
                (merge worker-data {
                    hours-worked: u0,
                    last-payment-block: burn-block-height,
                    total-earned: (+ (get total-earned worker-data) (get gross-amount payment-calculation)),
                    insurance-balance: (+ (get insurance-balance worker-data) (get insurance-deduction payment-calculation)),
                    retirement-balance: (+ (get retirement-balance worker-data) (get retirement-deduction payment-calculation))
                })
            )
            
            (ok (map-set payment-receipts
                { worker: worker, period: current-period }
                {
                    gross-amount: (get gross-amount payment-calculation),
                    insurance-deduction: (get insurance-deduction payment-calculation),
                    retirement-deduction: (get retirement-deduction payment-calculation),
                    net-amount: (get net-amount payment-calculation),
                    payment-block: burn-block-height,
                    payment-hash: (sha256 (concat (unwrap-panic (to-consensus-buff? worker)) (unwrap-panic (to-consensus-buff? burn-block-height))))
                }
            ))
        )
    )
)

(define-public (batch-process-payments (workers-list (list 50 principal)))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
        (ok (map process-payment workers-list))
    )
)

(define-public (withdraw-insurance (worker principal) (amount uint))
    (let
        (
            (worker-data (unwrap! (map-get? workers { worker: worker }) ERR_WORKER_NOT_FOUND))
        )
        (begin
            (asserts! (is-eq tx-sender worker) ERR_UNAUTHORIZED)
            (asserts! (get insurance-enabled worker-data) ERR_INSURANCE_NOT_ENABLED)
            (asserts! (>= (get insurance-balance worker-data) amount) ERR_INSUFFICIENT_FUNDS)
            (asserts! (> amount u0) ERR_INVALID_AMOUNT)
            
            (try! (as-contract (stx-transfer? amount tx-sender worker)))
            
            (ok (map-set workers
                { worker: worker }
                (merge worker-data {
                    insurance-balance: (- (get insurance-balance worker-data) amount)
                })
            ))
        )
    )
)

(define-public (withdraw-retirement (worker principal) (amount uint))
    (let
        (
            (worker-data (unwrap! (map-get? workers { worker: worker }) ERR_WORKER_NOT_FOUND))
        )
        (begin
            (asserts! (is-eq tx-sender worker) ERR_UNAUTHORIZED)
            (asserts! (get retirement-enabled worker-data) ERR_INSURANCE_NOT_ENABLED)
            (asserts! (>= (get retirement-balance worker-data) amount) ERR_INSUFFICIENT_FUNDS)
            (asserts! (> amount u0) ERR_INVALID_AMOUNT)
            
            (try! (as-contract (stx-transfer? amount tx-sender worker)))
            
            (ok (map-set workers
                { worker: worker }
                (merge worker-data {
                    retirement-balance: (- (get retirement-balance worker-data) amount)
                })
            ))
        )
    )
)

(define-public (update-insurance-rate (new-rate uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
        (asserts! (<= new-rate u10) ERR_INVALID_AMOUNT)
        (ok (var-set insurance-rate new-rate))
    )
)

(define-public (update-retirement-rate (new-rate uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
        (asserts! (<= new-rate u10) ERR_INVALID_AMOUNT)
        (ok (var-set retirement-rate new-rate))
    )
)

(define-public (update-payment-period (new-period uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
        (asserts! (> new-period u0) ERR_INVALID_PERIOD)
        (ok (var-set payment-period new-period))
    )
)

(define-public (emergency-withdraw-funds (amount uint))
    (let
        (
            (employer-balance (get-employer-balance tx-sender))
        )
        (begin
            (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
            (asserts! (>= employer-balance amount) ERR_INSUFFICIENT_FUNDS)
            (asserts! (> amount u0) ERR_INVALID_AMOUNT)

            (try! (as-contract (stx-transfer? amount tx-sender (var-get contract-owner))))

            (ok (map-set employer-balances
                { employer: tx-sender }
                { balance: (- employer-balance amount) }
            ))
        )
    )
)

(define-public (award-bonus (worker principal) (amount uint))
    (let
        (
            (worker-data (unwrap! (map-get? workers { worker: worker }) ERR_WORKER_NOT_FOUND))
            (employer-balance (get-employer-balance tx-sender))
        )
        (begin
            (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
            (asserts! (> amount u0) ERR_INVALID_AMOUNT)
            (asserts! (>= employer-balance amount) ERR_INSUFFICIENT_FUNDS)

            (try! (as-contract (stx-transfer? amount tx-sender worker)))

            (map-set employer-balances
                { employer: tx-sender }
                { balance: (- employer-balance amount) }
            )

            (ok (map-set workers
                { worker: worker }
                (merge worker-data {
                    total-earned: (+ (get total-earned worker-data) amount)
                })
            ))
        )
    )
)

(define-read-only (get-payment-period)
    (var-get payment-period)
)

(define-read-only (get-insurance-rate)
    (var-get insurance-rate)
)

(define-read-only (get-retirement-rate)
    (var-get retirement-rate)
)

(define-read-only (get-current-period)
    (/ burn-block-height (var-get payment-period))
)

(define-read-only (get-worker-statistics (worker principal))
    (match (map-get? workers { worker: worker })
        worker-data
        (some {
            total-payments: (get total-earned worker-data),
            insurance-contributions: (get insurance-balance worker-data),
            retirement-contributions: (get retirement-balance worker-data),
            current-hours: (get hours-worked worker-data),
            next-payment-due: (+ (get last-payment-block worker-data) (var-get payment-period))
        })
        none
    )
)

(define-read-only (get-worker-payment-count (worker principal))
    (let
        (
            (worker-data (map-get? workers { worker: worker }))
        )
        (match worker-data
            data (some (get total-earned data))
            none
        )
    )
)
