# AD-Automation-Homelab

Automates Active Directory user lifecycle management using PowerShell and a CSV file.

## What It Does
- Creates new AD users from a CSV file with auto-generated usernames and secure passwords
- Syncs existing users' properties, OUs, and usernames to match the CSV
- Disables removed users and permanently deletes them after a configurable retention period (7 days by default)
- Automatically creates OUs based on office locations in the CSV

## Prerequisites
- Windows Server with Active Directory
- PowerShell RSAT module (`Import-Module ActiveDirectory`)
- Sufficient AD permissions to create/modify/delete users and OUs

## Configuration
Edit the variables at the bottom of the script to match your environment:

| Variable | Description | Default |
|---|---|---|
| `$CsvFilePath` | Path to your employee CSV | `C:\Data\employee.csv` |
| `$Delimiter` | CSV delimiter | `,` |
| `$Domain` | Your AD domain | - |
| `$UniqueID` | Field used to uniquely identify users | `EmployeeID` |
| `$OUProperty` | Field used to determine OU placement | `Office` |
| `$KeepDisabledForDays` | Days before a disabled account is deleted | `7` |

## CSV Format
Free site used for generating CSV files: https://convertcsv.com/generate-test-data.htm
| EmployeeID | FirstName | LastName | Title | Department | Location |
|---|---|---|---|---|---|
| 1001 | John | Smith | Engineer | IT | Seattle |

## Usage
```powershell
.\CreateADUser.ps1
```

## Acknowledgements
Built as a hands-on learning project following a YouTube tutorial created by JackedProgrammer
