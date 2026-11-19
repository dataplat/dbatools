#nullable enable

namespace Dataplat.Dbatools.Commands;

public sealed partial class CompareDbaAgReplicaSyncCommand
{
    // PS: second half of the process foreach - Linked Servers, Agent Operators, Agent
    // Alerts, Agent Proxies and Custom Errors sections; see ScriptHead for the
    // substitution inventory. The closing line passes Exclude between
    // AvailabilityGroup and EnableException, matching the hop-arg order.
    private const string ProcessScriptTail = """
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
                            Stop-Function -Message "Failed to retrieve linked servers from replica $replicaInstance" -ErrorRecord $_ -Target $replicaInstance -Continue -FunctionName Compare-DbaAgReplicaSync
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
                            Stop-Function -Message "Failed to retrieve operators from replica $replicaInstance" -ErrorRecord $_ -Target $replicaInstance -Continue -FunctionName Compare-DbaAgReplicaSync
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
                            Stop-Function -Message "Failed to retrieve alerts from replica $replicaInstance" -ErrorRecord $_ -Target $replicaInstance -Continue -FunctionName Compare-DbaAgReplicaSync
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
                            Stop-Function -Message "Failed to retrieve proxies from replica $replicaInstance" -ErrorRecord $_ -Target $replicaInstance -Continue -FunctionName Compare-DbaAgReplicaSync
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
                            Stop-Function -Message "Failed to retrieve custom errors from replica $replicaInstance" -ErrorRecord $_ -Target $replicaInstance -Continue -FunctionName Compare-DbaAgReplicaSync
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
} $SqlInstance $SqlCredential $AvailabilityGroup $Exclude $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    private static string ProcessScript => ProcessScriptHead + "\n" + ProcessScriptTail;
}
