Function Export-DbaJob {
    <#
.SYNOPSIS
Export one, many or all SQL Server Agent jobs

.DESCRIPTION
Exports one, many or all SQL Server Agent jobs as T-SQL output

.PARAMETER SqlInstance
The target SQL Server instance - may be either a string or an SMO Server object

.PARAMETER SqlCredential
Allows you to login to servers using alternative SQL or Windows credentials

.PARAMETER Jobs
By default, all jobs are exported. This parameters allows you to export only specific jobs
	
.PARAMETER Path
The output filename and location. If no path is specified, one will be created 
	
.PARAMETER Append
Append contents to existing file. If append is not specified and the path exists, the export will be skipped.
	
.PARAMETER Encoding
Specifies the file encoding. The default is UTF8.
	
Valid values are:

-- ASCII: Uses the encoding for the ASCII (7-bit) character set.

-- BigEndianUnicode: Encodes in UTF-16 format using the big-endian byte order.

-- Byte: Encodes a set of characters into a sequence of bytes.

-- String: Uses the encoding type for a string.

-- Unicode: Encodes in UTF-16 format using the little-endian byte order.

-- UTF7: Encodes in UTF-7 format.

-- UTF8: Encodes in UTF-8 format.

-- Unknown: The encoding type is unknown or invalid. The data can be treated as binary.

.PARAMETER Passthru
Output script to console

.PARAMETER Silent 
Use this switch to disable any kind of verbose messages

.NOTES
Tags: Migration, Backup

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

.LINK
https://dbatools.io/Export-DbaJob

.EXAMPLE 
Export-DbaJob -SqlInstance sql2016

Exports all jobs on the SQL Server 2016 instance
	
.EXAMPLE 
Export-DbaJob -SqlInstance sql2016 -Jobs syspolicy_purge_history, 'Hourly Log Backups'
	
Exports only syspolicy_purge_history and 'Hourly Log Backups'

#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    Param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [object[]]$SqlInstance,
        [object]$SqlCredential,
        [string]$Path,
        [ValidateSet('ASCII', 'BigEndianUnicode', 'Byte', 'String', 'Unicode', 'UTF7', 'UTF8', 'Unknown')]
        [string]$Encoding = 'UTF8',
        [switch]$Append,
        [switch]$Passthru,
        [switch]$Silent
    )
	
    DynamicParam { if ($SqlInstance) { return Get-ParamSqlDatabases -SqlServer $SqlInstance[0] -SqlCredential $SqlCredential } }
	
    BEGIN {
        $jobs = $psboundparameters.Jobs
        $executinguser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $commandname = $MyInvocation.MyCommand.Name
        $timenow = (Get-Date -uformat "%m%d%Y%H%M%S")
    }
	
    PROCESS {
        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance"
                $server = Connect-SqlServer -SqlServer $instance -SqlCredential $sqlcredential
            }
            catch {
                Stop-Function -Message "Failed to connect to: $instance" -Continue -Target $instance
            }
			
            $servername = $server.name.replace('\', '$')
			
            if (!$passthru) {
                if ($path) {
                    $actualpath = $path
                }
                else {
                    $actualpath = "$servername-$timenow-jobs.sql"
                }
            }
			
            $prefix = "
/*			
	Created by $executinguser using dbatools $commandname for objects on $servername at $(Get-Date)
	See https://dbatools.io/$commandname for more information
*/"
			
            if (!$Append -and (Test-Path -Path $actualpath)) {
                Stop-Function -Message "OutputFile $actualpath already exists and Append was not specified." -Target $actualpath -Continue
            }
			
            $exportjobs = $server.JobServer.Jobs
			
            if ($jobs) {
                $exportjobs = $exportjobs | Where-Object { $_.Name -in $jobs }
            }
			
            if ($passthru) {
                $prefix | Out-String
            }
            else {
                Write-Message -Level Output -Message "Exporting objects on $servername to $actualpath"
                $prefix | Out-File -FilePath $actualpath -Encoding $encoding -Append
            }
			
            foreach ($job in $exportjobs) {
                If ($Pscmdlet.ShouldProcess($env:computername, "Exporting $job from $server to $actualpath")) {
                    Write-Message -Level Verbose -Message "Exporting $job"
					
                    if ($passthru) {
                        $job.Script() | Out-String
                    }
                    else {
                        $job.Script() | Out-File -FilePath $actualpath -Encoding $encoding -Append
                    }
                }
            }
			
            if (!$passthru) {
                Write-Message -Level Output -Message "Completed export for $server"
            }
        }
    }
}