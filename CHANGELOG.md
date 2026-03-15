# Changelog

All notable changes to this project will be documented here.

## [Unreleased]
- Nothing currently in progress

---

## [1.0.0] - 2026-03-01
### Added
- Initial release
- Get-EmployeeFromCsv: loads and maps CSV headers to AD fields via SyncFieldMap
- Get-EmployeesFromAD: fetches all AD users with an EmployeeID
- Compare-Users: compares CSV and AD users to identify new, synced, and removed accounts
- Get-UserSyncData: categorizes users into New, Synced, and Removed buckets
- Validate-OU: creates missing OUs in AD based on office locations in CSV
- New-Username: generates unique usernames using Surname + GivenName initials
- Create-NewUser: creates new AD users with auto-generated secure passwords
- Check-Username: validates and updates usernames if a user's name has changed
- Sync-ExistingUsers: syncs OU, username, and properties for existing users
- Remove-Users: disables removed users and deletes them after a configurable retention period

### Fixed
- Corrected spacing error on Set-ADUser -Server parameter in Sync-ExistingUsers
- Fixed $Domain scope issue in Create-NewUser and Sync-ExistingUsers
- Corrected $GivenName typo ($Givename) in username generation loop
- Fixed incomplete throw messages to include descriptive error text
- Resolved BOM character causing CommandNotFoundException on script load
- Corrected Write-Error call from $_.ExceptionMessge to $_.Exception.Message

---

## [0.2.0] - 2026-02-15
### Added
- Re-enable logic in Sync-ExistingUsers to restore previously disabled users 
  when re-added to CSV, clearing account expiration date

---

## [0.1.0] - 2026-02-01
### Added
- Initial development build
- Core CSV import and AD query functions
- Basic user comparison logic
