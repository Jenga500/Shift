# Shift Vehicle – Dokumentation

Diese Anleitung erklärt Schritt für Schritt, wie du das Auto-Addon **Shift Vehicle**
in deinem eigenen Godot-Projekt benutzt: vom Einbauen über das erste fahrende Auto
bis zum Feintuning, den Motorsounds und der Steuerung in VR.

Du brauchst **Godot 4.7** (oder neuer).

---

## Inhalt

1. [Was das Addon kann](#1-was-das-addon-kann)
2. [Installation](#2-installation)
3. [Dein erstes Auto in 10 Minuten](#3-dein-erstes-auto-in-10-minuten)
4. [Steuerung](#4-steuerung)
5. [Fahren: Motor, Gänge, Handbremse](#5-fahren-motor-gänge-handbremse)
6. [Die Einstellungen (CarValues) erklärt](#6-die-einstellungen-carvalues-erklärt)
7. [Motorsounds](#7-motorsounds)
8. [Oberflächen und Terrain3D](#8-oberflächen-und-terrain3d)
9. [VR und Tickrate](#9-vr-und-tickrate)
10. [Das Auto aus eigenem Code benutzen](#10-das-auto-aus-eigenem-code-benutzen)
11. [Tuning-Rezepte](#11-tuning-rezepte)
12. [Fehlersuche](#12-fehlersuche)
13. [Bekannte Einschränkungen](#13-bekannte-einschränkungen)

---

## 1. Was das Addon kann

Shift ist eine **realistische Autosimulation**. Das Auto ist ein normaler
`RigidBody3D`, der von vier Strahlen (`RayCast3D`) getragen wird, einer pro Rad.
Das Addon berechnet dafür:

- **Federung** mit Stoßdämpfern und Stabilisatoren
- **Reifen** nach dem „Brush“-Reifenmodell (Grip, Rutschen, Driften)
- **Motor** mit Drehmomentkurve, Leerlauf, Kaltstart, Anlasser und Abwürgen
- **Kupplung** und **Differenzial** (offen, Torsen, Lamellen-Sperre)
- **Getriebe**: manuell, ohne Kupplung oder vollautomatisch
- **Antrieb**: Heck (RWD), Front (FWD) oder Allrad (AWD)
- **Bremsen**, **ABS**, **Traktionskontrolle** und **Handbremse** (zum Driften)
- **Luftwiderstand**, der mit dem Quadrat der Geschwindigkeit wächst
- **Reifenspuren und Reifenrauch** beim Driften, Durchdrehen und Blockieren
- **Oberflächen** (Asphalt, Gras, Schotter, Sand, Schnee …) mit eigenem Grip,
  Rollwiderstand, Spurfarbe und Rauch/Staub, auch für **Terrain3D**
- **Motorsounds**: Anlassen, Abstellen, Leerlauf kalt/warm und beliebig viele
  Drehzahl-Samples für vier Lastzustände
- **Spieler- und NPC-Autos**: ein Schalter pro Auto, NPCs werden per Code gefahren
- läuft stabil bei **jeder Physik-Tickrate**, auch bei 72/90/120 Hz für VR

---

## 2. Installation

1. Kopiere den Ordner `addons/shift_vehicle` in den Ordner `addons/` deines
   Projekts. Falls es den Ordner `addons/` noch nicht gibt, lege ihn an.
   Danach sieht dein Projekt so aus:
   ```
   dein_projekt/
   ├── addons/
   │   └── shift_vehicle/
   │       ├── plugin.cfg
   │       ├── car/ …
   │       └── …
   └── project.godot
   ```
2. Öffne das Projekt in Godot.
3. Gehe zu **Projekt → Projekteinstellungen → Plugins** und setze bei
   **Shift Vehicle** den Haken bei **Aktiviert**.

Beim Aktivieren legt das Plugin die nötigen **Eingabe-Aktionen** (Gas, Bremse,
Lenken …) in deiner Input Map an. Aktionen, die es schon gibt, werden nicht
verändert. Wenn sie nicht sofort unter *Projekteinstellungen → Input Map*
erscheinen, starte den Editor einmal neu.

> **Gut zu wissen:** Auch ohne aktiviertes Plugin funktioniert das Auto. Fehlende
> Eingabe-Aktionen legt es beim Start selbst an. Das Plugin sorgt nur dafür, dass
> du sie im Editor siehst und ändern kannst.

---

## 3. Dein erstes Auto in 10 Minuten

### 3.1 Der Aufbau

Ein Auto besteht aus diesen Nodes:

```
MeinAuto (ShiftCar)                 ← das Auto selbst (ein RigidBody3D)
├── CollisionShape3D                ← Kollisionsform der Karosserie
├── KarosserieMesh (MeshInstance3D) ← optional: so sieht das Auto aus
├── VorneLinks  (RayCast3D)         ← Rad 1
│   └── Rad (Node3D)                ← Radhalter (muss das ERSTE Kind sein)
│       └── RadMesh (MeshInstance3D)← optional: das sichtbare Rad
├── VorneRechts (RayCast3D)         ← Rad 2
│   └── Rad (Node3D)
├── HintenRechts (RayCast3D)        ← Rad 3
│   └── Rad (Node3D)
└── HintenLinks (RayCast3D)         ← Rad 4
	└── Rad (Node3D)
```

Die Namen sind egal. Wichtig sind nur die **Typen** und die **Reihenfolge** im
nächsten Schritt.

> **Wichtig: Baue das Auto in echter Größe** (1 Godot-Einheit = 1 Meter). Die
> Strahlen gehören an die echten Radpositionen, also z. B. bei einem E30 ca.
> 2,57 m Radstand und 1,40 m Spurweite. Ist das Modell verkleinert, rechnet die
> Physik mit dem kleinen Radstand, aber mit echter Masse und echten Reifen. Dann
> wird das Auto extrem nervös und rutscht schon in leichten Kurven weg. Skaliere
> den `ShiftCar`-Node selbst nicht (ein RigidBody3D verträgt das nicht), sondern
> das Modell darunter.

### 3.2 Schritt für Schritt

1. **Auto anlegen:** Füge in deiner Szene einen neuen Node hinzu und suche nach
   **ShiftCar**. Er erscheint im „Node erstellen“-Dialog, weil das Addon ihn
   registriert.
2. **Masse einstellen:** Setze im Inspector unter *RigidBody3D → Mass* das
   Gewicht deines Autos in kg, zum Beispiel `1200`.
3. **Karosserie-Kollision:** Füge eine `CollisionShape3D` als Kind hinzu, zum
   Beispiel mit einer `BoxShape3D` in Autogröße (etwa 1,6 × 0,5 × 4 m). Die Box
   sollte im Stand **den Boden nicht berühren**; die Räder tragen das Auto.
4. **Vier Räder:** Füge vier `RayCast3D` als Kinder hinzu und setze sie an die
   vier Radpositionen.
   - **Target Position** auf `(0, -0.5, 0)` stellen. Der Strahl zeigt damit nach
	 unten. Seine Länge (hier 0,5 m) ist die Länge der voll ausgefederten
	 Federung.
   - Die Strahlen müssen **nach vorne in −Z** zeigen: Die Vorderseite des Autos
	 ist die lokale −Z-Richtung (in Godot üblich).
5. **Radhalter:** Gib jedem `RayCast3D` einen `Node3D` als **erstes Kind**. Diesen
   Node verschiebt das Addon an den Bodenkontaktpunkt. Hänge dein Rad-Mesh
   darunter, wenn du sichtbare Räder willst.
6. **Räder zuweisen:** Trage die vier Strahlen im Inspector unter **Wheels** ein,
   **genau in dieser Reihenfolge:**

   | Eintrag | Rad |
   |---|---|
   | 0 | vorne links |
   | 1 | vorne rechts |
   | 2 | **hinten rechts** |
   | 3 | **hinten links** |

   Achtung: hinten zuerst **rechts**, dann links!
7. **Einstellungen zuweisen:** Ziehe unter **Vehicle Values** eine der fertigen
   Vorlagen aus `addons/shift_vehicle/presets/` hinein:
   - `roadster.tres`: leichter Roadster (136 Nm, 7200 U/min)
   - `e30.tres`: stärkere Limousine (230 Nm, 6750 U/min, ABS an)

   > **Tipp:** Mach dir zuerst eine Kopie (Rechtsklick → *Duplizieren*) und
   > arbeite mit der Kopie. So bleiben die Vorlagen unverändert, und
   > Änderungen betreffen nur dein Auto.
8. **Boden:** Das Auto braucht einen Boden mit Kollision, zum Beispiel einen
   `StaticBody3D` mit einer großen `BoxShape3D`.
9. **Kamera:** Füge irgendwo eine `Camera3D` hinzu, die das Auto sieht.
10. **Starten:** Starte die Szene, drücke **G** (Motor an), dann **E** (erster
	Gang; im manuellen Modus dabei **Shift** gedrückt halten) und **W** (Gas).

### 3.3 Optional: Anzeige und Debug-Pfeile

- **Tacho-Anzeige:** Instanziere `addons/shift_vehicle/ui/info.tscn` als Kind
  des Autos und trage unter **Car** dein Auto ein. Sie zeigt
  `km/h | RPM | Gang` und ob der Motor aus ist. Beim Gang bedeutet `-1`
  Rückwärts und `0` Leerlauf.
- **Debug-Pfeile:** Standardmäßig zeigt jedes Rad bunte Kraftpfeile (grün =
  Federung, rot = Längskraft, blau = Seitenkraft). Ausschalten kannst du sie in
  den *Vehicle Values* unter **Debug → DEBUG**.

---

## 4. Steuerung

| Aktion | Tastatur | Gamepad | Funktion |
|---|---|---|---|
| `Gas` | W | rechter Trigger | Gaspedal (stufenlos) |
| `Brake` | S | linker Trigger | Bremspedal (stufenlos) |
| `SteerLeft` / `SteerRight` | A / D | linker Stick | Lenken |
| `Clutch` | Shift | A | Kupplung |
| `ShiftUp` / `ShiftDown` | E / Q | rechte / linke Schultertaste | Gang hoch / runter |
| `Ignition` | G | B | Motor an / aus |
| `Handbrake` | Leertaste | X | Handbremse |
| `ToggleTC` | T | Y | Traktionskontrolle an / aus |

**Tasten ändern:** wie bei jeder Godot-Eingabe unter *Projekteinstellungen →
Input Map*.

**Aktionsnamen ändern:** Wenn dein Projekt schon eine Aktion `Brake` für etwas
anderes nutzt, kannst du die Namen an **einer** Stelle ändern: in
`addons/shift_vehicle/shift_input.gd` (die Konstanten oben in der Datei).

**Nur Spieler-Autos** reagieren auf diese Tasten. Autos, bei denen
**Player Controlled** aus ist, werden per Code gefahren, siehe
[10.3](#103-npc-autos-ki-gegner-verkehr).

---

## 5. Fahren: Motor, Gänge, Handbremse

### 5.1 Motor

- Das Auto startet mit **ausgeschaltetem Motor**. **G** startet ihn: Der
  Anlasser dreht kurz (*starter_crank_time*, Standard 0,8 s), dann läuft der
  Motor.
- Nochmal **G** schaltet ihn aus.
- Ein **kalter** Motor läuft mit erhöhtem Leerlauf (*cold_idle_rpm*, 1200 U/min)
  und wird beim Fahren langsam warm. Ein warmer Motor geht auf *idle_rpm*.
- Soll der Motor beim Start schon laufen, setze in den Vehicle Values unter
  **Motor** den Haken bei **start_engine_running**.
- **Abwürgen** ist standardmäßig aus. Setze *stall_rpm* zum Beispiel auf `500`,
  dann geht der Motor aus, wenn du ihn unter diese Drehzahl drückst, etwa wenn
  du im manuellen Modus die Kupplung im Stand zu schnell kommen lässt.

### 5.2 Getriebe-Modi

Einstellung: *Vehicle Values → Transmission → transmission_mode*

| Modus | So schaltest du | Kupplung |
|---|---|---|
| **MANUAL** | **Shift** (Kupplung) gedrückt halten, dann **E** / **Q** | du selbst; Anfahren mit Gefühl |
| **CLUTCHLESS** | einfach **E** / **Q** | automatisch: beim Schalten, Anfahren und Anhalten |
| **AUTOMATIC** | **E** / **Q** wählt nur **R → N → D** | automatisch; in D wählt das Getriebe den Gang |

**Gänge in MANUAL / CLUTCHLESS:** Die Reihenfolge ist
`R ↔ N ↔ 1 ↔ 2 ↔ 3 …`. Vom Leerlauf geht **E** in den ersten Gang, **Q** in den
Rückwärtsgang.

**AUTOMATIC:** Leg mit **E** „D“ ein und gib Gas. Wenig Gas schaltet früh hoch
(bei *auto_upshift_rpm_min*), Vollgas spät (bei *auto_upshift_rpm_max*). Wenn
du kräftig Gas gibst, schaltet es auch zurück (Kickdown). Fällt die
Drehmomentkurve schon vor der Höchstdrehzahl stark ab, schaltet es früher hoch,
sobald der nächste Gang mehr Kraft ans Rad bringt.

### 5.3 Handbremse und Driften

- **Leertaste** zieht die Handbremse. Sie blockiert die **Hinterräder**
  (einstellbar mit *handbrake_wheels*).
- In **CLUTCHLESS** und **AUTOMATIC** wird dabei automatisch ausgekuppelt, und
  das Automatikgetriebe hält den Gang. So bleibt der Motor im Drift auf Drehzahl.
  Abschalten mit *handbrake_opens_clutch*.
- **Drift-Technik:** mit Tempo einlenken, kurz Handbremse ziehen, loslassen und
  mit Gas und Gegenlenken das Heck halten. Mit Heckantrieb geht das am besten.
- Rutschende Reifen hinterlassen **Spuren** auf dem Boden und erzeugen **Rauch**,
  siehe [Effects](#effects-reifenspuren-und-rauch).

### 5.4 Antrieb

Einstellung: *Vehicle Values → Motor → drive_type*

| Wert | Bedeutung |
|---|---|
| **RWD** | Heckantrieb (Standard) |
| **FWD** | Frontantrieb |
| **AWD** | Allrad; die Verteilung vorne/hinten regelt *center_diff_split* (0,5 = halb/halb) |
| **CUSTOM** | jedes Rad einzeln über die Haken *FL/FR/RL/RR_torque_engine* |

> **Achtung bei AWD mit der e30-Vorlage:** Dort ist *center_diff_split* = `0.0`,
> also geht die ganze Kraft nach hinten. Setze es auf etwa `0.4`–`0.5`, wenn du
> echten Allrad willst.

---

## 6. Die Einstellungen (CarValues) erklärt

Alle Fahrzeugwerte stehen in einer `CarValues`-Ressource (`.tres`), die du unter
**Vehicle Values** einträgst. Im Inspector sind sie in Gruppen sortiert.

**Einheiten:** Meter, Kilogramm, Sekunden, Newton, Newtonmeter (Nm) und U/min.

**Reihenfolge bei Listen mit 4 Werten:** `[vorne links, vorne rechts, hinten
links, hinten rechts]`. (Das ist eine andere Reihenfolge als bei **Wheels**!)

> **Wichtig:** Eine **neu angelegte** `CarValues`-Ressource hat die
> **Vorderbremsen ausgeschaltet** (*FL/FR_torque_brake*). Die Vorlagen haben sie
> an. Am einfachsten startest du deshalb immer mit einer Kopie einer Vorlage.

### Car (Fahrzeug)

| Einstellung | Bedeutung |
|---|---|
| `wheel_base` | Radstand (Abstand Vorder- zu Hinterachse) in m. Wird für die Lenkgeometrie gebraucht. |
| `track` | Spurweite (Abstand linkes zu rechtem Rad) in m. |
| `drag_coefficient` | Luftwiderstandsbeiwert (cW-Wert). Typisch **0,30–0,40** für Pkw, 0,25 für sehr windschnittige Autos. |
| `frontal_area` | Stirnfläche in m². Kleiner Roadster ~1,7, Limousine ~1,9–2,2, SUV ~2,5–3. |
| `air_density` | Luftdichte in kg/m³ (1,225 auf Meereshöhe). |

Der Luftwiderstand ist `0,5 · air_density · drag_coefficient · frontal_area · v²`
und wirkt gegen die Fahrtrichtung. Er bestimmt zusammen mit Motor und
Übersetzung die **Endgeschwindigkeit**.

> **Hinweis:** Das Auto schaltet die eingebaute Dämpfung von Godot
> (`linear_damp`) beim Start ab. Diese Dämpfung wächst linear mit Masse ×
> Geschwindigkeit und hat Autos früher schon um die 80–100 km/h ausgebremst. Wenn
> du am ShiftCar-Node selbst *Linear → Damp* einstellst, wird das überschrieben.

### Suspension (Federung)

| Einstellung | Bedeutung |
|---|---|
| `ride_frequency` | Federhärte als Eigenfrequenz in Hz. **1,0–1,5** = Straßenauto, **2–3** = Sportwagen/Rennwagen. Höher = härter. |
| `damper_ratio` | Dämpfung. **1,0** = schwingt gar nicht nach, **0,3–0,7** = federt etwas nach. |
| `max_compression` | maximaler Federweg in m |
| `weight_distribution` | Anteil des Gewichts auf jedem Rad. **Muss zusammen 1,0 ergeben.** Bestimmt die Federhärte pro Rad und den Halt im Stand. Sollte zur echten Gewichtsverteilung passen. |
| `front_/rear_antiroll_bar` | Stabilisator an/aus |
| `front_/rear_antiroll_bar_stiffness` | Härte des Stabilisators. Mehr = weniger Seitenneigung. |
| `velocity_exponent` | Dämpferkennlinie. `1,0` lassen, wenn du unsicher bist. |

### Steering (Lenkung)

| Einstellung | Bedeutung |
|---|---|
| `max_tire_turn_angle` | größter Lenkeinschlag der Räder in Grad |
| `steering_ratio` | Lenkübersetzung (Lenkradgrad pro Radgrad) |
| `steering_wheel_travel` | Lenkradweg von Anschlag zu Anschlag in Grad |
| `tire_turn_speed` | wie schnell die Räder dem Lenkbefehl folgen |
| `speed_factor_coeff` | **geschwindigkeitsabhängige Lenkung**: Der Lenkeinschlag wird durch `1 + speed_factor_coeff × km/h` geteilt. Mit dem Standard 0,05 lenkt eine gedrückte Taste beim Parken voll ein, bei 50 km/h nur ~10° und bei 100 km/h ~6°, so wie ein Fahrer auch lenken würde. Höher = ruhiger bei Tempo. **0 = aus** (für Lenkräder, die 1:1 lenken sollen). |
| `ackermann_factor` | 0 = beide Räder gleich, 1 = volle Ackermann-Geometrie (Innenrad lenkt mehr) |
| `steering_stiffness` | Steifigkeit der Lenkung |

### Brake (Bremsen)

| Einstellung | Bedeutung |
|---|---|
| `max_brake_torque` | Bremsmoment für das **ganze** Auto in Nm (wird auf die gebremsten Räder verteilt) |
| `FL/FR/RL/RR_torque_brake` (Gruppe Motor) | welche Räder Bremsen haben |
| `max_handbrake_torque` | Handbremsmoment **pro** Handbremsrad in Nm. Muss hoch genug sein, um die Räder zu blockieren. |
| `handbrake_wheels` | welche Räder die Handbremse hat (Standard: hinten) |
| `handbrake_opens_clutch` | beim Ziehen automatisch auskuppeln (nur CLUTCHLESS/AUTOMATIC) |

### Assists (Fahrhilfen)

| Einstellung | Bedeutung |
|---|---|
| `ABS` | Antiblockiersystem an/aus |
| `abs_rate_apply` / `abs_rate_release` | wie schnell das ABS den Bremsdruck auf- und abbaut. **Müssen größer als 0 sein**, wenn ABS an ist (die e30-Vorlage nutzt 0,1 / 0,05). |
| `abs_slip_apply` / `abs_slip_release` | Schlupfgrenzen, bei denen das ABS eingreift (negative Werte) |
| `abs_pedal_target` | Bremsdruck-Anteil, während das ABS eingreift |
| `TC` | Traktionskontrolle beim Start an/aus. Im Spiel schaltet **T** (Gamepad **Y**) sie um. |
| `tc_slip_threshold` | ab diesem Schlupf eines angetriebenen Rades greift die TC ein (Standard 0,12). 0,1–0,15 = bester Grip, höher = lässt etwas Durchdrehen zu |
| `tc_cut_rate` | wie schnell die TC das Gas wegnimmt (Vollgas pro Sekunde, Standard 6) |
| `tc_recover_rate` | wie schnell sie das Gas zurückgibt, wenn die Räder wieder greifen (Standard 2) |
| `tc_brake_torque` | Bremsmoment in Nm, mit dem die TC ein einzeln durchdrehendes Rad abbremst (Standard 300). Hilft, wenn ein Rad auf Gras und eins auf Asphalt steht. 0 = nur Gas wegnehmen |
| `tc_min_speed` | unter dieser Geschwindigkeit (m/s) wird der Schlupf gegen diesen Wert gemessen, damit Anfahren nicht als endloser Schlupf gilt (Standard 3) |

**So arbeitet die Traktionskontrolle:** Drehen die angetriebenen Räder schneller
als der Boden unter ihnen (mehr als `tc_slip_threshold`), nimmt sie das Gas
zurück und bremst das durchdrehende Rad. Greifen die Räder wieder, gibt sie das
Gas langsam frei. Sie greift nur beim Beschleunigen ein, nicht beim Bremsen und
nicht bei seitlichem Rutschen. Zum Driften schaltest du sie mit **T** aus.
Das HUD (`ui/info.tscn`) zeigt **TC**, wenn sie an ist, und **TC ACTIVE**, während
sie eingreift.

### Motor

| Einstellung | Bedeutung |
|---|---|
| `max_torque` | höchstes Drehmoment in Nm |
| `max_rpm` | Drehzahlbegrenzer |
| `torque_curve` | Drehmomentkurve: **X** = Drehzahl von 0 bis 1 (1 = *max_rpm*), **Y** = Anteil von *max_torque* (0 bis 1). Bearbeite sie direkt im Inspector. |
| `idle_rpm` / `cold_idle_rpm` | Leerlaufdrehzahl warm / kalt |
| `idle_throttle_max` | wie viel Gas die Leerlaufregelung höchstens geben darf |
| `stall_rpm` | Abwürgedrehzahl; `0` = Abwürgen aus |
| `starter_crank_time` | Dauer des Anlassens in s. Am besten an deinen Anlass-Sound anpassen. |
| `starter_torque` / `starter_rpm` | Kraft und Drehzahl des Anlassers |
| `start_engine_running` | Motor läuft schon beim Start (und ist warm) |
| `initial_engine_warmth` | Motortemperatur beim Start, 0 = kalt, 1 = warm |
| `warmup_time` / `cooldown_time` | wie lange Warmlaufen und Abkühlen dauern (s) |
| `engine_inertia` | Schwungmasse des Motors. Klein = dreht schnell hoch. |
| `friction_c0/c1/c2` | innere Reibung des Motors (Motorbremse) |
| `drive_type` | Antrieb, siehe [5.4](#54-antrieb) |
| `differential` | **OPEN** (offen), **TORSEN_LSD**, **CLUTCH_LSD** (Lamellensperre). *ELECTRONIC_LSD* ist noch nicht fertig. |
| `TBR` | Sperrwert des Torsen-Differenzials (2,0 = bis zu doppelt so viel Kraft aufs griffigere Rad) |
| `minimum_clutch_lsd_force` / `clutch_lsd_ramp_factor` | Vorspannung und Sperrwirkung der Lamellensperre |
| `center_diff_split` | Kraftverteilung bei AWD (Anteil vorne) |

### Transmission (Getriebe)

| Einstellung | Bedeutung |
|---|---|
| `gear_ratio` | Übersetzungen. **Position 0 = Rückwärts** (negativ), **1 = Leerlauf** (0,0), ab **2 = 1. Gang**, … Mehr Einträge = mehr Gänge. |
| `final_drive` | Achsübersetzung |
| `drive_train_efficeny` | Wirkungsgrad (1,0 = verlustfrei) |
| `max_clutch_torque` | was die Kupplung höchstens überträgt (Nm). Sollte über *max_torque* liegen. |
| `transmission_mode` | MANUAL / CLUTCHLESS / AUTOMATIC, siehe [5.2](#52-getriebe-modi) |
| `auto_clutch_engage_rpm` | ab dieser Drehzahl ist die Automatik-Kupplung ganz geschlossen |
| `auto_upshift_rpm_min` / `_max` | Hochschaltdrehzahl bei wenig / bei Vollgas |
| `auto_downshift_factor` | wann zurückgeschaltet wird (kleiner = Gang wird länger gehalten; unter 1,0 lassen) |
| `auto_shift_cooldown` | Mindestabstand zwischen zwei Automatik-Schaltvorgängen (s) |

### Wheel (Räder und Reifen)

| Einstellung | Bedeutung |
|---|---|
| `wheel_radius` | Radius des Rades **mit** Reifen in m |
| `wheel_inertia` | Drehträgheit eines Rades |
| `rolling_resistance_coeff` | Rollwiderstand |
| `brush_mu` | **Grip** (Reibwert) des Reifens auf Asphalt. 1,0 = normaler Straßenreifen, 1,2–1,5 = Sportreifen. Andere Böden über [Oberflächen](#8-oberflächen-und-terrain3d). |
| `brush_mu_slide` | **Gleitreibung:** wie viel vom Grip übrig bleibt, wenn der Reifen ganz rutscht (Standard 0,75 = 75 %). Echte Reifen haben rutschend weniger Grip als rollend; das macht Drifts und Dreher realistischer. Normale Kurvenfahrt und Bremsen kosten keinen Grip, die Gleitreibung setzt erst ein, wenn die ganze Aufstandsfläche rutscht. 1,0 schaltet das aus. |
| `brush_slide_speed` | Rutschgeschwindigkeit in m/s, bei der der Grip schon zu ~63 % auf die Gleitreibung gefallen ist (Standard 3). Kleiner = Grip bricht schneller weg. |
| `default_surface` | Oberfläche für Boden ohne eigene Oberfläche. Leer = Asphalt. Siehe [8](#8-oberflächen-und-terrain3d). |
| `brush_Csx` | wie schnell der Reifen beim Beschleunigen und Bremsen Kraft aufbaut |
| `brush_Csy` | wie schnell der Reifen in Kurven Kraft aufbaut |

### Effects (Reifenspuren und Rauch)

Spuren und Rauch entstehen, wenn ein Reifen **rutscht**: beim Driften (seitlich),
beim Durchdrehen der Räder (Burnout) und beim Blockieren unter Bremsen. Gemessen
wird die Rutschgeschwindigkeit der Reifenaufstandsfläche in m/s.

| Einstellung | Bedeutung |
|---|---|
| `tire_marks` | Reifenspuren an/aus |
| `tire_smoke` | Reifenrauch an/aus |
| `effect_slip_start` | ab dieser Rutschgeschwindigkeit (m/s) beginnen Spuren und Rauch (Standard 3) |
| `effect_slip_full` | ab dieser Rutschgeschwindigkeit (m/s) sind sie voll ausgeprägt (Standard 10) |
| `tire_mark_width` | Breite einer Spur in m (etwa die Reifenbreite) |
| `tire_mark_segment_length` | Länge eines Spurstücks in m. Kürzer = rundere Kurven, aber mehr Stücke |
| `tire_mark_max_segments` | wie viele Spurstücke ein Auto behält. Ist die Zahl erreicht, verschwinden die ältesten Spuren |
| `tire_smoke_amount` | wie viele Rauchwolken pro Rad gleichzeitig sichtbar sein können |
| `tire_smoke_lifetime` | wie lange eine Rauchwolke sichtbar bleibt, in Sekunden |

Die **Farben** von Spuren und Rauch, und ob es auf einem Boden überhaupt Spuren
oder Rauch gibt, stellst du pro Oberfläche ein (dunkle Spuren und weißer Rauch
auf Asphalt, grünbraune Spuren und Staub auf Gras), siehe
[8](#8-oberflächen-und-terrain3d).

Die Spuren bleiben in der Welt liegen, auch wenn das Auto weiterfährt. Sie sind
Kinder des Autos: Wird das Auto gelöscht, verschwinden auch seine Spuren.

### Debug

| Einstellung | Bedeutung |
|---|---|
| `DEBUG` | Kraftpfeile an den Rädern an/aus (**standardmäßig an**) |
| `…_Arrow_Color` | Farben der Pfeile |
| `Position_Offset` | Versatz der Pfeile neben das Auto |
| `Display_Force_Magntiude` | Kraftwerte als Zahl anzeigen |

### Einstellungen direkt am ShiftCar-Node

| Einstellung | Bedeutung |
|---|---|
| `Vehicle Values` | die CarValues-Ressource |
| `Player Controlled` | an: der Spieler fährt (Tastatur/Gamepad). Aus: das Auto ignoriert die Eingaben und wird per Code gefahren (NPC), siehe [10.3](#103-npc-autos-ki-gegner-verkehr) |
| `Substep Rate` | interne Rechenrate für Räder, Reifen und Motor (Standard 300/s), siehe [9](#9-vr-und-tickrate) |
| `Wheels` | die vier Rad-Strahlen, siehe [3.2](#32-schritt-für-schritt) |
| Gruppe `Engine Sounds` | siehe [7](#7-motorsounds) |

---

## 7. Motorsounds

Die Sounds trägst du direkt am **ShiftCar**-Node ein, in der Gruppe
**Engine Sounds**. Alle Felder sind optional; leere Felder bleiben still.

### 7.1 Die Slots

| Slot | Wann er spielt | Art |
|---|---|---|
| `sound_ignition` | beim Anlassen (Taste G) | einmalig |
| `sound_shutdown` | beim Abstellen oder Abwürgen | einmalig |
| `sound_idle_cold` | Leerlauf, kalter Motor | Schleife |
| `sound_idle_warm` | Leerlauf, warmer Motor | Schleife |
| `sounds_free_rev` | **Hochdrehen im Leerlauf** (kein Gang oder Kupplung getreten) | Liste von Schleifen |
| `sounds_engine_brake` | **Motorbremse** (Gang drin, eingekuppelt, Gas weg) | Liste von Schleifen |
| `sounds_partial_load` | **Teillast** (Gang drin, wenig Gas, z. B. konstante Fahrt) | Liste von Schleifen |
| `sounds_high_load` | **Volllast / Beschleunigen** (Gang drin, Vollgas) | Liste von Schleifen |

### 7.2 Samples für verschiedene Drehzahlen hinzufügen

Für die vier Last-Listen kannst du **beliebig viele** Aufnahmen hinzufügen,
jede mit ihrer eigenen Drehzahl:

1. Klappe zum Beispiel **Sounds Free Rev** auf und klicke **Element hinzufügen**.
2. Klicke auf das leere Feld und wähle **Neu EngineSoundSample**.
3. Klappe das neue Sample auf:
   - **Stream:** deine Audiodatei hineinziehen
   - **Rpm:** die Drehzahl, bei der die Aufnahme gemacht wurde (z. B. `3000`)
4. Wiederhole das für jede Aufnahme, zum Beispiel für 1000, 2000, 3000, 4500
   und 6000 U/min. Die Reihenfolge ist egal.

Für die Leerlauf-Slots stellst du die Aufnahmedrehzahl in
`idle_cold_sample_rpm` / `idle_warm_sample_rpm` ein.

### 7.3 Wichtig: Schleifen einschalten

Alle Schleifen-Sounds (Leerlauf und alle Last-Samples) müssen sich
**wiederholen**:

1. Wähle die Audiodatei im **Dateisystem**-Dock aus.
2. Öffne oben links das **Import**-Dock.
3. Bei **WAV**: *Loop Mode* auf **Forward** stellen. Bei **OGG/MP3**: Haken bei
   **Loop** setzen.
4. Klicke **Neu importieren**.

Anlass- und Abstell-Sound sollen sich **nicht** wiederholen.

### 7.4 Wie gemischt wird (damit du weißt, was du aufnehmen solltest)

- **Leerlauf → Fahren:** Beim Leerlauf hörst du nur die Leerlauf-Sounds. Kalt
  und warm werden je nach Motortemperatur überblendet. Ab der Leerlaufdrehzahl
  wird über `sound_idle_blend_range` (600 U/min) zu den Last-Sounds übergeblendet.
- **Innerhalb einer Liste:** Die zwei Samples, deren Drehzahl der aktuellen am
  nächsten liegt (eins darunter, eins darüber), werden überblendet. Jedes wird
  in der Tonhöhe angepasst (`aktuelle Drehzahl ÷ Aufnahmedrehzahl`). Unter dem
  tiefsten und über dem höchsten Sample spielt nur dieses eine.
- **Ausgekuppelt oder eingekuppelt:** Ist kein Gang drin, die Kupplung
  getreten oder gerade ein Schaltvorgang, hörst du *free rev*. Mit Gang und
  losgelassener Kupplung hörst du die drei Gang-Listen. Beim Kommenlassen der
  Kupplung wird weich übergeblendet. Ist eine Seite leer, spielt die andere.
- **Mit Gang:** Das Gaspedal entscheidet: kein Gas = *engine brake*,
  halbes Gas = *partial load*, Vollgas = *high load*. Dazwischen wird gemischt.
  Ist eine Liste leer, übernehmen die Nachbarn.

**Tipp:** Samples im Abstand von etwa 1000–1500 U/min klingen gut. Je weiter
sie auseinanderliegen, desto stärker muss die Tonhöhe verschoben werden, und
das hört man.

### 7.5 Weitere Sound-Einstellungen

| Einstellung | Bedeutung |
|---|---|
| `engine_sound_volume_db` | Gesamtlautstärke in dB |
| `engine_sound_bus` | Audio-Bus (z. B. ein eigener „Fahrzeuge“-Bus) |
| `sound_idle_blend_range` | Drehzahlbereich der Überblendung Leerlauf → Last |
| `sound_fade_speed` | wie schnell die Sounds nach dem Anlassen ein- und nach dem Abstellen ausblenden |
| `sound_load_smoothing` | wie schnell die Last-Überblendung dem Gas und der Kupplung folgt (höher = direkter) |

Die Sounds sind **3D-Sounds** (`AudioStreamPlayer3D`), die am Auto hängen. In VR
hörst du den Motor deshalb von dort, wo er ist.

---

## 8. Oberflächen und Terrain3D

Jeder Boden kann eine **Oberfläche** (`ShiftSurface`) haben. Sie bestimmt, wie
sich das Auto dort verhält: Auf Gras rutscht es früher und rollt schwerer, auf
Asphalt hat es vollen Grip. Das Auto schaut jeden Physik-Frame für **jedes Rad
einzeln** nach, auf welcher Oberfläche es steht. Mit zwei Rädern auf der Wiese
zieht das Auto also zur Seite, wie in echt.

### 8.1 Die Vorlagen

Fertige Oberflächen liegen in `addons/shift_vehicle/presets/surfaces/`:

| Vorlage | Grip | Rollwiderstand | Spuren | Rauch / Staub |
|---|---|---|---|---|
| `asphalt.tres` | 1,0 | 1× | dunkel | weißer Rauch |
| `gravel.tres` (Schotter) | 0,7 | 3× | graubraun | heller Staub |
| `grass.tres` (Gras) | 0,55 | 5× | grünbraun | wenig brauner Staub |
| `sand.tres` | 0,5 | 10× | sandfarben | Sandstaub |
| `snow.tres` (Schnee) | 0,3 | 4× | hellgrau | weißer Pulverschnee |

Eine Oberfläche hat diese Einstellungen:

| Einstellung | Bedeutung |
|---|---|
| `surface_name` | Name, z. B. für dein HUD (`car.wheeldata.surface[i].surface_name`) |
| `grip` | Faktor auf den Reifen-Grip (`brush_mu` des Autos). 1,0 = Asphalt |
| `rolling_resistance` | Faktor auf den Rollwiderstand (`rolling_resistance_coeff` des Autos). Weicher Boden bremst |
| `marks` / `mark_color` | Spuren an/aus und ihre Farbe (Alpha = Deckkraft) |
| `smoke` / `smoke_color` | Rauch bzw. Staub an/aus und seine Farbe (Alpha = Deckkraft einer Wolke) |

Für eine eigene Oberfläche (Matsch, Eis, Kopfsteinpflaster …) kopierst du eine
Vorlage und änderst die Werte. Neu anlegen geht auch: *Rechtsklick im
Dateisystem → Neu → Ressource → ShiftSurface*.

### 8.2 Normale Böden (StaticBody3D, CSG, GridMap …)

Gib dem **Kollisionsobjekt** des Bodens die Oberfläche als Metadaten:

1. Den Boden-Node auswählen, der die Kollision hat (z. B. den `StaticBody3D`
   der Wiese).
2. Ganz unten im Inspector **Metadaten hinzufügen** klicken.
3. Name: `shift_surface`, Typ: **Object**.
4. In das neue Feld die Oberfläche ziehen, z. B. `presets/surfaces/grass.tres`.

Per Code geht das genauso:

```gdscript
$Wiese.set_meta("shift_surface", preload("res://addons/shift_vehicle/presets/surfaces/grass.tres"))
```

Ein Boden **ohne** Metadaten bekommt die `default_surface` des Autos
(*Vehicle Values → Wheel → default_surface*), oder Asphalt, wenn die leer ist.

### 8.3 Terrain3D

Bei einem Terrain3D-Gelände hängt die Oberfläche an den **gemalten Texturen**:
Wo du Gras malst, fährt das Auto auf Gras.

1. Füge irgendwo in der Szene einen Node **ShiftTerrain3DSurfaces** hinzu
   (z. B. als Kind des Terrain3D-Nodes).
2. Trage bei **Terrain** deinen Terrain3D-Node ein.
3. Fülle **Surfaces**: Eintrag **N** ist die Oberfläche für die Textur mit der
   **ID N** im Asset-Dock von Terrain3D.

Beispiel, wenn im Asset-Dock Textur 0 Gras, 1 Asphalt und 2 Schotter ist:

| Surfaces-Index | Oberfläche |
|---|---|
| 0 | `grass.tres` |
| 1 | `asphalt.tres` |
| 2 | `gravel.tres` |

- Wo zwei Texturen ineinander übergehen, zählt die, die mehr zu sehen ist.
- Leere Einträge und Texturen ohne Eintrag bekommen die `default_surface` des
  Autos.
- **Straßen als eigene Meshes** über dem Terrain: Liegt das Rad mehr als
  *Height Tolerance* (Standard 0,3 m) über dem Terrain, wird das Terrain
  ignoriert. Gib der Straße dann wie in [8.2](#82-normale-böden-staticbody3d-csg-gridmap-)
  die Metadaten `shift_surface` (oder lass sie leer, dann gilt die
  `default_surface`, also Asphalt).
- Braucht **Terrain3D 1.0** oder neuer. Ohne Terrain3D funktioniert der Rest
  des Addons ganz normal; der Node wird dann einfach nicht benutzt.

### 8.4 Reihenfolge und eigene Böden per Code

Das Auto sucht die Oberfläche unter einem Rad in dieser Reihenfolge:

1. Metadaten `shift_surface` am Kollisionsobjekt
2. alle Nodes in der Gruppe `shift_surface_providers` (z. B. ShiftTerrain3DSurfaces)
3. `default_surface` des Autos, sonst Asphalt

Für andere Gelände-Systeme kannst du dir einen eigenen Provider schreiben: ein
Node in der Gruppe `shift_surface_providers` mit dieser Methode:

```gdscript
extends Node

func _enter_tree() -> void:
	add_to_group("shift_surface_providers")

## Gibt die Oberfläche am Punkt zurück, oder null, wenn der Punkt nicht zu
## diesem Gelände gehört.
func get_surface(point: Vector3, collider: Object) -> ShiftSurface:
	if collider == $MeinGelaende:
		return preload("res://addons/shift_vehicle/presets/surfaces/grass.tres")
	return null
```

Auslesen, worauf ein Rad gerade steht: `car.wheeldata.surface[i]`
(`i`: 0 = vorne links, 1 = vorne rechts, 2 = hinten links, 3 = hinten rechts).

---

## 9. VR und Tickrate

Das Addon läuft bei **jeder Physik-Tickrate**, auch wenn dein Projekt (etwa
durch die **Godot XR Tools**) die Tickrate auf die Bildwiederholrate des Headsets
setzt (72, 80, 90, 120 Hz …). Du musst **nichts umstellen**.

So funktioniert es:

- Die „schnellen“ Teile (Raddrehung, Reifenschlupf, Motor, Kupplung) rechnet das
  Auto intern in kleinen Zwischenschritten, mit der **Substep Rate** des
  ShiftCar-Nodes (Standard **300 pro Sekunde**). Bei 72 Hz sind das 5
  Zwischenschritte pro Bild, bei 300 Hz genau einer.
- Im Stand halten die Reifen wie echte Haftreibung. Ein gebremstes Auto steht
  daher ruhig, auch am Hang.

Getestet: 60, 72, 80, 90, 120 und 300 Hz liefern nahezu dasselbe Fahrverhalten.

| Substep Rate | Wirkung |
|---|---|
| höher (z. B. 600) | etwas genauer, kostet mehr Rechenzeit |
| niedriger (z. B. 200) | spart Rechenzeit, etwas ungenauer |

Rechenaufwand: bei 72 Hz etwa 0,35 ms pro Bild für ein Auto.

### VR-Controller als Pedale und Lenkung

OpenXR-Controller lösen **nicht automatisch** die Godot-Eingabe-Aktionen aus.
Ein kleines Skript kann sie weiterreichen. Hänge es an einen Node, der in der
Szene **über** dem Auto steht, oder setze seine *Process → Physics Priority* auf
`-1`, damit es vor dem Auto läuft:

```gdscript
extends Node

@export var left_hand: XRController3D
@export var right_hand: XRController3D

func _physics_process(_delta: float) -> void:
	# Pedale auf die Trigger
	set_axis(ShiftInput.GAS, right_hand.get_float("trigger"))
	set_axis(ShiftInput.BRAKE, left_hand.get_float("trigger"))

	# Lenken mit dem linken Stick
	var stick := left_hand.get_vector2("primary")
	set_axis(ShiftInput.STEER_LEFT, maxf(-stick.x, 0.0))
	set_axis(ShiftInput.STEER_RIGHT, maxf(stick.x, 0.0))

	# Tasten
	set_button(ShiftInput.SHIFT_UP, right_hand.is_button_pressed("by_button"))
	set_button(ShiftInput.SHIFT_DOWN, right_hand.is_button_pressed("ax_button"))
	set_button(ShiftInput.HANDBRAKE, left_hand.is_button_pressed("grip_click"))
	set_button(ShiftInput.IGNITION, left_hand.is_button_pressed("by_button"))

func set_axis(action: StringName, value: float) -> void:
	if value > 0.01:
		Input.action_press(action, value)
	else:
		Input.action_release(action)

func set_button(action: StringName, pressed: bool) -> void:
	if pressed and not Input.is_action_pressed(action):
		Input.action_press(action)
	elif not pressed and Input.is_action_pressed(action):
		Input.action_release(action)
```

Die Namen `"trigger"`, `"primary"`, `"ax_button"`, `"by_button"` und
`"grip_click"` stammen aus der Standard-Action-Map von Godot. Wenn du eine
eigene OpenXR-Action-Map hast, setze dort deine Namen ein. Für ein
**greifbares Lenkrad** gibst du statt des Sticks den Lenkradwinkel als
`STEER_LEFT` / `STEER_RIGHT` (je 0 bis 1) weiter.

---

## 10. Das Auto aus eigenem Code benutzen

### 10.1 Werte auslesen (z. B. für Tacho, HUD, Effekte)

Alle Laufzeitwerte stehen auf dem ShiftCar-Node:

```gdscript
@export var car: ShiftCar

func _process(_delta: float) -> void:
	var kmh: float = car.linear_velocity.length() * 3.6   # Geschwindigkeit
	var rpm: float = car.engine.engine_rpm                 # Drehzahl
	var motor_an: bool = car.engine.engine_running         # läuft der Motor?
	var gang: int = car.transmission.current_gear - 1      # -1 = R, 0 = N, 1 = 1. Gang …
	var warm: float = car.engine.engine_warmth             # 0 = kalt … 1 = warm
	var schlupf_hl: float = car.wheeldata.slip_ratio[2]    # Schlupf hinten links (z. B. für Reifenquietschen)
```

| Wert | Bedeutung |
|---|---|
| `car.engine.engine_rpm` | Motordrehzahl |
| `car.engine.engine_running` / `engine_starting` / `engine_stalled` | Motorzustand |
| `car.engine.engine_warmth` | Motortemperatur 0–1 |
| `car.engine.throttle` | tatsächliches Gas 0–1 (inkl. Leerlaufregelung) |
| `car.engine.clutch_input` | Kupplung 0 = geschlossen, 1 = offen |
| `car.transmission.current_gear` | Gang-Index (0 = R, 1 = N, 2 = 1. Gang …) |
| `car.transmission.is_shifting` | gerade am Schalten |
| `car.wheeldata.wheel_angular_velocity[i]` | Raddrehzahl in rad/s |
| `car.wheeldata.slip_ratio[i]` / `slip_angle[i]` | Längs- / Querschlupf (gut für Quietsch-Sounds und Reifenspuren) |
| `car.suspension.compression[i]` | Einfederung in m |
| `car.wheeldata.surface[i]` | Oberfläche unter dem Rad (`ShiftSurface`), z. B. `.surface_name` |
| `car.assists.tc_on` | Traktionskontrolle an (auch schreibbar, z. B. für ein eigenes Menü) |
| `car.assists.tc_active` | die Traktionskontrolle greift gerade ein (z. B. für eine Warnleuchte) |
| `car.brake.input_brake` / `input_handbrake` | Bremse / Handbremse 0–1 |

`i` ist hier immer: **0 = vorne links, 1 = vorne rechts, 2 = hinten links,
3 = hinten rechts**.

### 10.2 Spieler-Auto und NPC-Auto: der Schalter „Player Controlled“

Jedes ShiftCar hat im Inspector den Schalter **Player Controlled**:

| Player Controlled | Wer fährt? |
|---|---|
| **an** (Standard) | der Spieler, mit Tastatur, Gamepad oder VR-Controllern (die Eingabe-Aktionen aus [4](#4-steuerung)) |
| **aus** | dein eigener Code (NPC, KI-Gegner, Verkehr, Replay …). Das Auto **ignoriert** Tastatur und Gamepad. |

Intern liest das Auto seine Pedale, Lenkung und Knöpfe immer aus
`car.controls`. Bei einem Spieler-Auto füllt das Auto diese Werte selbst aus den
Eingabe-Aktionen, bei einem NPC-Auto schreibt dein Skript sie hinein:

| Wert | Bereich | Bedeutung |
|---|---|---|
| `car.controls.gas` | 0 … 1 | Gaspedal |
| `car.controls.brake` | 0 … 1 | Bremspedal |
| `car.controls.steer` | −1 … 1 | Lenkung: **positiv = links**, negativ = rechts |
| `car.controls.clutch` | 0 … 1 | Kupplungspedal (1 = ganz gedrückt); nur im MANUAL-Modus nötig |
| `car.controls.handbrake` | 0 … 1 | Handbremse |
| `car.controls.shift_up` | true | einen Gang hoch (AUTOMATIC: R → N → D) |
| `car.controls.shift_down` | true | einen Gang runter (AUTOMATIC: D → N → R) |
| `car.controls.ignition` | true | Motor an (Anlasser) bzw. aus |

Die Pedale und die Lenkung **behalten ihren Wert**, bis du einen neuen setzt.
`shift_up`, `shift_down` und `ignition` sind **Knopfdrücke**: setze sie einmal
auf `true`, das Auto führt sie aus und stellt sie danach selbst wieder auf
`false`.

Den Schalter kannst du auch im Spiel umlegen, zum Beispiel wenn der Spieler
in ein Auto einsteigt:

```gdscript
altes_auto.player_controlled = false   # steht jetzt still (oder ein NPC übernimmt)
neues_auto.player_controlled = true    # reagiert jetzt auf Tastatur/Gamepad
```

> Wenn ein Auto auf „aus“ gestellt wird, behält `car.controls` die letzten
> Werte. Wer aussteigt, sollte also Gas loslassen und die Handbremse ziehen:
> `car.controls.gas = 0.0` und `car.controls.handbrake = 1.0`.

### 10.3 NPC-Autos (KI-Gegner, Verkehr)

So baust du ein NPC-Auto:

1. Baue ein ganz normales ShiftCar (oder instanziere dein fertiges Auto noch
   einmal).
2. Schalte im Inspector **Player Controlled** aus.
3. Gib ihm ein Skript, das in jedem Physik-Frame `car.controls` setzt.

Hier ein fertiger, einfacher NPC-Fahrer, der eine Reihe von Wegpunkten im Kreis
abfährt. Er wurde mit einer 80-m-Runde getestet (auch bei 90 Hz):

```gdscript
extends Node
## Einfacher NPC-Fahrer: fährt eine Liste von Wegpunkten im Kreis ab.

## Das Auto, das dieser Fahrer steuert.
@export var car: ShiftCar
## Die Wegpunkte, der Reihe nach (z. B. leere Node3D-Nodes auf der Strecke).
@export var waypoints: Array[Node3D] = []
## Wunschgeschwindigkeit auf der Geraden.
@export var target_speed_kmh := 60.0

var current := 0


func _ready() -> void:
	car.player_controlled = false                  # Tastatur/Gamepad ignorieren
	car.VehicleValues = car.VehicleValues.duplicate()
	car.VehicleValues.transmission_mode = CarValues.TransmissionMode.AUTOMATIC
	car.controls.ignition = true                   # Motor starten
	car.controls.shift_up = true                   # von N auf D


func _physics_process(_delta: float) -> void:
	if waypoints.is_empty():
		return

	# Ziel aus Sicht des Autos: -Z ist vorne, +X ist rechts
	var local := car.to_local(waypoints[current].global_position)
	if local.length() < 8.0:
		current = (current + 1) % waypoints.size()  # nächster Wegpunkt

	# Lenken: Ziel links -> positiv, Ziel rechts -> negativ
	var angle := atan2(-local.x, -local.z)
	car.controls.steer = clampf(angle * 2.0, -1.0, 1.0)

	# Gas und Bremse: in Kurven langsamer
	var kmh := car.linear_velocity.length() * 3.6
	var wanted := target_speed_kmh * (1.0 - 0.6 * absf(car.controls.steer))
	if kmh < wanted:
		car.controls.gas = clampf((wanted - kmh) / 10.0, 0.0, 1.0)
		car.controls.brake = 0.0
	else:
		car.controls.gas = 0.0
		car.controls.brake = clampf((kmh - wanted) / 20.0, 0.0, 1.0)
```

So benutzt du ihn:

1. Lege einen `Node` an (z. B. als Kind des NPC-Autos) und hänge das Skript an.
2. Setze im Inspector **Car** auf das NPC-Auto.
3. Lege auf der Strecke ein paar leere `Node3D` als Wegpunkte an und ziehe sie
   der Reihe nach in die Liste **Waypoints**.
4. Starte das Spiel. Das NPC-Auto startet selbst den Motor, legt D ein und
   fährt los.

**Tipps für eigene NPCs:**

- Das Beispiel stellt das NPC-Auto auf **AUTOMATIC**, dann muss sich der NPC
  nicht ums Schalten kümmern. Im MANUAL- oder CLUTCHLESS-Modus musst du selbst
  `shift_up` / `shift_down` setzen, zum Beispiel ab 6000 U/min hochschalten.
- `car.VehicleValues.duplicate()` gibt dem NPC eine eigene Kopie der
  Einstellungen. So ändert der NPC nicht aus Versehen das Auto des Spielers,
  wenn beide dieselbe `.tres`-Datei benutzen.
- Mehrere NPCs sind kein Problem: jedes Auto hat seine eigenen `controls`.
- Gute Werte zum Reagieren: `car.linear_velocity` (Tempo),
  `car.engine.engine_rpm`, `car.transmission.current_gear` und
  `car.to_local(ziel)` (wo liegt das Ziel aus Sicht des Autos: −Z vorne,
  +X rechts).
- Mit einem `Path3D` statt Wegpunkten fährt der NPC eine glatte Linie:
  nimm `curve.get_closest_offset()` und schaue ein paar Meter voraus.

### 10.4 Ein Spieler-Auto per Code steuern

Bei einem Spieler-Auto kommt die Eingabe aus den Eingabe-Aktionen. Wenn du für
ein Spieler-Auto eine eigene Eingabe einbauen willst (z. B. VR-Controller, siehe
[9](#9-vr-und-tickrate)), „drückst“ du die Aktionen per Code:

```gdscript
Input.action_press(ShiftInput.GAS, 0.6)     # 60 % Gas
Input.action_release(ShiftInput.GAS)

Input.action_press(ShiftInput.IGNITION)      # Motor an/aus (einmal drücken …)
Input.action_release(ShiftInput.IGNITION)    # … und wieder loslassen
```

Für NPCs nimm stattdessen `car.controls` (siehe [10.3](#103-npc-autos-ki-gegner-verkehr)),
denn die Eingabe-Aktionen gelten für alle Spieler-Autos gleichzeitig.

### 10.5 Einstellungen zur Laufzeit ändern

Die CarValues kannst du jederzeit ändern, zum Beispiel für ein Optionsmenü:

```gdscript
car.VehicleValues.transmission_mode = CarValues.TransmissionMode.AUTOMATIC
car.VehicleValues.drive_type = CarValues.DriveType.FWD
car.VehicleValues.ABS = true
```

> Wenn zwei Autos **dieselbe** `.tres`-Datei benutzen, ändert sich das für
> beide. Gib jedem Auto eine eigene Kopie, oder rufe beim Start
> `car.VehicleValues = car.VehicleValues.duplicate()` auf.

---

## 11. Tuning-Rezepte

| Du willst … | Ändere … |
|---|---|
| mehr Grip | `brush_mu` erhöhen (z. B. 1,25 → 1,5) |
| leichter driften | `brush_mu` senken, Heckantrieb, `differential` = CLUTCH_LSD, hinten härtere Federn (`ride_frequency`) oder härterer Stabi hinten |
| weniger Übersteuern | vorne härterer Stabi, hinten weicher; `brush_mu` hinten kann man nicht getrennt einstellen, also eher über die Federung gehen |
| mehr Leistung | `max_torque` erhöhen, ggf. `max_clutch_torque` mit anheben |
| höhere Endgeschwindigkeit | kleinere Werte in `gear_ratio` (längere Gänge), kleinerer `final_drive`, oder weniger Luftwiderstand (`drag_coefficient`, `frontal_area`) |
| bessere Beschleunigung | größerer `final_drive` |
| sportlichere Federung | `ride_frequency` 2–3 Hz, `damper_ratio` 0,6–0,8 |
| weicheres, schaukelnderes Auto | `ride_frequency` ~1 Hz, `damper_ratio` 0,3–0,4 |
| Motor dreht giftiger hoch | `engine_inertia` verkleinern |
| stärkere Motorbremse | `friction_c0/c1/c2` erhöhen |
| Automatik schaltet zu früh | `auto_upshift_rpm_min` erhöhen |
| Handbremse greift nicht genug | `max_handbrake_torque` erhöhen |
| Spuren und Rauch schon bei leichtem Rutschen | `effect_slip_start` senken (z. B. 3 → 1,5) |
| weniger Rauch | in der Oberfläche `smoke_color` Alpha senken, oder `tire_smoke_amount` verkleinern |
| weniger Grip auf Gras / mehr auf Schotter | `grip` in der jeweiligen Oberfläche ändern |
| Auto bricht beim Rutschen weniger stark aus | `brush_mu_slide` erhöhen (z. B. 0,75 → 0,85) |
| Lenkung bei Tempo zu nervös / zu träge | `speed_factor_coeff` erhöhen / senken |
| Grip wie ein normales Straßenauto | `brush_mu` ≈ 1,0 (1,25 entspricht sportlichen Reifen) |
| Traktionskontrolle soll etwas Durchdrehen erlauben | `tc_slip_threshold` erhöhen (z. B. 0,12 → 0,25) |
| Traktionskontrolle regelt zu ruppig | `tc_cut_rate` senken, `tc_recover_rate` erhöhen |
| Spuren bleiben länger liegen | `tire_mark_max_segments` erhöhen |

**Faustregel:** Ändere immer nur **einen** Wert auf einmal und teste.

---

## 12. Fehlersuche

| Problem | Ursache / Lösung |
|---|---|
| Auto fällt durch den Boden oder liegt auf der Karosserie | Strahlen zeigen nicht nach unten, oder sind zu kurz: *Target Position* z. B. `(0, -0.5, 0)`. Boden braucht Kollision. |
| Auto springt wild oder fliegt weg | Karosserie-Kollision berührt den Boden oder die Strahlen; die Box kleiner oder höher setzen. `weight_distribution` muss zusammen 1,0 ergeben. |
| Auto fährt rückwärts, wenn ich Gas gebe | Das Auto (bzw. die Strahlen) zeigt mit der Front nicht nach −Z. Den ShiftCar-Node so drehen, dass vorne −Z ist. |
| Lenkung/Räder vertauscht | Reihenfolge unter **Wheels** prüfen: vorne links, vorne rechts, **hinten rechts**, hinten links. |
| Fehlermeldung in `car.gd` beim Start (bei `wheels[…]` oder `get_child(0)`) | **Wheels** ist leer oder hat keine 4 Einträge, oder ein Strahl hat keinen `Node3D` als erstes Kind. |
| Auto bewegt sich nicht | Motor aus (**G**)? Gang drin (**E**)? Handbremse gezogen? Im MANUAL-Modus Kupplung losgelassen? |
| Ich kann nicht schalten | Im MANUAL-Modus muss die Kupplung (**Shift**) ganz gedrückt sein. Oder CLUTCHLESS / AUTOMATIC wählen. |
| Auto bremst vorne nicht | `FL_torque_brake` / `FR_torque_brake` (Gruppe Motor) einschalten; bei neuen Ressourcen sind sie aus. |
| Motor geht beim Anfahren aus | `stall_rpm` ist gesetzt: mehr Gas geben, Kupplung langsamer kommen lassen, oder `stall_rpm` = 0. |
| Kein Sound | Streams eingetragen? Bei den Last-Listen auch die **Rpm** gesetzt? Läuft der Motor? Lautstärke / Bus prüfen. |
| Sound bricht nach kurzer Zeit ab | Schleife beim Import nicht aktiviert, siehe [7.3](#73-wichtig-schleifen-einschalten). |
| Bunte Pfeile an den Rädern | Debug-Anzeige: *Vehicle Values → Debug → DEBUG* aus. |
| Tasten funktionieren nicht | *Projekteinstellungen → Input Map* prüfen; Plugin aktivieren oder Editor neu starten. |
| NPC-Auto fährt nicht | Ist **Player Controlled** aus? Motor gestartet (`controls.ignition = true`)? Gang drin (`shift_up`)? Setzt dein Skript `controls.gas` jeden Frame? |
| NPC-Auto reagiert auf meine Tastatur | **Player Controlled** ist noch an. |
| Meine Aktion `Brake` macht jetzt zwei Sachen | Namenskonflikt: die Namen in `shift_input.gd` ändern. |
| Auto wird in hohen Gängen nicht schneller | Zu viel Luftwiderstand (`drag_coefficient`, `frontal_area` prüfen) oder zu lange Übersetzung für das Drehmoment. |
| Keine Reifenspuren oder kein Rauch | `tire_marks` / `tire_smoke` an? Rutscht der Reifen schnell genug (`effect_slip_start`)? |
| Spuren kaum sichtbar | Auf sehr dunklem Boden fallen dunkle Spuren kaum auf: in der Oberfläche `mark_color` Alpha erhöhen. |
| Motor stirbt nach einem Dreher ab | Im MANUAL-Modus normal und wie in echt: Rollt das Auto rückwärts oder bleibt es stehen, während ein Gang drin ist, würgt das den Motor ab. Kupplung treten („beide Füße rein“), oder CLUTCHLESS / AUTOMATIC nutzen. Neu starten mit **G**. |
| Auto rutscht schon in leichten Kurven weg | Ist das Auto in **echter Größe** gebaut (siehe [3.1](#31-der-aufbau))? Sitzen die Strahlen an den echten Radpositionen? `speed_factor_coeff` auf 0? Liegt der Schwerpunkt (*Center of Mass*) zu weit hinten? |
| Auto dreht sich auf Gras bei Vollgas | Wenig Grip und Heckantrieb: Gas dosieren oder die Traktionskontrolle einschalten (`TC`, im Spiel **T**). |
| Auto lässt sich nicht driften, Gas wirkt „gebremst“ | Die Traktionskontrolle ist an: mit **T** ausschalten. |
| Auto verhält sich auf Gras wie auf Asphalt | Hat das Kollisionsobjekt die Metadaten `shift_surface`? Bei Terrain3D: ShiftTerrain3DSurfaces mit **Terrain** und **Surfaces** in der Szene? Stimmt der Index zur Textur-ID? |
| Automatik schaltet nicht hoch | `auto_upshift_rpm_min` muss unter `max_rpm` liegen. |

---

## 13. Bekannte Einschränkungen

- **Splitscreen:** Alle Autos mit **Player Controlled** lesen dieselben
  Eingabe-Aktionen. Für zwei Spieler an einem Gerät schalte beide Autos aus und
  fülle ihre `controls` selbst, z. B. aus Gamepad 1 und Gamepad 2
  (`Input.get_joy_axis(gerät, …)`).
- **Langsames Wegrollen im Stand:** Steht ein Auto ohne Bremse und ohne Gang
  leicht schräg in der Federung (Nase hoch oder runter), kann es auf ebenem
  Boden sehr langsam anrollen. Abhilfe: Handbremse ziehen bzw. bei NPCs
  `controls.handbrake = 1.0`.
- Die **Traktionskontrolle** regelt nur den Schlupf beim Beschleunigen. Gegen
  seitliches Ausbrechen hilft sie nicht; das wäre die Aufgabe von ESP.
- **ELECTRONIC_LSD** und **Stability** (ESP) sind noch nicht umgesetzt.
- **Sturz** (`camber_angles`, `camber_gain`) und `wheel_mass` werden derzeit
  noch nicht verwendet.
- Nur das **Brush-Reifenmodell** ist verfügbar.
- **Reifenspuren** werden flach an der Aufstandsstelle gelegt. Auf stark
  gewölbtem Boden oder an Kanten können sie leicht schweben oder einsinken.
- Die **weichen Ränder des Rauchs** am Boden (Proximity Fade) brauchen den
  Forward+- oder Mobile-Renderer. Im Compatibility-Renderer sieht man dort eine
  harte Kante.
- Die Rad-Strahlen dürfen **skaliert** sein (z. B. Scale 1,4); das Addon rechnet
  die Richtungen trotzdem richtig.
- Getestet mit **Godot 4.7.2** und Tickraten von 60 bis 300 Hz.

---

*Lizenz: MIT, siehe `LICENSE`.*
