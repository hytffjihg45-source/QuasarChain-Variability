;; relativistic-jet-analysis
;; Radio interferometry tracking supermassive black hole jet formation and propagation patterns
;; This contract manages jet observations, analyzes plasma dynamics, and tracks magnetic field evolution

;; constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u200))
(define-constant ERR_INVALID_JET (err u201))
(define-constant ERR_INVALID_INTERFEROMETER (err u202))
(define-constant ERR_INVALID_MEASUREMENT (err u203))
(define-constant ERR_INSUFFICIENT_BASELINES (err u204))
(define-constant MIN_BASELINE_LENGTH u1000) ;; 1km minimum baseline
(define-constant MAX_JET_VELOCITY u99) ;; 0.99c maximum velocity
(define-constant SPEED_OF_LIGHT u299792458) ;; m/s
(define-constant MIN_FREQUENCY u1000000000) ;; 1 GHz minimum

;; data vars
(define-data-var next-jet-id uint u1)
(define-data-var next-interferometer-id uint u1)
(define-data-var next-measurement-id uint u1)
(define-data-var total-measurements uint u0)
(define-data-var active-interferometers uint u0)

;; data maps
(define-map jets
    { jet-id: uint }
    {
        source-name: (string-ascii 64),
        host-galaxy: (string-ascii 64),
        ra: uint, ;; Right Ascension in milliarcseconds
        dec: int, ;; Declination in milliarcseconds
        distance: uint, ;; Distance in megaparsecs * 10
        black-hole-mass: uint, ;; Solar masses * 100
        accretion-rate: uint, ;; Eddington ratio * 1000
        jet-power: uint, ;; Power in 10^43 erg/s
        opening-angle: uint, ;; Degrees * 100
        is-active: bool,
        discovery-date: uint
    }
)

(define-map interferometers
    { interferometer-id: uint }
    {
        name: (string-ascii 32),
        operator: principal,
        location: (string-ascii 64),
        num-antennas: uint,
        max-baseline: uint, ;; in meters
        min-frequency: uint, ;; Hz
        max-frequency: uint, ;; Hz
        angular-resolution: uint, ;; microarcseconds
        sensitivity: uint, ;; mJy * 1000
        is-active: bool,
        commissioning-date: uint
    }
)

(define-map jet-measurements
    { measurement-id: uint }
    {
        jet-id: uint,
        interferometer-id: uint,
        observer: principal,
        observation-date: uint,
        frequency: uint, ;; Hz
        flux-density: uint, ;; mJy * 1000
        jet-length: uint, ;; parsecs * 100
        jet-width: uint, ;; parsecs * 100
        knot-position: uint, ;; parsecs * 100 from core
        knot-velocity: uint, ;; fraction of c * 100
        brightness-temperature: uint, ;; Kelvin in scientific notation
        polarization-fraction: uint, ;; percentage * 100
        magnetic-field-strength: uint, ;; Gauss * 1000
        doppler-factor: uint, ;; factor * 100
        is-validated: bool
    }
)

(define-map jet-evolution
    { jet-id: uint }
    {
        initial-velocity: uint,
        current-velocity: uint,
        max-velocity: uint,
        acceleration: int, ;; m/s^2 * 1000 (can be negative)
        expansion-rate: uint, ;; mas/year * 1000
        precession-period: uint, ;; years * 10
        activity-state: uint, ;; 0=dormant, 1=active, 2=super-active
        last-flare: uint,
        total-energy-output: uint ;; erg * 10^-40
    }
)

(define-map plasma-properties
    { jet-id: uint, measurement-id: uint }
    {
        electron-density: uint, ;; cm^-3 * 1000
        magnetic-field: uint, ;; Gauss * 1000
        plasma-beta: uint, ;; ratio * 1000
        lorentz-factor: uint, ;; factor * 100
        synchrotron-frequency: uint, ;; Hz
        inverse-compton-flux: uint, ;; mJy * 1000
        particle-energy: uint ;; GeV * 1000
    }
)

