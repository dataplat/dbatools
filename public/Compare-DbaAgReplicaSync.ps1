function Compare-DbaAgReplicaSync {
    <#
    .SYNOPSIS
        Compares server-level objects across Availability Group replicas to identify synchronization differences.

    .DESCRIPTION
        Compares server-level objects across all replicas in an Availability Group to identify differences that would prevent seamless failover. Availability groups only synchronize databases, not the server-level dependencies that applications need to function properly after failover.

        This command reports differences without making any changes, making it ideal for monitoring, alerting, and situations where you need to review differences before deciding how to handle them.

        By default, compares these object types across all replicas:

        SpConfigure
        CustomErrors
        Credentials
        DatabaseMail
        LinkedServers
        Logins
        SystemTriggers
        AgentCategory
        AgentOperator
        AgentAlert
        AgentProxy
        AgentSchedule
        AgentJob

        Any of these object types can be excluded using the -Exclude parameter. The command returns structured data showing what objects are missing or different on each replica.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Can be any replica in the Availability Group.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER AvailabilityGroup
        Specifies one or more Availability Group names to compare objects across their replicas.

    .PARAMETER Exclude
        Excludes specific object types from comparison. Valid values:

        SpConfigure, CustomErrors, Credentials, DatabaseMail, LinkedServers, Logins,
        SystemTriggers, AgentCategory, AgentOperator, AgentAlert, AgentProxy, AgentSchedule, AgentJob

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: AvailabilityGroup, AG, Sync, Compare
        Author: the dbatools team + Claude

        Website: https://dbatools.io
        Copyright: (c) 2025 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Compare-DbaAgReplicaSync

    .EXAMPLE
        PS C:\> Compare-DbaAgReplicaSync -SqlInstance sql2016 -AvailabilityGroup AG1

        Compares all server-level objects across replicas in the AG1 Availability Group and reports differences.

    .EXAMPLE
        PS C:\> Compare-DbaAgReplicaSync -SqlInstance sql2016 -AvailabilityGroup AG1 -Exclude LinkedServers, DatabaseMail

        Compares server-level objects excluding LinkedServers and DatabaseMail configurations.

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sql2016 | Compare-DbaAgReplicaSync

        Compares server-level objects for all Availability Groups on sql2016 via pipeline input.

    .EXAMPLE
        PS C:\> Compare-DbaAgReplicaSync -SqlInstance sql2016 -AvailabilityGroup AG1 | Where-Object Status -eq "Missing"

        Shows only objects that are missing on one or more replicas.
    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$AvailabilityGroup,
        [ValidateSet("AgentCategory", "AgentOperator", "AgentAlert", "AgentProxy", "AgentSchedule", "AgentJob", "Credentials", "CustomErrors", "DatabaseMail", "LinkedServers", "Logins", "SpConfigure", "SystemTriggers")]
        [string[]]$Exclude,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 11
            } catch {
                Stop-Function -Message "Failure connecting to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if (-not $server.IsHadrEnabled) {
                Stop-Function -Message "Availability Group (HADR) is not configured for the instance: $instance." -Target $instance -Continue
            }

            $availabilityGroups = $server.AvailabilityGroups

            if ($AvailabilityGroup) {
                $availabilityGroups = $availabilityGroups | Where-Object Name -in $AvailabilityGroup
            }

            if (-not $availabilityGroups) {
                Stop-Function -Message "No Availability Groups found on $instance matching the specified criteria." -Target $instance -Continue
            }

            foreach ($ag in $availabilityGroups) {
                $replicas = $ag.AvailabilityReplicas

                if ($replicas.Count -lt 2) {
                    Stop-Function -Message "Availability Group '$($ag.Name)' has less than 2 replicas. Nothing to compare." -Target $ag -Continue
                }

                $replicaInstances = @()
                foreach ($replica in $replicas) {
                    $replicaInstances += $replica.Name
                }

                # Compare Logins
                if ($Exclude -notcontains "Logins") {
                    $loginsByReplica = @{}
                    $serversByReplica = @{}
                    $allLoginNames = New-Object System.Collections.ArrayList

                    foreach ($replicaInstance in $replicaInstances) {
                        try {
                            $splatConnection = @{
                                SqlInstance   = $replicaInstance
                                SqlCredential = $SqlCredential
                            }
                            $replicaServer = Connect-DbaInstance @splatConnection
                            $logins = Get-DbaLogin -SqlInstance $replicaServer
                            $loginsByReplica[$replicaInstance] = $logins
                            $serversByReplica[$replicaInstance] = $replicaServer

                            foreach ($login in $logins) {
                                if ($login.Name -notin $allLoginNames) {
                                    $null = $allLoginNames.Add($login.Name)
                                }
                            }
                        } catch {
                            Stop-Function -Message "Failed to retrieve logins from replica $replicaInstance" -ErrorRecord $_ -Target $replicaInstance -Continue
                        }
                    }

                    foreach ($loginName in $allLoginNames) {
                        $loginConfigs = @{}

                        # Collect login configurations from all replicas
                        foreach ($replicaInstance in $replicaInstances) {
                            $login = $loginsByReplica[$replicaInstance] | Where-Object Name -eq $loginName
                            $replicaServer = $serversByReplica[$replicaInstance]

                            if (-not $login) {
                                $loginConfigs[$replicaInstance] = $null
                            } else {
                                # Build comprehensive login configuration
                                $config = @{
                                    IsDisabled                = $login.IsDisabled
                                    DenyWindowsLogin          = $login.DenyWindowsLogin
                                    DefaultDatabase           = $login.DefaultDatabase
                                    Language                  = $login.Language
                                    LoginType                 = $login.LoginType
                                    PasswordExpirationEnabled = $null
                                    PasswordPolicyEnforced    = $null
                                    ServerRoles               = @()
                                }

                                # SQL Login specific properties
                                if ($login.LoginType -eq "SqlLogin") {
                                    $config.PasswordExpirationEnabled = $login.PasswordExpirationEnabled
                                    $config.PasswordPolicyEnforced = $login.PasswordPolicyEnforced
                                }

                                # Get server roles (SQL 2005+)
                                if ($replicaServer.VersionMajor -ge 9) {
                                    $roles = New-Object System.Collections.ArrayList
                                    foreach ($role in $replicaServer.Roles) {
                                        try {
                                            $members = $role.EnumMemberNames()
                                        } catch {
                                            $members = $role.EnumServerRoleMembers()
                                        }
                                        if ($members -contains $loginName) {
                                            $null = $roles.Add($role.Name)
                                        }
                                    }
                                    $config.ServerRoles = $roles.ToArray()
                                }

                                $loginConfigs[$replicaInstance] = $config
                            }
                        }

                        # Compare configurations across replicas
                        $replicaConfigList = @($loginConfigs.GetEnumerator())
                        $baseReplica = $replicaConfigList[0]
                        $baseConfig = $baseReplica.Value

                        foreach ($replicaInstance in $replicaInstances) {
                            $config = $loginConfigs[$replicaInstance]

                            if ($null -eq $config) {
                                # Login is missing - output directly
                                [PSCustomObject]@{
                                    AvailabilityGroup   = $ag.Name
                                    Replica             = $replicaInstance
                                    ObjectType          = "Login"
                                    ObjectName          = $loginName
                                    Status              = "Missing"
                                    PropertyDifferences = $null
                                }
                            } elseif ($null -ne $baseConfig) {
                                # Compare properties
                                $propertyDiffs = New-Object System.Collections.ArrayList

                                if ($config.IsDisabled -ne $baseConfig.IsDisabled) {
                                    $null = $propertyDiffs.Add("IsDisabled: $($config.IsDisabled) vs $($baseConfig.IsDisabled)")
                                }
                                if ($config.DenyWindowsLogin -ne $baseConfig.DenyWindowsLogin) {
                                    $null = $propertyDiffs.Add("DenyWindowsLogin: $($config.DenyWindowsLogin) vs $($baseConfig.DenyWindowsLogin)")
                                }
                                if ($config.DefaultDatabase -ne $baseConfig.DefaultDatabase) {
                                    $null = $propertyDiffs.Add("DefaultDatabase: $($config.DefaultDatabase) vs $($baseConfig.DefaultDatabase)")
                                }
                                if ($config.Language -ne $baseConfig.Language) {
                                    $null = $propertyDiffs.Add("Language: $($config.Language) vs $($baseConfig.Language)")
                                }
                                if ($config.LoginType -eq "SqlLogin" -and $baseConfig.LoginType -eq "SqlLogin") {
                                    if ($config.PasswordExpirationEnabled -ne $baseConfig.PasswordExpirationEnabled) {
                                        $null = $propertyDiffs.Add("PasswordExpirationEnabled: $($config.PasswordExpirationEnabled) vs $($baseConfig.PasswordExpirationEnabled)")
                                    }
                                    if ($config.PasswordPolicyEnforced -ne $baseConfig.PasswordPolicyEnforced) {
                                        $null = $propertyDiffs.Add("PasswordPolicyEnforced: $($config.PasswordPolicyEnforced) vs $($baseConfig.PasswordPolicyEnforced)")
                                    }
                                }

                                # Compare server roles
                                $roleComparison = Compare-Object -ReferenceObject $baseConfig.ServerRoles -DifferenceObject $config.ServerRoles
                                if ($roleComparison) {
                                    $missingRoles = ($roleComparison | Where-Object SideIndicator -eq "<=").InputObject
                                    $extraRoles = ($roleComparison | Where-Object SideIndicator -eq "=>").InputObject
                                    if ($missingRoles) {
                                        $null = $propertyDiffs.Add("Missing ServerRoles: $($missingRoles -join ', ')")
                                    }
                                    if ($extraRoles) {
                                        $null = $propertyDiffs.Add("Extra ServerRoles: $($extraRoles -join ', ')")
                                    }
                                }

                                if ($propertyDiffs.Count -gt 0) {
                                    [PSCustomObject]@{
                                        AvailabilityGroup   = $ag.Name
                                        Replica             = $replicaInstance
                                        ObjectType          = "Login"
                                        ObjectName          = $loginName
                                        Status              = "Different"
                                        PropertyDifferences = ($propertyDiffs -join "; ")
                                    }
                                }
                            }
                        }
                    }
                }

                # Compare Agent Jobs
                if ($Exclude -notcontains "AgentJob") {
                    $jobsByReplica = @{}
                    $allJobNames = New-Object System.Collections.ArrayList

                    foreach ($replicaInstance in $replicaInstances) {
                        try {
                            $splatConnection = @{
                                SqlInstance   = $replicaInstance
                                SqlCredential = $SqlCredential
                            }
                            $replicaServer = Connect-DbaInstance @splatConnection
                            $jobs = Get-DbaAgentJob -SqlInstance $replicaServer
                            $jobsByReplica[$replicaInstance] = $jobs

                            foreach ($job in $jobs) {
                                if ($job.Name -notin $allJobNames) {
                                    $null = $allJobNames.Add($job.Name)
                                }
                            }
                        } catch {
                            Stop-Function -Message "Failed to retrieve jobs from replica $replicaInstance" -ErrorRecord $_ -Target $replicaInstance -Continue
                        }
                    }

                    foreach ($jobName in $allJobNames) {
                        foreach ($replicaInstance in $replicaInstances) {
                            $job = $jobsByReplica[$replicaInstance] | Where-Object Name -eq $jobName

                            if (-not $job) {
                                [PSCustomObject]@{
                                    AvailabilityGroup = $ag.Name
                                    Replica           = $replicaInstance
                                    ObjectType        = "AgentJob"
                                    ObjectName        = $jobName
                                    Status            = "Missing"
                                }
                            }
                        }
                    }
                }

                # Compare Credentials
                if ($Exclude -notcontains "Credentials") {
                    $credentialsByReplica = @{}
                    $allCredentialNames = New-Object System.Collections.ArrayList

                    foreach ($replicaInstance in $replicaInstances) {
                        try {
                            $splatConnection = @{
                                SqlInstance   = $replicaInstance
                                SqlCredential = $SqlCredential
                            }
                            $replicaServer = Connect-DbaInstance @splatConnection
                            $credentials = $replicaServer.Credentials
                            $credentialsByReplica[$replicaInstance] = $credentials

                            foreach ($credential in $credentials) {
                                if ($credential.Name -notin $allCredentialNames) {
                                    $null = $allCredentialNames.Add($credential.Name)
                                }
                            }
                        } catch {
                            Stop-Function -Message "Failed to retrieve credentials from replica $replicaInstance" -ErrorRecord $_ -Target $replicaInstance -Continue
                        }
                    }

                    foreach ($credentialName in $allCredentialNames) {
                        foreach ($replicaInstance in $replicaInstances) {
                            $credential = $credentialsByReplica[$replicaInstance] | Where-Object Name -eq $credentialName

                            if (-not $credential) {
                                [PSCustomObject]@{
                                    AvailabilityGroup = $ag.Name
                                    Replica           = $replicaInstance
                                    ObjectType        = "Credential"
                                    ObjectName        = $credentialName
                                    Status            = "Missing"
                                }
                            }
                        }
                    }
                }

                # Compare Linked Servers
                if ($Exclude -notcontains "LinkedServers") {
                    $linkedServersByReplica = @{}
                    $allLinkedServerNames = New-Object System.Collections.ArrayList

                    foreach ($replicaInstance in $replicaInstances) {
                        try {
                            $splatConnection = @{
                                SqlInstance   = $replicaInstance
                                SqlCredential = $SqlCredential
                            }
                            $replicaServer = Connect-DbaInstance @splatConnection
                            $linkedServers = $replicaServer.LinkedServers
                            $linkedServersByReplica[$replicaInstance] = $linkedServers

                            foreach ($linkedServer in $linkedServers) {
                                if ($linkedServer.Name -notin $allLinkedServerNames) {
                                    $null = $allLinkedServerNames.Add($linkedServer.Name)
                                }
                            }
                        } catch {
                            Stop-Function -Message "Failed to retrieve linked servers from replica $replicaInstance" -ErrorRecord $_ -Target $replicaInstance -Continue
                        }
                    }

                    foreach ($linkedServerName in $allLinkedServerNames) {
                        foreach ($replicaInstance in $replicaInstances) {
                            $linkedServer = $linkedServersByReplica[$replicaInstance] | Where-Object Name -eq $linkedServerName

                            if (-not $linkedServer) {
                                [PSCustomObject]@{
                                    AvailabilityGroup = $ag.Name
                                    Replica           = $replicaInstance
                                    ObjectType        = "LinkedServer"
                                    ObjectName        = $linkedServerName
                                    Status            = "Missing"
                                }
                            }
                        }
                    }
                }

                # Compare Agent Operators
                if ($Exclude -notcontains "AgentOperator") {
                    $operatorsByReplica = @{}
                    $allOperatorNames = New-Object System.Collections.ArrayList

                    foreach ($replicaInstance in $replicaInstances) {
                        try {
                            $splatConnection = @{
                                SqlInstance   = $replicaInstance
                                SqlCredential = $SqlCredential
                            }
                            $replicaServer = Connect-DbaInstance @splatConnection
                            $operators = Get-DbaAgentOperator -SqlInstance $replicaServer
                            $operatorsByReplica[$replicaInstance] = $operators

                            foreach ($operator in $operators) {
                                if ($operator.Name -notin $allOperatorNames) {
                                    $null = $allOperatorNames.Add($operator.Name)
                                }
                            }
                        } catch {
                            Stop-Function -Message "Failed to retrieve operators from replica $replicaInstance" -ErrorRecord $_ -Target $replicaInstance -Continue
                        }
                    }

                    foreach ($operatorName in $allOperatorNames) {
                        foreach ($replicaInstance in $replicaInstances) {
                            $operator = $operatorsByReplica[$replicaInstance] | Where-Object Name -eq $operatorName

                            if (-not $operator) {
                                [PSCustomObject]@{
                                    AvailabilityGroup = $ag.Name
                                    Replica           = $replicaInstance
                                    ObjectType        = "AgentOperator"
                                    ObjectName        = $operatorName
                                    Status            = "Missing"
                                }
                            }
                        }
                    }
                }

                # Compare Agent Alerts
                if ($Exclude -notcontains "AgentAlert") {
                    $alertsByReplica = @{}
                    $allAlertNames = New-Object System.Collections.ArrayList

                    foreach ($replicaInstance in $replicaInstances) {
                        try {
                            $splatConnection = @{
                                SqlInstance   = $replicaInstance
                                SqlCredential = $SqlCredential
                            }
                            $replicaServer = Connect-DbaInstance @splatConnection
                            $alerts = Get-DbaAgentAlert -SqlInstance $replicaServer
                            $alertsByReplica[$replicaInstance] = $alerts

                            foreach ($alert in $alerts) {
                                if ($alert.Name -notin $allAlertNames) {
                                    $null = $allAlertNames.Add($alert.Name)
                                }
                            }
                        } catch {
                            Stop-Function -Message "Failed to retrieve alerts from replica $replicaInstance" -ErrorRecord $_ -Target $replicaInstance -Continue
                        }
                    }

                    foreach ($alertName in $allAlertNames) {
                        foreach ($replicaInstance in $replicaInstances) {
                            $alert = $alertsByReplica[$replicaInstance] | Where-Object Name -eq $alertName

                            if (-not $alert) {
                                [PSCustomObject]@{
                                    AvailabilityGroup = $ag.Name
                                    Replica           = $replicaInstance
                                    ObjectType        = "AgentAlert"
                                    ObjectName        = $alertName
                                    Status            = "Missing"
                                }
                            }
                        }
                    }
                }

                # Compare Agent Proxies
                if ($Exclude -notcontains "AgentProxy") {
                    $proxiesByReplica = @{}
                    $allProxyNames = New-Object System.Collections.ArrayList

                    foreach ($replicaInstance in $replicaInstances) {
                        try {
                            $splatConnection = @{
                                SqlInstance   = $replicaInstance
                                SqlCredential = $SqlCredential
                            }
                            $replicaServer = Connect-DbaInstance @splatConnection
                            $proxies = Get-DbaAgentProxy -SqlInstance $replicaServer
                            $proxiesByReplica[$replicaInstance] = $proxies

                            foreach ($proxy in $proxies) {
                                if ($proxy.Name -notin $allProxyNames) {
                                    $null = $allProxyNames.Add($proxy.Name)
                                }
                            }
                        } catch {
                            Stop-Function -Message "Failed to retrieve proxies from replica $replicaInstance" -ErrorRecord $_ -Target $replicaInstance -Continue
                        }
                    }

                    foreach ($proxyName in $allProxyNames) {
                        foreach ($replicaInstance in $replicaInstances) {
                            $proxy = $proxiesByReplica[$replicaInstance] | Where-Object Name -eq $proxyName

                            if (-not $proxy) {
                                [PSCustomObject]@{
                                    AvailabilityGroup = $ag.Name
                                    Replica           = $replicaInstance
                                    ObjectType        = "AgentProxy"
                                    ObjectName        = $proxyName
                                    Status            = "Missing"
                                }
                            }
                        }
                    }
                }

                # Compare Custom Errors
                if ($Exclude -notcontains "CustomErrors") {
                    $errorsByReplica = @{}
                    $allErrorIds = New-Object System.Collections.ArrayList

                    foreach ($replicaInstance in $replicaInstances) {
                        try {
                            $splatConnection = @{
                                SqlInstance   = $replicaInstance
                                SqlCredential = $SqlCredential
                            }
                            $replicaServer = Connect-DbaInstance @splatConnection
                            $errors = $replicaServer.UserDefinedMessages
                            $errorsByReplica[$replicaInstance] = $errors

                            foreach ($error in $errors) {
                                if ($error.ID -notin $allErrorIds) {
                                    $null = $allErrorIds.Add($error.ID)
                                }
                            }
                        } catch {
                            Stop-Function -Message "Failed to retrieve custom errors from replica $replicaInstance" -ErrorRecord $_ -Target $replicaInstance -Continue
                        }
                    }

                    foreach ($errorId in $allErrorIds) {
                        foreach ($replicaInstance in $replicaInstances) {
                            $error = $errorsByReplica[$replicaInstance] | Where-Object ID -eq $errorId

                            if (-not $error) {
                                [PSCustomObject]@{
                                    AvailabilityGroup = $ag.Name
                                    Replica           = $replicaInstance
                                    ObjectType        = "CustomError"
                                    ObjectName        = "Error $errorId"
                                    Status            = "Missing"
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
