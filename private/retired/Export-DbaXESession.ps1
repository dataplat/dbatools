function Export-DbaXESession {
    <#
    .SYNOPSIS
        Generates T-SQL creation scripts for Extended Events sessions to files or console

    .DESCRIPTION
        Generates T-SQL scripts that can recreate your Extended Events sessions, making it easy to migrate monitoring configurations between environments or create backups of your XE session definitions. This is particularly useful when moving sessions from development to production, creating deployment scripts, or documenting your current monitoring setup for compliance purposes. The function connects to your SQL Server instances, retrieves the session definitions, and outputs the complete CREATE EVENT SESSION statements with all events, actions, targets, and configuration settings intact.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input.
        Server version must be SQL Server version 2008 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER InputObject
        Accepts Extended Event session objects from Get-DbaXESession for pipeline processing. Use this when you already have session objects loaded and want to export specific sessions without re-querying the server.

    .PARAMETER Session
        Specifies specific Extended Event session names to export instead of all sessions. Accepts multiple session names and supports wildcards for pattern matching. Use this when you only need to export specific monitoring configurations rather than all sessions on the server.

    .PARAMETER Path
        Specifies the output directory for the generated T-SQL scripts. Creates automatically named files using the format ServerName-YYYYMMDDHHMMSS-xe.sql. Use this when you want files organized in a specific directory with consistent naming for multiple servers or scheduled exports.

    .PARAMETER FilePath
        Sets the exact file path and name for the output script. Use this when you need precise control over the output file location and naming. When exporting from multiple servers to a single file, you must also use -Append to prevent data loss from overwriting.

    .PARAMETER Encoding
        Controls the character encoding for the output file. Defaults to UTF8 which handles international characters properly. Use ASCII only if you need compatibility with older systems that don't support Unicode. Use Unicode (UTF-16) if required by specific deployment tools or when working with non-Latin scripts.

    .PARAMETER Passthru
        Displays the generated T-SQL script in the console instead of writing to a file. Use this for immediate review of the session definitions, copying to clipboard, or redirecting to other tools in your PowerShell pipeline.

    .PARAMETER BatchSeparator
        Sets the T-SQL batch separator in the output script, typically "GO". Use an empty string to remove batch separators when the target environment doesn't support them, or customize for specific deployment tools that require different separators.

    .PARAMETER NoPrefix
        Removes the header comments that identify when and who created the script. Use this when you need clean T-SQL scripts without metadata comments, or when scripts will be version controlled and you want to avoid unnecessary differences between exports.

    .PARAMETER NoClobber
        Prevents overwriting an existing file when using -FilePath. The function will stop with an error if the target file already exists. Use this as a safety check when you want to ensure you don't accidentally replace important script files.

    .PARAMETER Append
        Adds new content to an existing file instead of overwriting when using -FilePath. Required when exporting sessions from multiple servers to a single consolidated script file. Use this to build comprehensive deployment scripts that include sessions from multiple SQL Server instances.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: ExtendedEvent, XE, XEvent
        Author: Patrick Flynn (@sqllensman)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Export-DbaXESession

    .INPUTS
        A DbaInstanceParameter representing an array of SQL Server instances or output from Get-DbaSession

    .OUTPUTS
        System.String (when -Passthru is specified or no output path is specified)

        Returns the generated T-SQL CREATE EVENT SESSION script as a string. The script contains the complete definition of the Extended Events session including all events, actions, targets, and configuration settings.

        System.IO.FileInfo (when -Path or -FilePath is specified)

        Returns file information objects for each generated script file. One file is created per SQL Server instance processed. When exporting multiple sessions from the same instance using -Append, only the first session returns file information for that instance.

    .EXAMPLE
        PS C:\> Export-DbaXESession -SqlInstance sourceserver -Passthru

        Exports a script to create all Extended Events Sessions on sourceserver to the console
        Will include prefix information containing creator and datetime. and uses the default value for BatchSeparator value from configuration Formatting.BatchSeparator

    .EXAMPLE
        PS C:\> Export-DbaXESession -SqlInstance sourceserver

        Exports a script to create all Extended Events Sessions on sourceserver. As no Path was defined - automatically determines filename based on the Path.DbatoolsExport configuration setting, current time and server name like Servername-YYYYMMDDhhmmss-sp_configure.sql
        Will include prefix information containing creator and datetime. and uses the default value for BatchSeparator value from configuration Formatting.BatchSeparator

    .EXAMPLE
        PS C:\> Export-DbaXESession -SqlInstance sourceserver -FilePath C:\temp

        Exports a script to create all Extended Events Sessions on sourceserver to the directory C:\temp using the default name format of Servername-YYYYMMDDhhmmss-sp_configure.sql
        Will include prefix information containing creator and datetime. and uses the default value for BatchSeparator value from configuration Formatting.BatchSeparator

    .EXAMPLE
        PS C:\> $cred = Get-Credential sqladmin
        PS C:\> Export-DbaXESession -SqlInstance sourceserver -SqlCredential $cred -FilePath C:\temp\EEvents.sql -BatchSeparator "" -NoPrefix -NoClobber

        Exports a script to create all Extended Events Sessions on sourceserver to the file C:\temp\EEvents.sql.
        Will exclude prefix information containing creator and datetime and does not include a BatchSeparator
        Will not overwrite file if it already exists

    .EXAMPLE
        PS C:\> 'Server1', 'Server2' | Export-DbaXESession -FilePath 'C:\Temp\EE.sql' -Append

        Exports a script to create all Extended Events Sessions for Server1 and Server2 using pipeline.
        Writes to a single file using the Append switch

    .EXAMPLE
        PS C:\> Get-DbaXESession -SqlInstance Server1, Server2 -Session system_health | Export-DbaXESession -Path 'C:\Temp'

        Exports a script to create the System_Health Extended Events Sessions for Server1 and Server2 using pipeline.
        Write to the directory C:\temp using the default name format of Servername-YYYYMMDDhhmmss-sp_configure.sql
        Will include prefix information containing creator and datetime. and uses the default value for BatchSeparator value from configuration Formatting.BatchSeparator

    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.XEvent.Session[]]$InputObject,
        [string[]]$Session,
        [string]$Path = (Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport'),
        [Alias("OutFile", "FileName")]
        [string]$FilePath,
        [ValidateSet('ASCII', 'BigEndianUnicode', 'Byte', 'String', 'Unicode', 'UTF7', 'UTF8', 'Unknown')]
        [string]$Encoding = 'UTF8',
        [switch]$Passthru,
        [string]$BatchSeparator = (Get-DbatoolsConfigValue -FullName 'Formatting.BatchSeparator'),
        [switch]$NoPrefix,
        [switch]$NoClobber,
        [switch]$Append,
        [switch]$EnableException
    )
    begin {
        $null = Test-ExportDirectory -Path $Path
        $instanceArray = @()
        $SessionCollection = New-Object System.Collections.ArrayList
        if ($IsLinux -or $IsMacOs) {
            $executingUser = $env:USER
        } else {
            $executingUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        }
        $commandName = $MyInvocation.MyCommand.Name
    }
    process {
        if (Test-FunctionInterrupt) { return }

        if (-not $InputObject -and -not $SqlInstance) {
            Stop-Function -Message "You must pipe in a Credential or specify a SqlInstance"
            return
        }

        if ($SqlInstance) {
            $InputObject = Get-DbaXESession -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Session $Session
        }

        foreach ($xe in $InputObject) {
            $server = $xe.Parent
            $serverName = $server.Name.Replace('\', '$')

            $outsql = $xe.ScriptCreate().GetScript()

            $SessionObject = [PSCustomObject]@{
                Name     = $xe.Name
                Instance = $serverName
                Sql      = $outsql[0]
            }
            $SessionCollection.Add($SessionObject) | Out-Null
        }
    }
    end {
        $eol = [System.Environment]::NewLine

        foreach ($SessionObject in $SessionCollection) {

            if ($NoPrefix) {
                $prefix = $null
            } else {
                $prefix = "/*$eol`tCreated by $executingUser using dbatools $commandName for objects on $($SessionObject.Instance) at $(Get-Date -Format (Get-DbatoolsConfigValue -FullName 'Formatting.DateTime'))$eol`tSee https://dbatools.io/$commandName for more information$eol*/"
            }

            if ($BatchSeparator) {
                $sql = $SessionObject.SQL -join "$eol$BatchSeparator$eol"
                #add the final GO
                $sql += "$eol$BatchSeparator"
            } else {
                $sql = $SessionObject.SQL
            }

            if ($Passthru) {
                if ($null -ne $prefix) {
                    $sql = "$prefix$eol$sql"
                }
                $sql
            } elseif ($Path -Or $FilePath) {
                if ($instanceArray -notcontains $($SessionObject.Instance)) {
                    if ($null -ne $prefix) {
                        $sql = "$prefix$eol$sql"
                    }
                    $scriptPath = Get-ExportFilePath -Path $PSBoundParameters.Path -FilePath $PSBoundParameters.FilePath -Type sql -ServerName $SessionObject.Instance
                    if ((Test-Path -Path $scriptPath) -and $NoClobber) {
                        Stop-Function -Message "File already exists. If you want to overwrite it remove the -NoClobber parameter. If you want to append data, please Use -Append parameter." -Target $scriptPath -Continue
                    }
                    $sql | Out-File -Encoding $Encoding -FilePath $scriptPath -Append:$Append -NoClobber:$NoClobber
                    $instanceArray += $SessionObject.Instance
                    Get-ChildItem $scriptPath
                } else {
                    $sql | Out-File -Encoding $Encoding -FilePath $scriptPath -Append
                }
            } else {
                $sql
            }
        }
    }
}