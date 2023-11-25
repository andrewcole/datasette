FROM docker.io/library/python:3.9.18-bullseye AS builder

# Install sqlite-utils PIP package
RUN pip install sqlite-utils==3.35.2

FROM builder AS galog-builder

# Add galog.json file
ADD galog.json .

# Create database
RUN sqlite-utils insert galog.db flights galog.json --pk=id --flatten

# Normalize type and reg columns
RUN sqlite-utils extract galog.db flights type reg \
  --rename reg registration \
  --table aircraft

# Normalize type column
RUN sqlite-utils extract galog.db aircraft type \
  --table type

# Normalize crew column
RUN sqlite-utils extract galog.db flights crew \
  --rename crew name \
  --table crew \
  --fk-column crew_id

# Normalize pic column
RUN sqlite-utils extract galog.db flights pic \
  --rename pic name \
  --table crew \
  --fk-column pic_id

# Convert columns
RUN sqlite-utils convert galog.db flights \
  date 'r.parsedate(value)'
RUN sqlite-utils transform galog.db flights \
  --type singleengine_dual float \
  --type singleengine_command float \
  --type instrument_simulator float
 
# Create log view
RUN sqlite-utils create-view galog.db log \
  'select \
    flights.`date` as `Date`, \
    type.`type` as `Type`, \
    aircraft.`registration` as `Reg`, \
    pic.`name` as PIC, \
    crew.`name` as Crew, \
    flights.`route` as `Route`, \
    flights.`details` as `Details`, \
    flights.`singleengine_dual` as `Dual`, \
    flights.`singleengine_command` as `Command`, \
    flights.`instrument_simulator` as `Simulator`, \
    flights.`links_blog` as `Blog`, \
    flights.`links_photos` as `Photos` \
  from \
    flights \
    inner join crew as pic on flights.`pic_id` = pic.`id` \
    inner join crew as crew on flights.`crew_id` = crew.`id` \
    inner join aircraft on flights.`aircraft_id` = aircraft.`id` \
    inner join type on aircraft.`type_id` = type.`id` \
  order by flights.`date`'

FROM docker.io/datasetteproject/datasette:0.64.5

COPY --from=galog-builder galog.db /mnt/galog.db

CMD "datasette" "-p" "8001" "-h" "0.0.0.0" "/mnt/galog.db"
