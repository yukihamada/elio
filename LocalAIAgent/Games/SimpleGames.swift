import SwiftUI

/// Simple Games - Offline games for mental care and entertainment
/// Includes Solitaire, Memory Match, and Number Puzzle

// MARK: - Game Selection View

struct SimpleGamesView: View {
    @State private var selectedGame: GameType?

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 16) {
                    GameCard(
                        game: .solitaire,
                        icon: "suit.spade.fill",
                        color: .red
                    ) {
                        selectedGame = .solitaire
                    }

                    GameCard(
                        game: .memoryMatch,
                        icon: "brain.head.profile",
                        color: .blue
                    ) {
                        selectedGame = .memoryMatch
                    }

                    GameCard(
                        game: .numberPuzzle,
                        icon: "number.square",
                        color: .green
                    ) {
                        selectedGame = .numberPuzzle
                    }

                    GameCard(
                        game: .ticTacToe,
                        icon: "xmark.square",
                        color: .orange
                    ) {
                        selectedGame = .ticTacToe
                    }
                }
                .padding()
            }
            .navigationTitle("ゲーム")
            .sheet(item: $selectedGame) { game in
                gameView(for: game)
            }
        }
    }

    @ViewBuilder
    private func gameView(for game: GameType) -> some View {
        switch game {
        case .solitaire:
            SolitaireGame()
        case .memoryMatch:
            MemoryMatchGame()
        case .numberPuzzle:
            NumberPuzzleGame()
        case .ticTacToe:
            TicTacToeGame()
        }
    }
}

struct GameCard: View {
    let game: GameType
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 50))
                    .foregroundStyle(color)

                Text(game.displayName)
                    .font(.headline)

                Text(game.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

enum GameType: String, Identifiable {
    case solitaire, memoryMatch, numberPuzzle, ticTacToe

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .solitaire: return "ソリティア"
        case .memoryMatch: return "神経衰弱"
        case .numberPuzzle: return "数字パズル"
        case .ticTacToe: return "三目並べ"
        }
    }

    var description: String {
        switch self {
        case .solitaire: return "クラシックなカードゲーム"
        case .memoryMatch: return "記憶力を鍛える"
        case .numberPuzzle: return "数字を並べ替える"
        case .ticTacToe: return "AIと対戦"
        }
    }
}

// MARK: - Solitaire (Simple Version)

struct SolitaireGame: View {
    @Environment(\.dismiss) private var dismiss
    @State private var deck: [PlayingCard] = []
    @State private var tableau: [[PlayingCard]] = Array(repeating: [], count: 7)
    @State private var foundation: [[PlayingCard]] = Array(repeating: [], count: 4)
    @State private var waste: [PlayingCard] = []
    @State private var selectedCard: PlayingCard?
    @State private var moves: Int = 0

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Header
                HStack {
                    Text("手数: \(moves)")
                        .font(.headline)

                    Spacer()

                    Button("新しいゲーム") {
                        setupGame()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)

                // Foundation (目標)
                HStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { index in
                        foundationPile(index: index)
                    }
                }
                .padding(.horizontal)

                // Tableau (場札)
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(0..<7, id: \.self) { index in
                            tableauPile(index: index)
                        }
                    }
                    .padding(.horizontal)
                }

                Spacer()
            }
            .navigationTitle("ソリティア")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                setupGame()
            }
        }
    }

    private func foundationPile(index: Int) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray, lineWidth: 2)
                .frame(width: 60, height: 90)

            if let topCard = foundation[index].last {
                CardView(card: topCard)
            }
        }
    }

    private func tableauPile(index: Int) -> some View {
        VStack(spacing: -60) {
            if tableau[index].isEmpty {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray, lineWidth: 2)
                    .frame(width: 60, height: 90)
            } else {
                ForEach(tableau[index]) { card in
                    CardView(card: card)
                        .onTapGesture {
                            cardTapped(card, from: index)
                        }
                }
            }
        }
        .frame(minHeight: 90)
    }

    private func setupGame() {
        // Create standard 52-card deck
        deck = PlayingCard.standardDeck().shuffled()
        tableau = Array(repeating: [], count: 7)
        foundation = Array(repeating: [], count: 4)
        waste = []
        moves = 0

        // Deal to tableau
        var deckIndex = 0
        for i in 0..<7 {
            for j in i..<7 {
                var card = deck[deckIndex]
                card.isFaceUp = (i == j)
                tableau[j].append(card)
                deckIndex += 1
            }
        }
    }

    private func cardTapped(_ card: PlayingCard, from pileIndex: Int) {
        moves += 1
        // Simplified move logic
        if canMoveToFoundation(card) {
            moveToFoundation(card, from: pileIndex)
        }
    }

    private func canMoveToFoundation(_ card: PlayingCard) -> Bool {
        // Check if card can move to foundation
        guard let suitIndex = foundation.firstIndex(where: { $0.isEmpty || $0.last?.suit == card.suit }) else {
            return false
        }

        if foundation[suitIndex].isEmpty {
            return card.rank == .ace
        } else if let topCard = foundation[suitIndex].last {
            return card.rank.rawValue == topCard.rank.rawValue + 1
        }

        return false
    }

    private func moveToFoundation(_ card: PlayingCard, from pileIndex: Int) {
        guard let suitIndex = foundation.firstIndex(where: { $0.isEmpty || $0.last?.suit == card.suit }) else {
            return
        }

        if let cardIndex = tableau[pileIndex].firstIndex(of: card) {
            tableau[pileIndex].remove(at: cardIndex)
            foundation[suitIndex].append(card)
        }
    }
}

