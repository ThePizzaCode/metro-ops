#!/bin/bash

# SQLite database file
DB_FILE="metro.db"

# Hardcoded transfer points
declare -A TRANSFERS
TRANSFERS["M3"]="Eroilor 1 (M1/3)"
TRANSFERS["M5"]="Eroilor 2 (M5),Eroilor 1 (M1/3)"
TRANSFERS["M2"]="Piața Unirii 2 (M2),Piața Unirii 1 (M1/3)"

# Function to determine the line of a station
get_station_line() {
  local station="$1"
  sqlite3 "$DB_FILE" <<EOF
.headers off
.mode list
SELECT DISTINCT r.route_short_name
FROM routes r
JOIN trips t ON r.route_id = t.route_id
JOIN stop_times st ON t.trip_id = st.trip_id
JOIN stops s ON st.stop_id = s.stop_id
WHERE s.stop_name = "$station"
  AND r.agency_id = 2;  -- Only agency 2 (subways)
EOF
}

# Function to find the first available trip after the current time
find_first_trip() {
  local source_station="$1"
  local destination_station="$2"
  local current_time="$3"

  sqlite3 "$DB_FILE" <<EOF
.headers off
.mode list
SELECT DISTINCT
    t.trip_id,
    t.trip_headsign,
    r.route_short_name,
    COALESCE(st1.departure_time, 'N/A') AS departure_time,
    COALESCE(st2.arrival_time, 'N/A')  AS arrival_time,
    s1.stop_name,
    s2.stop_name
FROM trips t
JOIN routes r    ON t.route_id = r.route_id
JOIN stop_times st1 ON t.trip_id  = st1.trip_id
JOIN stop_times st2 ON t.trip_id  = st2.trip_id
JOIN stops s1    ON st1.stop_id   = s1.stop_id
JOIN stops s2    ON st2.stop_id   = s2.stop_id
WHERE s1.stop_name = "$source_station"
  AND s2.stop_name = "$destination_station"
  AND st1.stop_sequence < st2.stop_sequence
  -- If departure_time is missing or later than current_time, consider it valid
  AND (
    st1.departure_time > "$current_time"
    OR st1.departure_time IS NULL
    OR st1.departure_time = ''
  )
  AND r.agency_id = 2  -- Only agency 2 (subways)
ORDER BY COALESCE(st1.departure_time, st2.arrival_time)
LIMIT 1;
EOF
}

# Function to display a trip and return its arrival time (or current time if missing)
display_trip() {
  local trip_info="$1"
  if [[ -z "$trip_info" ]]; then
    echo "No available trip found."
    return 1
  fi

  IFS='|' read -r trip_id head_sign route departure_time arrival_time source_station destination_station <<< "$trip_info"

  echo "Trip ID: $trip_id"
  echo "Head Sign: $head_sign"
  echo "Route: $route"
  echo "Departure Time: $departure_time"
  echo "Arrival Time: $arrival_time"
  echo "From: $source_station"
  echo "To: $destination_station"

  # Return the arrival time or current time if arrival time is "N/A"
  if [[ "$arrival_time" == "N/A" ]]; then
    date +"%H:%M:%S"
  else
    echo "$arrival_time"
  fi
}

