# VoxelForge — architektura i status clean-room

## Ustalenia
- Target Godot 4.7.x standard, GDScript i Windows/Web. Jeden wspólny renderer `gl_compatibility` dla WebGL 2.0.
- Dane przechowujemy w sekcjach 16×16×16; WorldManager indeksuje sekcje po Vector3i i pozwala na nieograniczoną wysokość (zależną od budżetu świata).
- W etapie 1 każdy blok jest bajtem w `PackedByteArray` (4096 B). Później rejestr bloków i palette encoding mogą zastąpić prosty identyfikator 0-255.
- Koordynaty: X i Z poziomo; Y do góry. Indeks: `x + 16 * (z + 16 * y)`; to *własna* decyzja implementacyjna, nie deklaracja zgodności z formatem NBT/Anvil.

## Sekwencja prac — etapy 1–4 są zaimplementowane
1. **[Wykonano i sprawdzono w Godot 4.7.2]** Jeden chunk + widoczna geometria (`ArrayMesh`), ukrywanie ścian wewnętrznych, prosta paleta kolorów, kamera orbitalna, testy.
2. **[Wykonano i sprawdzono]** WorldManager: mapa `Vector3i -> VFChunkData`, lokalne i globalne współrzędne (także ujemne), odczyt sąsiadów przez `get_block_global()`. Kolejka dirty z deduplikacją, meshing po 32 voxele, miękki budżet 3000 µs/klatkę i maks. 2 ukończone chunki/klatkę. Dodanie/usunięcie/zastąpienie sekcji aktualizuje sąsiadów; edycja pojedynczego bloku tylko sekcje stykające się ze zmienioną ścianą. W toku pracy częściowy mesh jest odrzucany, jeśli jego dane lub sąsiad się zmienią.
3. **[Wykonano]** Kontroler `CharacterBody3D`, kapsuła 1,8 m, kolizje sekcji, raycast DDA po danych bloków, kopanie i stawianie, pasek materiałów, dirty mesh i aktualizacja kolizji. Menu startowe, pauza i bezpieczny respawn.
4. **[Wykonano]** `FastNoiseLite` + seed; cztery biomy, wysokości, drzewa, jaskinie i dostępne wejście. Deterministyczność sprawdzona w ramach generatora v1 / Godot 4.7.2.
5. [Plan] `user://` własny wersjonowany format z sumą kontrolną / atomową zmianą plików; oddzielna opcja importu NBT/Anvil, jeśli będzie wymagana.
6. [Plan] Światło w dwóch kanałach (sky/block, 0..15), przyrostowa aktualizacja; optymalizacja greedy meshing i occlusion, ograniczone budżetem GPU przeglądarki.

## Wzorzec obserwowany a własne rozwiązanie

| Obszar | Publicznie obserwowalne / opisane | Decyzja VoxelForge | Pułapka |
| --- | --- | --- | --- |
| Sekcje | Java Edition ma siatkę 16×16 i sekcje o wysokości 16 | sekcje 16³ | mnogość alokacji |
| Geometria | świat składa się z widocznych powierzchni bloków; **dokładny algorytm renderowania gry niepotwierdzony** | własny face culling; greedy później | wewnętrzne ściany, styk chunków |
| Generowanie | wyjściowy świat zależy od seed i wersji | własny noise i reguły | blokada renderera na Web |
| Zapis | dla Java Edition udokumentowano NBT/Anvil `.mca` | własny format; importer osobno | niezgodność wersji |
| Tick | Java Edition działa zwykle 20/s | 20 Hz logika, 60 Hz fizyka Godot | mieszanie kroków czasowych |
| Kolizje | ruch gracza ograniczony geometrią świata | `CharacterBody3D`, meshe kolizyjne | drogie aktualizacje |
| Światło | światło nieba i źródeł: zakres 0..15 | późniejszy BFS queue z kanałami | światło na granicach sekcji |

Źródła referencyjne (fakty/formats, nie kod):
- https://minecraft.wiki/w/Chunk
- https://minecraft.wiki/w/Chunk_format
- https://minecraft.wiki/w/Tick
- https://minecraft.wiki/w/Light
- https://minecraft.wiki/w/Region_file_format
- https://docs.godotengine.org/en/stable/tutorials/3d/procedural_geometry/arraymesh.html
- https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html

