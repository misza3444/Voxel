# VoxelForge — Etap 4

Własny prototyp voxelowy clean-room. Godot 4.7.2 Standard / GDScript, Windows Portable i Web.

## Co działa

- Teren z seeda: liczby albo własnego tekstu, np. imienia.
- Cztery biomy: łąka, las, wydmy i skaliste wzgórza; drzewa, jaskinie 3D oraz dostępne wejście z korytarzem i komorą.
- Menu wyboru seeda, losowanie, generowanie nowego świata i postęp ładowania.
- Widok FPS, chodzenie, sprint, skok, grawitacja i kolizje.
- Kopanie i stawianie sześciu materiałów, obrys wskazanego bloku, pasek materiałów, pauza i bezpieczny powrót.
- Przyrostowa przebudowa geometrii i kolizji po edycji.

## Pobranie Windows Portable

1. Otwórz [Actions → Build VoxelForge Portable](https://github.com/misza3444/Voxel/actions/workflows/portable.yml).
2. Wybierz zakończone zielone uruchomienie.
3. Pobierz artefakt **VoxelForge-Windows-Portable** na dole strony.
4. Wypakuj ZIP i uruchom `VoxelForge.exe`.

Bez instalatora, edytora Godot i BAT. Dane gry są osadzone w EXE. Artefakty są przechowywane 30 dni; nowe można wygenerować przyciskiem **Run workflow**.

## Źródła i Web

Źródła: otwórz `project.godot` w Godot 4.7.2 i naciśnij F5.

Web: pobierz artefakt **VoxelForge-Web**. Udostępnij cały wypakowany katalog przez HTTP/HTTPS, np. `python3 -m http.server 8000`, i otwórz `http://localhost:8000`. Nie uruchamiaj HTML przez `file://`. Wymagane WebGL 2, WebAssembly, klawiatura i mysz.

## Sterowanie

WASD — ruch; mysz — rozglądanie; Spacja — skok; Shift — bieg; LPM — kop; PPM — postaw; 1–6 / kółko — materiał; Esc — pauza; R — powrót na start; F11 — pełny ekran.

ZAGRAJ rozpoczyna grę na powierzchni i przechwytuje kursor. **Odkryj wejście do jaskini** przenosi na początek zejścia. Na jednoblokowe stopnie wskakuj Spacją.

## Seed i ograniczenia

Domyślny seed `20261022` zawiera wszystkie cztery biomy. Inne seedy mogą mieć ich mniej, ponieważ mapa jest skończona. Liczby są normalizowane do 31 bitów; tekst jest hashowany jako UTF-8 przez FNV-1a. HUD pokazuje wynikowy seed liczbowy, który można wpisać ponownie. Ten sam seed daje te same bloki w tej wersji generatora i silnika.

Świat: 64×64×64, X/Z od -32 do 31, Y od 0 do 63. Brak nieskończonego streamingu. Generowanie nowego świata usuwa zmiany bieżącej sesji. Losuj zmienia tylko pole seeda — zatwierdź przyciskiem generowania.

**Zmiany nie są jeszcze zapisywane po zamknięciu gry.** Materiały bez limitu, bez craftingu i obrażeń. Jeden klik to jedna edycja. Postać krótko zatrzymuje się podczas przebudowy terenu. Światło w jaskiniach jest na razie globalne.

## Plan

1. Jeden chunk i mesher — wykonane.
2. WorldManager i kolejka — wykonane.
3. Gracz, kolizje, kopanie i stawianie — wykonane.
4. Seed, biomy, drzewa i jaskinie — wykonane.
5. Własny zapis i wczytywanie świata — następny etap.
6. Światło sky/block i optymalizacja geometrii.

## Sprawdzenie i budowanie

```sh
python3 scripts/run_godot.py -- godot --headless --path . --editor --import
python3 scripts/run_godot.py --expect VOXELFORGE_STAGE04_OK -- godot --headless --path . --script res://tests/test_stage_04.gd
python3 scripts/run_godot.py --expect VOXELFORGE_SMOKE_OK -- godot --headless --path . -- --smoke-test
```

Workflow zawiera testy etapów 1–4, eksport Windows/Web i uruchomienie finalnego EXE na Windows. Opis lokalnych sprawdzeń: [docs/VALIDATION.md](docs/VALIDATION.md). Starsze sceny etapów 1–3 pozostają dostępne osobno.
