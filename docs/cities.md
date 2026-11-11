# Cities & Transit Networks Catalog

All **66** transit networks and cities supported by `api.zbiorkom.live` are
bundled with the app.

The catalog is defined statically in [`City.swift`](../KomunikacjaWiejska/Models/City.swift)
as compile-time `City` constants in `City.allCities`. Adding a city means
adding a static `City` entry — zero runtime JSON I/O or decoding overhead. Each entry may declare
`aliases` (additional search terms such as `gdansk` for `tricity`); the city
picker matches names, IDs, aliases, and diacritic-free queries.

| City ID | Display Name | Coordinates (Approx. Center) |
|---|---|---|
| `warsaw` | Warszawa | 52.2297° N, 21.0122° E |
| `krakow` | Kraków | 50.0647° N, 19.9450° E |
| `wroclaw` | Wrocław | 51.1079° N, 17.0385° E |
| `poznan` | Poznań | 52.4064° N, 16.9252° E |
| `tricity` | Trójmiasto (Gdańsk / Gdynia / Sopot) | 54.3520° N, 18.6466° E |
| `gzm` | Górnośląsko-Zagłębiowska Metropolia (Katowice) | 50.2649° N, 19.0238° E |
| `lodz` | Łódź | 51.7592° N, 19.4560° E |
| `szczecin` | Szczecin | 53.4285° N, 14.5528° E |
| `lublin` | Lublin | 51.2465° N, 22.5684° E |
| `bialystok` | Białystok | 53.1325° N, 23.1688° E |
| `bydgoszcz` | Bydgoszcz | 53.1235° N, 18.0084° E |
| `torun` | Toruń | 53.0138° N, 18.5984° E |
| `rzeszow` | Rzeszów | 50.0412° N, 21.9991° E |
| `kielce` | Kielce | 50.8661° N, 20.6286° E |
| `olsztyn` | Olsztyn | 53.7784° N, 20.4801° E |
| `opole` | Opole | 50.6751° N, 17.9213° E |
| `czestochowa` | Częstochowa | 50.8118° N, 19.1203° E |
| `radom` | Radom | 51.4027° N, 21.1471° E |
| `bielsko` | Bielsko-Biała | 49.8224° N, 19.0444° E |
| `rybnik` | Rybnik | 50.0970° N, 18.5418° E |
| `zielonagora` | Zielona Góra | 51.9356° N, 15.5062° E |
| `gorzow` | Gorzów Wielkopolski | 52.7368° N, 15.2288° E |
| `pkp` | PKP (Ogólnopolska Kolej) | 52.0693° N, 19.4803° E |
| `elblag` | Elbląg | 54.1561° N, 19.4045° E |
| `plock` | Płock | 52.5463° N, 19.7065° E |
| `tarnow` | Tarnów | 50.0121° N, 20.9858° E |
| `kalisz` | Kalisz | 51.7673° N, 18.0853° E |
| `legnica` | Legnica | 51.2070° N, 16.1553° E |
| `grudziadz` | Grudziądz | 53.4841° N, 18.7536° E |
| `jaworzno` | Jaworzno | 50.2052° N, 19.2750° E |
| `slupsk` | Słupsk | 54.4641° N, 17.0287° E |
| `jastrzebie` | Jastrzębie-Zdrój | 49.9536° N, 18.5878° E |
| `nowysacz` | Nowy Sącz | 49.6253° N, 20.6974° E |
| `inowroclaw` | Inowrocław | 52.7989° N, 18.2639° E |
| `lubin` | Lubin | 51.3984° N, 16.2017° E |
| `ostrowiec` | Ostrowiec Świętokrzyski | 50.9298° N, 21.3853° E |
| `suwalki` | Suwałki | 54.0990° N, 22.9252° E |
| `stargard` | Stargard | 53.3377° N, 15.0450° E |
| `gniezno` | Gniezno | 52.5348° N, 17.5826° E |
| `ostrow` | Ostrów Wielkopolski | 51.6550° N, 17.8068° E |
| `piotrkow` | Piotrków Trybunalski | 51.4052° N, 19.7032° E |
| `pabianice` | Pabianice | 51.6635° N, 19.3562° E |
| `zamosc` | Zamość | 50.7231° N, 23.2519° E |
| `lomza` | Łomża | 53.1781° N, 22.0594° E |
| `chelm` | Chełm | 51.1430° N, 23.4716° E |
| `tomaszow` | Tomaszów Mazowiecki | 51.5313° N, 20.0084° E |
| `zgierz` | Zgierz | 51.8564° N, 19.4061° E |
| `mielec` | Mielec | 50.2871° N, 21.4241° E |
| `stalowawola` | Stalowa Wola | 50.5828° N, 22.0534° E |
| `tczew` | Tczew | 54.0924° N, 18.7905° E |
| `belchatow` | Bełchatów | 51.3688° N, 19.3697° E |
| `swidnica` | Świdnica | 50.8438° N, 16.4886° E |
| `bedzin` | Będzin | 50.3259° N, 19.1278° E |
| `zgora` | Zgierz i okolice | 51.8564° N, 19.4061° E |
| `starachowice` | Starachowice | 51.0526° N, 21.0708° E |
| `tarnobrzeg` | Tarnobrzeg | 50.5744° N, 21.6791° E |
| `pulawy` | Puławy | 51.4166° N, 21.9694° E |
| `siedlce` | Siedlce | 52.1677° N, 22.2901° E |
| `ostroleka` | Ostrołęka | 53.0844° N, 21.5724° E |
| `skierniewice` | Skierniewice | 51.9566° N, 20.1431° E |
| `starogard` | Starogard Gdański | 53.9634° N, 18.5284° E |
| `krosno` | Krosno | 49.6887° N, 21.7706° E |
| `kolobrzeg` | Kołobrzeg | 54.1759° N, 15.5833° E |
| `myszkow` | Myszków | 50.5756° N, 19.3242° E |
| `zywiec` | Żywiec | 49.6865° N, 19.1945° E |
| `kutno` | Kutno | 52.2330° N, 19.3608° E |
