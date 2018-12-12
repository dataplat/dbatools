#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Export-DbaSpConfigure {
    <#
    .SYNOPSIS
        Exports advanced sp_configure global configuration options to sql file.

    .DESCRIPTION
        Exports advanced sp_configure global configuration options to sql file.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input.
        You must have sysadmin access if needs to set 'show advanced options' to 1 and server version must be SQL Server version 2005 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

    .PARAMETER Path
        Specifies the path to a file which will contain the sp_configure queries necessary to replicate the configuration settings on another instance. This file is suitable for input into Import-DbaSPConfigure.
        If not specified will output to My Documents folder with default name of ServerName-MMDDYYYYhhmmss-sp_configure.sql
        If a directory is passed then uses default name of ServerName-MMDDYYYYhhmmss-sp_configure.sql

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: SpConfig, Configure, Configuration
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Export-DbaSpConfigure

    .INPUTS
        A DbaInstanceParameter representing an array of SQL Server instances.

    .OUTPUTS
        Creates a new file for each SQL Server Instance

    .EXAMPLE
        PS C:\> Export-DbaSpConfigure -SqlInstance sourceserver

        Exports the SPConfigure settings on sourceserver. As no Path was defined outputs to My Documents folder with default name format of Servername-MMDDYYYYhhmmss-sp_configure.sql

    .EXAMPLE
        PS C:\> Export-DbaSpConfigure -SqlInstance sourceserver -Path C:\temp

        Exports the SPConfigure settings on sourceserver to the directory C:\temp using the default name format

    .EXAMPLE
        PS C:\> $cred = Get-Credential sqladmin
        PS C:\> Export-DbaSpConfigure -SqlInstance sourceserver -SqlCredential $cred -Path C:\temp\sp_configure.sql

        Exports the SPConfigure settings on sourceserver to the file C:\temp\sp_configure.sql. Uses SQL Authentication to connect. Will require SysAdmin rights if needs to set 'show advanced options'

    .EXAMPLE
        PS C:\> 'Server1', 'Server2' | Export-DbaSpConfigure -Path C:\temp\configure.sql

        Exports the SPConfigure settings for Server1 and Server2 using pipeline. As more than 1 Server adds prefix of Servername and date to the file name and saves to file like  C:\temp\Servername-MMDDYYYYhhmmss-configure.sql

    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$Path,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if (-not (Test-Bound -ParameterName Path)) {
                $timenow = (Get-Date -uformat "%m%d%Y%H%M%S")
                $mydocs = [Environment]::GetFolderPath('MyDocuments')
                $filepath = "$mydocs\$($server.name.replace('\', '$'))-$timenow-sp_configure.sql"
            }

            if (Test-Path $Path -PathType Container) {
                $timenow = (Get-Date -uformat "%m%d%Y%H%M%S")
                $filepath = Join-Path -Path $Path -ChildPath "$($server.name.replace('\', '$'))-$timenow-sp_configure.sql"
            } elseif (Test-Path $Path -PathType Leaf) {
                if ($SqlInstance.Count -gt 1) {
                    $timenow = (Get-Date -uformat "%m%d%Y%H%M%S")
                    $PathData = Get-ChildItem $Path
                    $filepath = "$($PathData.DirectoryName)\$($server.name.replace('\', '$'))-$timenow-$($PathData.Name)"
                } else {
                    $filepath = $Path
                }
            }

            If (-not $filepath) {
                $filepath = $Path
            }

            $topdir = Split-Path -Path $filepath

            if (-not (Test-Path -Path $topdir)) {
                New-Item -Path $topdir -ItemType Directory
            }

            $ShowAdvancedOptions = $server.Configuration.ShowAdvancedOptions.ConfigValue

            if ($ShowAdvancedOptions -eq 0) {
                try {
                    $server.Configuration.ShowAdvancedOptions.ConfigValue = $true
                    $server.Configuration.Alter($true)
                } catch {
                    Stop-Function -Message "Can't set 'show advanced options' to 1 on instance $instance" -ErrorRecord $_ -Continue
                }
            }

            try {
                Set-Content -Path $filepath "EXEC sp_configure 'show advanced options' , 1;  RECONFIGURE WITH OVERRIDE"
            } catch {
                Stop-Function -Message "Can't write to $filepath" -ErrorRecord $_ -Continue
            }

            foreach ($sourceprop in $server.Configuration.Properties) {
                $displayname = $sourceprop.DisplayName
                $configvalue = $sourceprop.ConfigValue
                Add-Content -Path $filepath "EXEC sp_configure '$displayname' , $configvalue;"
            }

            if ($ShowAdvancedOptions -eq 0) {
                Add-Content -Path $filepath "EXEC sp_configure 'show advanced options' , 0;"
                Add-Content -Path $filepath "RECONFIGURE WITH OVERRIDE"

                $server.Configuration.ShowAdvancedOptions.ConfigValue = $false
                $server.Configuration.Alter($true)
            }
            Get-ChildItem -Path $filepath
        }
    }

    end {
        Write-Message -Level Verbose -Message "Server configuration export finished"

        Test-DbaDeprecation -DeprecatedOn "1.0.0" -EnableException:$false -Alias Export-SqlSpConfigure
    }
}