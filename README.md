# DreamDress - Relational Database & Business Logic Implementation

## Overview
This repository contains a full-scale SQL implementation for managing a bridal salon's operations. The project focuses on automating the lifecycle of a dress—from initial booking and availability filtering to seamstress assignment and final pickup scheduling.

The core of this project is built on T-SQL, utilizing advanced programming constructs to solve real-world logistical challenges.

---

## Database Architecture & Core Logic

### 1. Automated Resource Management (Triggers)
The system includes a workload-balancing engine designed to optimize the alteration process.
* Smart Classification: When a new alteration is logged, a trigger analyzes the description (e.g., "Hemming", "Zipper", "Additions") to set complexity levels.
* Workload Optimization: Instead of random assignment, the system queries the current active tasks of each seamstress and assigns the new job to the available specialist with the lowest workload, ensuring efficient turnaround times.

### 2. Constraint-Based Scheduling (Procedures)
Managing appointments in a high-demand salon requires strict rules.
* Dynamic Slot Generation: A specialized procedure handles the recursive generation of 30-minute time slots, automatically filtering out weekends and non-business hours.
* Lead-Time Logic: The system includes a "Pickup" procedure that calculates the ideal dress-collection window (7 days prior to the wedding) and automatically secures the first available slot for the bride.

### 3. Inventory Availability & Conflict Resolution (Functions)
The search engine for dresses isn't just a simple filter; it manages temporal conflicts:
* The 15-Day Buffer: A Table-Valued Function ensures that no dress is booked within 15 days of a previous event to allow for professional cleaning and fittings.
* Asset Retirement: To maintain quality, the system automatically flags and hides dresses that have exceeded a usage threshold (3+ events).
* Newness Scaling: A dynamic "Status" column categorizes dresses (New Arrival, Trendy, Previous Season) based on their arrival date.

---

## Technical Stack
* Engine: Microsoft SQL Server (MSSQL)
* Language: T-SQL
* Advanced Features: 
  * Multi-step Triggers for data integrity.
  * Stored Procedures with Input/Output parameters.
  * Table-Valued Functions (TVFs) for complex filtering.
  * Views for real-time operational monitoring.
  * Cursors for batch processing of bride appointments.

---

## Operational Views
The project includes a Daily Logistics View designed for floor managers. It consolidates two critical data points:
1. Pickups Due Today: Brides scheduled to arrive for their final fitting/collection.
2. Overdue Returns: Flags dresses that have not been returned within the 7-day post-wedding window.

---

## Deployment
1. Execute the Schema script to initialize the DB and file structures.
2. Run the Table_and_data Data script to populate the catalog.
3. Run the  Logic_and_queries script to compile triggers and procedures.
4. Execute EXEC updateTurns NULL to generate the initial appointment matrix.

