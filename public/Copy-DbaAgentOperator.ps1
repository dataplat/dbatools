function Copy-DbaAgentOperator {
    <#
    .SYNOPSIS
        Copies SQL Server Agent operators between instances for migration and standardization.

    .DESCRIPTION
        Copies SQL Server Agent operators from a source instance to one or more destination instances, preserving all operator properties including email addresses, pager numbers, and notification schedules. This is essential during server migrations, environment standardization, or when setting up identical alerting configurations across multiple instances.

        All operators are copied by default, but you can target specific operators or exclude certain ones. Existing operators on the destination are skipped unless you use -Force to overwrite them. The function protects failsafe operators from being accidentally dropped during forced operations.

        Each operator is scripted from the source using SQL Management Objects and recreated on the destination, ensuring all configuration details are preserved exactly as configured on the source instance.

    .PARAMETER Source
        Source SQL Server. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

    .PARAMETER SourceSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Destination
        Destination SQL Server. You must have sysadmin access and the server must be SQL Server 2000 or higher.

    .PARAMETER DestinationSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Operator
        The operator(s) to process. This list is auto-populated from the server. If unspecified, all operators will be processed.

    .PARAMETER ExcludeOperator
        The operators(s) to exclude. This list is auto-populated from the server.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER Force
        If this switch is enabled, the Operator will be dropped and recreated on Destination.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Migration, Agent, Operator
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: sysadmin access on SQL Servers

    .LINK
        https://dbatools.io/Copy-DbaAgentOperator

    .EXAMPLE
        PS C:\> Copy-DbaAgentOperator -Source sqlserver2014a -Destination sqlcluster

        Copies all operators from sqlserver2014a to sqlcluster using Windows credentials. If operators with the same name exist on sqlcluster, they will be skipped.

    .EXAMPLE
        PS C:\> Copy-DbaAgentOperator -Source sqlserver2014a -Destination sqlcluster -Operator PSOperator -SourceSqlCredential $cred -Force

        Copies only the PSOperator operator from sqlserver2014a to sqlcluster using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster. If an operator with the same name exists on sqlcluster, it will be dropped and recreated because -Force was used.

    .EXAMPLE
        PS C:\> Copy-DbaAgentOperator -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

        Shows what would happen if the command were executed using force.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter]$Source,
        [PSCredential]
        $SourceSqlCredential,
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]
        $DestinationSqlCredential,
        [object[]]$Operator,
        [object[]]$ExcludeOperator,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {
        try {
            $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }
        $serverOperator = $sourceServer.JobServer.Operators

        if ($Force) { $ConfirmPreference = 'none' }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($destinstance in $Destination) {
            try {
                $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
            }

            $destOperator = $destServer.JobServer.Operators
            $failsafe = $destServer.JobServer.AlertSystem | Select-Object FailSafeOperator
            foreach ($sOperator in $serverOperator) {
                $operatorName = $sOperator.Name

                $copyOperatorStatus = [PSCustomObject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Name              = $operatorName
                    Type              = "Agent Operator"
                    Status            = $null
                    Notes             = $null
                    DateTime          = [DbaDateTime](Get-Date)
                }

                if ($Operator -and $Operator -notcontains $operatorName -or $ExcludeOperator -in $operatorName) {
                    continue
                }

                if ($destOperator.Name -contains $sOperator.Name) {
                    if ($force -eq $false) {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Operator $operatorName exists at destination. Use -Force to drop and migrate.")) {
                            $copyOperatorStatus.Status = "Skipped"
                            $copyOperatorStatus.Notes = "Already exists on destination"
                            $copyOperatorStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Write-Message -Level Verbose -Message "Operator $operatorName exists at destination. Use -Force to drop and migrate."
                        }
                        continue
                    } else {
                        if ($failsafe.FailSafeOperator -eq $operatorName) {
                            Write-Message -Level Verbose -Message "$operatorName is the failsafe operator. Skipping drop."
                            continue
                        }

                        if ($Pscmdlet.ShouldProcess($destinstance, "Dropping operator $operatorName and recreating")) {
                            try {
                                Write-Message -Level Verbose -Message "Dropping Operator $operatorName"
                                $destServer.JobServer.Operators[$operatorName].Drop()
                            } catch {
                                $copyOperatorStatus.Status = "Failed"
                                $copyOperatorStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                Write-Message -Level Verbose -Message "Issue dropping operator $operatorName on $destinstance | $PSItem"
                                continue
                            }
                        }
                    }
                }

                if ($Pscmdlet.ShouldProcess($destinstance, "Creating Operator $operatorName")) {
                    try {
                        Write-Message -Level Verbose -Message "Copying Operator $operatorName"
                        $sql = $sOperator.Script() | Out-String
                        Write-Message -Level Debug -Message $sql
                        $destServer.Query($sql)

                        $copyOperatorStatus.Status = "Successful"
                        $copyOperatorStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    } catch {
                        $copyOperatorStatus.Status = "Failed"
                        $copyOperatorStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Level Verbose -Message "Issue creating operator $operatorName on $destinstance | $PSItem"
                        continue
                    }
                }
            }
        }
    }
}