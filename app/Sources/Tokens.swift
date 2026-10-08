enum Tokens {
    static let poseFPS = 12
    static let springResponse = 0.35
    static let springDamping = 0.7
    static let anticipation = 0.2
    static let settle = 0.3
}

/// FrameClock still reads this name. The value lives on `Tokens`.
let poseFPS = Tokens.poseFPS
let springResponse = Tokens.springResponse
let springDamping = Tokens.springDamping