;; public functions
(define-public (register-interferometer (name (string-ascii 32))
                                       (location (string-ascii 64))
                                       (num-antennas uint)
                                       (max-baseline uint)
                                       (min-freq uint)
                                       (max-freq uint)
                                       (angular-res uint)
                                       (sensitivity uint))
    (let
        (
            (interferometer-id (var-get next-interferometer-id))
        )
        (asserts! (>= max-baseline MIN_BASELINE_LENGTH) ERR_INSUFFICIENT_BASELINES)
        (asserts! (>= min-freq MIN_FREQUENCY) ERR_INVALID_INTERFEROMETER)
        
        (map-set interferometers
            { interferometer-id: interferometer-id }
            {
                name: name,
                operator: tx-sender,
                location: location,
                num-antennas: num-antennas,
                max-baseline: max-baseline,
                min-frequency: min-freq,
                max-frequency: max-freq,
                angular-resolution: angular-res,
                sensitivity: sensitivity,
                is-active: true,
                commissioning-date: burn-block-height
            }
        )
        
        (var-set next-interferometer-id (+ interferometer-id u1))
        (var-set active-interferometers (+ (var-get active-interferometers) u1))
        (ok interferometer-id)
    )
)

(define-public (register-jet (source-name (string-ascii 64))
                            (host-galaxy (string-ascii 64))
                            (ra uint)
                            (dec int)
                            (distance uint)
                            (bh-mass uint)
                            (accretion-rate uint)
                            (opening-angle uint))
    (let
        (
            (jet-id (var-get next-jet-id))
        )
        (map-set jets
            { jet-id: jet-id }
            {
                source-name: source-name,
                host-galaxy: host-galaxy,
                ra: ra,
                dec: dec,
                distance: distance,
                black-hole-mass: bh-mass,
                accretion-rate: accretion-rate,
                jet-power: u0,
                opening-angle: opening-angle,
                is-active: true,
                discovery-date: burn-block-height
            }
        )
        
        (map-set jet-evolution
            { jet-id: jet-id }
            {
                initial-velocity: u0,
                current-velocity: u0,
                max-velocity: u0,
                acceleration: 0,
                expansion-rate: u0,
                precession-period: u0,
                activity-state: u0,
                last-flare: u0,
                total-energy-output: u0
            }
        )
        
        (var-set next-jet-id (+ jet-id u1))
        (ok jet-id)
    )
)

(define-public (submit-jet-measurement (jet-id uint)
                                      (interferometer-id uint)
                                      (frequency uint)
                                      (flux-density uint)
                                      (jet-length uint)
                                      (jet-width uint)
                                      (knot-position uint)
                                      (knot-velocity uint)
                                      (brightness-temp uint)
                                      (polarization uint)
                                      (magnetic-field uint))
    (let
        (
            (measurement-id (var-get next-measurement-id))
            (interferometer (unwrap! (map-get? interferometers { interferometer-id: interferometer-id }) ERR_INVALID_INTERFEROMETER))
            (jet (unwrap! (map-get? jets { jet-id: jet-id }) ERR_INVALID_JET))
            (doppler-factor (calculate-doppler-factor knot-velocity))
        )
        (asserts! (is-eq (get operator interferometer) tx-sender) ERR_UNAUTHORIZED)
        (asserts! (get is-active interferometer) ERR_INVALID_INTERFEROMETER)
        (asserts! (get is-active jet) ERR_INVALID_JET)
        (asserts! (<= knot-velocity MAX_JET_VELOCITY) ERR_INVALID_MEASUREMENT)
        
        (map-set jet-measurements
            { measurement-id: measurement-id }
            {
                jet-id: jet-id,
                interferometer-id: interferometer-id,
                observer: tx-sender,
                observation-date: burn-block-height,
                frequency: frequency,
                flux-density: flux-density,
                jet-length: jet-length,
                jet-width: jet-width,
                knot-position: knot-position,
                knot-velocity: knot-velocity,
                brightness-temperature: brightness-temp,
                polarization-fraction: polarization,
                magnetic-field-strength: magnetic-field,
                doppler-factor: doppler-factor,
                is-validated: false
            }
        )
        
        ;; Calculate and store plasma properties
        (calculate-plasma-properties jet-id measurement-id knot-velocity magnetic-field brightness-temp)
        
        ;; Update jet evolution tracking
        (update-jet-evolution jet-id knot-velocity)
        
        (var-set next-measurement-id (+ measurement-id u1))
        (var-set total-measurements (+ (var-get total-measurements) u1))
        
        (ok measurement-id)
    )
)

