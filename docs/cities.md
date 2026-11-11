# Cities & Transit Networks Catalog

**KomunikacjaWiejska** loads its transit network catalog exclusively at runtime from `GET https://api.zbiorkom.live/api6` (including each network's `id`, `name`, `description`, `category`, `location`, `timezone`, `zoom`, `virtual` flag, and `agencies`), with no bundled offline city catalog.

- Before `GET /api6` resolves on first launch (when no saved city or camera exists), the map frames `MapConstants.defaultCenterLatitude` / `defaultCenterLongitude` (`52.2297, 21.0122`) and requests `MapConstants.defaultCityID` (`"warsaw"`). Once the live catalog arrives, `MapViewModel` resolves the saved or default city ID (or falls back to the first non-virtual network in the fetched `/api6` response) and opens the viewport SSE stream.
- Entries flagged `virtual: true` (`digitraffic`, `flixbus`, `lka`, `mld`, `pkp`) are excluded from `CityPickerSheet` and region-switch suggestions (`City.pickerCities(from:)`), while preserved in `citiesCatalog` for cross-city timezone lookup and stream routing when tapping regional stops or vehicles inside local maps (such as MLD regional buses or PKP trains in Kraków).
- If `GET /api6` fails or returns an empty list, `citiesCatalog` stays empty, `CityPickerSheet` remains disabled, and `MapViewModel` surfaces a retryable error (`MapViewModel.retry()`) without falling back to stale local data.