list_trips() {
  echo "Enter the source station:"
  read SOURCE_STATION

  # Determine the line of the source station
  LINE=$(get_station_line "$SOURCE_STATION" | head -n 1)
  if [[ -z "$LINE" ]]; then
    echo "Error: Could not determine the line for '$SOURCE_STATION'."
    return
  fi

  if [[ "$LINE" == "M1" || "$LINE" == "M4" ]]; then
    # Direct route on M1 or M4
    DESTINATION="Gara de Nord 1 (M1)"
    if [[ "$LINE" == "M4" ]]; then
      DESTINATION="Gara de Nord 2 (M4)"
    fi

    echo "Finding direct routes from '$SOURCE_STATION' to $DESTINATION..."
    TRIP=$(find_first_trip "$SOURCE_STATION" "$DESTINATION" "$(date +"%H:%M:%S")")
    display_trip "$TRIP"
  else
    # Otherwise, look up the TRANSFERS array to see how many transfers
    TRANSFER=${TRANSFERS["$LINE"]}
    if [[ -z "$TRANSFER" ]]; then
      echo "Error: No transfer defined for line '$LINE'."
      return
    fi

    # If there's a comma, it means two-step transfer
    if [[ "$TRANSFER" == *","* ]]; then
      IFS=',' read -r FIRST_TRANSFER SECOND_TRANSFER <<< "$TRANSFER"

      echo "Finding routes from '$SOURCE_STATION' to '$FIRST_TRANSFER'..."
      FIRST_TRIP=$(find_first_trip "$SOURCE_STATION" "$FIRST_TRANSFER" "$(date +"%H:%M:%S")")
      ARRIVAL_TIME=$(display_trip "$FIRST_TRIP" | tail -1)

      # If arrival time is "N/A", replace it with the current time
      if [[ "$ARRIVAL_TIME" == "N/A" ]]; then
        ARRIVAL_TIME=$(date +"%H:%M:%S")
      fi
      if [[ -z "$ARRIVAL_TIME" || "$ARRIVAL_TIME" == "No available trip found." ]]; then
        echo "No available trip from '$SOURCE_STATION' to '$FIRST_TRANSFER'."
        return
      fi

      echo "Finding routes from '$SECOND_TRANSFER' to Gara de Nord after $ARRIVAL_TIME..."
      SECOND_TRIP=$(find_first_trip "$SECOND_TRANSFER" "Gara de Nord 1 (M1)" "$ARRIVAL_TIME")
      SECOND_DISPLAY=$(display_trip "$SECOND_TRIP")
      if [[ "$SECOND_DISPLAY" == "No available trip found." ]]; then
        echo "No available trip from '$SECOND_TRANSFER' to Gara de Nord after $ARRIVAL_TIME."
        return
      fi

      echo
      echo "Itinerary:"
      echo "---------------------------"
      echo "1. From $SOURCE_STATION to $FIRST_TRANSFER:"
      display_trip "$FIRST_TRIP"
      echo
      echo "2. From $SECOND_TRANSFER to Gara de Nord:"
      display_trip "$SECOND_TRIP"

    else
      # Only one transfer
      echo "Finding routes from '$SOURCE_STATION' to '$TRANSFER'..."
      FIRST_TRIP=$(find_first_trip "$SOURCE_STATION" "$TRANSFER" "$(date +"%H:%M:%S")")
      ARRIVAL_TIME=$(display_trip "$FIRST_TRIP" | tail -1)

      # If arrival time is "N/A", replace it with the current time
      if [[ "$ARRIVAL_TIME" == "N/A" ]]; then
        ARRIVAL_TIME=$(date +"%H:%M:%S")
      fi
      if [[ -z "$ARRIVAL_TIME" || "$ARRIVAL_TIME" == "No available trip found." ]]; then
        echo "No available trip from '$SOURCE_STATION' to '$TRANSFER'."
        return
      fi

      echo "Finding routes from '$TRANSFER' to Gara de Nord after $ARRIVAL_TIME..."
      SECOND_TRIP=$(find_first_trip "$TRANSFER" "Gara de Nord 1 (M1)" "$ARRIVAL_TIME")
      SECOND_DISPLAY=$(display_trip "$SECOND_TRIP")
      if [[ "$SECOND_DISPLAY" == "No available trip found." ]]; then
        echo "No available trip from '$TRANSFER' to Gara de Nord after $ARRIVAL_TIME."
        return
      fi

      echo
      echo "Itinerary:"
      echo "-------------------------------------"
      echo "1. From $SOURCE_STATION to $TRANSFER:"
      display_trip "$FIRST_TRIP"
      echo
      echo "2. From $TRANSFER to Gara de Nord:"
      display_trip "$SECOND_TRIP"
    fi
  fi
}

# Main menu
while true; do
  echo "Choose an option:"
  echo "1) Find routes to Gara de Nord"
  echo "2) Exit"
  read CHOICE
  case $CHOICE in
    1)
      list_trips
      ;;
    2)
      echo "Exiting. Goodbye!"
      exit 0
      ;;
    *)
      echo "Invalid choice. Please try again."
      ;;
  esac
done
