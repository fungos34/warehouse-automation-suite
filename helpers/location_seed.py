import numpy as np
from typing import Tuple, List
import sqlite3
import os

def generate_insert_sql(
    front_view: List[List[int]],
    top_view: List[List[int]],
    origin_coord: Tuple[float, float, float],
    location_dimensions: Tuple[float, float, float],
    corridor_dimensions: Tuple[float, float, float],
    postfix: str = ""
) -> str:
    
    A = np.array(front_view)
    B = np.array(top_view)

    A = np.flipud(A)
    A = np.fliplr(A)
    B = np.flipud(B)
    B = np.fliplr(B)

    if not A.shape[1] == B.shape[1]:
        raise ValueError("The number of columns in front_view must match the number of rows in top_view.")

    C = np.zeros((B.shape[0], A.shape[1], A.shape[0]))
    print("Matrix C: \n",C)
    for i in range(C.shape[0]):
        for j in range(C.shape[1]):
            for k in range(C.shape[2]):
                C[i, j, k] = A[k, j] * B[i, j]
    print("Matrix C: \n",C)
    O = np.zeros_like(C, dtype=tuple)
    for i in range(C.shape[0]):
        for j in range(C.shape[1]):
            for k in range(C.shape[2]):
                O[i, j, k] = (
                    (origin_coord[0] + (np.sum(C[:i, 0, 0], axis=0) * location_dimensions[0]) + ((i - np.sum(C[:i, 0, 0], axis=0)) * corridor_dimensions[0])),
                    (origin_coord[1] + (np.sum(C[0, :j, 0], axis=0) * location_dimensions[1]) + ((j - np.sum(C[0, :j, 0], axis=0)) * corridor_dimensions[1])),
                    (origin_coord[2] + (np.sum(C[0, 0, :k], axis=0) * location_dimensions[2]) + ((k - np.sum(C[0, 0, :k], axis=0)) * corridor_dimensions[2])),
                )
    print("Origin coordinates O: \n", origin_coord)
    values = []
    for i in range(C.shape[0]):
        for j in range(C.shape[1]):
            for k in range(C.shape[2]):
                if C[i, j, k] == 1:
                    x, y, z = O[i, j, k]
                    letter = chr(ord('A') + C.shape[1] - 1 - j)
                    number = i + 1
                    level = f"L{k+1}"
                    code = f"LOC_{letter}{number}_{level}{postfix}"
                    desc = f"Shelf {letter}{number} Level {level}"
                    values.append(
                        (code, x, y, z, location_dimensions[0], location_dimensions[1], location_dimensions[2], 1, None, desc)
                    )
    
    space = O[-1, -1, -1]
    space_list = list(space)
    if C[-1, -1, -1] == 1:
        for i in range(len(space_list)):
            space_list[i] = space_list[i] + location_dimensions[i]   
    else:
        for i in range(len(space_list)):
            space_list[i] = space_list[i] + corridor_dimensions[i]
    space = tuple(space_list) 

    return values, space

def write_sql_file(values, filename="locations.sql"):
    if values:
        sql = (
            "INSERT INTO location (code, x, y, z, dx, dy, dz, warehouse_id, partner_id, description) VALUES\n" +
            ",\n".join(
                f"('{v[0]}', {v[1]}, {v[2]}, {v[3]}, {v[4]}, {v[5]}, {v[6]}, {v[7]}, NULL, '{v[9]}')" for v in values
            ) + ";"
        )
    else:
        sql = "-- No locations to insert"
    with open(filename, "w", encoding="utf-8") as f:
        f.write(sql)

def update_database(values, db_path):
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    # Delete all locations starting with LOC_
    cur.execute("DELETE FROM location WHERE code LIKE 'LOC_%'")
    # Insert new locations
    cur.executemany(
        "INSERT INTO location (code, x, y, z, dx, dy, dz, warehouse_id, partner_id, description) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        values
    )
    conn.commit()
    conn.close()

# Example usage
if __name__ == "__main__":

    front_view = [
        [1, 1, 0, 1, 1, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1],
        [1, 1, 0, 1, 1, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1],
        [1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1],
        [1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1],
    ]

    top_view = [
        [1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1],
        [1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1],
        [1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1],
        [1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1],
        [1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1],
        [1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1],
        [1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1],
    ]
    values1, space1 = generate_insert_sql(front_view, top_view, (0.5, 0.5, 0), (4, 1, 2.5), (5, 5, 5))
    # i=0
    # for value in values:
    #     i+=1
    #     print("x: ", value[1], "\ty: ", value[2], "\tz: ", value[3], "\tcode: ", value[0], "\t#", i)
    # values2, space2 = generate_insert_sql(front_view, top_view, (space1[0] + 5, space1[1] + 5, 0), (4, 1, 2.5), (5, 5, 5), "_2")
    # values = values1
    write_sql_file(values1, "locations.sql")
    # db_path = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "warehouse.db"))
    # update_database(values, db_path)