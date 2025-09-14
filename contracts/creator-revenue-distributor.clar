;; Creator Revenue Distributor
;; Processes micropayments, subscription fees, and tip distributions to content creators

(define-constant ERR-NOT-AUTHORIZED (err u401))
(define-constant ERR-INSUFFICIENT-FUNDS (err u402))
(define-constant ERR-INVALID-AMOUNT (err u400))
(define-constant ERR-PAYMENT-FAILED (err u500))
(define-constant ERR-SUBSCRIPTION-NOT-FOUND (err u404))

(define-data-var total-payments-processed uint u0)
(define-data-var total-revenue-distributed uint u0)
(define-data-var platform-fee-rate uint u250) ;; 2.5% platform fee

;; Payment tracking
(define-map payments
    { payment-id: uint }
    {
        from: principal,
        to: principal,
        amount: uint,
        payment-type: (string-ascii 20), ;; "tip", "purchase", "subscription", "royalty"
        content-id: (optional uint),
        timestamp: uint,
        platform-fee: uint,
        net-amount: uint
    }
)

(define-data-var payment-counter uint u0)

;; Creator revenue analytics
(define-map creator-analytics
    { creator: principal, month: uint, year: uint }
    {
        total-revenue: uint,
        subscription-revenue: uint,
        content-sales: uint,
        tips-received: uint,
        unique-supporters: uint,
        content-views: uint,
        top-content-id: (optional uint)
    }
)

;; Tip jar for creators
(define-map tip-jars
    { creator: principal }
    {
        total-tips: uint,
        tip-count: uint,
        average-tip: uint,
        top-supporter: (optional principal),
        last-tip-date: uint
    }
)

;; Revenue sharing for collaborations
(define-map collaboration-revenue-shares
    { content-id: uint }
    {
        total-collaborators: uint,
        revenue-distributed: uint,
        pending-payments: uint
    }
)

;; Subscription payment tracking
(define-map subscription-payments
    { subscriber: principal, creator: principal, payment-id: uint }
    {
        amount: uint,
        payment-date: uint,
        subscription-month: uint,
        auto-renewed: bool
    }
)

;; Process tip payment
(define-public (send-tip (creator principal) (amount uint) (message (optional (string-ascii 100))))
    (let ((tipper tx-sender)
          (payment-id (+ (var-get payment-counter) u1))
          (platform-fee (/ (* amount (var-get platform-fee-rate)) u10000))
          (net-amount (- amount platform-fee)))
        
        ;; Validation checks
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (asserts! (>= (stx-get-balance tipper) amount) ERR-INSUFFICIENT-FUNDS)
        (asserts! (not (is-eq tipper creator)) ERR-NOT-AUTHORIZED)
        
        ;; Transfer tip to creator (minus platform fee)
        (try! (stx-transfer? net-amount tipper creator))
        
        ;; Transfer platform fee if applicable
        (if (> platform-fee u0)
            (try! (stx-transfer? platform-fee tipper (as-contract tx-sender)))
            true
        )
        
        ;; Record payment
        (map-set payments { payment-id: payment-id }
            {
                from: tipper,
                to: creator,
                amount: amount,
                payment-type: "tip",
                content-id: none,
                timestamp: block-height,
                platform-fee: platform-fee,
                net-amount: net-amount
            }
        )
        
        ;; Update tip jar stats
        (let ((current-jar (default-to 
                           { total-tips: u0, tip-count: u0, average-tip: u0,
                             top-supporter: none, last-tip-date: u0 }
                           (map-get? tip-jars { creator: creator })))
              (new-tip-count (+ (get tip-count current-jar) u1)))
            
            (map-set tip-jars { creator: creator }
                {
                    total-tips: (+ (get total-tips current-jar) net-amount),
                    tip-count: new-tip-count,
                    average-tip: (/ (+ (get total-tips current-jar) net-amount) new-tip-count),
                    top-supporter: (some tipper), ;; Simplified - would need to track amounts
                    last-tip-date: block-height
                }
            )
        )
        
        ;; Update counters
        (var-set payment-counter payment-id)
        (var-set total-payments-processed (+ (var-get total-payments-processed) u1))
        (var-set total-revenue-distributed (+ (var-get total-revenue-distributed) net-amount))
        
        (ok payment-id)
    )
)

