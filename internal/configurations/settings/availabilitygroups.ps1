<#
This is designed for all things related to availability groups
#>


# Parameters related to the availability group:

# Sets the default ClusterType
Set-DbatoolsConfig -FullName 'AvailabilityGroups.Default.ClusterType' -Value 'Wsfc' -Initialize -Description 'Used to identify if the availability group is on a Windows Server Failover Cluster (WSFC). See: https://docs.microsoft.com/en-us/sql/t-sql/statements/create-availability-group-transact-sql'

# Sets the default FailureConditionLevel
Set-DbatoolsConfig -FullName 'AvailabilityGroups.Default.FailureConditionLevel' -Value 'OnCriticalServerErrors' -Initialize -Description 'Specifies what failure conditions trigger an automatic failover for this availability group. See: https://docs.microsoft.com/en-us/sql/t-sql/statements/create-availability-group-transact-sql'


# Parameters related to the replica:

# Sets the default FailureConditionLevel
Set-DbatoolsConfig -FullName 'AvailabilityGroups.Default.ConnectionModeInSecondaryRole' -Value 'AllowNoConnections' -Initialize -Description 'Specifies whether the databases of a given availability replica that is performing the secondary role can accept connections from clients. See: https://docs.microsoft.com/en-us/sql/t-sql/statements/create-availability-group-transact-sql'
