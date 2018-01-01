if (Get-Command TabExpansionPlusPlus\Register-ArgumentCompleter -ErrorAction Ignore) {
    $script:TEPP = $true
}
else {
    $script:TEPP = $false
}

$functions = Get-ChildItem function:\*-Dba*
[Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::DbatoolsCommands = $functions
$names = $functions.Name

#region Automatic TEPP by parameter name
Register-DbaTeppArgumentCompleter -Command $names -Parameter Alert -Name Alert -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter AlertCategory -Name AlertCategory -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter Audit -Name Audit -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter AuditSpecification -Name AuditSpecification -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter AvailabilityGroup -Name AvailabilityGroup -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter BackupDevice -Name BackupDevice -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter ConfigName -Name ConfigName -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter Credential -Name Credential -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter CredentialIdentity -Name Credential -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter CustomError -Name CustomError -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter Database -Name Database -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter Endpoint -Name Endpoint -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter ExcludeAlert -Name Alert -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter ExcludeAlertCategory -Name AlertCategory -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter ExcludeAudit -Name Audit -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter ExcludeAuditSpecification -Name AuditSpecification -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter ExcludeAvailabilityGroup -Name AvailabilityGroup -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter ExcludeBackupDevice -Name BackupDevice -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter ExcludeConfigName -Name ConfigName -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter ExcludeCredential -Name Credential -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter ExcludeCredentialIdentity -Name Credential -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter ExcludeCustomError -Name CustomError -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter ExcludeDatabase -Name Database -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter ExcludeEndpoint -Name Endpoint -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter ExcludeGroup -Name Group -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter ExcludeJob -Name Job -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter ExcludeJobCategory -Name JobCategory -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter ExcludeLinkedServer -Name LinkedServer -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter ExcludeLogin -Name Login -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter ExcludeMailAccount -Name MailAccount -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter ExcludeMailProfile -Name MailProfile -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter ExcludeMailServer -Name MailServer -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter ExcludeOperator -Name Operator -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter ExcludeProxyAccount -Name ProxyAccount -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter ExcludeResourcePool -Name ResourcePool -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter ExcludeSchedule -Name Schedule -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter ExcludeServerTrigger -Name ServerTrigger -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter ExcludeSession -Name Session -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter ExcludeSnapshot -Name Snapshot -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter Group -Name Group -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter Job -Name Job -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter JobCategory -Name JobCategory -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter LinkedServer -Name LinkedServer -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter Login -Name Login -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter MailAccount -Name MailAccount -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter MailProfile -Name MailProfile -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter MailServer -Name MailServer -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter Operator -Name Operator -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter ProxyAccount -Name ProxyAccount -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter ResourcePool -Name ResourcePool -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter Schedule -Name Schedule -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter ServerTrigger -Name ServerTrigger -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter Session -Name Session -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter Snapshot -Name Snapshot -All
Register-DbaTeppArgumentCompleter -Command $names -Parameter SqlInstance -Name SqlInstance -All
#endregion Automatic TEPP by parameter name

#region Explicit TEPP
Register-DbaTeppArgumentCompleter -Command "Find-DbaCommand" -Parameter Tag -Name tag
Register-DbaTeppArgumentCompleter -Command "Get-DbaConfig", "Get-DbaConfigValue", "Register-DbaConfig", "Set-DbaConfig" -Parameter FullName -Name config
Register-DbaTeppArgumentCompleter -Command "Get-DbaConfig", "Register-DbaConfig", "Set-DbaConfig" -Parameter Module -Name configmodule
Register-DbaTeppArgumentCompleter -Command "Get-DbaConfig", "Register-DbaConfig", "Set-DbaConfig" -Parameter Name -Name config_name
Register-DbaTeppArgumentCompleter -Command "Get-DbaProcess", "Stop-DbaProcess" -Parameter ExcludeSpid -Name processSpid
Register-DbaTeppArgumentCompleter -Command "Get-DbaProcess", "Stop-DbaProcess" -Parameter Hostname -Name processHostname
Register-DbaTeppArgumentCompleter -Command "Get-DbaProcess", "Stop-DbaProcess" -Parameter Program -Name processProgram
Register-DbaTeppArgumentCompleter -Command "Get-DbaProcess", "Stop-DbaProcess" -Parameter Spid -Name processSpid
#endregion Explicit TEPP