;; Process content purchase payment
(define-public (process-content-payment (creator principal) (content-id uint) (amount uint))
    (let ((buyer tx-sender)
          (payment-id (+ (var-get payment-counter) u1))
          (platform-fee (/ (* amount (var-get platform-fee-rate)) u10000))
          (net-amount (- amount platform-fee)))
        
        ;; Validation checks
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (asserts! (>= (stx-get-balance buyer) amount) ERR-INSUFFICIENT-FUNDS)
        
        ;; Transfer payment to creator
        (try! (stx-transfer? net-amount buyer creator))
        
        ;; Transfer platform fee
        (if (> platform-fee u0)
            (try! (stx-transfer? platform-fee buyer (as-contract tx-sender)))
            true
        )
        
        ;; Record payment
        (map-set payments { payment-id: payment-id }
            {
                from: buyer,
                to: creator,
                amount: amount,
                payment-type: "purchase",
                content-id: (some content-id),
                timestamp: block-height,
                platform-fee: platform-fee,
                net-amount: net-amount
            }
        )
        
        ;; Update analytics
        (update-creator-analytics creator net-amount "purchase")
        
        ;; Update counters
        (var-set payment-counter payment-id)
        (var-set total-payments-processed (+ (var-get total-payments-processed) u1))
        (var-set total-revenue-distributed (+ (var-get total-revenue-distributed) net-amount))
        
        (ok payment-id)
    )
)

;; Process subscription payment
(define-public (process-subscription-payment (creator principal) (amount uint))
    (let ((subscriber tx-sender)
          (payment-id (+ (var-get payment-counter) u1))
          (platform-fee (/ (* amount (var-get platform-fee-rate)) u10000))
          (net-amount (- amount platform-fee)))
        
        ;; Validation checks
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (asserts! (>= (stx-get-balance subscriber) amount) ERR-INSUFFICIENT-FUNDS)
        
        ;; Transfer payment to creator
        (try! (stx-transfer? net-amount subscriber creator))
        
        ;; Transfer platform fee
        (if (> platform-fee u0)
            (try! (stx-transfer? platform-fee subscriber (as-contract tx-sender)))
            true
        )
        
        ;; Record payment
        (map-set payments { payment-id: payment-id }
            {
                from: subscriber,
                to: creator,
                amount: amount,
                payment-type: "subscription",
                content-id: none,
                timestamp: block-height,
                platform-fee: platform-fee,
                net-amount: net-amount
            }
        )
        
        ;; Record subscription payment details
        (map-set subscription-payments { subscriber: subscriber, creator: creator, payment-id: payment-id }
            {
                amount: net-amount,
                payment-date: block-height,
                subscription-month: (/ block-height u4320), ;; Rough monthly approximation
                auto-renewed: true
            }
        )
        
        ;; Update analytics
        (update-creator-analytics creator net-amount "subscription")
        
        ;; Update counters
        (var-set payment-counter payment-id)
        (var-set total-payments-processed (+ (var-get total-payments-processed) u1))
        (var-set total-revenue-distributed (+ (var-get total-revenue-distributed) net-amount))
        
        (ok payment-id)
    )
)

;; Distribute collaboration revenue
(define-public (distribute-collaboration-revenue 
    (content-id uint) 
    (collaborators (list 5 principal)) 
    (revenue-shares (list 5 uint))
    (total-amount uint)
)
    (let ((distributor tx-sender)
          (platform-fee (/ (* total-amount (var-get platform-fee-rate)) u10000))
          (distributable-amount (- total-amount platform-fee)))
        
        ;; Validation checks
        (asserts! (> total-amount u0) ERR-INVALID-AMOUNT)
        (asserts! (is-eq (len collaborators) (len revenue-shares)) ERR-INVALID-AMOUNT)
        (asserts! (>= (stx-get-balance distributor) total-amount) ERR-INSUFFICIENT-FUNDS)
        
        ;; Transfer platform fee
        (if (> platform-fee u0)
            (try! (stx-transfer? platform-fee distributor (as-contract tx-sender)))
            true
        )
        
        ;; Distribute to collaborators
        (try! (distribute-to-collaborators collaborators revenue-shares distributable-amount distributor))
        
        ;; Update revenue share tracking
        (let ((current-share (default-to 
                             { total-collaborators: u0, revenue-distributed: u0, pending-payments: u0 }
                             (map-get? collaboration-revenue-shares { content-id: content-id }))))
            (map-set collaboration-revenue-shares { content-id: content-id }
                {
                    total-collaborators: (len collaborators),
                    revenue-distributed: (+ (get revenue-distributed current-share) distributable-amount),
                    pending-payments: u0
                }
            )
        )
        
        (ok true)
    )
)