## Otwarte eksperymenty clean-room

- Eksperyment: w oryginalnej grze ustawić dwa pełne przylegające obszary z tego samego bloku, porównać metryki widoczności / FPS (bez wnioskowania o nieujawnionych algorytmach).
- Eksperyment: oświetlić jaskinię jednym źródłem światła i zmierzyć spadek poziomu po każdej kratce i w narożnikach.
- Nie zaglądamy do zdekompilowanego kodu ani nie kopiujemy tekstur, modeli, dźwięków czy znaków towarowych.

## Kryteria zakończenia etapu 1

- Po otwarciu projektu kamera pokazuje pojedynczą kolorową sekcję ze sceną testową.
- Każdy blok sąsiadujący z innym pełnym blokiem nie rysuje wewnętrznej ściany.
- 1 blok -> 6 quadów -> 12 trójkątów; dwa sąsiednie -> 10 quadów -> 20 trójkątów.
- Pełna sekcja -> 1536 quadów; 3072 trójkątów (bez greedy).
- Testy etapu 1 wykonano w Godot 4.7.2; wszystkie zaliczone. Eksporty Windows/Web wykonano lokalnie. Zakres sprawdzeń opisuje `VALIDATION.md`.

## Kontrakty etapu 2

- `add_chunk(coord, data)` przejmuje zarządzanie danymi sekcji. Ponowne wywołanie zastępuje sekcję.
- `remove_chunk(coord)` usuwa dane i render, odsłaniając ściany sąsiadów.
- Brak sekcji oznacza AIR. Sekcja jest tworzona przez `set_block_global()` tylko dla niepustego bloku.
- `get_chunk()` zwraca referencję do danych: po bezpośredniej masowej edycji trzeba wywołać `mark_dirty_with_neighbors()`. Zwykłe edycje prowadź przez `set_block_global()`.
- Wielkie współrzędne renderera nadal ogranicza precyzja float. Floating origin i streaming nie są częścią etapu 2.
- Przy edycji poprzedni kompletny mesh pozostaje widoczny do ukończenia nowego. Podczas przebudowy różnych sekcji mogą wystąpić krótkie przejścia wizualne.
- Budżet czasu jest miękki: pojedyncza porcja 32 voxeli i finalne przesłanie `ArrayMesh` na GPU są niepodzielne. To nie jest gwarancja czasu klatki.
- Dane są aktualizowane na głównym wątku. Web nie potrzebuje SharedArrayBuffer ani wątków.
- Scena 64×32×64 obejmuje 32 sekcje, w tym puste sekcje górne. To stała kompozycja testowa, nie generator terenu etapu 4.
- Usuwanie/przywracanie kolumny przyciskiem C jest narzędziem demonstracyjnym, nie mechaniką kopania.

## Kryteria zakończenia etapu 2

- Dwie pełne sekcje stykające się ścianą: 2560 widocznych quadów łącznie, we wszystkich sześciu kierunkach.
- Usunięcie jednej odsłania ścianę drugiej: 1536 quadów. Przywrócenie wraca do 2560.
- Współrzędna -1 należy do sekcji -1 i lokalnej pozycji 15; -17 do sekcji -2 i pozycji 15.
- Edycja wewnętrzna aktualizuje jeden chunk; edycja narożnika maks. właściciela i 3 osiowych sąsiadów.
- Zmiana sąsiada w trakcie meshingu nie publikuje nieaktualnej geometrii.
- Test sceny: 32 sekcje -> wyjęcie kolumny (30) -> przywrócenie (32), ta sama liczba ścian.

## Kontrakty etapu 3

