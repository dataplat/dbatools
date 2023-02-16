$password = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
$cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "sqladmin", $password

$PSDefaultParameterValues["*:SqlInstance"] = "localhost"
$PSDefaultParameterValues["*:SqlCredential"] = $cred
$PSDefaultParameterValues["*:Confirm"] = $false
$PSDefaultParameterValues["*:SharedPath"] = "/shared"
##$PSDefaultParameterValues["*:WarningAction"] = "SilentlyContinue"
#$global:ProgressPreference = "SilentlyContinue"



Invoke-DbaQuery -File .\bin\Replication\setup-test-replication.sql