;; quasar-luminosity-tracking
;; Multi-wavelength telescope arrays monitoring quasar brightness variations across electromagnetic spectrum
;; This contract manages quasar observations, validates data quality, and tracks luminosity patterns

;; constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INVALID_QUASAR (err u101))
(define-constant ERR_INVALID_OBSERVATION (err u102))
(define-constant ERR_TELESCOPE_NOT_REGISTERED (err u103))
(define-constant ERR_INSUFFICIENT_STAKE (err u104))
(define-constant MIN_STAKE_AMOUNT u1000000) ;; 1 STX in microSTX
(define-constant MAX_MAGNITUDE_CHANGE u500) ;; 5.00 magnitude change limit
(define-constant QUALITY_THRESHOLD u80) ;; 80% minimum quality score

;; data vars
(define-data-var next-quasar-id uint u1)
(define-data-var next-telescope-id uint u1)
(define-data-var next-observation-id uint u1)
(define-data-var total-observations uint u0)
(define-data-var active-telescopes uint u0)

;; data maps
(define-map quasars
    { quasar-id: uint }
    {
        name: (string-ascii 64),
        ra: uint, ;; Right Ascension in milliarcseconds
        dec: int, ;; Declination in milliarcseconds
        redshift: uint, ;; Redshift * 1000 for precision
        baseline-magnitude: uint, ;; Magnitude * 100 for precision
        last-observation: uint,
        total-observations: uint,
        is-active: bool
    }
)

(define-map telescopes
    { telescope-id: uint }
    {
        name: (string-ascii 32),
        operator: principal,
        location: (string-ascii 64),
        wavelength-range: (string-ascii 32),
        aperture-size: uint, ;; in centimeters
        stake-amount: uint,
        quality-score: uint, ;; percentage
        total-observations: uint,
        is-active: bool,
        registered-at: uint
    }
)

(define-map observations
    { observation-id: uint }
    {
        quasar-id: uint,
        telescope-id: uint,
        observer: principal,
        timestamp: uint,
        magnitude: uint, ;; Magnitude * 100 for precision
        wavelength: uint, ;; Wavelength in Angstroms
        exposure-time: uint, ;; in seconds
        seeing: uint, ;; Seeing in milliarcseconds
        airmass: uint, ;; Airmass * 100 for precision
        quality-flags: uint, ;; Bitmask for quality indicators
        is-validated: bool,
        validation-score: uint
    }
)

(define-map telescope-operators
    { operator: principal }
    { telescope-ids: (list 10 uint) }
)

(define-map quasar-variability
    { quasar-id: uint }
    {
        min-magnitude: uint,
        max-magnitude: uint,
        mean-magnitude: uint,
        rms-variability: uint, ;; RMS * 1000 for precision
        last-flare-time: uint,
        variability-class: uint ;; 0=stable, 1=variable, 2=highly-variable
    }
)

;; public functions
(define-public (register-telescope (name (string-ascii 32)) 
                                  (location (string-ascii 64))
                                  (wavelength-range (string-ascii 32))
                                  (aperture-size uint))
    (let
        (
            (telescope-id (var-get next-telescope-id))
            (stake-amount (stx-get-balance tx-sender))
        )
        (asserts! (>= stake-amount MIN_STAKE_AMOUNT) ERR_INSUFFICIENT_STAKE)
        (try! (stx-transfer? MIN_STAKE_AMOUNT tx-sender (as-contract tx-sender)))
        
        (map-set telescopes
            { telescope-id: telescope-id }
            {
                name: name,
                operator: tx-sender,
                location: location,
                wavelength-range: wavelength-range,
                aperture-size: aperture-size,
                stake-amount: MIN_STAKE_AMOUNT,
                quality-score: u100,
                total-observations: u0,
                is-active: true,
                registered-at: burn-block-height
            }
        )
        
        (var-set next-telescope-id (+ telescope-id u1))
        (var-set active-telescopes (+ (var-get active-telescopes) u1))
        (ok telescope-id)
    )
)

(define-public (register-quasar (name (string-ascii 64))
                               (ra uint)
                               (dec int)
                               (redshift uint)
                               (baseline-magnitude uint))
    (let
        (
            (quasar-id (var-get next-quasar-id))
        )
        (map-set quasars
            { quasar-id: quasar-id }
            {
                name: name,
                ra: ra,
                dec: dec,
                redshift: redshift,
                baseline-magnitude: baseline-magnitude,
                last-observation: u0,
                total-observations: u0,
                is-active: true
            }
        )
        
        (map-set quasar-variability
            { quasar-id: quasar-id }
            {
                min-magnitude: baseline-magnitude,
                max-magnitude: baseline-magnitude,
                mean-magnitude: baseline-magnitude,
                rms-variability: u0,
                last-flare-time: u0,
                variability-class: u0
            }
        )
        
        (var-set next-quasar-id (+ quasar-id u1))
        (ok quasar-id)
    )
)

