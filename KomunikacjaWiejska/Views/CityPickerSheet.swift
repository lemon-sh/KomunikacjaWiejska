import SwiftUI

struct CityPickerSheet: View {
    let selectedCity: City
    let onSelect: (City) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""

    private var filteredCities: [City] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? City.allCities : City.allCities.filter { $0.matches(searchText: query) }
    }

    var body: some View {
        NavigationStack {
            List(filteredCities) { city in
                Button {
                    onSelect(city)
                    dismiss()
                } label: {
                    HStack {
                        Text(city.name)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)

                        Spacer()

                        if city.id == selectedCity.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                                .fontWeight(.semibold)
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(city.id == selectedCity.id ? .isSelected : [])
            }
            .searchable(text: $searchText, prompt: Text("cityPicker.searchPrompt"))
            .navigationTitle("cityPicker.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("cityPicker.done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
