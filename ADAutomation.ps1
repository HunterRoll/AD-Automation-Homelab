##########################################
##ADAutomation
##Date: March 01 2026
##By: Hunter Roll
##Automates Active Directory using PowerShell and a CSV file w/ employee data
##########################################

#1. Load in csv file for employees

# Loads in csv and converts the headers to match w/ AD headers
function Get-EmployeeFromCsv{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [string]$FilePath,
        [Parameter(Mandatory)]
        [string]$Delimiter,
        [Parameter(Mandatory)]
        [hashtable]$SyncFieldMap
    )

    try{
        $SyncProperties=$SyncFieldMap.GetEnumerator() # Enumerator through all keys of SyncFieldMap
        $Properties=ForEach($Property in $SyncProperties){
        @{Name=$Property.value;Expression=[scriptblock]::Create("`$_.$($Property.key)")}
        }

        Import-Csv -Path $FilePath -Delimiter $Delimiter | Select-Object -Property $Properties

    }catch{
        Write-Error $_.Exception.Messge
    }
}


#2. Load in the employees already in AD

# Grabs all the AD Users that have an EmployeeID
function Get-EmployeesFromAD{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [hashtable]$SyncFieldMap,
        [parameter(Mandatory)]
        [string]$Domain,
        [parameter(Mandatory)]
        [string]$UniqueID
    )

    try{
        Get-ADUser -Filter "$UniqueID -like '*'" -Server $Domain -Properties @($SyncFieldMap.Values)
    }catch{
        Write-Error $_.Exception.Message
    }
}


#3. Compare those

# Compares the users in AD to the ones in the csv file
function Compare-Users{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [hashtable]$SyncFieldMap,
        [parameter(Mandatory)]
        [string]$UniqueID,
        [parameter(Mandatory)]
        [string]$CSVFilePath,
        [parameter()]
        [string]$Delimiter=",",
        [parameter(Mandatory)]
        [string]$Domain
    )

    $CSVUsers=Get-EmployeeFromCsv -FilePath $CsvFilePath -Delimiter $Delimiter -SyncFieldMap $SyncFieldMap
    $ADUsers=Get-EmployeesFromAD -SyncFieldMap $SyncFieldMap -Domain $Domain -UniqueID $UniqueID

    Compare-Object -ReferenceObject $ADUsers -DifferenceObject $CSVUsers -Property $UniqueID -IncludeEqual  
}


# 4. Get new, synced, and removed users

# Used to get the data of new, synced, and removed users
function Get-UserSyncData{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [hashtable]$SyncFieldMap,
        [parameter(Mandatory)]
        [string]$UniqueID,
        [parameter(Mandatory)]
        [string]$CSVFilePath,
        [parameter()]
        [string]$Delimiter=",",
        [parameter(Mandatory)]
        [string]$Domain,
        [parameter(Mandatory)]
        [string]$OUProperty
    )

    try{
        $CompareData=Compare-Users -SyncFieldMap $SyncFieldMap -UniqueID $UniqueID -Delimiter $Delimiter -Domain $Domain -CSVFilePath $CsvFilePath
        $NewUsersID=$CompareData | where SideIndicator -eq "=>"
        $SyncedUsersID=$CompareData | where SideIndicator -eq "=="
        $RemovedUsersID=$CompareData | where SideIndicator -eq "<="

        $NewUsers=Get-EmployeeFromCsv -FilePath $CsvFilePath -Delimiter $Delimiter -SyncFieldMap $SyncFieldMap | where $UniqueID -In $NewUsersID.$UniqueID
        $SyncedUsers=Get-EmployeeFromCsv -FilePath $CsvFilePath -Delimiter $Delimiter -SyncFieldMap $SyncFieldMap | where $UniqueID -In $SyncedUsersID.$UniqueID
        $RemovedUsers=Get-EmployeesFromAD -SyncFieldMap $SyncFieldMap -Domain $Domain -UniqueID $UniqueID | where $UniqueID -In $RemovedUsersID.$UniqueID
   
        @{
            New=$NewUsers
            Synced=$SyncedUsers
            Removed=$RemovedUsers
            UniqueID=$UniqueID
            Domain=$Domain
            OUProperty=$OUProperty
        }
    }catch{
        Write-Error $_.Exception.Message
    }
}

