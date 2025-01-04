#!/bin/bash

# Set SQLite database file
DB_FILE="metro.db"

echo "Enter the source subway station name:"
read SOURCE_STATION

# Get current date and time in HH:MM:SS format
CURRENT_TIME=$(date +"%H:%M:%S")

# Execute SQL query
sqlite3 "$DB_FILE" <<EOF
.mode column
.header on

-- Query to find trips
SELECT DISTINCT t.trip_id, t.trip_headsign, r.route_id, r.route_short_name, st1.departure_time
FROM trips t
JOIN routes r ON t.route_id = r.route_id
JOIN stop_times st1 ON t.trip_id = st1.trip_id
JOIN stops s1 ON st1.stop_id = s1.stop_id
JOIN stop_times st2 ON t.trip_id = st2.trip_id
JOIN stops s2 ON st2.stop_id = s2.stop_id
WHERE s1.stop_name = "$SOURCE_STATION"
  AND s2.stop_id IN ("14703", "14703R", "14703T")
  AND r.agency_id = 2
  AND st1.stop_sequence < st2.stop_sequence
  AND st1.departure_time > "$CURRENT_TIME"
  ORDER BY st1.departure_time;

EOF