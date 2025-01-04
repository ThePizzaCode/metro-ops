#!/bin/bash

# SQLite database file
DB_FILE="metro.db"

# Function to list available trips
list_trips() {
  echo "Enter the source station on M1 (e.g., 'Eroilor'):"
  read SOURCE_STATION
  sqlite3 "$DB_FILE" <<EOF
.headers on
.mode column
SELECT DISTINCT
    t.trip_id AS "Trip ID",
    t.trip_headsign AS "Head Sign",
    r.route_short_name AS "Route",
    st1.departure_time AS "Departure Time",
    s1.stop_name AS "Source Station",
    s2.stop_name AS "Destination Station"
FROM trips t
JOIN routes r ON t.route_id = r.route_id
JOIN stop_times st1 ON t.trip_id = st1.trip_id
JOIN stop_times st2 ON t.trip_id = st2.trip_id
JOIN stops s1 ON st1.stop_id = s1.stop_id
JOIN stops s2 ON st2.stop_id = s2.stop_id
WHERE s1.stop_name = "$SOURCE_STATION"
  AND (s2.stop_name = "Gara de Nord 1 (M1)" OR s2.stop_name = "Gara de Nord 2 (M4)")
  AND st1.stop_sequence < st2.stop_sequence
ORDER BY st1.departure_time;
EOF
}

# Function to show trip details
show_trip_details() {
  echo "Enter the Trip ID to view details:"
  read TRIP_ID
  sqlite3 "$DB_FILE" <<EOF
.headers on
.mode column
SELECT
    st.stop_sequence AS "Stop Sequence",
    s.stop_name AS "Stop Name",
    st.departure_time AS "Departure Time"
FROM stop_times st
JOIN stops s ON st.stop_id = s.stop_id
WHERE st.trip_id = "$TRIP_ID"
ORDER BY st.stop_sequence;
EOF
}

# Main menu
while true; do
  echo "Choose an option:"
  echo "1) List available trips from a station to Gara de Nord"
  echo "2) View details for a specific trip"
  echo "3) Exit"
  read CHOICE
  case $CHOICE in
    1)
      list_trips
      ;;
    2)
      show_trip_details
      ;;
    3)
      echo "Exiting. Goodbye!"
      exit 0
      ;;
    *)
      echo "Invalid choice. Please try again."
      ;;
  esac
done
