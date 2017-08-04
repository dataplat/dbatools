$functions = Get-ChildItem function:\*-Dba*

#region Automatic TEPP by parameter name
foreach ($function in $functions) {
	if ($function.Parameters.Keys -contains "SqlInstance") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter SqlInstance -Name SqlInstance
	}
	if ($function.Parameters.Keys -contains "Database") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter Database -Name Database
	}
	if ($function.Parameters.Keys -contains "ExcludeDatabase") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter ExcludeDatabase -Name Database
	}
	if ($function.Parameters.Keys -contains "Job") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter Job -Name Job
	}
	if ($function.Parameters.Keys -contains "ExcludeJob") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter ExcludeJob -Name Job
	}
	if ($function.Parameters.Keys -contains "Login") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter Login -Name Login
	}
	if ($function.Parameters.Keys -contains "ExcludeLogin") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter ExcludeLogin -Name Login
	}
	if ($function.Parameters.Keys -contains "Operator") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter Operator -Name Operator
	}
	if ($function.Parameters.Keys -contains "ExcludeOperator") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter ExcludeOperator -Name Operator
	}
	if ($function.Parameters.Keys -contains "Snapshot") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter Snapshot -Name Snapshot
	}
	if ($function.Parameters.Keys -contains "ExcludeSnapshot") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter ExcludeSnapshot -Name Snapshot
	}

	if ($function.Parameters.Keys -contains "ConfigName") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter ConfigName -Name ConfigName
	}
	if ($function.Parameters.Keys -contains "ExcludeConfigName") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter ExcludeConfigName -Name ConfigName
	}

	if ($function.Parameters.Keys -contains "Alert") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter Alert -Name Alert
	}
	if ($function.Parameters.Keys -contains "ExcludeAlert") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter ExcludeAlert -Name Alert
	}

	if ($function.Parameters.Keys -contains "AlertCategory") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter AlertCategory -Name AlertCategory
	}
	if ($function.Parameters.Keys -contains "ExcludeAlertCategory") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter ExcludeAlertCategory -Name AlertCategory
	}

	if ($function.Parameters.Keys -contains "JobCategory") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter JobCategory -Name JobCategory
	}
	if ($function.Parameters.Keys -contains "ExcludeJobCategory") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter ExcludeJobCategory -Name JobCategory
	}

	if ($function.Parameters.Keys -contains "AvailabilityGroup") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter AvailabilityGroup -Name AvailabilityGroup
	}
	if ($function.Parameters.Keys -contains "ExcludeAvailabilityGroup") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter ExcludeAvailabilityGroup -Name AvailabilityGroup
	}

	if ($function.Parameters.Keys -contains "BackupDevice") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter BackupDevice -Name BackupDevice
	}
	if ($function.Parameters.Keys -contains "ExcludeBackupDevice") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter ExcludeBackupDevice -Name BackupDevice
	}

	if ($function.Parameters.Keys -contains "Credential") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter Credential -Name Credential
	}
	if ($function.Parameters.Keys -contains "ExcludeCredential") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter ExcludeCredential -Name Credential
	}
	
	if ($function.Parameters.Keys -contains "CredentialIdentity") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter CredentialIdentity -Name Credential
	}
	if ($function.Parameters.Keys -contains "ExcludeCredentialIdentity") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter ExcludeCredentialIdentity -Name Credential
	}
	
	if ($function.Parameters.Keys -contains "CustomError") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter CustomError -Name CustomError
	}
	if ($function.Parameters.Keys -contains "ExcludeCustomError") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter ExcludeCustomError -Name CustomError
	}

	if ($function.Parameters.Keys -contains "MailAccount") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter MailAccount -Name MailAccount
	}
	if ($function.Parameters.Keys -contains "ExcludeMailAccount") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter ExcludeMailAccount -Name MailAccount
	}

	if ($function.Parameters.Keys -contains "MailServer") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter MailServer -Name MailServer
	}
	if ($function.Parameters.Keys -contains "ExcludeMailServer") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter ExcludeMailServer -Name MailServer
	}

	if ($function.Parameters.Keys -contains "MailProfile") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter MailProfile -Name MailProfile
	}
	if ($function.Parameters.Keys -contains "ExcludeMailProfile") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter ExcludeMailProfile -Name MailProfile
	}

	if ($function.Parameters.Keys -contains "Endpoint") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter Endpoint -Name Endpoint
	}
	if ($function.Parameters.Keys -contains "ExcludeEndpoint") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter ExcludeEndpoint -Name Endpoint
	}

	if ($function.Parameters.Keys -contains "LinkedServer") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter LinkedServer -Name LinkedServer
	}
	if ($function.Parameters.Keys -contains "ExcludeLinkedServer") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter ExcludeLinkedServer -Name LinkedServer
	}

	if ($function.Parameters.Keys -contains "ProxyAccount") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter ProxyAccount -Name ProxyAccount
	}
	if ($function.Parameters.Keys -contains "ExcludeProxyAccount") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter ExcludeProxyAccount -Name ProxyAccount
	}

	if ($function.Parameters.Keys -contains "ResourcePool") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter ResourcePool -Name ResourcePool
	}
	if ($function.Parameters.Keys -contains "ExcludeResourcePool") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter ExcludeResourcePool -Name ResourcePool
	}

	if ($function.Parameters.Keys -contains "Audit") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter Audit -Name Audit
	}
	if ($function.Parameters.Keys -contains "ExcludeAudit") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter ExcludeAudit -Name Audit
	}

	if ($function.Parameters.Keys -contains "AuditSpecification") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter AuditSpecification -Name AuditSpecification
	}
	if ($function.Parameters.Keys -contains "ExcludeAuditSpecification") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter ExcludeAuditSpecification -Name AuditSpecification
	}

	if ($function.Parameters.Keys -contains "ServerTrigger") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter ServerTrigger -Name ServerTrigger
	}
	if ($function.Parameters.Keys -contains "ExcludeServerTrigger") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter ExcludeServerTrigger -Name ServerTrigger
	}

	if ($function.Parameters.Keys -contains "Schedule") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter Schedule -Name Schedule
	}
	if ($function.Parameters.Keys -contains "ExcludeSchedule") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter ExcludeSchedule -Name Schedule
	}

	if ($function.Parameters.Keys -contains "Group") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter Group -Name Group
	}
	if ($function.Parameters.Keys -contains "ExcludeGroup") {
		Register-DbaTeppArgumentCompleter -Command $function.Name -Parameter ExcludeGroup -Name Group
	}
}
#endregion Automatic TEPP by parameter name

