import SwiftUI

struct CityPickerSheet: View {
    private let selectedCity: City
    private let onSelect: (City) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""

    init(selectedCity: City, onSelect: @escaping (City) -> Void) {
        self.selectedCity = selectedCity
        self.onSelect = onSelect
    }

    init(selectedCity: Binding<City>) {
        self.selectedCity = selectedCity.wrappedValue
        self.onSelect = { selectedCity.wrappedValue = $0 }
    }

    private var filteredCities: [City] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return City.allCities
        }
        return City.allCities.filter { $0.matches(searchText: searchText) }
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