(define-public (submit-observation (quasar-id uint)
                                  (telescope-id uint)
                                  (magnitude uint)
                                  (wavelength uint)
                                  (exposure-time uint)
                                  (seeing uint)
                                  (airmass uint))
    (let
        (
            (observation-id (var-get next-observation-id))
            (telescope (unwrap! (map-get? telescopes { telescope-id: telescope-id }) ERR_TELESCOPE_NOT_REGISTERED))
            (quasar (unwrap! (map-get? quasars { quasar-id: quasar-id }) ERR_INVALID_QUASAR))
            (quality-score (calculate-observation-quality seeing airmass exposure-time))
        )
        (asserts! (is-eq (get operator telescope) tx-sender) ERR_UNAUTHORIZED)
        (asserts! (get is-active telescope) ERR_TELESCOPE_NOT_REGISTERED)
        (asserts! (get is-active quasar) ERR_INVALID_QUASAR)
        
        (map-set observations
            { observation-id: observation-id }
            {
                quasar-id: quasar-id,
                telescope-id: telescope-id,
                observer: tx-sender,
                timestamp: burn-block-height,
                magnitude: magnitude,
                wavelength: wavelength,
                exposure-time: exposure-time,
                seeing: seeing,
                airmass: airmass,
                quality-flags: u0,
                is-validated: false,
                validation-score: quality-score
            }
        )
        
        ;; Update counters
        (var-set next-observation-id (+ observation-id u1))
        (var-set total-observations (+ (var-get total-observations) u1))
        
        ;; Update telescope stats
        (map-set telescopes
            { telescope-id: telescope-id }
            (merge telescope { total-observations: (+ (get total-observations telescope) u1) })
        )
        
        ;; Update quasar stats and check for variability
        (try! (update-quasar-variability quasar-id magnitude))
        
        (ok observation-id)
    )
)

(define-public (validate-observation (observation-id uint) (is-valid bool))
    (let
        (
            (observation (unwrap! (map-get? observations { observation-id: observation-id }) ERR_INVALID_OBSERVATION))
        )
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        
        (map-set observations
            { observation-id: observation-id }
            (merge observation { is-validated: is-valid })
        )
        
        (ok true)
    )
)

;; read only functions
(define-read-only (get-quasar (quasar-id uint))
    (map-get? quasars { quasar-id: quasar-id })
)

(define-read-only (get-telescope (telescope-id uint))
    (map-get? telescopes { telescope-id: telescope-id })
)

(define-read-only (get-observation (observation-id uint))
    (map-get? observations { observation-id: observation-id })
)

(define-read-only (get-quasar-variability (quasar-id uint))
    (map-get? quasar-variability { quasar-id: quasar-id })
)

(define-read-only (get-total-observations)
    (var-get total-observations)
)

(define-read-only (get-active-telescopes)
    (var-get active-telescopes)
)

(define-read-only (get-next-ids)
    {
        next-quasar-id: (var-get next-quasar-id),
        next-telescope-id: (var-get next-telescope-id),
        next-observation-id: (var-get next-observation-id)
    }
)

;; private functions
(define-private (calculate-observation-quality (seeing uint) (airmass uint) (exposure-time uint))
    (let
        (
            (seeing-score (if (<= seeing u1000) u40 u20)) ;; Good seeing < 1 arcsec
            (airmass-score (if (<= airmass u150) u30 u15)) ;; Good airmass < 1.5
            (exposure-score (if (>= exposure-time u300) u30 u15)) ;; Good exposure >= 5 min
        )
        (+ seeing-score airmass-score exposure-score)
    )
)

(define-private (update-quasar-variability (quasar-id uint) (new-magnitude uint))
    (let
        (
            (current-var (unwrap! (map-get? quasar-variability { quasar-id: quasar-id }) ERR_INVALID_QUASAR))
            (quasar (unwrap! (map-get? quasars { quasar-id: quasar-id }) ERR_INVALID_QUASAR))
            (new-min (if (< new-magnitude (get min-magnitude current-var)) new-magnitude (get min-magnitude current-var)))
            (new-max (if (> new-magnitude (get max-magnitude current-var)) new-magnitude (get max-magnitude current-var)))
            (magnitude-range (- new-max new-min))
            (variability-class (if (> magnitude-range u200) u2 (if (> magnitude-range u50) u1 u0)))
        )
        
        (map-set quasar-variability
            { quasar-id: quasar-id }
            {
                min-magnitude: new-min,
                max-magnitude: new-max,
                mean-magnitude: (/ (+ new-min new-max) u2),
                rms-variability: magnitude-range,
                last-flare-time: (if (> magnitude-range u100) burn-block-height (get last-flare-time current-var)),
                variability-class: variability-class
            }
        )
        
        (map-set quasars
            { quasar-id: quasar-id }
            (merge quasar { 
                last-observation: burn-block-height,
                total-observations: (+ (get total-observations quasar) u1)
            })
        )
        
        (ok true)
    )
)

