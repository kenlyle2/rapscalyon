# jobs-tracker
A job-search pipeline: applications and an event log per subject (use `subject-individual`). Status changes are logged by a trigger,
so clients cannot forge `status_change` events. Matching, scraping and auto-apply are deliberately out of scope.
