import face_recognition
import cv2
import os
import numpy as np

# 1. LOAD STUDENT DATABASE
known_face_encodings = []
known_face_names = []

print("--- System: Loading Registered Students ---")
student_dir = "students/"

# Loop through every image in the 'students' folder
for filename in os.listdir(student_dir):
    if filename.endswith((".jpg", ".png", ".jpeg")):
        # Load the image
        image = face_recognition.load_image_file(os.path.join(student_dir, filename))
        
        # Convert the image into a 128-number encoding
        encodings = face_recognition.face_encodings(image)
        
        if len(encodings) > 0:
            known_face_encodings.append(encodings[0])
            # Use the filename (minus the .jpg) as the student's name
            known_face_names.append(filename.split(".")[0].capitalize())
            print(f"Registered: {filename.split('.')[0]}")

print("--- System: Registration Complete. Starting Scanner ---")

# 2. START THE CAMERA (Simulating the Teacher's device)
video_capture = cv2.VideoCapture(0)

while True:
    ret, frame = video_capture.read()
    if not ret:
        break

    # To make it fast, we process a smaller version of the frame
    small_frame = cv2.resize(frame, (0, 0), fx=0.25, fy=0.25)
    rgb_small_frame = cv2.cvtColor(small_frame, cv2.COLOR_BGR2RGB)

    # Detect faces and calculate their encodings
    face_locations = face_recognition.face_locations(rgb_small_frame)
    face_encodings = face_recognition.face_encodings(rgb_small_frame, face_locations)

    for (top, right, bottom, left), face_encoding in zip(face_locations, face_encodings):
        # Check if this face matches any registered student
        matches = face_recognition.compare_faces(known_face_encodings, face_encoding, tolerance=0.5)
        name = "Unknown"

        # Find the best match (lowest distance = highest similarity)
        face_distances = face_recognition.face_distance(known_face_encodings, face_encoding)
        if len(face_distances) > 0:
            best_match_index = np.argmin(face_distances)
            if matches[best_match_index]:
                name = known_face_names[best_match_index]

        # Scale coordinates back up (since we resized to 1/4th earlier)
        top *= 4; right *= 4; bottom *= 4; left *= 4

        # Draw the box: Green if recognized, Red if unknown
        color = (0, 255, 0) if name != "Unknown" else (0, 0, 255)
        cv2.rectangle(frame, (left, top), (right, bottom), color, 2)
        cv2.putText(frame, name, (left, top - 10), cv2.FONT_HERSHEY_SIMPLEX, 0.75, color, 2)

    # Display the live feed
    cv2.imshow('Teacher Attendance Scanner (Press Q to quit)', frame)

    if cv2.waitKey(1) & 0xFF == ord('q'):
        break

video_capture.release()
cv2.destroyAllWindows()