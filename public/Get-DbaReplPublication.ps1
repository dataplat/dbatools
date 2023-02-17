function Get-DbaReplPublication {
    <#
    .SYNOPSIS
        Displays all publications for a server or database.

    .DESCRIPTION
        Quickly find all transactional, merge, and snapshot publications on a specific server or database.

        All replication commands need SQL Server Management Studio installed and are therefore currently not supported.
        Have a look at this issue to get more information: https://github.com/dataplat/dbatools/issues/7428

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER Database
        The database(s) to process. If unspecified, all databases will be processed.

    .PARAMETER Name
        The name of the publication.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER PublicationType
        Limit by specific type of publication. Valid choices include: Transactional, Merge, Snapshot

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Replication
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
        PS C:\> Get-DbaReplPublication -SqlInstance sql2008 -PublicationType Transactional

        Return all publications on server sql2008 for all databases that have Transactional publications

    .EXAMPLE
        PS C:\> Get-DbaReplPublication -SqlInstance mssql1 -Name Mergey

        Returns the Mergey publications on server mssql1
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [object[]]$Database,
        [PSCredential]$SqlCredential,
        [String]$Name,
        [ValidateSet("Transactional", "Merge", "Snapshot")]
        [object[]]$PublicationType,     #TODO: change to just Type
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

            $databases = $server.Databases | Where-Object { $_.IsAccessible -eq $true -and (-not $_.IsSystemObject) }
            if ($Database) {
                $databases = $databases | Where-Object Name -In $Database
            }


            foreach ($db in $databases) {

                if (($db.ReplicationOptions -ne "Published") -and ($db.ReplicationOptions -ne "MergePublished")) {
                    Write-Message -Level Verbose -Message "Skipping $($db.name). Database is not published."
                }

                $repDB = Connect-ReplicationDB -Server $server -Database $db


                $pubTypes = $repDB.TransPublications + $repDB.MergePublications

                if ($PublicationType) {
                    $pubTypes = $pubTypes | Where-Object Type -in $PublicationType
                }

                if ($Name) {
                    $pubTypes = $pubTypes | Where-Object Name -in $Name
                }

                foreach ($pub in $pubTypes) {

                    [PSCustomObject]@{
                        ComputerName    = $server.ComputerName
                        InstanceName    = $server.ServiceName
                        SqlInstance     = $server.Name
                        Server          = $server.name
                        Database        = $db.name
                        PublicationName = $pub.Name  #TODO: change to just name
                        PublicationType = $pub.Type  #TODO: change to just Type
                        Articles        = $pub.TransArticles #TODO what about merge articles?

                    }
                }
            }
        }
    }
}