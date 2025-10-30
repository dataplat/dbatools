function Remove-DbaReplPublication {
    <#
    .SYNOPSIS
        Removes a publication from the database on the target SQL instances.

    .DESCRIPTION
        Removes a publication from the database on the target SQL instances.

        https://learn.microsoft.com/en-us/sql/relational-databases/replication/publish/delete-a-publication?view=sql-server-ver16#RMOProcedure

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the database containing the replication publication to remove. Required when using SqlInstance to identify which database's publications to target.
        Use this to scope the operation to a specific database when multiple databases have replication configured.

    .PARAMETER Name
        Specifies the exact name of the replication publication to remove. Required when using SqlInstance to identify which specific publication to target.
        Use this when you know the publication name and want to remove a specific publication rather than all publications in a database.

    .PARAMETER InputObject
        Accepts replication publication objects from Get-DbaReplPublication for pipeline operations. Use this when you want to filter publications first, then remove selected ones.
        Particularly useful when removing multiple publications based on specific criteria or when integrating with other replication management workflows.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .NOTES
        Tags: repl, Replication
        Author: Jess Pomfret (@jpomfret), jesspomfret.com

        Website: https://dbatools.io
        Copyright: (c) 2023 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaReplPublication

    .EXAMPLE
        PS C:\> Remove-DbaReplPublication -SqlInstance mssql1 -Database Northwind -Name PubFromPosh

        Removes a publication called PubFromPosh from the Northwind database on mssql1

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [String]$Database,
        [String]$Name,
        [parameter(ValueFromPipeline)]
        [psobject[]]$InputObject,
        [Switch]$EnableException
    )
    begin {
        Add-ReplicationLibrary
        $publications = @( )
    }
    process {
        if (-not $PSBoundParameters.SqlInstance -and -not $PSBoundParameters.InputObject) {
            Stop-Function -Message "You must specify either SqlInstance or InputObject"
            return
        }

        if ($InputObject) {
            $publications += $InputObject
        } else {
            $params = $PSBoundParameters
            $null = $params.Remove('InputObject')
            $null = $params.Remove('WhatIf')
            $null = $params.Remove('Confirm')
            $publications = Get-DbaReplPublication @params
        }
    }

    end {
        # We have to delete in the end block to prevent "Collection was modified; enumeration operation may not execute." if directly piped from Get-DbaReplArticle.
        foreach ($pub in $publications) {
            if ($PSCmdlet.ShouldProcess($pub.Name, "Removing the publication $($pub.Name) on $($pub.SqlInstance)")) {
                $output = [PSCustomObject]@{
                    ComputerName = $pub.ComputerName
                    InstanceName = $pub.InstanceName
                    SqlInstance  = $pub.SqlInstance
                    Database     = $pub.DatabaseName
                    Name         = $pub.Name
                    Type         = $pub.Type
                    Status       = $null
                    IsRemoved    = $false
                }

                if ($pub.Type -in ('Transactional', 'Snapshot')) {
                    try {
                        if ($pub.IsExistingObject) {
                            Write-Message -Level Verbose -Message "Removing $($pub.Name) from $($pub.SqlInstance).$($pub.DatabaseName)"

                            if ($PSCmdlet.ShouldProcess($pub.Name, "Stopping the REPL-LogReader job for the database $($pub.DatabaseName) on $($pub.SqlInstance)")) {
                                $null = Get-DbaAgentJob -SqlInstance $pub.SqlInstance -SqlCredential $SqlCredential -Category REPL-LogReader | Where-Object { $_.Name -like ('*{0}*' -f $pub.DatabaseName) } | Stop-DbaAgentJob
                            }
                            $pub.Remove()

                            $output.Status = "Removed"
                            $output.IsRemoved = $true
                        }
                    } catch {
                        Stop-Function -Message "Failed to remove the publication from $($pub.SqlInstance)" -ErrorRecord $_
                        $output.Status = (Get-ErrorMessage -Record $_)
                        $output.IsRemoved = $false
                    }

                    try {
                        # If no other transactional publications exist for this database, the database can be disabled for transactional publishing
                        if (-not (Get-DbaReplPublication -SqlInstance $pub.SqlInstance -SqlCredential $SqlCredential -Database $pub.DatabaseName -Type Transactional, Snapshot -EnableException:$EnableException)) {
                            $pubDatabase = New-Object Microsoft.SqlServer.Replication.ReplicationDatabase
                            $pubDatabase.ConnectionContext = $pub.ConnectionContext
                            $pubDatabase.Name = $pub.DatabaseName
                            if (-not $pubDatabase.LoadProperties()) {
                                throw "Database $Database not found on $($pub.SqlInstance)"
                            }

                            if ($pubDatabase.EnabledTransPublishing) {
                                Write-Message -Level Verbose -Message "No transactional publications on $Instance.$Database so disabling transactional publishing"
                                $pubDatabase.EnabledTransPublishing = $false
                            }
                        }
                    } catch {
                        Stop-Function -Message "Failed to disable transactional publishing on $($pub.SqlInstance)" -ErrorRecord $_
                    }

                } elseif ($pub.Type -eq 'Merge') {
                    try {
                        if ($pub.IsExistingObject) {
                            Write-Message -Level Verbose -Message "Removing $($pub.Name) from $($pub.SqlInstance).$($pub.DatabaseName)"
                            if ($PSCmdlet.ShouldProcess($pub.Name, "Stopping the REPL-LogReader job for the database $($pub.DatabaseName) on $($pub.SqlInstance)")) {
                                $null = Get-DbaAgentJob -SqlInstance $pub.SqlInstance -SqlCredential $SqlCredential -Category REPL-LogReader | Where-Object { $_.Name -like ('*{0}*' -f $pub.DatabaseName) } | Stop-DbaAgentJob
                            }
                            $pub.Remove()

                            $output.Status = "Removed"
                            $output.IsRemoved = $true
                        } else {
                            Write-Warning "Didn't find $($pub.Name) on $($pub.SqlInstance).$($pub.DatabaseName)"
                        }
                    } catch {
                        Stop-Function -Message "Failed to remove the publication from $($pub.SqlInstance)" -ErrorRecord $_
                        $output.Status = (Get-ErrorMessage -Record $_)
                        $output.IsRemoved = $false
                    }

                    try {
                        # If no other merge publications exist for this database, the database can be disabled for merge publishing
                        if (-not (Get-DbaReplPublication -SqlInstance $pub.SqlInstance -SqlCredential $SqlCredential -Database $pub.DatabaseName -Type Merge -EnableException:$EnableException)) {
                            $pubDatabase = New-Object Microsoft.SqlServer.Replication.ReplicationDatabase
                            $pubDatabase.ConnectionContext = $pub.ConnectionContext
                            $pubDatabase.Name = $pub.DatabaseName

                            if (-not $pubDatabase.LoadProperties()) {
                                throw "Database $Database not found on $instance"
                            }

                            if ($pubDatabase.EnabledTransPublishing) {
                                Write-Message -Level Verbose -Message "No merge publications on $Instance.$Database so disabling merge publishing"
                                $pubDatabase.EnabledMergePublishing = $false
                            }
                        }
                    } catch {
                        Stop-Function -Message "Failed to disable transactional publishing on $($pub.SqlInstance)" -ErrorRecord $_
                    }
                }

                $output
            }
        }
    }
}