function Get-DbaDetachedDatabaseInfo {
    <#
        .SYNOPSIS
            Get detailed information about detached SQL Server database files.

        .DESCRIPTION
            Gathers the following information from detached database files: database name, SQL Server version (compatibility level), collation, and file structure.

            "Data files" and "Log file" report the structure of the data and log files as they were when the database was detached. "Database version" is the compatibility level.

            MDF files are most easily read by using a SQL Server to interpret them. Because of this, you must specify a SQL Server and the path must be relative to the SQL Server.

        .PARAMETER SqlInstance
            Source SQL Server. This instance must be online and is required to parse the information contained with in the detached database file.

            This function will not attach the database file, it will only use SQL Server to read its contents.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Path
            Specifies the path to the MDF file to be read. This path must be readable by the SQL Server service account. Ideally, the MDF will be located on the SQL Server itself, or on a network share to which the SQL Server service account has access.

        .NOTES
            Tags: DisasterRecovery
            dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Get-DbaDetachedDatabaseInfo

        .EXAMPLE
            Get-DbaDetachedDatabaseInfo -SqlInstance sql2016 -Path M:\Archive\mydb.mdf

            Returns information about the detached database file M:\Archive\mydb.mdf using the SQL Server instance sql2016. The M drive is relative to the SQL Server instance.
     #>

    [CmdletBinding(DefaultParameterSetName = "Default")]
    Param (
        [parameter(Mandatory = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter]$SqlInstance,
        [parameter(Mandatory = $true)]
        [Alias("Mdf")]
        [string]$Path,
        [PSCredential]$SqlCredential
    )

    begin {
        function Get-MdfFileInfo {
            $datafiles = New-Object System.Collections.Specialized.StringCollection
            $logfiles = New-Object System.Collections.Specialized.StringCollection

            $servername = $server.name
            $serviceaccount = $server.ServiceAccount

            $exists = Test-DbaSqlPath -SqlInstance $server -Path $Path

            if ($exists -eq $false) {
                throw "$servername cannot access the file $path. Does the file exist and does the service account ($serviceaccount) have access to the path?"
            }

            try {
                $detachedDatabaseInfo = $server.DetachedDatabaseInfo($path)
                $dbname = ($detachedDatabaseInfo | Where-Object { $_.Property -eq "Database name" }).Value
                $exactdbversion = ($detachedDatabaseInfo | Where-Object { $_.Property -eq "Database version" }).Value
                $collationid = ($detachedDatabaseInfo | Where-Object { $_.Property -eq "Collation" }).Value
            }
            catch {
                throw "$servername cannot read the file $path. Is the database detached?"
            }

            switch ($exactdbversion) {
                852 { $dbversion = "SQL Server 2016" }
                829 { $dbversion = "SQL Server 2016 Prerelease" }
                782 { $dbversion = "SQL Server 2014" }
                706 { $dbversion = "SQL Server 2012" }
                684 { $dbversion = "SQL Server 2012 CTP1" }
                661 { $dbversion = "SQL Server 2008 R2" }
                660 { $dbversion = "SQL Server 2008 R2" }
                655 { $dbversion = "SQL Server 2008 SP2+" }
                612 { $dbversion = "SQL Server 2005" }
                611 { $dbversion = "SQL Server 2005" }
                539 { $dbversion = "SQL Server 2000" }
                515 { $dbversion = "SQL Server 7.0" }
                408 { $dbversion = "SQL Server 6.5" }
                default { $dbversion = "Unknown" }
            }

            $collationsql = "SELECT name FROM fn_helpcollations() where collationproperty(name, N'COLLATIONID')  = $collationid"

            try {
                $dataset = $server.databases['master'].ExecuteWithResults($collationsql)
                $collation = "$($dataset.Tables[0].Rows[0].Item(0))"
            }
            catch {
                $collation = $collationid
            }

            if ($collation.length -eq 0) { $collation = $collationid }

            try {
                foreach ($file in $server.EnumDetachedDatabaseFiles($path)) {
                    $datafiles += $file
                }

                foreach ($file in $server.EnumDetachedLogFiles($path)) {
                    $logfiles += $file
                }
            }
            catch {
                throw "$servername unable to enumerate database or log structure information for $path"
            }

            $mdfinfo = [pscustomobject]@{
                Name         = $dbname
                Version      = $dbversion
                ExactVersion = $exactdbversion
                Collation    = $collation
                DataFiles    = $datafiles
                LogFiles     = $logfiles
            }

            return $mdfinfo
        }
    }

    process {

        $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        $mdfinfo = Get-MdfFileInfo $server $path

    }

    end {
        $server.ConnectionContext.Disconnect()
        return $mdfinfo
    }
}
