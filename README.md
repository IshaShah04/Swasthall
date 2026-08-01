
SwasthAll

Family-Centric Digital Healthcare Super App for Nepal

SwasthAll is a comprehensive healthcare platform designed to connect patients, families, doctors, nurses, laboratories, pharmacies, and healthcare providers into a single digital ecosystem.

The platform simplifies healthcare by enabling appointment scheduling, digital health records, online consultations, prescriptions, laboratory reports, and family health management through one unified application.

⸻

Overview

Healthcare services often require patients to interact with multiple providers for appointments, diagnostics, prescriptions, and medical records. SwasthAll brings these services together in one platform to improve accessibility, efficiency, and patient experience.

The application is designed with a role-based architecture that supports different stakeholders while maintaining secure access to sensitive medical information.

⸻

Features

Patient Portal

* User authentication
* Personal health dashboard
* Medical history
* Digital prescriptions
* Appointment management
* Laboratory reports
* Notification center

Family Management

* Manage multiple family members
* Shared medical records
* Emergency contact information
* Family health timeline

Doctor Portal

* Appointment scheduling
* Patient record access
* Digital prescription generation
* Consultation management

Laboratory Module

* Lab test booking
* Digital report uploads
* Report history
* Report downloads

Pharmacy Module

* Medicine ordering
* Prescription verification
* Inventory management
* Order tracking

Administrative Features

* User management
* Role management
* System monitoring
* Analytics dashboard

⸻

User Roles

* Patient
* Family Member
* Doctor
* Nurse
* Laboratory Staff
* Pharmacist
* Receptionist
* Administrator

⸻

Technology Stack

Frontend

* Flutter
* Dart
* Material Design

Backend

* Supabase
* PostgreSQL

Authentication

* Supabase Authentication

Database

* PostgreSQL

Cloud Storage

* Supabase Storage

Deployment

* GitHub Pages
* GitHub Actions

⸻

Project Structure

lib/
├── models/
├── providers/
├── screens/
├── services/
├── widgets/
├── routes/
├── utils/
└── main.dart
assets/
├── fonts/
├── icons/
└── images/
android/
ios/
web/

⸻

System Architecture

                    Users
                      │
      ┌───────────────┼────────────────┐
      │               │                │
   Patients        Doctors       Administrators
      │               │                │
      └───────────────┼────────────────┘
                      │
               Flutter Application
                      │
          Authentication (Supabase)
                      │
               PostgreSQL Database
                      │
      ┌───────────────┼────────────────┐
      │               │                │
 Medical Records  Appointments   Laboratory
      │               │                │
      └───────────────┼────────────────┘
                      │
                 Pharmacy Module

⸻

Installation

Clone the repository

git clone https://github.com/IshaShah04/Swasthall.git

Move into the project directory

cd Swasthall

Install dependencies

flutter pub get

Run the application

flutter run

Run on Chrome

flutter run -d chrome

⸻

Deployment

Build the web application

flutter build web --release

The project can be deployed using GitHub Pages with GitHub Actions for automatic deployment after every push.

⸻

Screenshots

Add screenshots of the following pages.

* Login Screen
* Home Dashboard
* Appointment Booking
* Doctor Dashboard
* Laboratory Reports
* Pharmacy
* Profile
* Administration Dashboard

⸻

Security

* Secure authentication using Supabase
* Role-based access control
* Protected application routes
* Secure cloud storage
* Database access policies
* Encrypted communication

⸻

Future Enhancements

* AI-powered symptom analysis
* Video consultation support
* Wearable device integration
* Health analytics dashboard
* Multi-language support
* Digital insurance integration
* AI-assisted prescription recommendations
* Emergency ambulance tracking

⸻

Development Workflow

Clone Repository
        │
        ▼
Install Dependencies
        │
        ▼
Configure Supabase
        │
        ▼
Run Flutter Application
        │
        ▼
Develop Features
        │
        ▼
Commit Changes
        │
        ▼
Push to GitHub
        │
        ▼
GitHub Actions
        │
        ▼
Automatic Web Deployment

⸻

License

This project is developed for educational, research, and portfolio purposes.

⸻

Author

Isha Shah
