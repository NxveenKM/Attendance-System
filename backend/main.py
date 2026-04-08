import sqlite3
from fastapi import FastAPI, File, UploadFile, Form
import face_recognition
import numpy as np
import os
import io
import cv2
import json
from datetime import datetime
import uvicorn

app = FastAPI()

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DB_NAME = os.path.join(BASE_DIR, "attendance_system.db")

def init_db():
    conn = sqlite3.connect(DB_NAME)
    cursor = conn.cursor()
    cursor.execute('CREATE TABLE IF NOT EXISTS classes (id INTEGER PRIMARY KEY, name TEXT UNIQUE)')
    cursor.execute('''CREATE TABLE IF NOT EXISTS students 
                      (id INTEGER PRIMARY KEY, name TEXT, reg_no TEXT UNIQUE, 
                       class_name TEXT, encoding TEXT)''')
    cursor.execute('CREATE TABLE IF NOT EXISTS logs (id INTEGER PRIMARY KEY, name TEXT, reg_no TEXT, class_name TEXT, date TEXT, time TEXT, status TEXT)')
    
    cursor.execute("SELECT COUNT(*) FROM classes")
    if cursor.fetchone()[0] == 0:
        cursor.execute("INSERT INTO classes (name) VALUES (?)", ("VIII - R",))
    conn.commit()
    conn.close()

init_db()

@app.get("/get_classes")
def get_classes():
    conn = sqlite3.connect(DB_NAME); cursor = conn.cursor()
    cursor.execute("SELECT name FROM classes ORDER BY name ASC")
    classes = [row[0] for row in cursor.fetchall()]
    conn.close(); return classes

@app.post("/add_class")
def add_class(name: str = Form(...)):
    clean_name = name.strip().upper()
    try:
        conn = sqlite3.connect(DB_NAME); cursor = conn.cursor()
        cursor.execute("INSERT INTO classes (name) VALUES (?)", (clean_name,))
        conn.commit(); conn.close(); return {"status": "success"}
    except: return {"status": "error"}

@app.post("/edit_class")
def edit_class(old_name: str = Form(...), new_name: str = Form(...)):
    old, new = old_name.strip().upper(), new_name.strip().upper()
    conn = sqlite3.connect(DB_NAME); cursor = conn.cursor()
    cursor.execute("UPDATE classes SET name = ? WHERE name = ?", (new, old))
    cursor.execute("UPDATE students SET class_name = ? WHERE class_name = ?", (new, old))
    cursor.execute("UPDATE logs SET class_name = ? WHERE class_name = ?", (new, old))
    conn.commit(); conn.close(); return {"status": "success"}

@app.post("/delete_class")
def delete_class(name: str = Form(...)):
    target = name.strip().upper()
    conn = sqlite3.connect(DB_NAME); cursor = conn.cursor()
    cursor.execute("DELETE FROM classes WHERE name = ?", (target,))
    cursor.execute("DELETE FROM students WHERE class_name = ?", (target,))
    cursor.execute("DELETE FROM logs WHERE class_name = ?", (target,))
    conn.commit(); conn.close(); return {"status": "success"}

@app.post("/register")
async def register(name: str = Form(...), reg_no: str = Form(...), class_name: str = Form(...), file: UploadFile = File(...)):
    try:
        cn, cr, cl = name.strip().title(), reg_no.strip().upper(), class_name.strip().upper()
        image = face_recognition.load_image_file(io.BytesIO(await file.read()))
        encs = face_recognition.face_encodings(image)
        if not encs: return {"status": "error", "message": "No face detected"}
        conn = sqlite3.connect(DB_NAME); cursor = conn.cursor()
        cursor.execute("INSERT INTO students (name, reg_no, class_name, encoding) VALUES (?, ?, ?, ?)", 
                       (cn, cr, cl, json.dumps(encs[0].tolist())))
        conn.commit(); conn.close(); return {"status": "success"}
    except Exception as e: return {"status": "error", "message": str(e)}

