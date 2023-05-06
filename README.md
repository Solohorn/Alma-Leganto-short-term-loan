# Alma-Leganto short-term loans

## What does it do?
This script reads in two reports from Analytics:
* A list of all active citations in the Course Reserves subject area with corresponding repository items in Alma.
* A list of all physical items with their item policies.
* Reports here:	/shared/Community/Reports/Institutions/Trent University/Eluna2023
* Adds/removes item temporary location, temporary library, temporary item policy and fulfillment note.

## What do I need to do to use this?
There are several things that will need to be configured:
* Schedule the script to run daily (we use Windows Task Scheduler)
* API keys are managed in a local Perl module in libperl/AlmaAPI.pm. I'd recommend keeping this module outside of the public_html folder.
* Generate an API key at https://developers.exlibrisgroup.com/ with 'Bibs - Production Read/write' permission and use this as the key value for $QuickTitle_api_key in AlmaAPI.pm
* Add your Alma institution code to AlmaAPI.pm
* Enter the location of your local Perl library path(s) in racer-records.pl

## To do
* Now that the items report has been modified to include citations, this could be re-written to use only that report.