// MARK: - Playing Card

struct PlayingCard: Identifiable, Equatable {
    let id = UUID()
    let suit: Suit
    let rank: Rank
    var isFaceUp: Bool = true

    enum Suit: String, CaseIterable {
        case spades = "♠️"
        case hearts = "♥️"
        case diamonds = "♦️"
        case clubs = "♣️"

        var color: Color {
            switch self {
            case .hearts, .diamonds: return .red
            case .spades, .clubs: return .black
            }
        }
    }

    enum Rank: Int, CaseIterable {
        case ace = 1, two, three, four, five, six, seven
        case eight, nine, ten, jack, queen, king

        var displayValue: String {
            switch self {
            case .ace: return "A"
            case .jack: return "J"
            case .queen: return "Q"
            case .king: return "K"
            default: return "\(rawValue)"
            }
        }
    }

    static func standardDeck() -> [PlayingCard] {
        var deck: [PlayingCard] = []
        for suit in Suit.allCases {
            for rank in Rank.allCases {
                deck.append(PlayingCard(suit: suit, rank: rank))
            }
        }
        return deck
    }
}

struct CardView: View {
    let card: PlayingCard

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(.white)
                .frame(width: 60, height: 90)
                .shadow(radius: 2)

            if card.isFaceUp {
                VStack(spacing: 4) {
                    Text(card.suit.rawValue)
                        .font(.title2)
                    Text(card.rank.displayValue)
                        .font(.headline)
                }
                .foregroundStyle(card.suit.color)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue)
            }
        }
        .frame(width: 60, height: 90)
    }
}

// MARK: - Memory Match Game

struct MemoryMatchGame: View {
    @Environment(\.dismiss) private var dismiss
    @State private var cards: [MemoryCard] = []
    @State private var flippedIndices: Set<Int> = []
    @State private var matchedPairs: Set<Int> = []
    @State private var moves: Int = 0
    @State private var isProcessing = false

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                HStack {
                    Text("手数: \(moves)")
                    Spacer()
                    Text("ペア: \(matchedPairs.count / 2) / 8")
                }
                .font(.headline)
                .padding(.horizontal)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                    ForEach(cards.indices, id: \.self) { index in
                        MemoryCardView(
                            card: cards[index],
                            isFlipped: flippedIndices.contains(index) || matchedPairs.contains(index)
                        )
                        .onTapGesture {
                            cardTapped(at: index)
                        }
                    }
                }
                .padding()

                if matchedPairs.count == cards.count {
                    VStack {
                        Text("🎉 クリア！")
                            .font(.title.bold())
                        Text("\(moves)手でクリアしました")
                            .font(.subheadline)
                        Button("もう一度") {
                            setupGame()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                Spacer()
            }
            .navigationTitle("神経衰弱")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("リセット") { setupGame() }
                }
            }
            .onAppear { setupGame() }
        }
    }

    private func setupGame() {
        let symbols = ["🍎", "🍊", "🍋", "🍌", "🍉", "🍇", "🍓", "🍒"]
        var newCards: [MemoryCard] = []
        for symbol in symbols {
            newCards.append(MemoryCard(symbol: symbol))
            newCards.append(MemoryCard(symbol: symbol))
        }
        cards = newCards.shuffled()
        flippedIndices = []
        matchedPairs = []
        moves = 0
    }

    private func cardTapped(at index: Int) {
        guard !isProcessing,
              !matchedPairs.contains(index),
              !flippedIndices.contains(index),
              flippedIndices.count < 2 else {
            return
        }

        flippedIndices.insert(index)

        if flippedIndices.count == 2 {
            moves += 1
            isProcessing = true

            let indices = Array(flippedIndices)
            if cards[indices[0]].symbol == cards[indices[1]].symbol {
                // Match found
                matchedPairs.insert(indices[0])
                matchedPairs.insert(indices[1])
                flippedIndices = []
                isProcessing = false
            } else {
                // No match, flip back after delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    flippedIndices = []
                    isProcessing = false
                }
            }
        }
    }
}

struct MemoryCard: Identifiable {
    let id = UUID()
    let symbol: String
}

struct MemoryCardView: View {
    let card: MemoryCard
    let isFlipped: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(isFlipped ? Color.white : Color.blue)
                .frame(height: 80)
                .shadow(radius: 2)

