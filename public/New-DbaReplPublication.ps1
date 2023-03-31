function New-DbaReplPublication {
    <#
    .SYNOPSIS
        Creates a publication for the database on the target SQL instances.

    .DESCRIPTION
        Creates a publication for the database on the target SQL instances.

        https://learn.microsoft.com/en-us/sql/relational-databases/replication/publish/create-a-publication?view=sql-server-ver16

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database that will be replicated.

    .PARAMETER PublicationName
        The name of the replication publication

    .PARAMETER Type
        The flavour of replication.

        Currently supported 'Transactional'

        Coming soon 'Snapshot', 'Merge'

    .PARAMETER LogReaderAgentCredential
        Used to provide the credentials for the Microsoft Windows account under which the Log Reader Agent runs

        Setting LogReaderAgentProcessSecurity is not required when the publication is created by a member of the sysadmin fixed server role.
        In this case, the agent will impersonate the SQL Server Agent account. For more information, see Replication Agent Security Model.

        TODO: Implement & test this

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
        https://dbatools.io/New-DbaReplPublication

    .EXAMPLE
        PS C:\> New-DbaReplPublication -SqlInstance mssql1 -Database Northwind -PublicationName PubFromPosh

        Creates a publication called PubFromPosh for the Northwind database on mssql1

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,

        [PSCredential]$SqlCredential,

        [String]$Database,

        [parameter(Mandatory)]
        [String]$PublicationName,

        [parameter(Mandatory)]
        [ValidateSet("Snapshot", "Transactional", "Merge")]
        [String]$Type,

        [PSCredential]$LogReaderAgentCredential,

        [Switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $replServer = Get-DbaReplServer -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            Write-Message -Level Verbose -Message "Creating publication on $instance"

            try {
                if ($PSCmdlet.ShouldProcess($instance, "Creating publication on $instance")) {

                    $pubDatabase = New-Object Microsoft.SqlServer.Replication.ReplicationDatabase
                    $pubDatabase.ConnectionContext = $replServer.ConnectionContext
                    $pubDatabase.Name = $Database
                    if (-not $pubDatabase.LoadProperties()) {
                        throw "Database $Database not found on $instance"
                    }

                    if ($Type -in ('Transactional', 'Snapshot')) {
                        Write-Message -Level Verbose -Message "Enable trans publishing publication on $instance.$Database"
                        $pubDatabase.EnabledTransPublishing = $true
                    } elseif ($Type -eq 'Merge') {
                        Write-Message -Level Verbose -Message "Enable merge publishing publication on $instance.$Database"
                        $pubDatabase.EnabledMergePublishing = $true
                        $pubDatabase.CommitPropertyChanges
                    }
                    #TODO: snapshot repl?

                    if (-not $pubDatabase.LogReaderAgentExists) {
                        #TODO: if this needed for merge?

                        Write-Message -Level Verbose -Message "Create Log Read Agent job for $Database on $instance"
                        if ($LogReaderAgentCredential) {
                            #TODO: Test this
                            $pubDatabase.LogReaderAgentProcessSecurity.Login = $LogReaderAgentCredential.UserName
                            $pubDatabase.LogReaderAgentProcessSecurity.Password = $LogReaderAgentCredential.Password
                        }

                        #(Optional) Set the SqlStandardLogin and SqlStandardPassword or
                        # SecureSqlStandardPassword fields of LogReaderAgentPublisherSecurity when using SQL Server Authentication to connect to the Publisher.

                        $pubDatabase.CreateLogReaderAgent()
                    } else {
                        Write-Message -Level Verbose -Message "Log Read Agent job already exists for $Database on $instance"
                    }

                    if ($Type -in ('Transactional', 'Snapshot')) {

                        $transPub = New-Object Microsoft.SqlServer.Replication.TransPublication
                        $transPub.ConnectionContext = $replServer.ConnectionContext
                        $transPub.DatabaseName = $Database
                        $transPub.Name = $PublicationName
                        $transPub.Type = $Type
                        $transPub.Create()

                        # create the Snapshot Agent job
                        $transPub.CreateSnapshotAgent()

                        <#
                        TODO: add these in?

                        The Login and Password fields of SnapshotGenerationAgentProcessSecurity to provide the credentials for the Windows account under which the Snapshot Agent runs.
                        This account is also used when the Snapshot Agent makes connections to the local Distributor and for any remote connections when using Windows Authentication.

                        Note
                        Setting SnapshotGenerationAgentProcessSecurity is not required when the publication is created by a member of the sysadmin fixed server role.
                        In this case, the agent will impersonate the SQL Server Agent account. For more information, see Replication Agent Security Model.

                        (Optional) The SqlStandardLogin and SqlStandardPassword or
                        SecureSqlStandardPassword fields of SnapshotGenerationAgentPublisherSecurity when using SQL Server Authentication to connect to the Publisher.
                        #>
                    } elseif ($Type -eq 'Merge') {
                        $mergePub = New-Object Microsoft.SqlServer.Replication.MergePublication
                        $mergePub.ConnectionContext = $replServer.ConnectionContext
                        $mergePub.DatabaseName = $Database
                        $mergePub.Name = $PublicationName
                        $mergePub.Create()

                        # create the Snapshot Agent job
                        $mergePub.CreateSnapshotAgent()

                        <#
                        TODO: add these in?

                        The Login and Password fields of SnapshotGenerationAgentProcessSecurity to provide the credentials for the Windows account under which the Snapshot Agent runs.
                        This account is also used when the Snapshot Agent makes connections to the local Distributor and for any remote connections when using Windows Authentication.

                        Note
                        Setting SnapshotGenerationAgentProcessSecurity is not required when the publication is created by a member of the sysadmin fixed server role.
                        For more information, see Replication Agent Security Model.

                        (Optional) Use the inclusive logical OR operator (| in Visual C# and Or in Visual Basic) and the exclusive logical OR operator (^ in Visual C# and Xor in Visual Basic)
                        to set the PublicationAttributes values for the Attributes property.

                        #>

                    }



                }
            } catch {
                Stop-Function -Message ("Unable to create publication - {0}" -f $_) -ErrorRecord $_ -Target $instance -Continue
            }

            #TODO: What to return

        }
    }
}



