function Get-DbaReplPublication {
    <#
    .SYNOPSIS
        Retrieves replication publications from SQL Server instances, including transactional, merge, and snapshot publications.

    .DESCRIPTION
        Scans SQL Server instances to identify and return all replication publications configured as publishers. This function examines each database's replication options to locate published databases, then retrieves detailed information about their publications including associated articles and subscriptions. DBAs use this to audit replication topology, troubleshoot publication configuration issues, and document existing replication setup across their environment. Results can be filtered by specific databases, publication names, or publication types to focus on particular replication components.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process. If unspecified, all databases will be processed.

    .PARAMETER Name
        The name of the publication.

    .PARAMETER Type
        Limit by specific type of publication. Valid choices include: Transactional, Merge, Snapshot.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: repl, Replication
        Author: Colin Douglas

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaReplPublication

    .EXAMPLE
        PS C:\> Get-DbaReplPublication -SqlInstance sql2008, sqlserver2012

        Return all publications for servers sql2008 and sqlserver2012.

    .EXAMPLE
        PS C:\> Get-DbaReplPublication -SqlInstance sql2008 -Database TestDB

        Return all publications on server sql2008 for only the TestDB database

    .EXAMPLE
        PS C:\> Get-DbaReplPublication -SqlInstance sql2008 -Type Transactional

        Return all transactional publications on server sql2008.

    .EXAMPLE
        PS C:\> Get-DbaReplPublication -SqlInstance mssql1 -Name Merge

        Returns the Mergey publications on server mssql1

    .EXAMPLE
        PS C:\> Connect-DbaInstance -SqlInstance mssql1 | Get-DbaReplPublication

        Returns all publications on server mssql1 using the pipeline.
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [String]$Name,
        [Alias("PublicationType")]
        [ValidateSet("Transactional", "Merge", "Snapshot")]
        [object[]]$Type,
        [switch]$EnableException
    )
    begin {
        Add-ReplicationLibrary
    }
    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($instance in $SqlInstance) {
            # Connect to Publisher
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            try {
                $databases = $server.Databases | Where-Object { $_.IsAccessible -eq $true -and (-not $_.IsSystemObject) }
                if ($Database) {
                    $databases = $databases | Where-Object Name -In $Database
                }
            } catch {
                Stop-Function -Message "Unable to get databases for" -ErrorRecord $_ -Target $server -Continue
            }

            try {
                foreach ($db in $databases) {

                    #test if the database published
                    if ((($db.ReplicationOptions -band [Microsoft.SqlServer.Management.Smo.ReplicationOptions]::Published) -ne [Microsoft.SqlServer.Management.Smo.ReplicationOptions]::Published) -and
                        (($db.ReplicationOptions -band [Microsoft.SqlServer.Management.Smo.ReplicationOptions]::MergePublished) -ne [Microsoft.SqlServer.Management.Smo.ReplicationOptions]::MergePublished)) {
                        # The database is not published
                        Write-Message -Level Verbose -Message "Skipping $($db.name). Database is not published."
                        continue
                    }


                    $repDB = Connect-ReplicationDB -Server $server -Database $db -EnableException:$EnableException

                    $pubTypes = $repDB.TransPublications + $repDB.MergePublications

                    if ($Type) {
                        $pubTypes = $pubTypes | Where-Object Type -in $Type
                    }

                    if ($Name) {
                        $pubTypes = $pubTypes | Where-Object Name -in $Name
                    }

                    foreach ($pub in $pubTypes) {
                        if ($pub.Type -eq 'Merge') {
                            $articles = $pub.MergeArticles
                            $subscriptions = $pub.MergeSubscriptions
                        } else {
                            $articles = $pub.TransArticles
                            $subscriptions = $pub.TransSubscriptions
                        }


                        Add-Member -Force -InputObject $pub -MemberType NoteProperty -Name ComputerName -Value $server.ComputerName
                        Add-Member -Force -InputObject $pub -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
                        Add-Member -Force -InputObject $pub -MemberType NoteProperty -Name SQLInstance -Value $server
                        Add-Member -Force -InputObject $pub -MemberType NoteProperty -Name Articles -Value $articles
                        Add-Member -Force -InputObject $pub -MemberType NoteProperty -Name Subscriptions -Value $subscriptions

                        Select-DefaultView -InputObject $pub -Property ComputerName, InstanceName, SQLInstance, DatabaseName, Name, Type, Articles, Subscriptions

                    }
                }
            } catch {
                Stop-Function -Message "Unable to get publications from " -ErrorRecord $_ -Target $server -Continue
            }
        }
    }
}