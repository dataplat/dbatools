function Get-DbaDbDetachedFileInfo {
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
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Path
        Specifies the path to the MDF file to be read. This path must be readable by the SQL Server service account. Ideally, the MDF will be located on the SQL Server itself, or on a network share to which the SQL Server service account has access.

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
            $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Error occurred while establishing connection to $SqlInstance" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance
            return
        }
        $servername = $server.name
        $serviceaccount = $server.ServiceAccount
    }
    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($filepath in $Path) {
            $datafiles = New-Object System.Collections.Specialized.StringCollection
            $logfiles = New-Object System.Collections.Specialized.StringCollection

            if (-not (Test-DbaPath -SqlInstance $server -Path $filepath)) {
                Stop-Function -Message "$servername cannot access the file $filepath. Does the file exist and does the service account ($serviceaccount) have access to the path?" -Continue
            }

            try {
                $detachedDatabaseInfo = $server.DetachedDatabaseInfo($filepath)
                $dbname = ($detachedDatabaseInfo | Where-Object { $_.Property -eq "Database name" }).Value
                $exactdbversion = ($detachedDatabaseInfo | Where-Object { $_.Property -eq "Database version" }).Value
                $collationid = ($detachedDatabaseInfo | Where-Object { $_.Property -eq "Collation" }).Value
            } catch {
                Stop-Function -Message "$servername cannot read the file $filepath. Is the database detached?" -Continue
            }

            switch ($exactdbversion) {
                869 { $dbversion = "SQL Server 2017" }
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

            $collationsql = "SELECT name FROM fn_helpcollations() where collationproperty(name, N'COLLATIONID')  = $collationid"

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
            [pscustomobject]@{
                ComputerName = $SqlInstance.ComputerName
                InstanceName = $SqlInstance.InstanceName
                SqlInstance  = $SqlInstance.InputObject
                Name         = $dbname
                Version      = $dbversion
                ExactVersion = $exactdbversion
                Collation    = $collation
                DataFiles    = $datafiles
                LogFiles     = $logfiles
            }
        }
    }
}