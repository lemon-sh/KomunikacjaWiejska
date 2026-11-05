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
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $searchText, prompt: "Szukaj miasta...")
            .navigationTitle("Wybierz miasto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Gotowe") {
                        dismiss()
                    }
                }
            }
        }
    }
}
