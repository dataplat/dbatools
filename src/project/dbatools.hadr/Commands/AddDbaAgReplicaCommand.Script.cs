#nullable enable

namespace Dataplat.Dbatools.Commands;

public sealed partial class AddDbaAgReplicaCommand
{
    // PS: the process block VERBATIM inside a dot-sourced block, so the three write-only
    // latching Stop-Function+return sites (the source has no Test-FunctionInterrupt) and
    // the Passthru return exit the dot-block while the state tail still runs. The source
    // MUTATES two parameters in function scope that later iterations and records read:
    // EndpointUrl (the destructive per-instance shift `$epUrl, $EndpointUrl =
    // $EndpointUrl`) and Endpoint (the sticky hadr_endpoint default) - both restored
    // from the carried state before the body and written back at the tail. The
    // ConnectionModeInSecondaryRole friendly-alias normalization is idempotent per
    // record and needs no carry. Substitutions: one Test-Bound becomes a carried
    // bound-flag (SOURCE comment per site), five ShouldProcess routes to the real
    // cmdlet, nineteen -FunctionName appends - stripping all reproduces the source
    // bytes md5-exact. The undeclared $second reads at the two Grant gates ride
    // verbatim (the ShouldProcess targets stringify empty exactly like the function).
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Name, $ClusterType, $AvailabilityMode, $FailoverMode, $BackupPriority, $ConnectionModeInPrimaryRole, $ConnectionModeInSecondaryRole, $SeedingMode, $Endpoint, $EndpointUrl, $Passthru, $ReadOnlyRoutingList, $ReadonlyRoutingConnectionUrl, $Certificate, $ConfigureXESession, $SessionTimeout, $InputObject, $EnableException, $__state, $__realCmdlet, $__boundName, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess)]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string]$Name, [string]$ClusterType, [string]$AvailabilityMode, [string]$FailoverMode, [int]$BackupPriority, [string]$ConnectionModeInPrimaryRole, [string]$ConnectionModeInSecondaryRole, [string]$SeedingMode, [string]$Endpoint, [string[]]$EndpointUrl, $Passthru, [string[]]$ReadOnlyRoutingList, [string]$ReadonlyRoutingConnectionUrl, [string]$Certificate, $ConfigureXESession, [int]$SessionTimeout, [Microsoft.SqlServer.Management.Smo.AvailabilityGroup]$InputObject, $EnableException, $__state, $__realCmdlet, $__boundName, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    if ($null -ne $__state) {
        $EndpointUrl = $__state.endpointUrl
        $Endpoint = $__state.endpoint
        $epUrl = $__state.epUrl
    }
    . {
        if ($EndpointUrl) {
            if ($EndpointUrl.Count -ne $SqlInstance.Count) {
                Stop-Function -Message "The number of elements in EndpointUrl is not correct" -FunctionName Add-DbaAgReplica
                return
            }
            foreach ($epUrl in $EndpointUrl) {
                if ($epUrl -notmatch 'TCP://.+:\d+') {
                    Stop-Function -Message "EndpointUrl '$epUrl' not in correct format 'TCP://system-address:port'" -FunctionName Add-DbaAgReplica
                    return
                }
            }
        }

        if ($ReadonlyRoutingConnectionUrl -and ($ReadonlyRoutingConnectionUrl -notmatch 'TCP://.+:\d+')) {
            Stop-Function -Message "ReadonlyRoutingConnectionUrl not in correct format 'TCP://system-address:port'" -FunctionName Add-DbaAgReplica
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
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Add-DbaAgReplica
            }

            if ($Certificate) {
                $cert = Get-DbaDbCertificate -SqlInstance $server -Certificate $Certificate
                if (-not $cert) {
                    Stop-Function -Message "Certificate $Certificate does not exist on $instance" -Target $Certificate -Continue -FunctionName Add-DbaAgReplica
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
                if ($__realCmdlet.ShouldProcess($server.Name, "Adding endpoint named $Endpoint to $instance")) {
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

            if ((-not $__boundName)) { # SOURCE: if ((Test-Bound -Not -ParameterName Name)) {
                $Name = $server.DomainInstanceName
            }

            if ($__realCmdlet.ShouldProcess($server.Name, "Creating a replica for $($InputObject.Name) named $Name")) {
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
                            Write-Message -Level Warning -Message $Message -FunctionName Add-DbaAgReplica -ModuleName "dbatools"
                        }
                        $replica.SessionTimeout = $SessionTimeout
                    }

                    # Add cluster permissions
                    if ($ClusterType -eq 'Wsfc') {
                        if ($__realCmdlet.ShouldProcess($server.Name, "Adding cluster permissions for availability group named $($InputObject.Name)")) {
                            Write-Message -Level Verbose -Message "WSFC Cluster requires granting [NT AUTHORITY\SYSTEM] a few things. Setting now." -FunctionName Add-DbaAgReplica -ModuleName "dbatools"
                            # To support non-english systems, get the name of SYSTEM login by the sid
                            # See SECURITY_LOCAL_SYSTEM_RID on https://docs.microsoft.com/en-us/windows/win32/secauthz/well-known-sids
                            $systemLoginSidString = '1-1-0-0-0-0-0-5-18-0-0-0'
                            $systemLoginName = ($server.Logins | Where-Object { ($_.Sid -join '-') -eq $systemLoginSidString }).Name
                            if (-not $systemLoginName) {
                                Write-Message -Level Verbose -Message "SYSTEM login not found, so we hope system language is english and create login [NT AUTHORITY\SYSTEM]" -FunctionName Add-DbaAgReplica -ModuleName "dbatools"
                                try {
                                    $null = New-DbaLogin -SqlInstance $server -Login 'NT AUTHORITY\SYSTEM'
                                    $systemLoginName = 'NT AUTHORITY\SYSTEM'
                                } catch {
                                    Stop-Function -Message "Failed to add login [NT AUTHORITY\SYSTEM]. If it's a non-english system you have to add the equivalent login manually." -ErrorRecord $_ -FunctionName Add-DbaAgReplica
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
                                Stop-Function -Message "Failure adding cluster service account permissions." -ErrorRecord $_ -FunctionName Add-DbaAgReplica
                            }
                        }
                    }

                    if ($ConfigureXESession) {
                        try {
                            Write-Message -Level Debug -Message "Getting session 'AlwaysOn_health' on $instance." -FunctionName Add-DbaAgReplica -ModuleName "dbatools"
                            $xeSession = Get-DbaXESession -SqlInstance $server -Session AlwaysOn_health -EnableException
                            if ($xeSession) {
                                if (-not $xeSession.AutoStart) {
                                    Write-Message -Level Debug -Message "Setting autostart for session 'AlwaysOn_health' on $instance." -FunctionName Add-DbaAgReplica -ModuleName "dbatools"
                                    $xeSession.AutoStart = $true
                                    $xeSession.Alter()
                                }
                                if (-not $xeSession.IsRunning) {
                                    Write-Message -Level Debug -Message "Starting session 'AlwaysOn_health' on $instance." -FunctionName Add-DbaAgReplica -ModuleName "dbatools"
                                    $null = $xeSession | Start-DbaXESession -EnableException
                                }
                                Write-Message -Level Verbose -Message "ConfigureXESession was set, session 'AlwaysOn_health' is now configured and running on $instance." -FunctionName Add-DbaAgReplica -ModuleName "dbatools"
                            } else {
                                Write-Message -Level Warning -Message "ConfigureXESession was set, but no session named 'AlwaysOn_health' was found on $instance." -FunctionName Add-DbaAgReplica -ModuleName "dbatools"
                            }
                        } catch {
                            Write-Message -Level Warning -Message "ConfigureXESession was set, but configuration failed on $instance with this error: $_" -FunctionName Add-DbaAgReplica -ModuleName "dbatools"
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
                            if ($__realCmdlet.ShouldProcess($second.Name, "Granting CreateAnyDatabase permission to the availability group")) {
                                try {
                                    $null = Grant-DbaAgPermission -SqlInstance $server -Type AvailabilityGroup -AvailabilityGroup $InputObject.Name -Permission CreateAnyDatabase -EnableException
                                } catch {
                                    Stop-Function -Message "Failure granting CreateAnyDatabase permission to the availability group" -ErrorRecord $_ -FunctionName Add-DbaAgReplica
                                }
                            }
                        }
                        # In case a certificate is used, the endpoint is owned by the certificate and this step is not needed and in most cases not possible as the instance does not run under a domain account.
                        if (-not $Certificate) {
                            $serviceAccount = $server.ServiceAccount
                            if ($__realCmdlet.ShouldProcess($second.Name, "Granting Connect permission for the endpoint to service account $serviceAccount")) {
                                try {
                                    $null = Grant-DbaAgPermission -SqlInstance $server -Type Endpoint -Login $serviceAccount -Permission Connect -EnableException
                                } catch {
                                    Stop-Function -Message "Failure granting Connect permission for the endpoint to service account $serviceAccount" -ErrorRecord $_ -FunctionName Add-DbaAgReplica
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
                    Stop-Function -Message $msg -ErrorRecord $_ -Continue -FunctionName Add-DbaAgReplica
                }
            }
        }
    }
    @{ __w4003State = @{
        endpointUrl = $EndpointUrl
        endpoint    = $Endpoint
        epUrl       = $epUrl
    } }
} $SqlInstance $SqlCredential $Name $ClusterType $AvailabilityMode $FailoverMode $BackupPriority $ConnectionModeInPrimaryRole $ConnectionModeInSecondaryRole $SeedingMode $Endpoint $EndpointUrl $Passthru $ReadOnlyRoutingList $ReadonlyRoutingConnectionUrl $Certificate $ConfigureXESession $SessionTimeout $InputObject $EnableException $__state $__realCmdlet $__boundName $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
