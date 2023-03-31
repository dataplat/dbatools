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
        The database that will be replicated.

    .PARAMETER Name
        The name of the replication publication

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .NOTES
        Tags: Replication
        Author: Jess Pomfret (@jpomfret)

        Website: https://dbatools.io
        Copyright: (c) 2022 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaReplPublication

    .EXAMPLE
        PS C:\> Remove-DbaReplPublication -SqlInstance mssql1 -Database Northwind -Name PubFromPosh

        Removes a publication called PubFromPosh from the Northwind database on mssql1

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,

        [PSCredential]$SqlCredential,

        [String]$Database,

        [parameter(Mandatory)]
        [String]$Name,

        [Switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $replServer = Get-DbaReplServer -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            try {
                if ($PSCmdlet.ShouldProcess($instance, "Removing publication on $instance")) {

                    $pub = Get-DbaReplPublication -SqlInstance $instance -SqlCredential $SqlCredential -Name $Name

                    if (-not $pub) {
                        Write-Warning "Didn't find $Name on $Instance.$Database"
                    }

                    if ($pub.Type -in ('Transactional', 'Snapshot')) {

                        $transPub = New-Object Microsoft.SqlServer.Replication.TransPublication
                        $transPub.ConnectionContext = $replServer.ConnectionContext
                        $transPub.DatabaseName = $Database
                        $transPub.Name = $Name

                        if ($transPub.IsExistingObject) {
                            Write-Message -Level Verbose -Message "Removing $Name from $Instance.$Database"
                            $transPub.Remove()
                        }

                        # If no other transactional publications exist for this database, the database can be disabled for transactional publishing
                        #TODO: transactional & snapshot.. or just trans?
                        if(-not (Get-DbaReplPublication -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database -Type Transactional, Snapshot)) {
                            $pubDatabase = New-Object Microsoft.SqlServer.Replication.ReplicationDatabase
                            $pubDatabase.ConnectionContext = $replServer.ConnectionContext
                            $pubDatabase.Name = $Database
                            if (-not $pubDatabase.LoadProperties()) {
                                throw "Database $Database not found on $instance"
                            }

                            if ($pubDatabase.EnabledTransPublishing) {
                                Write-Message -Level Verbose -Message "No transactional publications on $Instance.$Database so disabling transactional publishing"
                                $pubDatabase.EnabledTransPublishing = $false
                            }
                        }
                            # https://learn.microsoft.com/en-us/sql/relational-databases/replication/publish/delete-a-publication?view=sql-server-ver16#RMOProcedure

                    } elseif ($pub.Type -eq 'Merge') {
                        $mergePub = New-Object Microsoft.SqlServer.Replication.MergePublication
                        $mergePub.ConnectionContext = $replServer.ConnectionContext
                        $mergePub.DatabaseName = $Database
                        $mergePub.Name = $Name

                        if ($mergePub.IsExistingObject) {
                            Write-Message -Level Verbose -Message "Removing $Name from $Instance.$Database"
                            $mergePub.Remove()
                        } else {
                            Write-Warning "Didn't find $Name on $Instance.$Database"
                        }

                        # If no other merge publications exist for this database, the database can be disabled for merge publishing
                        if(-not (Get-DbaReplPublication -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database -Type Merge)) {
                            $pubDatabase = New-Object Microsoft.SqlServer.Replication.ReplicationDatabase
                            $pubDatabase.ConnectionContext = $replServer.ConnectionContext
                            $pubDatabase.Name = $Database

                            if (-not $pubDatabase.LoadProperties()) {
                                throw "Database $Database not found on $instance"
                            }

                            if($pubDatabase.EnabledTransPublishing) {
                                Write-Message -Level Verbose -Message "No merge publications on $Instance.$Database so disabling merge publishing"
                                $pubDatabase.EnabledMergePublishing = $false
                            }
                        }
                    }
                }
            } catch {
                Stop-Function -Message ("Unable to remove publication - {0}" -f $_) -ErrorRecord $_ -Target $instance -Continue
            }
        }
    }
}



