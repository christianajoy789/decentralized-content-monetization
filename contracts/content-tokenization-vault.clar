;; Content Tokenization Vault
;; Tokenizes digital content into NFTs with usage rights management and ownership verification

(define-constant ERR-NOT-AUTHORIZED (err u401))
(define-constant ERR-CONTENT-NOT-FOUND (err u404))
(define-constant ERR-INVALID-CONTENT (err u400))
(define-constant ERR-ACCESS-DENIED (err u403))
(define-constant ERR-ALREADY-EXISTS (err u409))

(define-data-var content-counter uint u0)
(define-data-var total-creators uint u0)

;; Content metadata structure
(define-map content-registry
    { content-id: uint }
    {
        creator: principal,
        title: (string-ascii 100),
        description: (string-ascii 300),
        content-hash: (string-ascii 64),
        content-type: (string-ascii 20),
        access-level: uint, ;; 1=free, 2=paid, 3=subscription
        price: uint,
        royalty-rate: uint, ;; percentage for resales
        created-at: uint,
        total-views: uint,
        total-sales: uint
    }
)

;; Creator profiles
(define-map creators
    { creator: principal }
    {
        name: (string-ascii 50),
        bio: (string-ascii 200),
        total-content: uint,
        total-earnings: uint,
        subscriber-count: uint,
        verification-status: bool,
        joined-at: uint
    }
)

;; Content ownership and access rights
(define-map content-ownership
    { content-id: uint, owner: principal }
    { 
        purchase-date: uint,
        access-type: (string-ascii 20), ;; "owner", "subscriber", "rental"
        expiry-date: (optional uint)
    }
)

;; Subscription management
(define-map subscriptions
    { subscriber: principal, creator: principal }
    {
        tier-level: uint,
        monthly-price: uint,
        start-date: uint,
        next-payment: uint,
        active: bool
    }
)

;; Content collaboration tracking
(define-map collaborations
    { content-id: uint, collaborator: principal }
    { 
        contribution-type: (string-ascii 30),
        revenue-share: uint, ;; percentage
        confirmed: bool
    }
)

;; Register creator profile
(define-public (register-creator (name (string-ascii 50)) (bio (string-ascii 200)))
    (let ((creator tx-sender))
        ;; Check if creator already exists
        (asserts! (is-none (map-get? creators { creator: creator })) ERR-ALREADY-EXISTS)
        
        ;; Create creator profile
        (map-set creators { creator: creator }
            {
                name: name,
                bio: bio,
                total-content: u0,
                total-earnings: u0,
                subscriber-count: u0,
                verification-status: false,
                joined-at: block-height
            }
        )
        
        (var-set total-creators (+ (var-get total-creators) u1))
        (ok true)
    )
)

;; Tokenize content as NFT
(define-public (tokenize-content 
    (title (string-ascii 100))
    (description (string-ascii 300))
    (content-hash (string-ascii 64))
    (content-type (string-ascii 20))
    (access-level uint)
    (price uint)
    (royalty-rate uint)
)
    (let ((content-id (+ (var-get content-counter) u1))
          (creator tx-sender))
        
        ;; Validation checks
        (asserts! (and (>= access-level u1) (<= access-level u3)) ERR-INVALID-CONTENT)
        (asserts! (<= royalty-rate u50) ERR-INVALID-CONTENT) ;; Max 50% royalty
        (asserts! (is-some (map-get? creators { creator: creator })) ERR-NOT-AUTHORIZED)
        
        ;; Create content registry entry
        (map-set content-registry { content-id: content-id }
            {
                creator: creator,
                title: title,
                description: description,
                content-hash: content-hash,
                content-type: content-type,
                access-level: access-level,
                price: price,
                royalty-rate: royalty-rate,
                created-at: block-height,
                total-views: u0,
                total-sales: u0
            }
        )
        
        ;; Creator owns the content initially
        (map-set content-ownership { content-id: content-id, owner: creator }
            {
                purchase-date: block-height,
                access-type: "owner",
                expiry-date: none
            }
        )
        
        ;; Update creator stats
        (let ((creator-data (unwrap-panic (map-get? creators { creator: creator }))))
            (map-set creators { creator: creator }
                (merge creator-data {
                    total-content: (+ (get total-content creator-data) u1)
                })
            )
        )
        
        (var-set content-counter content-id)
        (ok content-id)
    )
)

;; Purchase content access
(define-public (purchase-content (content-id uint))
    (let ((content (unwrap! (map-get? content-registry { content-id: content-id }) ERR-CONTENT-NOT-FOUND))
          (buyer tx-sender)
          (creator (get creator content))
          (price (get price content)))
        
        ;; Check access level and price
        (asserts! (is-eq (get access-level content) u2) ERR-INVALID-CONTENT)
        (asserts! (> price u0) ERR-INVALID-CONTENT)
        (asserts! (>= (stx-get-balance buyer) price) ERR-ACCESS-DENIED)
        
        ;; Transfer payment to creator
        (try! (stx-transfer? price buyer creator))
        
        ;; Grant access to buyer
        (map-set content-ownership { content-id: content-id, owner: buyer }
            {
                purchase-date: block-height,
                access-type: "owner",
                expiry-date: none
            }
        )
        
        ;; Update content stats
        (map-set content-registry { content-id: content-id }
            (merge content {
                total-sales: (+ (get total-sales content) u1)
            })
        )
        
        ;; Update creator earnings
        (let ((creator-data (unwrap-panic (map-get? creators { creator: creator }))))
            (map-set creators { creator: creator }
                (merge creator-data {
                    total-earnings: (+ (get total-earnings creator-data) price)
                })
            )
        )
        
        (ok true)
    )
)