#region Explicit TEPP
Register-DbaTeppArgumentCompleter -Command "Find-DbaCommand" -Parameter Tag -Name tag
Register-DbaTeppArgumentCompleter -Command "Get-DbaConfig" -Parameter FullName -Name config
Register-DbaTeppArgumentCompleter -Command "Get-DbaConfig" -Parameter Name -Name configname
Register-DbaTeppArgumentCompleter -Command "Get-DbaConfig" -Parameter Module -Name configmodule
Register-DbaTeppArgumentCompleter -Command "Get-DbaConfigValue" -Parameter Name -Name config
Register-DbaTeppArgumentCompleter -Command "Get-DbaProcess" -Parameter ExcludeSpid -Name processSpid
Register-DbaTeppArgumentCompleter -Command "Get-DbaProcess" -Parameter Hostname -Name processHostname
Register-DbaTeppArgumentCompleter -Command "Get-DbaProcess" -Parameter Program -Name processProgram
Register-DbaTeppArgumentCompleter -Command "Get-DbaProcess" -Parameter Spid -Name processSpid
Register-DbaTeppArgumentCompleter -Command "Stop-DbaProcess" -Parameter ExcludeSpid -Name processSpid
Register-DbaTeppArgumentCompleter -Command "Stop-DbaProcess" -Parameter Hostname -Name processHostname
Register-DbaTeppArgumentCompleter -Command "Stop-DbaProcess" -Parameter Program -Name processProgram
Register-DbaTeppArgumentCompleter -Command "Stop-DbaProcess" -Parameter Spid -Name processSpid
Register-DbaTeppArgumentCompleter -Command "Set-DbaConfig" -Parameter Name -Name config
Register-DbaTeppArgumentCompleter -Command "Set-DbaConfig" -Parameter Module -Name configmodule
#endregion Explicit TEPP