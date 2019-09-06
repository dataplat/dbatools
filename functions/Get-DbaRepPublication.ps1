function Get-DbaRepPublication {
    <#
    .SYNOPSIS
        Displays all publications for a server or database.

    .DESCRIPTION
        Quickly find all transactional, merge, and snapshot publications on a specific server or database.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER Database
        The database(s) to process. If unspecified, all databases will be processed.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER PublicationType
        Limit by specific type of publication. Valid choices include: Transactional, Merge, Snapshot

    .PARAMETER EnableException
        byng this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Replication
        Author: Colin Douglas

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaRepPublication

    .EXAMPLE
        PS C:\> Get-DbaRepPublication -SqlInstance sql2008, sqlserver2012

        Return all publications for servers sql2008 and sqlserver2012.

    .EXAMPLE
        PS C:\> Get-DbaRepPublication -SqlInstance sql2008 -Database TestDB

        Return all publications on server sql2008 for only the TestDB database

    .EXAMPLE
        PS C:\> Get-DbaRepPublication -SqlInstance sql2008 -PublicationType Transactional

        Return all publications on server sql2008 for all databases that have Transactional publications

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [object[]]$Database,
        [PSCredential]$SqlCredential,
        [ValidateSet("Transactional", "Merge", "Snapshot")]
        [object[]]$PublicationType,
        [switch]$EnableException
    )

    process {

        foreach ($instance in $SqlInstance) {

            # Connect to Publisher
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $dbList = $server.Databases

            if ($Database) {
                $dbList = $dbList | Where-Object name -in $Database
            }

            $dbList = $dbList | Where-Object { ($_.ID -gt 4) -and ($_.status -ne "Offline") }


            foreach ($db in $dbList) {

                if (($db.ReplicationOptions -ne "Published") -and ($db.ReplicationOptions -ne "MergePublished")) {
                    Write-Message -Level Verbose -Message "Skipping $($db.name). Database is not published."
                }

                $repDB = Connect-ReplicationDB -Server $server -Database $db

                $pubTypes = $repDB.TransPublications + $repDB.MergePublications

                if ($PublicationType) {
                    $pubTypes = $pubTypes | Where-Object Type -in $PublicationType
                }

                foreach ($pub in $pubTypes) {

                    [PSCustomObject]@{
                        ComputerName    = $server.ComputerName
                        InstanceName    = $server.InstanceName
                        SqlInstance     = $server.SqlInstance
                        Server          = $server.name
                        Database        = $db.name
                        PublicationName = $pub.Name
                        PublicationType = $pub.Type
                    }
                }
            }
        }
    }
}