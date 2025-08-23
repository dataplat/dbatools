function New-DbaReplPublication {
    <#
    .SYNOPSIS
        Creates a SQL Server replication publication for transactional, snapshot, or merge replication

    .DESCRIPTION
        Creates a new replication publication on a SQL Server instance that's already configured as a publisher. This function enables publishing on the specified database, creates necessary replication agents (Log Reader for transactional/snapshot, Snapshot Agent for all types), and establishes the publication object that defines what data will be replicated to subscribers.

        Use this command when setting up the publisher side of SQL Server replication to distribute data across multiple servers. The publication acts as a container for the articles (tables, views, stored procedures) you want to replicate. After creating the publication, you'll typically add articles using Add-DbaReplArticle and create subscriptions on target servers.

        https://learn.microsoft.com/en-us/sql/relational-databases/replication/publish/create-a-publication?view=sql-server-ver16

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the database where the publication will be created and which contains the objects to be replicated.
        This database must already exist on the publisher instance and will be enabled for the specified replication type.

    .PARAMETER Name
        Sets the unique name for the publication within the database.
        Use a descriptive name that identifies the purpose or content of the publication, as this name will be referenced when creating subscriptions and managing replication.

    .PARAMETER Type
        Determines the replication method used for distributing data to subscribers.
        Transactional provides near real-time synchronization for frequently changing data, Snapshot creates point-in-time copies for less volatile data, and Merge allows bidirectional changes with conflict resolution.
        Choose based on your data synchronization requirements and network constraints.

    .PARAMETER LogReaderAgentCredential
        Specifies the Windows account credentials for the Log Reader Agent, which is required for Transactional and Snapshot replication types.
        This agent reads the transaction log to identify changes for replication. Only needed when not running as sysadmin, as sysadmin members default to using the SQL Server Agent service account.
        Use a domain account with appropriate permissions to the publisher database and distributor.

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
        https://dbatools.io/New-DbaReplPublication

    .EXAMPLE
        PS C:\> New-DbaReplPublication -SqlInstance mssql1 -Database Northwind -Name PubFromPosh -Type Transactional

        Creates a transactional publication called PubFromPosh for the Northwind database on mssql1

    .EXAMPLE
        PS C:\> New-DbaReplPublication -SqlInstance mssql1 -Database pubs -Name snapPub -Type Snapshot

        Creates a snapshot publication called snapPub for the pubs database on mssql1

    .EXAMPLE
        PS C:\> New-DbaReplPublication -SqlInstance mssql1 -Database pubs -Name mergePub -Type Merge

        Creates a merge publication called mergePub for the pubs database on mssql1
    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory)]
        [String]$Database,
        [parameter(Mandatory)]
        [String]$Name,
        [parameter(Mandatory)]
        [ValidateSet("Snapshot", "Transactional", "Merge")]
        [String]$Type,
        [PSCredential]$LogReaderAgentCredential,
        [Switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $replServer = Get-DbaReplServer -SqlInstance $instance -SqlCredential $SqlCredential -EnableException:$EnableException

                if (-not $replServer.IsPublisher) {
                    Stop-Function -Message "Instance $instance is not a publisher, run Enable-DbaReplPublishing to set this up" -Target $instance -Continue
                }

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
                        $pubDatabase.CommitPropertyChanges()
                        # log reader agent is only needed for transactional and snapshot replication.
                        if (-not $pubDatabase.LogReaderAgentExists) {
                            Write-Message -Level Verbose -Message "Create log reader agent job for $Database on $instance"
                            if ($LogReaderAgentCredential) {
                                $pubDatabase.LogReaderAgentProcessSecurity.Login = $LogReaderAgentCredential.UserName
                                $pubDatabase.LogReaderAgentProcessSecurity.Password = $LogReaderAgentCredential.Password
                            }

                            #(Optional) Set the SqlStandardLogin and SqlStandardPassword or
                            # SecureSqlStandardPassword fields of LogReaderAgentPublisherSecurity when using SQL Server Authentication to connect to the Publisher.

                            $pubDatabase.CreateLogReaderAgent()
                        } else {
                            Write-Message -Level Verbose -Message "Log reader agent job already exists for $Database on $instance"
                        }

                    } elseif ($Type -eq 'Merge') {
                        Write-Message -Level Verbose -Message "Enable merge publishing publication on $instance.$Database"
                        $pubDatabase.EnabledMergePublishing = $true
                        $pubDatabase.CommitPropertyChanges()
                    }

                    if ($Type -in ('Transactional', 'Snapshot')) {

                        $transPub = New-Object Microsoft.SqlServer.Replication.TransPublication
                        $transPub.ConnectionContext = $replServer.ConnectionContext
                        $transPub.DatabaseName = $Database
                        $transPub.Name = $Name
                        $transPub.Type = $Type
                        $transPub.Create()

                        # create the Snapshot Agent job
                        $transPub.CreateSnapshotAgent()

                        <#
                        TODO: add SnapshotGenerationAgentProcessSecurity creds in?

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
                        $mergePub.Name = $Name
                        $mergePub.Create()

                        # create the Snapshot Agent job
                        $mergePub.CreateSnapshotAgent()

                        <#
                        TODO: add SnapshotGenerationAgentProcessSecurity creds in?

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
            Get-DbaRepPublication -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database -Name $Name
        }
    }
}