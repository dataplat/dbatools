function Get-DbaDbDetachedFileInfo {
    <#
    .SYNOPSIS
        Reads detached SQL Server database files to extract metadata and file structure without attaching them.

    .DESCRIPTION
        Analyzes detached MDF files to retrieve essential database metadata including name, SQL Server version, collation, and complete file structure. This lets you examine database files sitting in storage or archives without the risk of attaching them to a live instance.

        Perfect for migration planning when you need to verify compatibility before moving databases between SQL Server versions. Also invaluable for troubleshooting scenarios where you have detached database files and need to understand their structure or requirements before reattachment.

        The function reads the MDF file header using SQL Server's built-in methods, so it requires an online SQL Server instance to interpret the binary data. All file paths must be accessible to the specified SQL Server service account.

        Returns comprehensive details including the original database name, exact SQL Server version (mapped from internal version numbers), collation settings, and complete lists of associated data and log files as they existed when detached.

    .PARAMETER SqlInstance
        Source SQL Server. This instance must be online and is required to parse the information contained with in the detached database file.

        This function will not attach the database file, it will only use SQL Server to read its contents.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Path
        Specifies the full file path to one or more detached MDF database files to analyze. The SQL Server service account must have read access to these file locations.
        Use this when you need to examine database files in archives, backups, or migration staging areas before deciding whether to attach them.
        Supports multiple file paths and accepts wildcards, but each MDF file must be accessible from the specified SQL Server instance.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Database, Detach
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbDetachedFileInfo

    .EXAMPLE
        PS C:\> Get-DbaDbDetachedFileInfo -SqlInstance sql2016 -Path M:\Archive\mydb.mdf

        Returns information about the detached database file M:\Archive\mydb.mdf using the SQL Server instance sql2016. The M drive is relative to the SQL Server instance.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory, ValueFromPipeline)]
        [Alias("Mdf", "FilePath", "FullName")]
        [string[]]$Path,
        [switch]$EnableException
    )
    begin {
        try {
            $server = Connect-DbaInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance
            return
        }
        $servername = $server.name
        $serviceAccount = $server.ServiceAccount
    }
    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($filepath in $Path) {
            $datafiles = New-Object System.Collections.Specialized.StringCollection
            $logfiles = New-Object System.Collections.Specialized.StringCollection

            if (-not (Test-DbaPath -SqlInstance $server -Path $filepath)) {
                Stop-Function -Message "$servername cannot access the file $filepath. Does the file exist and does the service account ($serviceAccount) have access to the path?" -Continue
            }

            try {
                $detachedDatabaseInfo = $server.DetachedDatabaseInfo($filepath)
                $dbName = ($detachedDatabaseInfo | Where-Object { $_.Property -eq "Database name" }).Value
                $exactdbversion = ($detachedDatabaseInfo | Where-Object { $_.Property -eq "Database version" }).Value
                $collationid = ($detachedDatabaseInfo | Where-Object { $_.Property -eq "Collation" }).Value
            } catch {
                Stop-Function -Message "$servername cannot read the file $filepath. Is the database detached?" -Continue
            }

            # Source: https://sqlserverbuilds.blogspot.com/2014/01/sql-server-internal-database-versions.html
            switch ($exactdbversion) {
                998 { $dbversion = "SQL Server 2025" }
                957 { $dbversion = "SQL Server 2022" }
                904 { $dbversion = "SQL Server 2019" }
                869 { $dbversion = "SQL Server 2017" }
                868 { $dbversion = "SQL Server 2017" }
                852 { $dbversion = "SQL Server 2016" }
                782 { $dbversion = "SQL Server 2014" }
                706 { $dbversion = "SQL Server 2012" }
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

            $collationsql = "SELECT name FROM fn_helpcollations() WHERE COLLATIONPROPERTY(name, N'COLLATIONID')  = $collationid"

            try {
                $dataset = $server.databases['master'].ExecuteWithResults($collationsql)
                $collation = "$($dataset.Tables[0].Rows[0].Item(0))"
            } catch {
                $collation = $collationid
            }

            if (-not $collation) { $collation = $collationid }

            try {
                foreach ($file in $server.EnumDetachedDatabaseFiles($filepath)) {
                    $datafiles += $file
                }

                foreach ($file in $server.EnumDetachedLogFiles($filepath)) {
                    $logfiles += $file
                }
            } catch {
                Stop-Function -Message "$servername unable to enumerate database or log structure information for $filepath" -Continue
            }
            [PSCustomObject]@{
                ComputerName = $SqlInstance.ComputerName
                InstanceName = $SqlInstance.InstanceName
                SqlInstance  = $SqlInstance.InputObject
                Name         = $dbName
                Version      = $dbversion
                ExactVersion = $exactdbversion
                Collation    = $collation
                DataFiles    = $datafiles
                LogFiles     = $logfiles
            }
        }
    }
}