(define-public (validate-measurement (measurement-id uint) (is-valid bool))
    (let
        (
            (measurement (unwrap! (map-get? jet-measurements { measurement-id: measurement-id }) ERR_INVALID_MEASUREMENT))
        )
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        
        (map-set jet-measurements
            { measurement-id: measurement-id }
            (merge measurement { is-validated: is-valid })
        )
        
        (ok true)
    )
)

;; read only functions
(define-read-only (get-jet (jet-id uint))
    (map-get? jets { jet-id: jet-id })
)

(define-read-only (get-interferometer (interferometer-id uint))
    (map-get? interferometers { interferometer-id: interferometer-id })
)

(define-read-only (get-measurement (measurement-id uint))
    (map-get? jet-measurements { measurement-id: measurement-id })
)

(define-read-only (get-jet-evolution (jet-id uint))
    (map-get? jet-evolution { jet-id: jet-id })
)

(define-read-only (get-plasma-properties (jet-id uint) (measurement-id uint))
    (map-get? plasma-properties { jet-id: jet-id, measurement-id: measurement-id })
)

(define-read-only (get-total-measurements)
    (var-get total-measurements)
)

(define-read-only (get-active-interferometers)
    (var-get active-interferometers)
)

(define-read-only (get-next-ids)
    {
        next-jet-id: (var-get next-jet-id),
        next-interferometer-id: (var-get next-interferometer-id),
        next-measurement-id: (var-get next-measurement-id)
    }
)

;; private functions
(define-private (calculate-doppler-factor (velocity uint))
    (let
        (
            (beta (/ velocity u100)) ;; velocity as fraction of c
            (gamma (/ u100 (pow (- u100 (* beta beta)) u50))) ;; Lorentz factor approximation
        )
        (* gamma (+ u100 beta)) ;; Simplified Doppler factor
    )
)

(define-private (calculate-plasma-properties (jet-id uint) (measurement-id uint) (velocity uint) (b-field uint) (temp uint))
    (let
        (
            (lorentz-factor (/ u100 (pow (- u10000 (* velocity velocity)) u50)))
            (electron-density (/ (* temp u1000) (* b-field b-field)))
            (plasma-beta (/ (* u2000 temp) (* b-field b-field)))
            (synch-freq (/ (* b-field b-field) u1000000))
        )
        
        (map-set plasma-properties
            { jet-id: jet-id, measurement-id: measurement-id }
            {
                electron-density: electron-density,
                magnetic-field: b-field,
                plasma-beta: plasma-beta,
                lorentz-factor: lorentz-factor,
                synchrotron-frequency: synch-freq,
                inverse-compton-flux: (/ (* temp u100) u1000),
                particle-energy: (* lorentz-factor u511) ;; electron rest mass energy
            }
        )
    )
)

(define-private (update-jet-evolution (jet-id uint) (new-velocity uint))
    (match (map-get? jet-evolution { jet-id: jet-id })
        current-evolution
        (let
            (
                (current-vel (get current-velocity current-evolution))
                (max-vel (get max-velocity current-evolution))
                (new-max (if (> new-velocity max-vel) new-velocity max-vel))
                (acceleration (if (> current-vel u0) (to-int (- new-velocity current-vel)) 0))
                (activity-level (if (> new-velocity u80) u2 (if (> new-velocity u50) u1 u0)))
            )
            
            (map-set jet-evolution
                { jet-id: jet-id }
                {
                    initial-velocity: (if (is-eq (get initial-velocity current-evolution) u0) new-velocity (get initial-velocity current-evolution)),
                    current-velocity: new-velocity,
                    max-velocity: new-max,
                    acceleration: acceleration,
                    expansion-rate: (get expansion-rate current-evolution),
                    precession-period: (get precession-period current-evolution),
                    activity-state: activity-level,
                    last-flare: (if (> activity-level u1) burn-block-height (get last-flare current-evolution)),
                    total-energy-output: (+ (get total-energy-output current-evolution) (* new-velocity u1000))
                }
            )
        )
        false ;; do nothing if jet evolution not found
    )
)

