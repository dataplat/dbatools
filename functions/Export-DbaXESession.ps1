function Export-DbaXESession {
    <#
    .SYNOPSIS
        Exports Extended Events creation script to a T-SQL file or console.

    .DESCRIPTION
        Exports script to create Extended Events Session to sql file  or console.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input.
        Server version must be SQL Server version 2008 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER InputObject
        A SQL Management Object - Microsoft.SqlServer.Management.XEvent.Session such as the one returned from Get-DbaSession

    .PARAMETER Session
        The Extended Event Session(s) to process. If unspecified, all Extended Event Sessions will be processed. This is ignored if An input object from Get-DbaSession is specified

    .PARAMETER Path
        Specifies the directory where the file or files will be exported.

    .PARAMETER FilePath
        Specifies the full file path of the output file.
        If FilePath is specified and more than one Server is in input then -Append parameter is required to avoid overwriting data

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

    .PARAMETER BatchSeparator
        Batch separator for scripting output. Uses the value from configuration Formatting.BatchSeparator by default. This is normally "GO"

    .PARAMETER NoPrefix
        If this switch is used, the scripts will not include prefix information containing creator and datetime.

    .PARAMETER NoClobber
        Do not overwrite file. Only required if FilePath is specified

    .PARAMETER Append
        Append to file. Only required if FilePath is specified

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
        Creates a new file for each SQL Server Instance

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
        $executingUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $commandName = $MyInvocation.MyCommand.Name
    }
    process {
        if (Test-FunctionInterrupt) { return }

        if (-not $InputObject -and -not $SqlInstance) {
            Stop-Function -Message "You must pipe in a Credential or specify a SqlInstance"
            return
        }

        if ($SqlInstance) {
            $InputObject = Get-DbaXeSession -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Session $Session
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
        foreach ($SessionObject in $SessionCollection) {

            if ($NoPrefix) {
                $prefix = $null
            } else {
                $prefix = "/*`n`tCreated by $executingUser using dbatools $commandName for objects on $($SessionObject.Instance) at $(Get-Date -Format (Get-DbatoolsConfigValue -FullName 'Formatting.DateTime'))`n`tSee https://dbatools.io/$commandName for more information`n*/"
            }

            if ($BatchSeparator) {
                $sql = $SessionObject.SQL -join "`r`n$BatchSeparator`r`n"
                #add the final GO
                $sql += "`r`n$BatchSeparator"
            } else {
                $sql = $SessionObject.SQL
            }

            if ($Passthru) {
                if ($null -ne $prefix) {
                    $sql = "$prefix`r`n$sql"
                }
                $sql
            } elseif ($Path -Or $FilePath) {
                if ($instanceArray -notcontains $($SessionObject.Instance)) {
                    if ($null -ne $prefix) {
                        $sql = "$prefix`r`n$sql"
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