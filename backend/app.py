import psycopg2
from psycopg2.extras import RealDictCursor
from fastapi import FastAPI, File, UploadFile, Form
import face_recognition
import numpy as np
import io
import cv2
import json
import os
from datetime import datetime
import uvicorn

app = FastAPI()

# Render will provide the DATABASE_URL environment variable
# Format: postgresql://postgres:[PASSWORD]@db.xyz.supabase.co:5432/postgres
DATABASE_URL = os.getenv("DATABASE_URL", "your_supabase_uri_here")

def get_db_connection():
    return psycopg2.connect(DATABASE_URL)

def init_db():
    conn = get_db_connection()
    cursor = conn.cursor()
    # Create tables in PostgreSQL (Supabase)
    cursor.execute('CREATE TABLE IF NOT EXISTS classes (id SERIAL PRIMARY KEY, name TEXT UNIQUE)')
    cursor.execute('''CREATE TABLE IF NOT EXISTS students 
                      (id SERIAL PRIMARY KEY, name TEXT, reg_no TEXT UNIQUE, 
                       class_name TEXT, encoding TEXT)''')
    cursor.execute('CREATE TABLE IF NOT EXISTS logs (id SERIAL PRIMARY KEY, name TEXT, reg_no TEXT, class_name TEXT, date TEXT, time TEXT, status TEXT)')
    
    cursor.execute("SELECT COUNT(*) FROM classes")
    if cursor.fetchone()[0] == 0:
        cursor.execute("INSERT INTO classes (name) VALUES (%s)", ("VIII - R",))
    
    conn.commit()
    cursor.close()
    conn.close()

init_db()

@app.get("/get_classes")
def get_classes():
    conn = get_db_connection(); cursor = conn.cursor()
    cursor.execute("SELECT name FROM classes ORDER BY name ASC")
    classes = [row[0] for row in cursor.fetchall()]
    cursor.close(); conn.close(); return classes

@app.post("/add_class")
def add_class(name: str = Form(...)):
    clean_name = name.strip().upper()
    try:
        conn = get_db_connection(); cursor = conn.cursor()
        cursor.execute("INSERT INTO classes (name) VALUES (%s)", (clean_name,))
        conn.commit(); cursor.close(); conn.close(); return {"status": "success"}
    except: return {"status": "error"}

@app.post("/edit_class")
def edit_class(old_name: str = Form(...), new_name: str = Form(...)):
    old, new = old_name.strip().upper(), new_name.strip().upper()
    conn = get_db_connection(); cursor = conn.cursor()
    cursor.execute("UPDATE classes SET name = %s WHERE name = %s", (new, old))
    cursor.execute("UPDATE students SET class_name = %s WHERE class_name = %s", (new, old))
    cursor.execute("UPDATE logs SET class_name = %s WHERE class_name = %s", (new, old))
    conn.commit(); cursor.close(); conn.close(); return {"status": "success"}

@app.post("/delete_class")
def delete_class(name: str = Form(...)):
    target = name.strip().upper()
    conn = get_db_connection(); cursor = conn.cursor()
    cursor.execute("DELETE FROM classes WHERE name = %s", (target,))
    cursor.execute("DELETE FROM students WHERE class_name = %s", (target,))
    cursor.execute("DELETE FROM logs WHERE class_name = %s", (target,))
    conn.commit(); cursor.close(); conn.close(); return {"status": "success"}

@app.post("/register")
async def register(name: str = Form(...), reg_no: str = Form(...), class_name: str = Form(...), file: UploadFile = File(...)):
    try:
        cn, cr, cl = name.strip().title(), reg_no.strip().upper(), class_name.strip().upper()
        image = face_recognition.load_image_file(io.BytesIO(await file.read()))
        encs = face_recognition.face_encodings(image)
        if not encs: return {"status": "error", "message": "No face detected"}
        
        conn = get_db_connection(); cursor = conn.cursor()
        cursor.execute("INSERT INTO students (name, reg_no, class_name, encoding) VALUES (%s, %s, %s, %s)", 
                       (cn, cr, cl, json.dumps(encs[0].tolist())))
        conn.commit(); cursor.close(); conn.close()
        return {"status": "success"}
    except Exception as e: return {"status": "error", "message": str(e)}