            if isFlipped {
                Text(card.symbol)
                    .font(.system(size: 40))
            } else {
                Text("?")
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - Number Puzzle (15 Puzzle)

struct NumberPuzzleGame: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tiles: [Int] = Array(1...15) + [0]
    @State private var moves: Int = 0

    let gridSize = 4

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("手数: \(moves)")
                    .font(.headline)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: gridSize), spacing: 8) {
                    ForEach(tiles.indices, id: \.self) { index in
                        if tiles[index] != 0 {
                            Button(action: { moveTile(at: index) }) {
                                Text("\(tiles[index])")
                                    .font(.title.bold())
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .aspectRatio(1, contentMode: .fit)
                                    .background(Color.blue)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        } else {
                            Color.clear
                                .aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
                .padding()

                if isSolved() {
                    VStack {
                        Text("🎉 クリア！")
                            .font(.title.bold())
                        Button("もう一度") {
                            setupGame()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                Spacer()
            }
            .navigationTitle("数字パズル")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("シャッフル") { setupGame() }
                }
            }
            .onAppear { setupGame() }
        }
    }

    private func setupGame() {
        tiles = (Array(1...15) + [0]).shuffled()
        moves = 0
    }

    private func moveTile(at index: Int) {
        guard let emptyIndex = tiles.firstIndex(of: 0) else { return }

        let emptyRow = emptyIndex / gridSize
        let emptyCol = emptyIndex % gridSize
        let tileRow = index / gridSize
        let tileCol = index % gridSize

        // Check if tile is adjacent to empty space
        if (abs(emptyRow - tileRow) == 1 && emptyCol == tileCol) ||
           (abs(emptyCol - tileCol) == 1 && emptyRow == tileRow) {
            tiles.swapAt(index, emptyIndex)
            moves += 1
        }
    }

    private func isSolved() -> Bool {
        return tiles == Array(1...15) + [0]
    }
}

// MARK: - Tic Tac Toe

struct TicTacToeGame: View {
    @Environment(\.dismiss) private var dismiss
    @State private var board: [Player?] = Array(repeating: nil, count: 9)
    @State private var currentPlayer: Player = .human
    @State private var gameState: GameState = .ongoing
    @State private var humanScore: Int = 0
    @State private var aiScore: Int = 0

    enum Player: String {
        case human = "⭕️"
        case ai = "❌"
    }

    enum GameState {
        case ongoing, humanWin, aiWin, draw
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                HStack(spacing: 40) {
                    VStack {
                        Text("あなた")
                            .font(.headline)
                        Text("\(humanScore)")
                            .font(.title.bold())
                            .foregroundStyle(.blue)
                    }

                    Text("VS")
                        .font(.title3.bold())
                        .foregroundStyle(.secondary)

                    VStack {
                        Text("AI")
                            .font(.headline)
                        Text("\(aiScore)")
                            .font(.title.bold())
                            .foregroundStyle(.red)
                    }
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                    ForEach(0..<9, id: \.self) { index in
                        Button(action: { makeMove(at: index) }) {
                            Text(board[index]?.rawValue ?? "")
                                .font(.system(size: 50))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .aspectRatio(1, contentMode: .fit)
                                .background(Color(.systemGray6))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(board[index] != nil || gameState != .ongoing)
                    }
                }
                .padding()

                if gameState != .ongoing {
                    VStack(spacing: 12) {
                        Text(resultMessage)
                            .font(.title2.bold())

                        Button("もう一度") {
                            resetGame()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                Spacer()
            }
            .navigationTitle("三目並べ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private var resultMessage: String {
        switch gameState {
        case .humanWin: return "🎉 あなたの勝ち！"
        case .aiWin: return "😔 AIの勝ち"
        case .draw: return "引き分け"
        case .ongoing: return ""
        }
    }

    private func makeMove(at index: Int) {
        guard board[index] == nil, gameState == .ongoing else { return }

        board[index] = .human
        checkGameState()

        if gameState == .ongoing {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                makeAIMove()
            }
        }
    }

    private func makeAIMove() {
        // Simple AI: random valid move
        let availableIndices = board.indices.filter { board[$0] == nil }
        guard let randomIndex = availableIndices.randomElement() else { return }

        board[randomIndex] = .ai
        checkGameState()
    }

    private func checkGameState() {
        let winPatterns: [[Int]] = [
            [0, 1, 2], [3, 4, 5], [6, 7, 8], // Rows
            [0, 3, 6], [1, 4, 7], [2, 5, 8], // Columns
            [0, 4, 8], [2, 4, 6]             // Diagonals
        ]

        for pattern in winPatterns {
            let values = pattern.map { board[$0] }
            if values.allSatisfy({ $0 == .human }) {
                gameState = .humanWin
                humanScore += 1
                return
            }
            if values.allSatisfy({ $0 == .ai }) {
                gameState = .aiWin
                aiScore += 1
                return
            }
        }

        if board.allSatisfy({ $0 != nil }) {
            gameState = .draw
        }
    }

    private func resetGame() {
        board = Array(repeating: nil, count: 9)
        currentPlayer = .human
        gameState = .ongoing
    }
}

#Preview {
    SimpleGamesView()
}
