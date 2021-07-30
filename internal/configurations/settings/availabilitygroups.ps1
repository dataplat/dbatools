<#
This is designed for all things related to availability groups
#>

# Sets the default FailureConditionLevel
Set-DbatoolsConfig -FullName 'AvailabilityGroups.Default.FailureConditionLevel' -Value 'OnCriticalServerErrors' -Initialize -Description 'Specifies what failure conditions trigger an automatic failover for this availability group. See: https://docs.microsoft.com/en-us/sql/t-sql/statements/create-availability-group-transact-sql'
