;; Instant Payment Processor Contract
;; A comprehensive real-time payment processing system with biometric authorization and fraud detection

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-INSUFFICIENT-FUNDS (err u201))
(define-constant ERR-INVALID-AMOUNT (err u202))
(define-constant ERR-PAYMENT-FAILED (err u203))
(define-constant ERR-INVALID-RECIPIENT (err u204))
(define-constant ERR-BIOMETRIC-AUTH-REQUIRED (err u205))
(define-constant ERR-BIOMETRIC-AUTH-FAILED (err u206))
(define-constant ERR-TRANSACTION-LIMIT-EXCEEDED (err u207))
(define-constant ERR-FRAUD-DETECTED (err u208))
(define-constant ERR-ACCOUNT-FROZEN (err u209))
(define-constant ERR-INVALID-SESSION (err u210))
(define-constant ERR-PAYMENT-TIMEOUT (err u211))
(define-constant ERR-DUPLICATE-TRANSACTION (err u212))
(define-constant ERR-CURRENCY-NOT-SUPPORTED (err u213))
(define-constant ERR-DAILY-LIMIT-EXCEEDED (err u214))
(define-constant ERR-VELOCITY-CHECK-FAILED (err u215))
(define-constant ERR-GEOLOCATION-RESTRICTED (err u216))
(define-constant ERR-MERCHANT-NOT-VERIFIED (err u217))

;; Payment limits and thresholds
(define-constant MAX-TRANSACTION-AMOUNT u1000000) ;; 1M micro-STX
(define-constant DAILY-TRANSACTION-LIMIT u5000000) ;; 5M micro-STX
(define-constant BIOMETRIC-AUTH-THRESHOLD u100000) ;; 100K micro-STX
(define-constant FRAUD-SCORE-THRESHOLD u75)
(define-constant MAX-VELOCITY-TRANSACTIONS u10)
(define-constant VELOCITY-TIME-WINDOW u144) ;; blocks (~24 hours)
(define-constant TRANSACTION-TIMEOUT u10) ;; blocks

;; Payment status codes
(define-constant STATUS-PENDING u1)
(define-constant STATUS-PROCESSING u2)
(define-constant STATUS-COMPLETED u3)
(define-constant STATUS-FAILED u4)
(define-constant STATUS-REFUNDED u5)
(define-constant STATUS-DISPUTED u6)

;; Currency types
(define-constant CURRENCY-STX u1)
(define-constant CURRENCY-USD u2)
(define-constant CURRENCY-BTC u3)
(define-constant CURRENCY-ETH u4)

;; Data structures
(define-map user-accounts
    { user: principal }
    {
        balance-stx: uint,
        balance-usd: uint,
        daily-spent: uint,
        daily-reset-block: uint,
        is-verified: bool,
        is-frozen: bool,
        trust-score: uint,
        kyc-level: uint,
        last-activity: uint,
        total-volume: uint
    }
)

(define-map payment-transactions
    { tx-id: (buff 32) }
    {
        sender: principal,
        recipient: principal,
        amount: uint,
        currency: uint,
        status: uint,
        created-at: uint,
        completed-at: (optional uint),
        biometric-verified: bool,
        fraud-score: uint,
        session-id: (optional (buff 32)),
        merchant-id: (optional (string-ascii 64)),
        description: (string-ascii 256),
        fee-amount: uint,
        refund-amount: uint
    }
)

(define-map biometric-authorizations
    { auth-id: (buff 32) }
    {
        user: principal,
        transaction-id: (buff 32),
        biometric-types: uint,
        confidence-score: uint,
        device-fingerprint: (buff 32),
        location-hash: (buff 32),
        authorized-at: uint,
        expires-at: uint,
        is-used: bool
    }
)

(define-map fraud-detection-rules
    { rule-id: uint }
    {
        rule-name: (string-ascii 64),
        is-active: bool,
        weight: uint,
        threshold: uint,
        description: (string-ascii 256),
        created-by: principal,
        last-updated: uint
    }
)

(define-map user-transaction-velocity
    { user: principal }
    {
        transaction-count: uint,
        total-amount: uint,
        window-start: uint,
        last-transaction: uint,
        velocity-score: uint
    }
)

(define-map merchant-registry
    { merchant-id: (string-ascii 64) }
    {
        owner: principal,
        is-verified: bool,
        verification-level: uint,
        business-type: (string-ascii 32),
        daily-limit: uint,
        transaction-fee-rate: uint,
        total-processed: uint,
        reputation-score: uint,
        registered-at: uint
    }
)

