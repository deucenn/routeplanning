from flask import Flask, jsonify, request
from sqlalchemy import create_engine, text
from geopy.geocoders import Nominatim
from geopy.exc import GeocoderTimedOut
from flask_cors import CORS  

app = Flask(__name__)
CORS(app)  

#  Datenbankverbindung herstellen
engine = create_engine('postgresql://osmuser:postgis123-@localhost:57001/osmdb')

# Geocoding-Service initialisieren und defininieren
geolocator = Nominatim(user_agent="routing_app")

def geocode_address(address):
    try:
        location = geolocator.geocode(address)
        if location:
            return location.latitude, location.longitude
        else:
            return None
    except GeocoderTimedOut:
        return None

@app.route('/', methods=['GET'])
def hello():
    return jsonify({"message": "Server runs!"})

@app.route('/route', methods=['GET'])
def get_route():
    try:
        with engine.connect() as conn:
            print("Connection to database established successfully.")
    except Exception as e:
        print(f"Failed to connect to database: {e}")
    # Adressen vom Frontend aufnehmen
    start_address = request.args.get('start_address')
    end_address = request.args.get('end_address')

    # Adressen in Koordinaten umwandeln
    start_coords = geocode_address(start_address)
    end_coords = geocode_address(end_address)

    if not start_coords or not end_coords:
        return jsonify({"error": "Could not geocode one or both addresses"}), 400

    # Koordinaten in EPSG:4326 umwandeln
    start_point = f"SRID=4326;POINT({start_coords[1]} {start_coords[0]})"
    end_point = f"SRID=4326;POINT({end_coords[1]} {end_coords[0]})"

    # SQL-Abfrage: pgr_dijkstra
    sql_query = text("""
    WITH route AS (
        SELECT edge
        FROM pgr_dijkstra(
            'SELECT osm_id AS id, source, target, length AS cost FROM wuppertal_roads_topology',
            (
                SELECT id 
                FROM wuppertal_roads_topology_vertices_pgr 
                ORDER BY the_geom <-> ST_Transform(ST_GeomFromText(:start_point, 4326), 3857) 
                LIMIT 1
            ),
            (
                SELECT id 
                FROM wuppertal_roads_topology_vertices_pgr 
                ORDER BY the_geom <-> ST_Transform(ST_GeomFromText(:end_point, 4326), 3857) 
                LIMIT 1
            ),
            directed := false
        )
    )
    SELECT ST_AsGeoJSON(ST_Union(way)) AS route
    FROM wuppertal_roads_topology
    WHERE osm_id IN (SELECT edge FROM route);
""")


    # SQL-Abfrage ausführen und Ergebnis auslesen
    try:
        with engine.connect() as conn:
            result = conn.execute(sql_query, {"start_point": start_point, "end_point": end_point})
            rows = result.fetchall()
    except Exception as e:
        return jsonify({"error": str(e)}), 500

    # Ergebnis in GeoJSON-Format umwandeln und weiterleiten an Frontend
    if rows:
        route_geojson = rows[0][0]
        return jsonify({"route": route_geojson})
    else:
        return jsonify({"error": "No route found"}), 404

if __name__ == '__main__':
    app.run(debug=True)
