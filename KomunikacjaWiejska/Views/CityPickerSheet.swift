import SwiftUI

public struct CityPickerSheet: View {
    @Binding public var selectedCity: City
    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""

    public init(selectedCity: Binding<City>) {
        self._selectedCity = selectedCity
    }

    private var filteredCities: [City] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return City.allCities
        }
        return City.allCities.filter { $0.matches(searchText: searchText) }
    }

    public var body: some View {
        NavigationStack {
            List(filteredCities) { city in
                Button {
                    selectedCity = city
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(city.name)
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                            Text(city.id)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

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
