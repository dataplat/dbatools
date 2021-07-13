$PSDefaultParameterValues["*:SqlCredential"] = $cred
$PSDefaultParameterValues["*:SourceSqlCredential"] = $cred
$PSDefaultParameterValues["*:DestinationSqlCredential"] = $cred
$PSDefaultParameterValues["*:PrimarySqlCredential"] = $cred
$PSDefaultParameterValues["*:MirrorSqlCredential"] = $cred
$PSDefaultParameterValues["*:WitnessSqlCredential"] = $cred
$PSDefaultParameterValues["*:Confirm"] = $false


Import-Module ./dbatools.psm1 -Force
$commands = Get-XPlatVariable | Where-Object { $PSItem -notmatch "Copy-", "Migration" } | Sort-Object
$password = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
$cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "sqladmin", $password

# test migration
$params = @{
    Source        = "localhost"
    Destination   = "localhost:14333"
    BackupRestore = $true
    SharedPath    = "/shared"
    Exclude       = "LinkedServers", "Credentials", "DataCollector", "EndPoints", "PolicyManagement", "ResourceGovernor"
}

Start-DbaMigration @params | Out-Host

# Test Mirroring
$newdb = New-DbaDatabase -SqlInstance localhost

$params = @{
    Primary       = "localhost"
    Mirror        = "localhost:14333"
    Database      = $newdb.Name
    Force         = $true
    SharedPath    = "/shared"
    WarningAction = "SilentlyContinue"
}

Invoke-DbaDbMirroring @params | Out-Host

Get-DbaDbMirror -SqlInstance localhost | Out-Host