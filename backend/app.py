import cv2
import sqlite3
import numpy as np
import face_recognition
from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from typing import List
import uvicorn
import json
import os
from datetime import datetime

app = FastAPI()

# SECURITY: Enable CORS for Flutter communication
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

DB_NAME = "attendance_system.db"

# --- DATABASE CORE ---
def init_db():
    conn = sqlite3.connect(DB_NAME)
    cursor = conn.cursor()
    
    # Staff Users Table
    cursor.execute('''CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT, 
        username TEXT UNIQUE, 
        password TEXT)''')
    
    # Classes Table
    cursor.execute('''CREATE TABLE IF NOT EXISTS classes (
        id INTEGER PRIMARY KEY AUTOINCREMENT, 
        name TEXT UNIQUE)''')
    
    # Students Table (Stores 128-d math encodings as text)
    cursor.execute('''CREATE TABLE IF NOT EXISTS students (
        id INTEGER PRIMARY KEY AUTOINCREMENT, 
        name TEXT, 
        class_name TEXT, 
        encoding TEXT,
        FOREIGN KEY(class_name) REFERENCES classes(name))''')
    
    # Attendance Logs Table
    cursor.execute('''CREATE TABLE IF NOT EXISTS attendance (
        id INTEGER PRIMARY KEY AUTOINCREMENT, 
        student_name TEXT, 
        class_name TEXT, 
        timestamp DATETIME DEFAULT CURRENT_TIMESTAMP)''')
    
    # Populate Default Data
    cursor.execute("INSERT OR IGNORE INTO users (username, password) VALUES ('admin', 'admin123')")
    default_classes = [('CLASS 10-A',), ('CLASS 10-B',), ('CLASS 11-A',), ('CLASS 12-B',)]
    cursor.executemany("INSERT OR IGNORE INTO classes (name) VALUES (?)", default_classes)
    
    conn.commit()
    conn.close()

init_db()

# --- AUTHENTICATION ---
@app.post("/login")
async def login(username: str = Form(...), password: str = Form(...)):
    conn = sqlite3.connect(DB_NAME)
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM users WHERE username = ? AND password = ?", (username, password))
    user = cursor.fetchone()
    conn.close()
    if user:
        return {"status": "success", "message": "Access Granted"}
    raise HTTPException(status_code=401, detail="Invalid Credentials")

# --- CLASS MANAGEMENT ---
@app.get("/get_classes")
def get_classes():
    conn = sqlite3.connect(DB_NAME)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM classes ORDER BY name ASC")
    classes = [row[0] for row in cursor.fetchall()]
    conn.close()
    return classes

# --- STUDENT REGISTRATION ---
@app.post("/register_student")
async def register_student(name: str = Form(...), class_name: str = Form(...), image: UploadFile = File(...)):
    # Convert image to OpenCV format
    contents = await image.read()
    nparr = np.frombuffer(contents, np.uint8)
    frame = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
    
    # AI Encoding
    encodings = face_recognition.face_encodings(frame)
    if not encodings:
        return {"status": "error", "message": "No face detected in photo"}
    
    # Convert encoding array to JSON string for storage
    encoding_str = json.dumps(encodings[0].tolist())
    
    try:
        conn = sqlite3.connect(DB_NAME)
        cursor = conn.cursor()
        cursor.execute("INSERT INTO students (name, class_name, encoding) VALUES (?, ?, ?)", 
                       (name.upper(), class_name.upper(), encoding_str))
        conn.commit()
        conn.close()
        return {"status": "success", "message": f"{name} registered successfully"}
    except Exception as e:
        return {"status": "error", "message": str(e)}

# --- ATTENDANCE ENGINE ---
@app.post("/mark_attendance")
async def mark_attendance(class_name: str = Form(...), image: UploadFile = File(...)):
    contents = await image.read()
    nparr = np.frombuffer(contents, np.uint8)
    frame = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
    
    # AI Detection
    face_locations = face_recognition.face_locations(frame)
    face_encodings = face_recognition.face_encodings(frame, face_locations)
    
    if not face_encodings:
        return {"status": "error", "message": "No face detected"}
    
    current_encoding = face_encodings[0]
    conn = sqlite3.connect(DB_NAME)
    cursor = conn.cursor()
    
    # Only fetch students in the selected class
    cursor.execute("SELECT name, encoding FROM students WHERE class_name = ?", (class_name.upper(),))
    records = cursor.fetchall()

    for name, encoded_str in records:
        known_encoding = np.array(json.loads(encoded_str))
        # Tolerance 0.5 for high accuracy
        matches = face_recognition.compare_faces([known_encoding], current_encoding, tolerance=0.5)

        if matches[0]:
            # Log Attendance
            cursor.execute("INSERT INTO attendance (student_name, class_name) VALUES (?, ?)", 
                           (name.upper(), class_name.upper()))
            conn.commit()
            conn.close()
            return {"status": "success", "student_name": name.title()}

    conn.close()
    return {"status": "error", "message": "Match not found in database"}

# --- SERVER START ---
if __name__ == "__main__":
    print("--- Face Recognition Server Starting ---")
    print(f"Accessible at: http://10.10.99.51:8000")
    uvicorn.run(app, host="0.0.0.0", port=8000)