@app.post("/scan")
async def scan_face(class_name: str = Form(...), file: UploadFile = File(...)):
    now = datetime.now(); today = now.strftime("%Y-%m-%d"); cl = class_name.upper()
    conn = get_db_connection(); cursor = conn.cursor()
    cursor.execute("SELECT name, reg_no, encoding FROM students WHERE class_name = %s", (cl,))
    rows = cursor.fetchall()
    
    if not rows: return {"status": "none", "message": "No students"}
    
    known_encs = [np.array(json.loads(r[2])) for r in rows]
    meta = [{"name": r[0], "reg_no": r[1]} for r in rows]
    
    frame = cv2.imdecode(np.frombuffer(await file.read(), np.uint8), cv2.IMREAD_COLOR)
    rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    face_encs = face_recognition.face_encodings(rgb, face_recognition.face_locations(rgb, model="hog"))
    
    if not face_encs: return {"status": "none", "message": "No face detected"}
    
    matches = face_recognition.compare_faces(known_encs, face_encs[0], tolerance=0.5)
    msg = "UNKNOWN"
    if True in matches:
        m = meta[matches.index(True)]
        cursor.execute("SELECT id FROM logs WHERE reg_no=%s AND date=%s AND class_name=%s", (m['reg_no'], today, cl))
        if not cursor.fetchone():
            cursor.execute("INSERT INTO logs (name, reg_no, class_name, date, time, status) VALUES (%s, %s, %s, %s, %s, %s)", 
                           (m['name'], m['reg_no'], cl, today, now.strftime("%H:%M:%S"), "Present"))
            msg = f"MARKED: {m['name']}"
        else: msg = f"ALREADY MARKED: {m['name']}"
    
    conn.commit(); cursor.close(); conn.close()
    return {"status": "done", "message": msg}

@app.post("/toggle_status")
async def toggle(reg_no: str = Form(...), class_name: str = Form(...)):
    today = datetime.now().strftime("%Y-%m-%d"); cl = class_name.upper(); rn = reg_no.upper()
    conn = get_db_connection(); cursor = conn.cursor()
    cursor.execute("SELECT name FROM students WHERE reg_no = %s AND class_name = %s", (rn, cl))
    student = cursor.fetchone()
    if not student: return {"status": "error"}
    cursor.execute("SELECT id FROM logs WHERE reg_no=%s AND date=%s AND class_name=%s", (rn, today, cl))
    log = cursor.fetchone()
    if log: cursor.execute("DELETE FROM logs WHERE id = %s", (log[0],))
    else: cursor.execute("INSERT INTO logs (name, reg_no, class_name, date, time, status) VALUES (%s, %s, %s, %s, %s, %s)", 
                       (student[0], rn, cl, today, datetime.now().strftime("%H:%M:%S"), "Present"))
    conn.commit(); cursor.close(); conn.close(); return {"status": "success"}

@app.post("/bulk_delete")
async def bulk(reg_nos: str = Form(...)):
    conn = get_db_connection(); cursor = conn.cursor()
    for r in reg_nos.split(","):
        cursor.execute("DELETE FROM students WHERE reg_no = %s", (r.upper(),))
        cursor.execute("DELETE FROM logs WHERE reg_no = %s", (r.upper(),))
    conn.commit(); cursor.close(); conn.close(); return {"status": "success"}

@app.get("/students/{class_name}")
def get_students(class_name: str):
    today = datetime.now().strftime("%Y-%m-%d"); cl = class_name.upper()
    conn = get_db_connection(); cursor = conn.cursor()
    cursor.execute("SELECT name, reg_no FROM students WHERE class_name = %s ORDER BY name ASC", (cl,))
    sts = cursor.fetchall()
    cursor.execute("SELECT reg_no FROM logs WHERE class_name=%s AND date=%s", (cl, today))
    pres = [r[0] for r in cursor.fetchall()]
    cursor.close(); conn.close()
    return [{"name": s[0], "reg_no": s[1], "is_present": s[1] in pres} for s in sts]

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8000))
    uvicorn.run(app, host="0.0.0.0", port=port)