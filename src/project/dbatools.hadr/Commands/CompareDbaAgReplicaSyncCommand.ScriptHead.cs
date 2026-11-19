#nullable enable

namespace Dataplat.Dbatools.Commands;

public sealed partial class CompareDbaAgReplicaSyncCommand
{
    // PS: the source process foreach VERBATIM, first half - Logins, Agent Jobs and
    // Credentials sections (composed as ProcessScript = head + newline + tail; the
    // composition is re-parsed at build verification). Per-element hop, one source
    // pipeline element per invocation: the source foreach line doubles as the guard
    // loop for every Stop-Function -Continue site. No begin block. Substitutions
    // across both halves: twelve -FunctionName appends only - no gates, no Test-Bound.
    private const string ProcessScriptHead = """
param($SqlInstance, $SqlCredential, $AvailabilityGroup, $Exclude, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$AvailabilityGroup, [string[]]$Exclude, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 11
            } catch {
                Stop-Function -Message "Failure connecting to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Compare-DbaAgReplicaSync
            }

            if (-not $server.IsHadrEnabled) {
                Stop-Function -Message "Availability Group (HADR) is not configured for the instance: $instance." -Target $instance -Continue -FunctionName Compare-DbaAgReplicaSync
            }

            $availabilityGroups = $server.AvailabilityGroups

            if ($AvailabilityGroup) {
                $availabilityGroups = $availabilityGroups | Where-Object Name -in $AvailabilityGroup
            }

            if (-not $availabilityGroups) {
                Stop-Function -Message "No Availability Groups found on $instance matching the specified criteria." -Target $instance -Continue -FunctionName Compare-DbaAgReplicaSync
            }

            foreach ($ag in $availabilityGroups) {
                $replicas = $ag.AvailabilityReplicas

                if ($replicas.Count -lt 2) {
                    Stop-Function -Message "Availability Group '$($ag.Name)' has less than 2 replicas. Nothing to compare." -Target $ag -Continue -FunctionName Compare-DbaAgReplicaSync
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
                            Stop-Function -Message "Failed to retrieve logins from replica $replicaInstance" -ErrorRecord $_ -Target $replicaInstance -Continue -FunctionName Compare-DbaAgReplicaSync
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
                            Stop-Function -Message "Failed to retrieve jobs from replica $replicaInstance" -ErrorRecord $_ -Target $replicaInstance -Continue -FunctionName Compare-DbaAgReplicaSync
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
                            Stop-Function -Message "Failed to retrieve credentials from replica $replicaInstance" -ErrorRecord $_ -Target $replicaInstance -Continue -FunctionName Compare-DbaAgReplicaSync
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

""";
}