@app.post("/scan")
async def scan_face(class_name: str = Form(...), file: UploadFile = File(...)):
    now = datetime.now(); today = now.strftime("%Y-%m-%d"); cl = class_name.upper()
    conn = sqlite3.connect(DB_NAME); cursor = conn.cursor()
    cursor.execute("SELECT name, reg_no, encoding FROM students WHERE class_name = ?", (cl,))
    rows = cursor.fetchall()
    if not rows: return {"status": "none", "message": "No students in class"}
    
    known_encs = [np.array(json.loads(r[2])) for r in rows]
    meta = [{"name": r[0], "reg_no": r[1]} for r in rows]
    
    frame = cv2.imdecode(np.frombuffer(await file.read(), np.uint8), cv2.IMREAD_COLOR)
    rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    face_locs = face_recognition.face_locations(rgb, model="hog")
    face_encs = face_recognition.face_encodings(rgb, face_locs)
    
    if not face_encs: return {"status": "none", "message": "No face detected"}
    
    matches = face_recognition.compare_faces(known_encs, face_encs[0], tolerance=0.5)
    msg = "UNKNOWN"
    if True in matches:
        m = meta[matches.index(True)]
        cursor.execute("SELECT id FROM logs WHERE reg_no=? AND date=? AND class_name=?", (m['reg_no'], today, cl))
        if not cursor.fetchone():
            cursor.execute("INSERT INTO logs (name, reg_no, class_name, date, time, status) VALUES (?, ?, ?, ?, ?, ?)", 
                           (m['name'], m['reg_no'], cl, today, now.strftime("%H:%M:%S"), "Present"))
            msg = f"MARKED: {m['name']}"
        else: msg = f"ALREADY MARKED: {m['name']}"
    conn.commit(); conn.close(); return {"status": "done", "message": msg}

@app.post("/toggle_status")
async def toggle(reg_no: str = Form(...), class_name: str = Form(...)):
    today = datetime.now().strftime("%Y-%m-%d"); cl = class_name.upper(); rn = reg_no.upper()
    conn = sqlite3.connect(DB_NAME); cursor = conn.cursor()
    cursor.execute("SELECT name FROM students WHERE reg_no = ? AND class_name = ?", (rn, cl))
    student = cursor.fetchone()
    if not student: return {"status": "error"}
    cursor.execute("SELECT id FROM logs WHERE reg_no=? AND date=? AND class_name=?", (rn, today, cl))
    log = cursor.fetchone()
    if log: cursor.execute("DELETE FROM logs WHERE id = ?", (log[0],))
    else: cursor.execute("INSERT INTO logs (name, reg_no, class_name, date, time, status) VALUES (?, ?, ?, ?, ?, ?)", 
                       (student[0], rn, cl, today, datetime.now().strftime("%H:%M:%S"), "Present"))
    conn.commit(); conn.close(); return {"status": "success"}

@app.post("/bulk_delete")
async def bulk(reg_nos: str = Form(...)):
    conn = sqlite3.connect(DB_NAME); cursor = conn.cursor()
    for r in reg_nos.split(","):
        cursor.execute("DELETE FROM students WHERE reg_no = ?", (r.upper(),))
        cursor.execute("DELETE FROM logs WHERE reg_no = ?", (r.upper(),))
    conn.commit(); conn.close(); return {"status": "success"}

@app.get("/students/{class_name}")
def get_students(class_name: str):
    today = datetime.now().strftime("%Y-%m-%d"); cl = class_name.upper()
    conn = sqlite3.connect(DB_NAME); cursor = conn.cursor()
    cursor.execute("SELECT name, reg_no FROM students WHERE class_name = ? ORDER BY name ASC", (cl,))
    sts = cursor.fetchall()
    cursor.execute("SELECT reg_no FROM logs WHERE class_name=? AND date=?", (cl, today))
    pres = [r[0] for r in cursor.fetchall()]
    conn.close(); return [{"name": s[0], "reg_no": s[1], "is_present": s[1] in pres} for s in sts]

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)