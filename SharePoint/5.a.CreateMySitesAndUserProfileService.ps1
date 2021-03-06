# Create Managed Account and Application Pool for MySites
$currentScriptPath = $MyInvocation.MyCommand.Path
$scriptFolder = Split-Path $currentScriptPath
$targetScriptPath = Join-Path $scriptFolder "\5.b.CreateUserProfileServiceApplication.ps1"

$mysitesAppPoolName = "SharePoint MySites Default"
$mysitesAppPoolUserName = "splive360\svcspmysites"
$mysitesHeader = "my.splive360.local"
$mysitesFullURL = "http://" + $mysitesHeader
$mysitesDBName = "SP2013_Auto_Content_MySites"
$mysitesSCTitle = "MySites Host"

# Needed to start the service instance
$farmAccount = "splive360\svcspfarm"
$farmPassword = "Devise!!!"

# Service App Pools
$saAppPoolName = "SharePoint Web Services Default"

# Set the MySites App Pool up
$mySitesAppPool = Get-SPServiceApplicationPool $mysitesAppPoolName -ErrorAction SilentlyContinue -ErrorVariable err

if ($mySitesAppPool -eq $null) {
    # Create Managed Account and Application Pool for Services

    # Service Apps Generic Pool
    $mysitesAppPoolAccount = Get-SPManagedAccount -Identity $mysitesAppPoolUserName -ErrorAction SilentlyContinue -ErrorVariable err
    if ($mysitesAppPoolAccount -eq $null) {
        Write-Host "Please supply the password for the $mysitesAppPoolUserName Account..."
        $appPoolCred = Get-Credential $mysitesAppPoolUserName
        $mysitesAppPoolAccount = New-SPManagedAccount -Credential $appPoolCred
    }

    $mySitesAppPool = Get-SPServiceApplicationPool $mysitesAppPoolName -ErrorAction SilentlyContinue -ErrorVariable err
    if ($mySitesAppPool -eq $null) {
        $mySitesAppPool = New-SPServiceApplicationPool -Name $mysitesAppPoolName -Account $mysitesAppPoolAccount
    }
} else {
    # Service Apps Generic Pool
    $mysitesAppPoolAccount = Get-SPManagedAccount -Identity $mysitesAppPoolUserName -ErrorAction SilentlyContinue -ErrorVariable err
    if ($mysitesAppPoolAccount -eq $null) {
        Write-Host "Please supply the password for the $mysitesAppPoolUserName Account..."
        $appPoolCred = Get-Credential $mysitesAppPoolUserName
        $mysitesAppPoolAccount = New-SPManagedAccount -Credential $appPoolCred
    }
}

# Create the MySites Web app. Creation of the web app will create our application pool.
Write-Host "Creating Web Application..."
$ap = New-SPAuthenticationProvider -UseWindowsIntegratedAuthentication -DisableKerberos 
New-SPWebApplication -Name $mysitesHeader `
                     -Port 80 `
                     -HostHeader $mysitesHeader `
                     -ApplicationPool $mysitesAppPoolName `
                     -ApplicationPoolAccount $mysitesAppPoolAccount `
                     -AuthenticationMethod "NTLM" `
                     -AuthenticationProvider $ap `
                     -DatabaseName $mysitesDBName `
                     -Url $mysitesFullURL `
                     -Confirm:$false | out-null

# Create the mysite host site collection in the root
Write-Host "Creating MySite Host Root Site Collection at $mysitesFullURL..."
New-SPSite -Name $mysitesSCTitle -Url $mysitesFullURL -OwnerAlias $farmAccount -Template "SPSMSITEHOST#0" -ContentDatabase $mysitesDBName -Confirm:$false | out-null

# Create the /personal managed path
Write-Host "Setting Managed Path for /personal..."
New-SPManagedPath -RelativeURL "personal" -WebApplication $mysitesFullURL | out-null

Write-Host "MySites Web Application Configuration Complete!"

Write-Host "Provisioning UPS..."

Start-Process $PSHOME\powershell.exe `
                  -ArgumentList "-Command Start-Process $PSHOME\powershell.exe -ArgumentList `"'$targetScriptPath'`" -Verb Runas" -Wait 

iisreset
Write-Host "UPS Done!"
Write-Host "Don't forget to remove the Farm Account from local admins!"