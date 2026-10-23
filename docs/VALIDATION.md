# Walidacja etapu 4

## Sprawdzone lokalnie podczas implementacji

- Godot 4.7.2.stable.official.ed1daf0bf, edytor i szablony sprawdzone względem oficjalnych sum SHA-512.
- Test etapu 1: 5 przypadków geometrii zaliczonych.
- Test etapu 2: 1006 asercji, zero błędów.
- Test etapu 3: 46 sprawdzeń, zero błędów: raycast, ruch, kolizje, edycje i usuwanie collidera.
- Test etapu 4: 16 sprawdzeń, zero błędów: seed liczbowy i UTF-8, zgodność wszystkich 64 sekcji przy odwróconej kolejności i innych porcjach generowania, różne seedy, cztery biomy, drzewa, rzeźba terenu, jaskinie, podłoga i prześwit wejścia, granice, czyszczenie danych/kolejki oraz rzeczywiste usunięcie starego collidera z fizyki i odbudowa nowego świata.
- Domyślny seed: wysokości 10–36; kolumny biomów: 785 łąka, 1194 las, 1275 wydmy, 842 wzgórza. 43 niepuste sekcje kolizyjne.
- Test głównej sceny: gracz ląduje, raycast wybiera blok, teren ma kolizje. Powtórzony po rozdzieleniu startu na powierzchni i wejścia do jaskini.
- Eksporty release Web i Windows x86_64 bez błędów silnika. Windows: nagłówki MZ/PE i osadzony PCK poprawne; projekt wydobyty z EXE uruchomiony z pasującym szablonem release Linuksa.
- Web uruchomiony w Chromium Headless / WebGL 2 / SwiftShader. Obejrzano menu, widok FPS przy wejściu, przejście do korytarza i pauzę. Potwierdzono Pointer Lock i zmianę pozycji gracza. Menu startowe oraz pauza mieszczą się w oknie 1280×720.

## Zakres potwierdzenia

- Natywnego EXE nie uruchomiono lokalnie na Windows. Workflow repozytorium wykonuje ten test na runnerze Windows; jego bieżący wynik jest dostępny w Actions.
- Pełna ścieżka regeneracji przez menu Web po ostatnich poprawkach nie została potwierdzona do końca. Test danych i fizyki po czyszczeniu świata jest zaliczony.
- Środowisko SwiftShader używa renderowania programowego; czas ładowania i FPS nie stanowią benchmarku komputera użytkownika.
- Nie sprawdzono dotyku, Safari/iOS ani kontrolerów. Wersja przeznaczona do klawiatury i myszy.
- Budżety generowania, meshingu oraz kolizji są miękkie. Brak zapisu po wyjściu, streamingu i światła voxelowego to zakres kolejnych etapów.
