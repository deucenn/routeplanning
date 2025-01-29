import psycopg2
import re

# Verbindung zur PostgreSQL-Datenbank
conn = psycopg2.connect(
    database="osmdb",
    user="osmuser",
    password="postgis123-",
    host="localhost",
    port="57001"
)

cur = conn.cursor()
num_iterations = 100  # Anzahl der Messungen
total_time = 0  # Gesamtzeit

for _ in range(num_iterations):
    # EXPLAIN ANALYZE ausführen
    cur.execute("""
        EXPLAIN ANALYZE
        SELECT * FROM pgr_dijkstra(
            'SELECT osm_id AS id,
                source,
                target,
                length AS cost
            FROM germany_roads',
            1181197, 5, directed := false);
    """)

    # Alle Zeilen von EXPLAIN ANALYZE auslesen
    explain_output = "\n".join(row[0] for row in cur.fetchall())

    # "Execution Time" mit Regex extrahieren
    match = re.search(r"Execution Time: ([0-9\.]+) ms", explain_output)
    if match:
        execution_time = float(match.group(1))  # Zeit in Millisekunden
        total_time += execution_time
    else:
        print("⚠️ Fehler: Execution Time nicht gefunden")

# Durchschnitt berechnen & ausgeben
average_time = total_time / num_iterations
print(f"✅ Durchschnittliche Execution Time: {average_time:.3f} ms")

# Verbindung schließen
cur.close()
conn.close()