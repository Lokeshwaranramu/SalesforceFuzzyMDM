# Salesforce Fuzzy MDM Processor

A custom Master Data Management (MDM) solution for Salesforce that uses fuzzy logic to identify and merge duplicate records for any object, with support for dependent records.

## Features
- Supports both standard and custom Salesforce objects and fields.
- Uses fuzzy logic to compare the first 3-5 characters of fields with per-field similarity thresholds.
- Merges duplicates by keeping the record with the latest LastModifiedDate and deleting older records.
- Optionally reparents child records and updates lookup fields to the master record, with UI feedback if no dependent relationships exist.
- Configurable via a simple Aura component.
- Schedule the MDM process to run daily at a specified time, with the ability to update the time or remove the schedule.
- Dynamically changes the "Start MDM Process Now" button to "Terminate MDM Process" if a scheduled job exists for the object.
- Sends email notifications to user-provided addresses if merge errors occur.

## Installation
1. Clone this repository.
2. Deploy the `force-app` folder to your Salesforce org using Salesforce CLI:

## Usage
- Open 'Salesforce_Fuzzy_MDM' page under lightning app builder and activate it by adding it to exisitng lightning apps.
- Open the page from the added lightning app.
- Select an object, fields to compare, and set a similarity threshold for each field (0-100%).
- Check "Include Dependent Records?" to reparent child records and update lookup fields (disabled with a message if no dependent relationships exist).
- Enter email addresses for error notifications (comma-separated).
- Optionally, set a daily schedule by specifying a time (e.g., 14:30) and enabling the schedule. Update the time and click "Save Schedule" to reschedule.
- If a job is scheduled for the object, the "Start MDM Process Now" button changes to "Terminate MDM Process", which cancels the scheduled job.
- A "Remove Schedule" button also appears to cancel the scheduled job.
- Click "Start MDM Process Now" to run immediately, or "Save Schedule" to schedule the job.

## License
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.