- WorldManager ma opcjonalne `collision_enabled`; stare demonstratory bez gracza nie płacą kosztu kolizji.
- W trybie z kolizjami kolejka jest obsługiwana w `_physics_process`. Dla każdego mesha tworzony jest `StaticBody3D` z kształtem trójkątowym. Pusty mesh usuwa poprzedni kształt; usunięcie chunka usuwa też jego ciało.
- Mesh i jego collider są zastępowane razem. Budowanie kształtu kolizyjnego i wysłanie mesha są niepodzielne; limit 3000 µs jest nadal miękki.
- Postać wstrzymuje przemieszczenie podczas kolejki zmian i dwóch kolejnych kroków fizyki. W tej wersji daje to bezpieczne przejście do nowych kolizji kosztem krótkiego zatrzymania po edycji. Przy większych światach należy ograniczyć tę blokadę do otoczenia gracza.
- `VFVoxelRaycast.cast()` czyta aktualne dane świata, ma zasięg 6 bloków dla gracza i rozwiązuje wszystkie jednoczesne przecięcia osi na krawędziach. Trafienie od wewnątrz bloku ma normalną zero i nie jest podstawą do stawiania.
- `place_target()` sprawdza puste miejsce, granice demonstratora i konserwatywne AABB kapsuły. Własna pozycja nie może zostać zabudowana.
- Ruch: 4,8 jednostki/s, sprint 7,5, skok 7,2 i grawitacja 22. Jedna jednostka odpowiada szerokości bloku. Bez automatycznego wchodzenia na pełne schodki: użyj skoku.
- Świat startowy zachowuje 32 sekcje. Budowanie może dodać sekcje nad nim do Y=47. X i Z mieszczą się w [-32,31].
- Respawn szuka aktualnej najwyższej bryły w kilku kolumnach i stawia postać nad nią. Gdy kolumny są puste, powstaje awaryjny blok podparcia.
- Warstwy fizyki: teren 1, postać 2; postać z maską 1. WorldManager i postać mają jednostkową skalę i działają w globalnej siatce przy początku sceny.
- Menu pauzy zatrzymuje sterowanie postaci, zwalnia kursor i zachowuje świat w pamięci. Przeglądarka wymaga kliknięcia do Pointer Lock.
- Zapis, crafting, ekwipunek z ilościami, obrażenia i generowanie z seeda pozostają poza zakresem etapu 3.

## Kryteria zakończenia etapu 3

- Lądowanie na terenie, chodzenie przez X=0 i X=16, blokowanie przez ścianę, skok i lądowanie.
- Usunięcie podparcia powoduje spadanie; postawiony blok fizycznie zatrzymuje postać.
- Sześć kierunków trafienia, ujemne współrzędne, limity zasięgu i przekątne DDA.
- Brak stawiania wewnątrz kapsuły; usunięcie sekcji usuwa niewidzialną kolizję.


## Kontrakty etapu 4

- Generator v1: lokalne kanały FastNoiseLite dla wysokości, detalu, wilgotności i dwóch szumów jaskiń. Reguły liczą we współrzędnych globalnych; nie korzystają z globalnego RNG.
- Seed liczbowy jest maskowany do 31 bitów; tekst przechodzi FNV-1a po UTF-8. Losuj korzysta z RNG tylko do wyboru seeda w formularzu.
- Kotwice drzew są deterministycznie przesunięte na siatce 8×8. Sekcja rozpatruje też kotwice poza swoją granicą, aby pnie i korony były zgodne niezależnie od kolejności generowania.
- Mapa 64³, maksymalnie 64 sekcje. Sekcje całkowicie puste pomijamy. Dwie dolne warstwy są pełne podczas generowania; gracz może je wykopać.
- Generator: porcje po 4 kolumny i miękki budżet 2000 µs na klatkę. Finalna dekoracja sekcji jest niepodzielna. Meshing i kolizje zachowują dotychczasowy budżet 3000 µs.
- Podczas generowania teren jest ukryty, aby nie renderować częściowych meshów pod menu. Widoczność i sterowanie wracają po gotowości danych oraz kolizji.
- clear_world() anuluje mesher, czyści kolejki/dane i odłącza stare widoki wraz z colliderami z przestrzeni fizyki.
- Start na powierzchni i przycisk wejścia do jaskini czytają aktualne bloki. Scena etapu 4 rozszerza etap 3 przez hooki populacji, gotowości, opisów i menu.
- Zgodność generatora między dowolnymi wersjami silnika nie jest gwarantowana; aktualizacja Godota wymaga walidacji.
