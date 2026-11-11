import SwiftUI

/// Searchable city switcher over non-virtual transit networks.

struct CityPickerSheet: View {
    let cities: [City]
    let selectedCity: City?
    let onSelect: (City) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    init(
        cities: [City],
        selectedCity: City?,
        onSelect: @escaping (City) -> Void
    ) {
        self.cities = cities
        self.selectedCity = selectedCity
        self.onSelect = onSelect
    }

    private var filteredCities: [City] {
        query.isEmpty ? cities : cities.filter { $0.matches(searchText: query) }
    }

    var body: some View {
        NavigationStack {
            List(filteredCities) { city in
                Button {
                    onSelect(city)
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(city.name)
                                .foregroundStyle(.primary)
                            if let description = city.description, !description.isEmpty {
                                Text(description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer()

                        if city.id == selectedCity?.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                                .fontWeight(.semibold)
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(city.id == selectedCity?.id ? .isSelected : [])
            }
            .searchable(text: $query, prompt: "cityPicker.searchPrompt")
            .navigationTitle("cityPicker.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("cityPicker.done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
