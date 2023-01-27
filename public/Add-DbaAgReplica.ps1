function Add-DbaAgReplica {
    <#
    .SYNOPSIS
        Adds a replica to an availability group on one or more SQL Server instances.

    .DESCRIPTION
        Adds a replica to an availability group on one or more SQL Server instances.

        Automatically creates database mirroring endpoints if required.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Server version must be SQL Server version 2012 or higher.

    .PARAMETER SqlCredential
        Login to the target instances using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Name
        The name of the replica. Defaults to the SQL Server instance name.

        This parameter is only supported if the replica is added to just one instance.

    .PARAMETER ClusterType
        Cluster type of the Availability Group. Only supported in SQL Server 2017 and above.
        Options include: Wsfc, External or None.

        Defaults to Wsfc (Windows Server Failover Cluster).

        The default can be changed with:
        Set-DbatoolsConfig -FullName 'AvailabilityGroups.Default.ClusterType' -Value '...' -Passthru | Register-DbatoolsConfig

    .PARAMETER AvailabilityMode
        Sets the availability mode of the availability group replica. Options are: AsynchronousCommit and SynchronousCommit. SynchronousCommit is default.

    .PARAMETER FailoverMode
        Sets the failover mode of the availability group replica. Options are Automatic and Manual. Automatic is default.

    .PARAMETER BackupPriority
        Sets the backup priority availability group replica. Default is 50.

    .PARAMETER Endpoint
        By default, this command will attempt to find a DatabaseMirror endpoint. If one does not exist, it will create it.

        If an endpoint must be created, the name "hadr_endpoint" will be used. If an alternative is preferred, use Endpoint.

    .PARAMETER EndpointUrl
        By default, the property Fqdn of Get-DbaEndpoint is used as EndpointUrl.

        Use EndpointUrl if a different URL is required due to special network configurations.
        EndpointUrl has to be an array of strings in format 'TCP://system-address:port', one entry for every instance.
        See details at: https://docs.microsoft.com/en-us/sql/database-engine/availability-groups/windows/specify-endpoint-url-adding-or-modifying-availability-replica

        If an endpoint must be created, EndpointUrl will be used for configuration, if system-address is an ipv4 address.

    .PARAMETER Passthru
        Don't create the replica, just pass thru an object that can be further customized before creation.

    .PARAMETER InputObject
        Enables piping from Get-DbaAvailabilityGroup.

    .PARAMETER ConnectionModeInPrimaryRole
        Specifies the connection intent mode of an Availability Replica in primary role. AllowAllConnections by default.

    .PARAMETER ConnectionModeInSecondaryRole
        Specifies the connection modes of an Availability Replica in secondary role.
        Options include: AllowNoConnections, AllowReadIntentConnectionsOnly,  AllowAllConnections

        Defaults to AllowNoConnections.

        The default can be changed with:
        Set-DbatoolsConfig -FullName 'AvailabilityGroups.Default.ConnectionModeInSecondaryRole' -Value '...' -Passthru | Register-DbatoolsConfig

    .PARAMETER ReadOnlyRoutingList
        Sets the read only routing ordered list of replica server names to use when redirecting read-only connections through this availability replica.

        This parameter is only supported if the replica is added to just one instance.

    .PARAMETER ReadonlyRoutingConnectionUrl
        Sets the read only routing connection url for the availability replica.

        This parameter is only supported if the replica is added to just one instance.

    .PARAMETER SeedingMode
        Specifies how the secondary replica will be initially seeded.

        Automatic enables direct seeding. This method will seed the secondary replica over the network. This method does not require you to backup and restore a copy of the primary database on the replica.

        Manual requires you to create a backup of the database on the primary replica and manually restore that backup on the secondary replica.

    .PARAMETER Certificate
        Specifies that the endpoint is to authenticate the connection using the certificate specified by certificate_name to establish identity for authorization.

        The far endpoint must have a certificate with the public key matching the private key of the specified certificate.

    .PARAMETER ConfigureXESession
        Configure the AlwaysOn_health extended events session to start automatically as the SSMS wizard would do.
        https://docs.microsoft.com/en-us/sql/database-engine/availability-groups/windows/always-on-extended-events#BKMK_alwayson_health

    .PARAMETER SessionTimeout
        How many seconds an availability replica waits for a ping response from a connected replica before considering the connection to have failed.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: AG, HA
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Add-DbaAgReplica

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sql2017a -AvailabilityGroup SharePoint | Add-DbaAgReplica -SqlInstance sql2017b

        Adds sql2017b to the SharePoint availability group on sql2017a

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sql2017a -AvailabilityGroup SharePoint | Add-DbaAgReplica -SqlInstance sql2017b -FailoverMode Manual

        Adds sql2017b to the SharePoint availability group on sql2017a with a manual failover mode.

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sql2017a -AvailabilityGroup SharePoint | Add-DbaAgReplica -SqlInstance sql2017b -EndpointUrl 'TCP://sql2017b.specialnet.local:5022'

        Adds sql2017b to the SharePoint availability group on sql2017a with a custom endpoint URL.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$Name,
        [ValidateSet('Wsfc', 'External', 'None')]
        [string]$ClusterType = (Get-DbatoolsConfigValue -FullName 'AvailabilityGroups.Default.ClusterType' -Fallback 'Wsfc'),
        [ValidateSet('AsynchronousCommit', 'SynchronousCommit')]
        [string]$AvailabilityMode = "SynchronousCommit",
        [ValidateSet('Automatic', 'Manual', 'External')]
        [string]$FailoverMode = "Automatic",
        [int]$BackupPriority = 50,
        [ValidateSet('AllowAllConnections', 'AllowReadWriteConnections')]
        [string]$ConnectionModeInPrimaryRole = 'AllowAllConnections',
        [ValidateSet('AllowNoConnections', 'AllowReadIntentConnectionsOnly', 'AllowAllConnections', 'No', 'Read-intent only', 'Yes')]
        [string]$ConnectionModeInSecondaryRole = (Get-DbatoolsConfigValue -FullName 'AvailabilityGroups.Default.ConnectionModeInSecondaryRole' -Fallback 'AllowNoConnections'),
        [ValidateSet('Automatic', 'Manual')]
        [string]$SeedingMode,
        [string]$Endpoint,
        [string[]]$EndpointUrl,
        [switch]$Passthru,
        [string[]]$ReadOnlyRoutingList,
        [string]$ReadonlyRoutingConnectionUrl,
        [string]$Certificate,
        [switch]$ConfigureXESession,
        [int]$SessionTimeout,
        [parameter(ValueFromPipeline, Mandatory)]
        [Microsoft.SqlServer.Management.Smo.AvailabilityGroup]$InputObject,
        [switch]$EnableException
    )
    process {
        if ($EndpointUrl) {
            if ($EndpointUrl.Count -ne $SqlInstance.Count) {
                Stop-Function -Message "The number of elements in EndpointUrl is not correct"
                return
            }
            foreach ($epUrl in $EndpointUrl) {
                if ($epUrl -notmatch 'TCP://.+:\d+') {
                    Stop-Function -Message "EndpointUrl '$epUrl' not in correct format 'TCP://system-address:port'"
                    return
                }
            }
        }

        if ($ReadonlyRoutingConnectionUrl -and ($ReadonlyRoutingConnectionUrl -notmatch 'TCP://.+:\d+')) {
            Stop-Function -Message "ReadonlyRoutingConnectionUrl not in correct format 'TCP://system-address:port'"
            return
        }

        if ($ConnectionModeInSecondaryRole) {
            $ConnectionModeInSecondaryRole =
            switch ($ConnectionModeInSecondaryRole) {
                "No" { "AllowNoConnections" }
                "Read-intent only" { "AllowReadIntentConnectionsOnly" }
                "Yes" { "AllowAllConnections" }
                default { $ConnectionModeInSecondaryRole }
            }
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 11
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($Certificate) {
                $cert = Get-DbaDbCertificate -SqlInstance $server -Certificate $Certificate
                if (-not $cert) {
                    Stop-Function -Message "Certificate $Certificate does not exist on $instance" -ErrorRecord $_ -Target $Certificate -Continue
                }
            }

            # Split of endpoint URL here, as it will be used in two places.
            if ($EndpointUrl) {
                $epUrl, $EndpointUrl = $EndpointUrl
            }

            $ep = Get-DbaEndpoint -SqlInstance $server -Type DatabaseMirroring
            if (-not $ep) {
                if (-not $Endpoint) {
                    $Endpoint = "hadr_endpoint"
                }
                if ($Pscmdlet.ShouldProcess($server.Name, "Adding endpoint named $Endpoint to $instance")) {
                    $epParams = @{
                        SqlInstance         = $server
                        Name                = $Endpoint
                        Type                = 'DatabaseMirroring'
                        EndpointEncryption  = 'Supported'
                        EncryptionAlgorithm = 'Aes'
                        Certificate         = $Certificate
                    }
                    # If the endpoint URL is using an ipv4 address, we will use the URL to create a custom endpoint
                    if ($epUrl -match 'TCP://\d+\.\d+.\d+\.\d+:\d+') {
                        $epParams['IPAddress'] = $epUrl -replace 'TCP://(.+):\d+', '$1'
                        $epParams['Port'] = $epUrl -replace 'TCP://.+:(\d+)', '$1'
                    }
                    $ep = New-DbaEndpoint @epParams
                    $null = $ep | Start-DbaEndpoint
                    $epUrl = $ep.Fqdn
                }
            } else {
                $epUrl = $ep.Fqdn
            }

            if ((Test-Bound -Not -ParameterName Name)) {
                $Name = $server.DomainInstanceName
            }

            if ($Pscmdlet.ShouldProcess($server.Name, "Creating a replica for $($InputObject.Name) named $Name")) {
                try {
                    $replica = New-Object Microsoft.SqlServer.Management.Smo.AvailabilityReplica -ArgumentList $InputObject, $Name
                    $replica.EndpointUrl = $epUrl
                    $replica.FailoverMode = [Microsoft.SqlServer.Management.Smo.AvailabilityReplicaFailoverMode]::$FailoverMode
                    $replica.AvailabilityMode = [Microsoft.SqlServer.Management.Smo.AvailabilityReplicaAvailabilityMode]::$AvailabilityMode
                    if ($server.EngineEdition -ne "Standard") {
                        $replica.ConnectionModeInPrimaryRole = [Microsoft.SqlServer.Management.Smo.AvailabilityReplicaConnectionModeInPrimaryRole]::$ConnectionModeInPrimaryRole
                        $replica.ConnectionModeInSecondaryRole = [Microsoft.SqlServer.Management.Smo.AvailabilityReplicaConnectionModeInSecondaryRole]::$ConnectionModeInSecondaryRole
                    }
                    $replica.BackupPriority = $BackupPriority

                    if ($ReadonlyRoutingList -and $server.VersionMajor -ge 13) {
                        $replica.ReadonlyRoutingList = $ReadonlyRoutingList
                    }

                    if ($ReadonlyRoutingConnectionUrl -and $server.VersionMajor -ge 13) {
                        $replica.ReadonlyRoutingConnectionUrl = $ReadonlyRoutingConnectionUrl
                    }

                    if ($SeedingMode -and $server.VersionMajor -ge 13) {
                        $replica.SeedingMode = $SeedingMode
                    }

                    if ($SessionTimeout) {
                        if ($SessionTimeout -lt 10) {
                            $Message = "We recommend that you keep the time-out period at 10 seconds or greater. Setting the value to less than 10 seconds creates the possibility of a heavily loaded system missing pings and falsely declaring failure. Please see sqlps.io/agrec for more information."
                            Write-Message -Level Warning -Message $Message
                        }
                        $replica.SessionTimeout = $SessionTimeout
                    }

                    # Add cluster permissions
                    if ($ClusterType -eq 'Wsfc') {
                        if ($Pscmdlet.ShouldProcess($server.Name, "Adding cluster permissions for availability group named $($InputObject.Name)")) {
                            Write-Message -Level Verbose -Message "WSFC Cluster requires granting [NT AUTHORITY\SYSTEM] a few things. Setting now."
                            # To support non-english systems, get the name of SYSTEM login by the sid
                            # See SECURITY_LOCAL_SYSTEM_RID on https://docs.microsoft.com/en-us/windows/win32/secauthz/well-known-sids
                            $systemLoginSidString = '1-1-0-0-0-0-0-5-18-0-0-0'
                            $systemLoginName = ($server.Logins | Where-Object { ($_.Sid -join '-') -eq $systemLoginSidString }).Name
                            if (-not $systemLoginName) {
                                Write-Message -Level Verbose -Message "SYSTEM login not found, so we hope system language is english and create login [NT AUTHORITY\SYSTEM]"
                                try {
                                    $null = New-DbaLogin -SqlInstance $server -Login 'NT AUTHORITY\SYSTEM'
                                    $systemLoginName = 'NT AUTHORITY\SYSTEM'
                                } catch {
                                    Stop-Function -Message "Failed to add login [NT AUTHORITY\SYSTEM]. If it's a non-english system you have to add the equivalent login manually." -ErrorRecord $_
                                }
                            }
                            $permissionSet = New-Object -TypeName Microsoft.SqlServer.Management.SMO.ServerPermissionSet(
                                [Microsoft.SqlServer.Management.SMO.ServerPermission]::AlterAnyAvailabilityGroup,
                                [Microsoft.SqlServer.Management.SMO.ServerPermission]::ConnectSql,
                                [Microsoft.SqlServer.Management.SMO.ServerPermission]::ViewServerState
                            )
                            try {
                                $server.Grant($permissionSet, $systemLoginName)
                            } catch {
                                Stop-Function -Message "Failure adding cluster service account permissions." -ErrorRecord $_
                            }
                        }
                    }

                    if ($ConfigureXESession) {
                        try {
                            Write-Message -Level Debug -Message "Getting session 'AlwaysOn_health' on $instance."
                            $xeSession = Get-DbaXESession -SqlInstance $server -Session AlwaysOn_health -EnableException
                            if ($xeSession) {
                                if (-not $xeSession.AutoStart) {
                                    Write-Message -Level Debug -Message "Setting autostart for session 'AlwaysOn_health' on $instance."
                                    $xeSession.AutoStart = $true
                                    $xeSession.Alter()
                                }
                                if (-not $xeSession.IsRunning) {
                                    Write-Message -Level Debug -Message "Starting session 'AlwaysOn_health' on $instance."
                                    $null = $xeSession | Start-DbaXESession -EnableException
                                }
                                Write-Message -Level Verbose -Message "ConfigureXESession was set, session 'AlwaysOn_health' is now configured and running on $instance."
                            } else {
                                Write-Message -Level Warning -Message "ConfigureXESession was set, but no session named 'AlwaysOn_health' was found on $instance."
                            }
                        } catch {
                            Write-Message -Level Warning -Message "ConfigureXESession was set, but configuration failed on $instance with this error: $_"
                        }

                    }

                    if ($Passthru) {
                        return $replica
                    }

                    $InputObject.AvailabilityReplicas.Add($replica)
                    $agreplica = $InputObject.AvailabilityReplicas[$Name]
                    if ($InputObject.State -eq 'Existing') {
                        Invoke-Create -Object $replica
                        $null = Join-DbaAvailabilityGroup -SqlInstance $instance -SqlCredential $SqlCredential -AvailabilityGroup $InputObject.Name
                        $agreplica.Alter()
                    }

                    if ($server.HostPlatform -ne "Linux") {
                        # Only grant CreateAnyDatabase permission if AG already exists.
                        # If this command is started from New-DbaAvailabilityGroup, this will be done there after AG is created.
                        if ($SeedingMode -eq "Automatic" -and $InputObject.State -eq 'Existing') {
                            if ($Pscmdlet.ShouldProcess($second.Name, "Granting CreateAnyDatabase permission to the availability group")) {
                                try {
                                    $null = Grant-DbaAgPermission -SqlInstance $server -Type AvailabilityGroup -AvailabilityGroup $InputObject.Name -Permission CreateAnyDatabase -EnableException
                                } catch {
                                    Stop-Function -Message "Failure granting CreateAnyDatabase permission to the availability group" -ErrorRecord $_
                                }
                            }
                        }
                        # In case a certificate is used, the endpoint is owned by the certificate and this step is not needed and in most cases not possible as the instance does not run under a domain account.
                        if (-not $Certificate) {
                            $serviceAccount = $server.ServiceAccount
                            if ($Pscmdlet.ShouldProcess($second.Name, "Granting Connect permission for the endpoint to service account $serviceAccount")) {
                                try {
                                    $null = Grant-DbaAgPermission -SqlInstance $server -Type Endpoint -Login $serviceAccount -Permission Connect -EnableException
                                } catch {
                                    Stop-Function -Message "Failure granting Connect permission for the endpoint to service account $serviceAccount" -ErrorRecord $_
                                }
                            }
                        }
                    }

                    Add-Member -Force -InputObject $agreplica -MemberType NoteProperty -Name ComputerName -Value $agreplica.Parent.ComputerName
                    Add-Member -Force -InputObject $agreplica -MemberType NoteProperty -Name InstanceName -Value $agreplica.Parent.InstanceName
                    Add-Member -Force -InputObject $agreplica -MemberType NoteProperty -Name SqlInstance -Value $agreplica.Parent.SqlInstance
                    Add-Member -Force -InputObject $agreplica -MemberType NoteProperty -Name AvailabilityGroup -Value $agreplica.Parent.Name
                    Add-Member -Force -InputObject $agreplica -MemberType NoteProperty -Name Replica -Value $agreplica.Name # backwards compat

                    $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'AvailabilityGroup', 'Name', 'Role', 'RollupSynchronizationState', 'AvailabilityMode', 'BackupPriority', 'EndpointUrl', 'SessionTimeout', 'FailoverMode', 'ReadonlyRoutingList'
                    Select-DefaultView -InputObject $agreplica -Property $defaults
                } catch {
                    $msg = $_.Exception.InnerException.InnerException.Message
                    if (-not $msg) {
                        $msg = $_
                    }
                    Stop-Function -Message $msg -ErrorRecord $_ -Continue
                }
            }
        }
    }
}
