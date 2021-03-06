Add-PSSnapin Microsoft.SharePoint.Powershell -EA 0 

# Settings
$databaseServer = "SPLive360SQL1\SHAREPOINT"
$databaseServerAlias = "SPSQL"
$configDatabase = "SP2013_Auto_Config"
$adminContentDB = "SP2013_Auto_Content_Admin"
$passphrase = "Devise!!!"
$farmAccountName = "splive360\svcspfarm"
# Set to true to disable loopback check. False will just Disable the scrict name check
# and BackConnectionHostNames will be created and populated with the server name. 
# Additional host names should be added to the script.
$bDisableLoopback = $true

# Create SQL Alias if they don't yet exist
Write-Host "Creating SQL ALiases..."

$sqlAliasPath32 = "HKLM:SOFTWARE\Microsoft\MSSQLServer\Client\ConnectTo"
$sqlAliasPath64 = "HKLM:\Software\Wow6432Node\Microsoft\MSSQLServer\Client\ConnectTo"

Write-Host "    Checking for 32-bit sql alias..."
if (Get-Item $sqlAliasPath32 -ErrorAction SilentlyContinue | ?{$_.property -match $databaseServerAlias}) {  
    Write-Host "    32-bit alias for $databaseServerAlias already exists..." 
} else {  
    Write-Host "    Creating 32-bit sql alias..."
    $sqlAlias32Connect = Get-ChildItem -Path $sqlAliasPath32 -ErrorAction SilentlyContinue
    if ($sqlAlias32Connect -eq $null) { New-Item -Path $sqlAliasPath32 | out-null }
    New-ItemProperty $sqlAliasPath32 -name $databaseServerAlias -propertytype String -value "DBMSSOCN,$databaseServer" | out-null
} 

Write-Host "    Checking for 64-bit sql alias..."
if (Get-Item $sqlAliasPath64 -ErrorAction SilentlyContinue | ?{$_.property -match $databaseServerAlias}) {  
    Write-Host "    64-bit alias for $databaseServerAlias already exists..." 
} else {  
    Write-Host "    Creating 64-bit sql alias..."
    $sqlAlias64Connect = Get-ChildItem -Path $sqlAliasPath64 -ErrorAction SilentlyContinue
    if ($sqlAlias64Connect -eq $null) { New-Item -Path $sqlAliasPath64 | out-null }
    New-ItemProperty $sqlAliasPath64 -name $databaseServerAlias -propertytype String -value "DBMSSOCN,$databaseServer" | out-null
} 

# Automate the credential entry
$farmAccountPassword = ConvertTo-SecureString $passphrase -AsPlainText -Force
$farmAccount = New-Object system.management.automation.pscredential $farmAccountName, $farmAccountPassword

# Don't automate entry. This way we're not distributing farm creds
#$farmAccount = Get-Credential $farmAccountName

$passphrase = (ConvertTo-SecureString $passphrase -AsPlainText -force)

# will error, but fix the regkey...
# we do this to prevent an error if the machine state registry key is not correctly set,
# which will prevent the next command from completing.

Write-Host "Executing psconfig upgrade..."
# psconfig.exe -cmd upgrade
$psconfig = "psconfig.exe"
$psconfigcmdLine = "-cmd upgrade"
invoke-expression "$psconfig $psconfigcmdLine" | out-null

Write-Host "Creating Configuration Database and Central Admin Content Database..."
New-SPConfigurationDatabase -DatabaseServer $databaseServerAlias -DatabaseName $configDatabase `
    -AdministrationContentDatabaseName $adminContentDB `
    -Passphrase $passphrase -FarmCredentials $farmAccount
    
$spfarm = Get-SPFarm -ErrorAction SilentlyContinue -ErrorVariable err        
if ($spfarm -eq $null -or $err) {
   throw "Unable to verify farm creation."
}

Write-Host "ACLing SharePoint Resources..."
Initialize-SPResourceSecurity | out-null
Write-Host "Installing Services ..."
Install-SPService | out-null
Write-Host "Installing Features..."
Install-SPFeature -AllExistingFeatures | out-null
Write-Host "Installing Help..."
Install-SPHelpCollection -All | out-null
Write-Host "Installing Application Content..."
Install-SPApplicationContent | out-null

Write-Host "Creating Central Administration..."              
New-SPCentralAdministration -Port 2013 -WindowsAuthProvider NTLM

Write-Host "Farm Creation Done!"

Write-Host "Setting Server Registry Keys..."
Write-Host "    Disabling Strict Name Checking..."
New-ItemProperty HKLM:\System\CurrentControlSet\Services\LanmanServer\Parameters -Name DisableStrictNameChecking -value "1" -PropertyType dword | out-null

if ($bDisableLoopBack -eq $true) {
    Write-Host "    Disabling the Loopback Check..."
    New-ItemProperty HKLM:\System\CurrentControlSet\Control\Lsa -Name "DisableLoopbackCheck" -value "1" -PropertyType dword | out-null
} else {
    Write-Host "    Writing BackConnectionHostNames..."
    # Get the current computer name and fqdn
    $objIPProperties = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties()
    $currentHostName = $objIPProperties.HostName
    $currentHostFQDN = "{0}.{1}" -f  $objIPProperties.HostName, $objIPProperties.DomainName
    # Multi-value example. Adapt to your environments needs
    #New-ItemProperty HKLM:\System\CurrentControlSet\Control\Lsa\MSV1_0 -Name "BackConnectionHostNames" -Value "intranet.cybertron.local","mysites.cybertron.local" -PropertyType multistring | out-null
    New-ItemProperty HKLM:\System\CurrentControlSet\Control\Lsa\MSV1_0 -Name "BackConnectionHostNames" -Value "$currentHostName","$currentHostFQDN","intranet.splive360.local","ca.splive360.local","my.splive360.local" -PropertyType multistring | out-null
}

Write-Host "Farm initialized. Press any key to restart server..."
$x = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
Restart-Computer