function Export-DbaDacpac {
    <#
    .SYNOPSIS
    Exports a dacpac from a server.

    .DESCRIPTION
    Using SQLPackage, export a dacpac from an instance of SQL Server.

    Note - Extract from SQL Server is notoriously flaky - for example if you have three part references to external databases it will not work.

    For help with the extract action parameters and properties, refer to https://msdn.microsoft.com/en-us/library/hh550080(v=vs.103).aspx

    .PARAMETER SqlInstance
    SQL Server name or SMO object representing the SQL Server to connect to and publish to.

    .PARAMETER SqlCredential
    Allows you to login to servers using alternative logins instead Integrated, accepts Credential object created by Get-Credential

    .PARAMETER Path
    The directory where the .dacpac files will be exported to. Defaults to documents.

    .PARAMETER Database
    The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
    The database(s) to exclude - this list is auto-populated from the server

    .PARAMETER AllUserDatabases
    Run command against all user databases

    .PARAMETER ExtendedParameters
    Optional parameters used to extract the DACPAC. More information can be found at
    https://msdn.microsoft.com/en-us/library/hh550080.aspx

    .PARAMETER ExtendedProperties
    Optional properties used to extract the DACPAC. More information can be found at
    https://msdn.microsoft.com/en-us/library/hh550080.aspx


    .PARAMETER EnableException
    By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
    Tags: Migration, Database, Dacpac
    Author: Richie lee (@bzzzt_io)

    Website: https://dbatools.io
    Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
    License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

    .LINK
    https://dbatools.io/Export-DbaDacpac

    .EXAMPLE
    Export-DbaDacpac -SqlInstance sql2016 -Database SharePoint_Config
    Exports the dacpac for SharePoint_Config on sql2016 to $home\Documents\SharePoint_Config.dacpac

    .EXAMPLE
    $moreprops = "/p:VerifyExtraction=$true /p:CommandTimeOut=10"
    Export-DbaDacpac -SqlInstance sql2016 -Database SharePoint_Config -Path C:\temp -ExtendedProperties $moreprops

    Sets the CommandTimeout to 10 then extracts the dacpac for SharePoint_Config on sql2016 to C:\temp\SharePoint_Config.dacpac then verifies extraction.


    #>
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstance[]]$SqlInstance,
        [Alias("Credential")]
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$AllUserDatabases,
        [string]$Path = "$home\Documents",
        [string]$ExtendedParameters,
        [string]$ExtendedProperties,
        [switch]$EnableException
    )

    process {
        if ((Test-Bound -Not -ParameterName Database) -and (Test-Bound -Not -ParameterName ExcludeDatabase) -and (Test-Bound -Not -ParameterName AllUserDatabases)) {
            Stop-Function -Message "You must specify databases to execute against using either -Database, -ExcludeDatabase or -AllUserDatabases"
        }

        if (-not (Test-Path $Path)) {
            Stop-Function -Message "$Path doesn't exist or access denied"
        }

        if ((Get-Item $path) -isnot [System.IO.DirectoryInfo]) {
            Stop-Function -Message "Path must be a directory"
        }

        foreach ($instance in $sqlinstance) {

            try {
                Write-Message -Level Verbose -Message "Connecting to $instance."
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            $cleaninstance = $instance.ToString().Replace('\', '-')

            $dbs = $server.Databases | Where-Object { $_.IsSystemObject -eq $false -and $_.IsAccessible }

            if ($Database) {
                $dbs = $dbs | Where-Object Name -in $Database
                if (-not $dbs.name) {
                    Stop-Function -Message "Database $Database does not exist on $instance" -Target $instance -Continue
                }
            }

            if ($ExcludeDatabase) {
                $dbs = $dbs | Where-Object Name -notin $ExcludeDatabase
            }

            foreach ($db in $dbs) {
                $dbname = $db.name
                $connstring = $server.ConnectionContext.ConnectionString.Replace('"', "'")
                if ($connstring -notmatch 'Database=') {
                    $connstring = "$connstring;Database=$dbname"
                }
                $filename = "$Path\$cleaninstance-$dbname.dacpac"
                Write-Message -Level Verbose -Message "Exporting $filename"
                Write-Message -Level Verbose -Message "Using connection string $connstring"

                $sqlPackageArgs = "/action:Extract /tf:""$filename"" /SourceConnectionString:""$connstring"" $ExtendedParameters $ExtendedProperties"
                $resultstime = [diagnostics.stopwatch]::StartNew()

                try {
                    $startprocess = New-Object System.Diagnostics.ProcessStartInfo
                    $startprocess.FileName = "$script:PSModuleRoot\bin\smo\sqlpackage.exe"
                    $startprocess.Arguments = $sqlPackageArgs
                    $startprocess.RedirectStandardError = $true
                    $startprocess.RedirectStandardOutput = $true
                    $startprocess.UseShellExecute = $false
                    $startprocess.CreateNoWindow = $true
                    $process = New-Object System.Diagnostics.Process
                    $process.StartInfo = $startprocess
                    $process.Start() | Out-Null
                    $process.WaitForExit()
                    $stdout = $process.StandardOutput.ReadToEnd()
                    $stderr = $process.StandardError.ReadToEnd()
                    Write-Message -level Verbose -Message "StandardOutput: $stdout"

                    [pscustomobject]@{
                        ComputerName = $server.NetName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Database     = $dbname
                        Path         = $filename
                        Elapsed      = [prettytimespan]($resultstime.Elapsed)
                    } | Select-DefaultView -ExcludeProperty ComputerName, InstanceName
                }
                catch {
                    Stop-Function -Message "SQLPackage Failure" -ErrorRecord $_ -Continue
                }

                if ($process.ExitCode -ne 0) {
                    Stop-Function -Message "Standard output - $stderr" -Continue
                }
            }
        }
    }
}