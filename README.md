# SwasthAll
> **Family-Centric Digital Healthcare Super App for Nepal**

SwasthAll is a comprehensive healthcare platform designed to connect patients, families, doctors, nurses, laboratories, pharmacies, and healthcare providers into a single digital ecosystem. 

The platform simplifies healthcare by enabling appointment scheduling, digital health records, online consultations, prescriptions, laboratory reports, and family health management through one unified application.

---

## Overview
Healthcare services often require patients to interact with multiple providers for appointments, diagnostics, prescriptions, and medical records. SwasthAll brings these services together in one platform to improve accessibility, efficiency, and patient experience.

The application is designed with a role-based architecture that supports different stakeholders while maintaining secure access to sensitive medical information.

---

## Features

### Patient Portal
* **Personal health dashboard** & medical history
* **Digital prescriptions** & laboratory reports
* **Appointment management** & notification center

### Family Management
* Manage multiple family members
* Shared medical records & health timelines
* Emergency contact information

### Doctor Portal
* Appointment scheduling & consultation management
* Patient record access
* Digital prescription generation

### Laboratory Module
* Lab test booking
* Digital report uploads & history
* Report downloads

### Pharmacy Module
* Medicine ordering & order tracking
* Prescription verification
* Inventory management

### Administrative Features
* User & role management
* System monitoring
* Analytics dashboard

---

## User Roles
The platform incorporates strict role-based access control for:
* Patient
* Family Member
* Doctor
* Nurse
* Laboratory Staff
* Pharmacist
* Receptionist
* Administrator

---

## Technology Stack

| Category | Technology |
| :--- | :--- |
| **Frontend** | Flutter, Dart, Material Design |
| **Backend & Auth** | Supabase, PostgreSQL |
| **Storage** | Supabase Storage |
| **Deployment** | GitHub Pages, GitHub Actions |

---

## System Architecture

```text
                Users
                  │
  ┌───────────────┼────────────────┐
  │               │                │
Patients       Doctors       Administrators
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
Medical      Appointments      Laboratory
Records           │                │
  │               │                │
  └───────────────┼────────────────┘
                  │
           Pharmacy Module

```

---

## Project Structure

```text
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

```

---

## Installation & Setup

1. **Clone the repository**
```bash
git clone [https://github.com/IshaShah04/Swasthall.git](https://github.com/IshaShah04/Swasthall.git)

```


2. **Navigate into the project directory**
```bash
cd Swasthall

```


3. **Install dependencies**
```bash
flutter pub get

```


4. **Run the application**
```bash
flutter run

```


*To run specifically on Chrome:*
```bash
flutter run -d chrome

```



---

## Deployment

To build the web application for production:

```bash
flutter build web --release

```

*Note: This project can be deployed using GitHub Pages with GitHub Actions for automatic deployment after every push.*

---

## Screenshots

*(Replace the placeholder links below with your actual screenshot paths once uploaded to your repository)*

| Login Screen | Home Dashboard | Appointment Booking |
| --- | --- | --- |
|  |  |  |

| Doctor Dashboard | Laboratory Reports | Pharmacy |
| --- | --- | --- |
|  |  |  |

| Profile | Admin Dashboard |
| --- | --- |
|  |  |

---

## Security

* Secure authentication using Supabase
* Role-based access control (RBAC)
* Protected application routes
* Secure cloud storage & database access policies
* Encrypted communication

---

## Future Enhancements

* [ ] AI-powered symptom analysis & prescription recommendations
* [ ] Video consultation support
* [ ] Wearable device integration
* [ ] Health analytics dashboard
* [ ] Multi-language support
* [ ] Digital insurance integration
* [ ] Emergency ambulance tracking

---

## Development Workflow

1. `Clone Repository`
2. `Install Dependencies`
3. `Configure Supabase`
4. `Run Flutter Application`
5. `Develop Features`
6. `Commit Changes`
7. `Push to GitHub`
8. `GitHub Actions trigger Automatic Web Deployment`

---

## License

This project is developed for educational, research, and portfolio purposes.

## Author

**Isha Shah**

```

```