;; Subscribe to creator
(define-public (subscribe-to-creator (creator principal) (tier-level uint) (monthly-price uint))
    (let ((subscriber tx-sender))
        
        ;; Validation checks
        (asserts! (is-some (map-get? creators { creator: creator })) ERR-NOT-AUTHORIZED)
        (asserts! (> monthly-price u0) ERR-INVALID-CONTENT)
        (asserts! (>= (stx-get-balance subscriber) monthly-price) ERR-ACCESS-DENIED)
        
        ;; Pay first month
        (try! (stx-transfer? monthly-price subscriber creator))
        
        ;; Create subscription
        (map-set subscriptions { subscriber: subscriber, creator: creator }
            {
                tier-level: tier-level,
                monthly-price: monthly-price,
                start-date: block-height,
                next-payment: (+ block-height u4320), ;; ~30 days
                active: true
            }
        )
        
        ;; Update creator subscriber count
        (let ((creator-data (unwrap-panic (map-get? creators { creator: creator }))))
            (map-set creators { creator: creator }
                (merge creator-data {
                    subscriber-count: (+ (get subscriber-count creator-data) u1),
                    total-earnings: (+ (get total-earnings creator-data) monthly-price)
                })
            )
        )
        
        (ok true)
    )
)

;; Add collaborator to content
(define-public (add-collaborator 
    (content-id uint) 
    (collaborator principal) 
    (contribution-type (string-ascii 30)) 
    (revenue-share uint)
)
    (let ((content (unwrap! (map-get? content-registry { content-id: content-id }) ERR-CONTENT-NOT-FOUND)))
        
        ;; Only creator can add collaborators
        (asserts! (is-eq tx-sender (get creator content)) ERR-NOT-AUTHORIZED)
        (asserts! (<= revenue-share u100) ERR-INVALID-CONTENT)
        
        ;; Add collaboration record
        (map-set collaborations { content-id: content-id, collaborator: collaborator }
            {
                contribution-type: contribution-type,
                revenue-share: revenue-share,
                confirmed: false
            }
        )
        
        (ok true)
    )
)

;; Confirm collaboration
(define-public (confirm-collaboration (content-id uint))
    (let ((collaboration (unwrap! (map-get? collaborations { content-id: content-id, collaborator: tx-sender }) 
                                 ERR-NOT-AUTHORIZED)))
        
        ;; Update collaboration status
        (map-set collaborations { content-id: content-id, collaborator: tx-sender }
            (merge collaboration { confirmed: true })
        )
        
        (ok true)
    )
)

;; Track content view
(define-public (track-view (content-id uint))
    (let ((content (unwrap! (map-get? content-registry { content-id: content-id }) ERR-CONTENT-NOT-FOUND)))
        
        ;; Update view count
        (map-set content-registry { content-id: content-id }
            (merge content {
                total-views: (+ (get total-views content) u1)
            })
        )
        
        (ok true)
    )
)

;; Check content access
(define-public (check-access (content-id uint) (user principal))
    (let ((content (unwrap! (map-get? content-registry { content-id: content-id }) ERR-CONTENT-NOT-FOUND))
          (creator (get creator content))
          (access-level (get access-level content)))
        
        ;; Free content - everyone has access
        (if (is-eq access-level u1)
            (ok true)
            ;; Paid content - check ownership
            (if (is-eq access-level u2)
                (ok (is-some (map-get? content-ownership { content-id: content-id, owner: user })))
                ;; Subscription content - check subscription
                (ok (match (map-get? subscriptions { subscriber: user, creator: creator })
                    subscription (get active subscription)
                    false
                ))
            )
        )
    )
)

;; Read-only functions
(define-read-only (get-content-info (content-id uint))
    (map-get? content-registry { content-id: content-id })
)

(define-read-only (get-creator-profile (creator principal))
    (map-get? creators { creator: creator })
)

(define-read-only (get-subscription (subscriber principal) (creator principal))
    (map-get? subscriptions { subscriber: subscriber, creator: creator })
)

(define-read-only (get-collaboration (content-id uint) (collaborator principal))
    (map-get? collaborations { content-id: content-id, collaborator: collaborator })
)

(define-read-only (get-platform-stats)
    {
        total-content: (var-get content-counter),
        total-creators: (var-get total-creators)
    }
)

(define-read-only (has-content-access (content-id uint) (user principal))
    (unwrap-panic (check-access content-id user))
)