;; Helper function to distribute to collaborators
(define-private (distribute-to-collaborators 
    (collaborators (list 5 principal)) 
    (shares (list 5 uint)) 
    (total-amount uint) 
    (distributor principal)
)
    (let ((collaborator-count (len collaborators)))
        (if (> collaborator-count u0)
            (let ((collaborator (unwrap-panic (element-at collaborators u0)))
                  (share (unwrap-panic (element-at shares u0)))
                  (payment-amount (/ (* total-amount share) u100)))
                
                ;; Transfer to collaborator
                (try! (stx-transfer? payment-amount distributor collaborator))
                
                ;; Continue with remaining collaborators (simplified)
                (ok true)
            )
            (ok true)
        )
    )
)

;; Update creator analytics
(define-private (update-creator-analytics (creator principal) (amount uint) (payment-type (string-ascii 20)))
    (let ((current-month (/ block-height u4320))  ;; Rough monthly calculation
          (current-year (/ block-height u52560))   ;; Rough yearly calculation
          (current-analytics (default-to
                             { total-revenue: u0, subscription-revenue: u0, content-sales: u0,
                               tips-received: u0, unique-supporters: u0, content-views: u0,
                               top-content-id: none }
                             (map-get? creator-analytics { creator: creator, month: current-month, year: current-year }))))
        
        (map-set creator-analytics { creator: creator, month: current-month, year: current-year }
            {
                total-revenue: (+ (get total-revenue current-analytics) amount),
                subscription-revenue: (if (is-eq payment-type "subscription")
                                      (+ (get subscription-revenue current-analytics) amount)
                                      (get subscription-revenue current-analytics)),
                content-sales: (if (is-eq payment-type "purchase")
                               (+ (get content-sales current-analytics) amount)
                               (get content-sales current-analytics)),
                tips-received: (if (is-eq payment-type "tip")
                               (+ (get tips-received current-analytics) amount)
                               (get tips-received current-analytics)),
                unique-supporters: (get unique-supporters current-analytics), ;; Would need more complex tracking
                content-views: (get content-views current-analytics),
                top-content-id: (get top-content-id current-analytics)
            }
        )
    )
)

;; Withdraw platform fees (admin only)
(define-public (withdraw-platform-fees (amount uint))
    (begin
        ;; Simple admin check - in production would use proper access control
        (asserts! (is-eq tx-sender (as-contract tx-sender)) ERR-NOT-AUTHORIZED)
        (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
        (ok true)
    )
)

;; Read-only functions
(define-read-only (get-payment-info (payment-id uint))
    (map-get? payments { payment-id: payment-id })
)

(define-read-only (get-creator-analytics (creator principal) (month uint) (year uint))
    (map-get? creator-analytics { creator: creator, month: month, year: year })
)

(define-read-only (get-tip-jar (creator principal))
    (map-get? tip-jars { creator: creator })
)

(define-read-only (get-revenue-share-info (content-id uint))
    (map-get? collaboration-revenue-shares { content-id: content-id })
)

(define-read-only (get-platform-stats)
    {
        total-payments: (var-get total-payments-processed),
        total-revenue: (var-get total-revenue-distributed),
        platform-fee-rate: (var-get platform-fee-rate)
    }
)

(define-read-only (calculate-platform-fee (amount uint))
    (/ (* amount (var-get platform-fee-rate)) u10000)
)

(define-read-only (get-net-amount (amount uint))
    (- amount (calculate-platform-fee amount))
)