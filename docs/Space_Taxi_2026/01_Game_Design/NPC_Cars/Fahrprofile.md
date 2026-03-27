
# 🏎️ NPC Fahrprofile: Konfiguration



## 📊 Quick-Vergleich der Profile

| **Parameter**        | **Vorsichtig** | **Baseline (Normal)** | **Elegant (Sanft)** | **Sportlich** |
| -------------------- | -------------- | --------------------- | ------------------- | ------------- |
| `max_speed`          | 180            | **200**               | 225                 | 225           |
| `steering_lerp`      | 5.0            | **5.0**               | 3.8                 | 5.2           |
| `hover_height`       | 30             | **30**                | 44                  | 32            |
| `hover_speed_factor` | 0.35           | **0.35**              | 0.22                | 0.35          |
| `touchdown_speed`    | 60             | **60**                | 42                  | 60            |

## ⚙️ Detail-Konfigurationen

### 1. Vorsichtiges Profil

_Reduzierte Geschwindigkeit, standardmäßiges Parkverhalten._
`_max_speed = 180`
`_steering_lerp = 5.0`
`lot_landing_start_distance = 64`
`lot_hover_height = 30`
`lot_hover_speed_factor = 0.35`
`lot_touchdown_speed = 60`
`gear_transition_duration = 0.5`
`lot_wait_time_min = 15`
`lot_wait_time_max = 30`

### 2. Baseline (Normal)

_Die Standardwerte für den durchschnittlichen Verkehr._
`_max_speed = 200`
`_steering_lerp = 5.0`
`lot_landing_start_distance = 64`
`lot_hover_height = 30`
`lot_hover_speed_factor = 0.35`
`lot_touchdown_speed = 60`
`gear_transition_duration = 0.5`
`lot_wait_time_min = 15`
`lot_wait_time_max = 30`


## 3. Elegant & Bedächtig

*Höhere Geschwindigkeit auf der Strecke, aber ein sehr sanfter, fast "schwebender" Parkvorgang.*
`_max_speed = 225`
`_steering_lerp = 3.8            # Trägeres Lenken`
`lot_landing_start_distance = 86 # Früherer Sinkflug`
`lot_hover_height = 44           # Höheres Schweben`
`lot_hover_speed_factor = 0.22   # Sehr langsames Einschweben`
`lot_touchdown_speed = 42        # Sanftes Aufsetzen`
`gear_transition_duration = 0.62`
`lot_wait_time_min = 18`
`lot_wait_time_max = 32`


## 4. Sportlich & Direkt

*Flott unterwegs mit direkterem Lenkverhalten und Standard-Parkmanövern.*
`_max_speed = 225`
`_steering_lerp = 5.2            # Direktere Lenkung`
`lot_landing_start_distance = 70`
`lot_hover_height = 32`
`lot_hover_speed_factor = 0.35`
`lot_touchdown_speed = 60`
`gear_transition_duration = 0.5`
`lot_wait_time_min = 15`
`lot_wait_time_max = 30`