;; Statistics and monitoring
(define-data-var total-transactions uint u0)
(define-data-var total-volume uint u0)
(define-data-var fraud-attempts uint u0)
(define-data-var system-fees-collected uint u0)
(define-data-var next-rule-id uint u1)
(define-data-var system-status uint u1) ;; 1=active, 2=maintenance, 3=suspended

;; Administrative functions
(define-public (set-system-status (new-status uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (asserts! (and (>= new-status u1) (<= new-status u3)) ERR-INVALID-AMOUNT)
        (var-set system-status new-status)
        (ok true)
    )
)

(define-public (add-fraud-detection-rule
    (rule-name (string-ascii 64))
    (weight uint)
    (threshold uint)
    (description (string-ascii 256))
)
    (let (
        (rule-id (var-get next-rule-id))
    )
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (map-set fraud-detection-rules
            { rule-id: rule-id }
            {
                rule-name: rule-name,
                is-active: true,
                weight: weight,
                threshold: threshold,
                description: description,
                created-by: tx-sender,
                last-updated: stacks-block-height
            }
        )
        (var-set next-rule-id (+ rule-id u1))
        (ok rule-id)
    )
)

;; Account management
(define-public (create-account (initial-deposit uint))
    (let (
        (user tx-sender)
    )
        (asserts! (is-none (map-get? user-accounts { user: user })) ERR-NOT-AUTHORIZED)
        (asserts! (>= initial-deposit u0) ERR-INVALID-AMOUNT)
        
        (map-set user-accounts
            { user: user }
            {
                balance-stx: initial-deposit,
                balance-usd: u0,
                daily-spent: u0,
                daily-reset-block: stacks-block-height,
                is-verified: false,
                is-frozen: false,
                trust-score: u50,
                kyc-level: u0,
                last-activity: stacks-block-height,
                total-volume: u0
            }
        )
        (ok true)
    )
)

(define-public (deposit-funds (amount uint) (currency uint))
    (let (
        (user tx-sender)
        (account (unwrap! (map-get? user-accounts { user: user }) ERR-INVALID-RECIPIENT))
    )
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (asserts! (not (get is-frozen account)) ERR-ACCOUNT-FROZEN)
        (asserts! (is-eq (var-get system-status) u1) ERR-PAYMENT-FAILED)
        
        (if (is-eq currency CURRENCY-STX)
            (map-set user-accounts
                { user: user }
                (merge account { 
                    balance-stx: (+ (get balance-stx account) amount),
                    last-activity: stacks-block-height 
                })
            )
            (if (is-eq currency CURRENCY-USD)
                (map-set user-accounts
                    { user: user }
                    (merge account { 
                        balance-usd: (+ (get balance-usd account) amount),
                        last-activity: stacks-block-height 
                    })
                )
                false
            )
        )
        (ok true)
    )
)

;; Biometric authorization for high-value transactions
(define-public (create-biometric-authorization
    (transaction-id (buff 32))
    (biometric-types uint)
    (confidence-score uint)
    (device-fingerprint (buff 32))
    (location-hash (buff 32))
)
    (let (
        (user tx-sender)
        (auth-id (hash160 (concat transaction-id device-fingerprint)))
    )
        (asserts! (>= confidence-score u85) ERR-BIOMETRIC-AUTH-FAILED)
        (asserts! (> biometric-types u0) ERR-BIOMETRIC-AUTH-FAILED)
        
        (map-set biometric-authorizations
            { auth-id: auth-id }
            {
                user: user,
                transaction-id: transaction-id,
                biometric-types: biometric-types,
                confidence-score: confidence-score,
                device-fingerprint: device-fingerprint,
                location-hash: location-hash,
                authorized-at: stacks-block-height,
                expires-at: (+ stacks-block-height u10),
                is-used: false
            }
        )
        (ok auth-id)
    )
)

;; Main payment processing function
(define-public (process-instant-payment
    (recipient principal)
    (amount uint)
    (currency uint)
    (description (string-ascii 256))
    (biometric-auth-id (optional (buff 32)))
    (merchant-id (optional (string-ascii 64)))
)
    (let (
        (sender tx-sender)
        (tx-id (hash160 (concat (unwrap-panic (to-consensus-buff? sender)) (unwrap-panic (to-consensus-buff? stacks-block-height)))))
        (sender-account (unwrap! (map-get? user-accounts { user: sender }) ERR-INVALID-RECIPIENT))
        (recipient-account (unwrap! (map-get? user-accounts { user: recipient }) ERR-INVALID-RECIPIENT))
        (fee-amount (calculate-transaction-fee amount currency))
        (total-amount (+ amount fee-amount))
    )
        ;; Basic validations
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (asserts! (<= amount MAX-TRANSACTION-AMOUNT) ERR-TRANSACTION-LIMIT-EXCEEDED)
        (asserts! (not (is-eq sender recipient)) ERR-INVALID-RECIPIENT)
        (asserts! (not (get is-frozen sender-account)) ERR-ACCOUNT-FROZEN)
        (asserts! (not (get is-frozen recipient-account)) ERR-ACCOUNT-FROZEN)
        (asserts! (is-eq (var-get system-status) u1) ERR-PAYMENT-FAILED)
        
        ;; Check sufficient balance
        (asserts! (>= (get-account-balance sender-account currency) total-amount) ERR-INSUFFICIENT-FUNDS)
        
        ;; Check daily limits
        (let (
            (updated-account (update-daily-spending sender-account amount))
        )
            (asserts! (is-ok updated-account) ERR-DAILY-LIMIT-EXCEEDED)
            
            ;; Fraud detection
            (let (
                (fraud-score (calculate-fraud-score sender recipient amount currency))
            )
                (asserts! (<= fraud-score FRAUD-SCORE-THRESHOLD) ERR-FRAUD-DETECTED)
                
                ;; Biometric auth for high-value transactions
                (if (>= amount BIOMETRIC-AUTH-THRESHOLD)
                    (begin
                        (asserts! (is-some biometric-auth-id) ERR-BIOMETRIC-AUTH-REQUIRED)
                        (asserts! (verify-biometric-authorization (unwrap-panic biometric-auth-id) tx-id) ERR-BIOMETRIC-AUTH-FAILED)
                    )
                    true
                )
                
                ;; Velocity checks
                (asserts! (check-transaction-velocity sender amount) ERR-VELOCITY-CHECK-FAILED)
                
                ;; Execute payment
                (let (
                    (payment-result (execute-payment sender recipient amount currency fee-amount tx-id))
                )
                    (asserts! (is-ok payment-result) ERR-PAYMENT-FAILED)
                    
                    ;; Record transaction
                    (map-set payment-transactions
                        { tx-id: tx-id }
                        {
                            sender: sender,
                            recipient: recipient,
                            amount: amount,
                            currency: currency,
                            status: STATUS-COMPLETED,
                            created-at: stacks-block-height,
                            completed-at: (some stacks-block-height),
                            biometric-verified: (is-some biometric-auth-id),
                            fraud-score: fraud-score,
                            session-id: none,
                            merchant-id: merchant-id,
                            description: description,
                            fee-amount: fee-amount,
                            refund-amount: u0
                        }
                    )
                    
                    ;; Update statistics
                    (var-set total-transactions (+ (var-get total-transactions) u1))
                    (var-set total-volume (+ (var-get total-volume) amount))
                    (var-set system-fees-collected (+ (var-get system-fees-collected) fee-amount))
                    
                    (ok { tx-id: tx-id, fee: fee-amount, status: STATUS-COMPLETED })
                )
            )
        )
    )
)

;; Helper functions
(define-private (get-account-balance (account { balance-stx: uint, balance-usd: uint, daily-spent: uint, daily-reset-block: uint, is-verified: bool, is-frozen: bool, trust-score: uint, kyc-level: uint, last-activity: uint, total-volume: uint }) (currency uint))
    (if (is-eq currency CURRENCY-STX)
        (get balance-stx account)
        (if (is-eq currency CURRENCY-USD)
            (get balance-usd account)
            u0
        )
    )
)

(define-private (calculate-transaction-fee (amount uint) (currency uint))
    (let (
        (base-fee (if (is-eq currency CURRENCY-STX) u1000 u100)) ;; Base fee in micro units
        (percentage-fee (/ (* amount u25) u10000)) ;; 0.25% fee
    )
        (+ base-fee percentage-fee)
    )
)

(define-private (update-daily-spending (account { balance-stx: uint, balance-usd: uint, daily-spent: uint, daily-reset-block: uint, is-verified: bool, is-frozen: bool, trust-score: uint, kyc-level: uint, last-activity: uint, total-volume: uint }) (amount uint))
    (let (
        (current-daily-spent (if (> (- stacks-block-height (get daily-reset-block account)) u144)
            u0
            (get daily-spent account)
        ))
        (new-daily-spent (+ current-daily-spent amount))
    )
        (if (<= new-daily-spent DAILY-TRANSACTION-LIMIT)
            (ok (merge account { 
                daily-spent: new-daily-spent,
                daily-reset-block: (if (> (- stacks-block-height (get daily-reset-block account)) u144)
                    stacks-block-height
                    (get daily-reset-block account)
                )
            }))
            ERR-DAILY-LIMIT-EXCEEDED
        )
    )
)

(define-private (calculate-fraud-score (sender principal) (recipient principal) (amount uint) (currency uint))
    (let (
        (base-score u20)
        (amount-risk (if (> amount u500000) u30 u10))
        (velocity-risk (get-velocity-risk sender))
        (time-risk (if (< (mod stacks-block-height u144) u12) u15 u5)) ;; Higher risk during night hours
    )
        (+ base-score amount-risk velocity-risk time-risk)
    )
)

(define-private (get-velocity-risk (user principal))
    (match (map-get? user-transaction-velocity { user: user })
        velocity-data (
            if (and 
                (> (get transaction-count velocity-data) MAX-VELOCITY-TRANSACTIONS)
                (< (- stacks-block-height (get window-start velocity-data)) VELOCITY-TIME-WINDOW)
            )
                u25
                u5
        )
        u0
    )
)

(define-private (verify-biometric-authorization (auth-id (buff 32)) (transaction-id (buff 32)))
    (match (map-get? biometric-authorizations { auth-id: auth-id })
        auth-data (
            and
                (not (get is-used auth-data))
                (< stacks-block-height (get expires-at auth-data))
                (is-eq (get transaction-id auth-data) transaction-id)
                (>= (get confidence-score auth-data) u85)
        )
        false
    )
)

(define-private (check-transaction-velocity (user principal) (amount uint))
    (let (
        (current-velocity (default-to 
            { transaction-count: u0, total-amount: u0, window-start: stacks-block-height, last-transaction: u0, velocity-score: u0 }
            (map-get? user-transaction-velocity { user: user })
        ))
        (window-expired (> (- stacks-block-height (get window-start current-velocity)) VELOCITY-TIME-WINDOW))
        (new-count (if window-expired u1 (+ (get transaction-count current-velocity) u1)))
        (new-amount (if window-expired amount (+ (get total-amount current-velocity) amount)))
    )
        (map-set user-transaction-velocity
            { user: user }
            {
                transaction-count: new-count,
                total-amount: new-amount,
                window-start: (if window-expired stacks-block-height (get window-start current-velocity)),
                last-transaction: stacks-block-height,
                velocity-score: (calculate-velocity-score new-count new-amount)
            }
        )
        (<= new-count MAX-VELOCITY-TRANSACTIONS)
    )
)

(define-private (calculate-velocity-score (tx-count uint) (total-amount uint))
    (+ (* tx-count u5) (/ total-amount u100000))
)

(define-private (execute-payment (sender principal) (recipient principal) (amount uint) (currency uint) (fee uint) (tx-id (buff 32)))
    (let (
        (sender-account (unwrap-panic (map-get? user-accounts { user: sender })))
        (recipient-account (unwrap-panic (map-get? user-accounts { user: recipient })))
        (total-deduct (+ amount fee))
    )
        (if (is-eq currency CURRENCY-STX)
            (begin
                ;; Deduct from sender
                (map-set user-accounts
                    { user: sender }
                    (merge sender-account { 
                        balance-stx: (- (get balance-stx sender-account) total-deduct),
                        total-volume: (+ (get total-volume sender-account) amount),
                        last-activity: stacks-block-height
                    })
                )
                ;; Credit to recipient
                (map-set user-accounts
                    { user: recipient }
                    (merge recipient-account { 
                        balance-stx: (+ (get balance-stx recipient-account) amount),
                        last-activity: stacks-block-height
                    })
                )
                (ok true)
            )
            (if (is-eq currency CURRENCY-USD)
                (begin
                    ;; Deduct from sender
                    (map-set user-accounts
                        { user: sender }
                        (merge sender-account { 
                            balance-usd: (- (get balance-usd sender-account) total-deduct),
                            total-volume: (+ (get total-volume sender-account) amount),
                            last-activity: stacks-block-height
                        })
                    )
                    ;; Credit to recipient
                    (map-set user-accounts
                        { user: recipient }
                        (merge recipient-account { 
                            balance-usd: (+ (get balance-usd recipient-account) amount),
                            last-activity: stacks-block-height
                        })
                    )
                    (ok true)
                )
                ERR-CURRENCY-NOT-SUPPORTED
            )
        )
    )
)

;; Read-only functions
(define-read-only (get-account-info (user principal))
    (map-get? user-accounts { user: user })
)

(define-read-only (get-transaction-info (tx-id (buff 32)))
    (map-get? payment-transactions { tx-id: tx-id })
)

(define-read-only (get-system-statistics)
    {
        total-transactions: (var-get total-transactions),
        total-volume: (var-get total-volume),
        fraud-attempts: (var-get fraud-attempts),
        fees-collected: (var-get system-fees-collected),
        system-status: (var-get system-status)
    }
)

(define-read-only (calculate-payment-fee (amount uint) (currency uint))
    (calculate-transaction-fee amount currency)
)

(define-read-only (get-user-velocity (user principal))
    (map-get? user-transaction-velocity { user: user })
)