# 5. Update AD to reflect the new Physical Office Names present in the CSV

# Fetch the unique physical office names from the CSV file, then check if the Physical Office Name from the CSV is not in AD, then create a new OU
function Validate-OU{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [hashtable]$SyncFieldMap,
        [Parameter(Mandatory)]
        [string]$CSVFilePath,
        [Parameter()]
        [string]$Delimiter=",",
        [Parameter(Mandatory)]
        [string]$Domain,
        [Parameter(Mandatory)]
        [string]$OUProperty
    )
    try{
        # Fetch the unique physical office names from the CSV file
        $OUNames=Get-EmployeeFromCsv -FilePath $CsvFilePath -Delimiter $Delimiter -SyncFieldMap $SyncFieldMap `
        | Select -Unique -Property $OUProperty

        foreach($OUname in $OUnames){
            $OuName=$OUName.$OUProperty
            # If the Physical Office Name from the CSV is not in AD, then create a new OU
            if(-not(Get-ADOrganizationalUnit -Filter "name -eq '$OUName'" -Server $Domain)){
                New-ADOrganizationalUnit -Name $OUName -Server $Domain -ProtectedFromAccidentalDeletion $False
            }
        }
    }catch{
        Write-Error $_.Exception.Message
    }
}


# 6. Create a unique username for a given user

function New-Username{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)] 
        [string]$GivenName,
        [Parameter(Mandatory)] 
        [string]$Surname,
        [Parameter(Mandatory)] 
        [string]$Domain
    )

    # Remove spaces, dashes, & apostrophes
    [RegEx]$Pattern="\s|-|'"
    $index=1

    # exit loop when a free username is found or when all name combos have been exhausted
    do{
        # Append first letter of GivenName to SurName, growing by one char each iteration
        $Username="$Surname$($GivenName.Substring(0,$index))" -replace $Pattern,""
        $index++
    }while((Get-ADUser -Filter "SamAccountName -like '$Username'" -Server $Domain) -and ($Username -notlike "$Surname$Givename"))
    
    if(Get-ADUser -Filter "SamAccountName -like '$Username'" -Server $Domain){
        throw "No usernames available for this user!"
    }else{
        $Username
    }
}

# 7. Create a new AD User

function Create-NewUser{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)] 
        [hashtable]$UserSyncData
    )
    try{
        $NewUsers=$UserSyncData.New

        foreach($NewUser in $NewUsers){
            Write-Verbose "Creating user: {$($NewUser.givenname) $($NewUser.surname)}"
            $Username=New-Username -GivenName $NewUser.GivenName -Surname $NewUser.surname -Domain $UserSyncData.Domain
            Write-Verbose "Creating user: {$($NewUser.givenname) $($NewUser.surname)} with username: {$($Username)}"
    
            # Grab the new user's corresponding office OU
            if(-not($OU=Get-ADOrganizationalUnit -Filter "name -eq '$($NewUser.$($UserSyncData.OUProperty))'" -Server $Domain)){
                throw "The organizational unit {$($NewUser.$($UserSyncData.OUProperty))}"
            }

            Write-Verbose "Creating user: {$($NewUser.givenname) $($NewUser.surname)} with username: {$($Username)}, {$($OU)}"

            # Create a new *strong* password for the user
            Add-Type -AssemblyName 'System.Web'
            $Password=[System.Web.Security.Membership]::GeneratePassword((Get-Random -Minimum 12 -Maximum 16),3)
            $SecuredPassword=ConvertTo-SecureString -String $Password -AsPlainText -Force

            $NewADUserParams=@{
                EmployeeID=$NewUser.EmployeeID
                GivenName=$NewUser.GivenName
                Surname=$NewUser.Surname
                Name=$Username
                SamAccountName=$Username
                UserPrincipalName="$Username@$($UserSyncData.Domain)"
                AccountPassword=$SecuredPassword
                ChangePasswordAtLogon=$true
                Enabled=$true
                Title=$NewUser.Title
                Department=$NewUser.Department
                Office=$NewUser.Office
                Path=$OU.DistinguishedName
                Confirm=$false
                Server=$UserSyncData.Domain
            }

            New-ADUser @NewADUserParams
            Write-Verbose "Created user: {$($NewUser.GivenName) $($NewUser.Surname)} EmpID: {$($NewUser.EmployeeID) Username: {$Username} Password: {$Password}}"
        }
    }catch{
        Write-Error $_.Exception.Message
    }
}


# 8. Check the usernames of all users, and update them if the persons name has changed

function Check-Username{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)] 
        [string]$GivenName,
        [Parameter(Mandatory)] 
        [string]$Surname,
        [Parameter(Mandatory)] 
        [string]$Domain,
        [Parameter(Mandatory)] 
        [string]$CurrentUserName
    )

    # Remove spaces, dashes, & apostrophes
    [RegEx]$Pattern="\s|-|'"
    $index=1

    # exit loop when a free username is found, all name combos have been exhausted, or the generated name matches the user's current one
    do{
        # Append first letter of GivenName to SurName, growing by one char each iteration
        $Username="$Surname$($GivenName.Substring(0,$index))" -replace $Pattern,""
        $index++
    }while((Get-ADUser -Filter "SamAccountName -like '$Username'" -Server $Domain) -and ($Username -notlike "$Surname$Givename") -and ($Username -notlike $CurrentUserName))
    
    if((Get-ADUser -Filter "SamAccountName -like '$Username'" -Server $Domain) -and ($Username -notlike $CurrentUserName)){
        throw "No usernames available for this user!"
    }else{
        $Username
    }
}


# 9. Sync user data from CSV and AD

# Loop through users in both CSV and AD, then sync their AD account to match CSV data
function Sync-ExistingUsers{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [hashtable]$UserSyncData,
        [Parameter(Mandatory)]
        [hashtable]$SyncFieldMap
    )
    
    $SyncedUsers=$UserSyncData.Synced

    foreach($SyncedUser in $SyncedUsers){
        Write-Verbose "Loading data for $($SyncedUser.givenname) $($SyncedUser.surname)"

        # Check the OU and see if it needs to be changed
        $ADUser=Get-ADUser -Filter "$($UserSyncData.UniqueID) -eq $($SyncedUser.$($UserSyncData.UniqueID))" -Server $UserSyncData.Domain -Properties *
        if(-not($OU=Get-ADOrganizationalUnit -Filter "name -eq '$($SyncedUser.$($UserSyncData.OUProperty))'" -Server $Domain)){
            throw "The organizational unit {$($SyncedUser.$($UserSyncData.OUProperty))}"
        }
        Write-Verbose "User is currently in $($ADUser.DistinguishedName) but should be in $OU"
        
        # Check the OU and remove container (CN) from the string to be able to compare 
        if(($ADUser.DistinguishedName.split(",")[1..$($ADUser.DistinguishedName.Length)] -join ",") -ne ($OU.DistinguishedName)){
            Write-Verbose "OU needs to be changed"
            Move-ADObject -Identity $ADUser -Server $UserSyncData.Domain -TargetPath $OU
        }

        $ADUser=Get-ADUser -Filter "$($UserSyncData.UniqueID) -eq $($SyncedUser.$($UserSyncData.UniqueID))" -Server $UserSyncData.Domain -Properties *
        
        if($ADUser.Enabled -eq $false){
            Write-Verbose "Re-enabling previously disabled user $($ADUser.Name)"
            Set-ADUser -Identity $ADUser -Enabled $true -AccountExpirationDate $null -Server $UserSyncData.Domain -Confirm:$false
        }
        # Check and update username
        $Username=Check-Username -GivenName $SyncedUser.GivenName -Surname $SyncedUser.Surname -CurrentUserName $ADUser.SamAccountName -Domain $UserSyncData.Domain
    
        if($ADUser.SamAccountName -notlike $Username){
            Write-Verbose "Username needs to be changed"
            Set-ADUser -Identity $ADUser -Replace @{userprincipalname="$Username@$($UserSyncData.Domain)"} -Server $UserSyncData.Domain
            Set-ADUser -Identity $ADUser -Replace @{samaccountname="$Username"} -Server $UserSyncData.Domain
            Rename-ADObject -Identity $ADUser -NewName $Username -Server $UserSyncData.Domain
        }

        $SetADUserParams=@{
            Identity=$Username
            Server=$UserSyncData.Domain
        }

        # Sync all properties from the CSV
        foreach($Property in $SyncFieldMap.Values){
            $SetADUserParams[$Property]=$SyncedUser.$Property
        }

        Set-ADUser @SetADUserParams
    }
}

#10. Check removed users, then disable them

# Check which users need to be removed, then disabled their account for 7 days. After 7 days delete their account
function Remove-Users{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [hashtable]$UserSyncData,
        [Parameter()]
        [int]$KeepDisabledForDays=7
    )

    try{
        $RemovedUsers=$UserSyncData.Removed

        foreach($RemovedUser in $RemovedUsers){
            Write-Verbose "Fetching data for $($RemovedUser.Name)"
            $ADUser=Get-ADUser $RemovedUser -Properties * -Server $UserSyncData.Domain
            if($ADUser.Enabled -eq $true){
                Write-Verbose "Disabling User $($ADUser.Name)"
                Set-ADUser -Identity $ADUser -Enabled $false -AccountExpirationDate (Get-Date).AddDays($KeepDisabledForDays) -Server $UserSyncData.Domain -Confirm:$false
            }else{
                if($ADUser.AccountExpirationDate -lt (Get-Date)){
                    Write-Verbose "Deleting account $($ADUser.Name)"
                    Remove-ADUser -Identity $ADUser -Server $UserSyncData.Domain -Confirm:$false
                }else{
                    Write-Verbose "Account $($ADUser.Name) is still within the retention period"
                }
            }
        }
    }catch{
         Write-Error $_.Exception.Message
    }
}


$SyncFieldMap=@{
    EmployeeID="EmployeeID"
    FirstName="GivenName"
    LastName="SurName"
    Title="Title"
    Department="Department"
    Location="Office"
    # can now add more headers / can change headers easily 
}


$CsvFilePath="C:\Data\employee.csv"
$Delimiter=","
$Domain="hunterpractice.local"
$UniqueID = "EmployeeID"
$OUProperty="Office"
$KeepDisabledForDays=7

# Verify the new OUs in the CSV are updated in AD
Validate-OU -SyncFieldMap $SyncFieldMap -CSVFilePath $CsvFilePath -Delimiter $Delimiter `
-OUProperty $OUProperty -Domain $Domain

# Compare the users in the CSV to the ones currently in AD
$UserSyncData=Get-UserSyncData -SyncFieldMap $SyncFieldMap -UniqueID $UniqueID `
-CSVFilePath $CsvFilePath -Delimiter $Delimiter -Domain $Domain -OUProperty $OUProperty

# For each new user from CSV, make them a username & password, and place them in the corresponding OU
Create-NewUser -UserSyncData $UserSyncData -Verbose

Sync-ExistingUsers -UserSyncData $UserSyncData -SyncFieldMap $SyncFieldMap -Verbose

#Check removed users, then disable them
Remove-Users -UserSyncData $UserSyncData -KeepDisabledForDays $KeepDisabledForDays -Verbose