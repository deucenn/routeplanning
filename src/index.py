from flask import Flask, jsonify, request
from sqlalchemy import create_engine
from geoalchemy2 import Geometry

app = Flask(__name__)

engine = create_engine('postgresql://user:password@host:port/database')

print("Connection to database established")

@app.route('/route', methods=['GET'])
def get_route():
    start_point = request.args.get('start')  # z.B. 'SRID=4326;POINT(10.0 50.0)'
    end_point = request.args.get('end')

    # SQL-Abfrage erstellen (dynamisch mit start_point und end_point)
    sql_query = f"""
        SELECT ST_AsGeoJSON(ST_MakeLine(n1.geom, n2.geom)) AS route, n1.id AS start_node_id, n2.id AS end_node_id
        FROM nodes n1, nodes n2
        WHERE n1.id = {start_node_id} AND n2.id = {end_node_id}
    """


    with engine.connect() as conn:
        result = conn.execute(sql_query)
        rows = result.fetchall()

    print("Query send")

    # Ergebnis in JSON umwandeln

    return jsonify(result)

if __name__ == '__main__':
    app.run(debug=True)

