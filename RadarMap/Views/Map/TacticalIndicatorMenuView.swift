import SwiftUI

public struct TacticalIndicatorMenuView: View {
    @EnvironmentObject var gameState: GameStateManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedCategory: TacticalIndicatorCategory? = nil
    
    public init() {}
    
    private var themeColor: Color {
        gameState.radarColorTheme.color
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                if let category = selectedCategory {
                    // Level 2: Specific Indicator Options
                    indicatorOptionsList(for: category)
                } else {
                    // Level 1: Category Selection
                    categorySelectionList
                }
            }
            .navigationTitle(selectedCategory?.title ?? "Tactical Tree")
            #if os(watchOS) || os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: {
                        if selectedCategory != nil {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedCategory = nil
                            }
                        } else {
                            dismiss()
                        }
                    }) {
                        if selectedCategory != nil {
                            HStack(spacing: 3) {
                                Image(systemName: "chevron.left")
                                Text("Back")
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(themeColor)
                        } else {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Level 1: Categories
    
    private var categorySelectionList: some View {
        VStack(spacing: 8) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedCategory = .squadOrder
                }
            }) {
                HStack {
                    Text("Team Orders")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.08))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(themeColor.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedCategory = .enemyIndicator
                }
            }) {
                HStack {
                    Text("Tac Indicators")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.08))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(themeColor.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
    }
    
    // MARK: - Level 2: Specific Indicators
    
    private func indicatorOptionsList(for category: TacticalIndicatorCategory) -> some View {
        let types: [TacticalIndicatorType] = category == .squadOrder
            ? [.watchHere, .goHere, .attackHere, .protectHere]
            : [.infantry, .lightVehicle, .heavyVehicle]
        
        return ScrollView {
            VStack(spacing: 6) {
                ForEach(types) { type in
                    Button(action: {
                        gameState.selectIndicatorForPlacement(type)
                    }) {
                        HStack {
                            Text(type.title)
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                            
                            Spacer()
                            
                            TacticalIndicatorIcon(type: type, size: 16)
                                .foregroundColor(themeColor)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(themeColor.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
        }
    }
}
