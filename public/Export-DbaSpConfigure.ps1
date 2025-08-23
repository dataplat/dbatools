function Export-DbaSpConfigure {
    <#
    .SYNOPSIS
        Generates SQL script containing all sp_configure settings for SQL Server instance configuration replication and documentation.

    .DESCRIPTION
        Creates a complete SQL script file with EXEC sp_configure statements for all server configuration options, including advanced settings. This script can be executed on another SQL Server instance to replicate the exact same configuration settings, making it invaluable for environment standardization, disaster recovery preparation, or compliance documentation. The function temporarily enables 'show advanced options' if needed to capture all available settings, then restores the original setting.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input.
        You must have sysadmin access if needs to set 'show advanced options' to 1 and server version must be SQL Server version 2005 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Path
        Specifies the directory where the sp_configure script files will be exported. Defaults to the configured DbatoolsExport path.
        Use this when you need to organize configuration scripts in a specific location for documentation or deployment procedures.

    .PARAMETER FilePath
        Specifies the complete file path including filename for the exported sp_configure script. Overrides the Path parameter when specified.
        Use this when you need precise control over the output filename, especially for automated deployment scripts or standardized naming conventions.

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
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$Path = (Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport'),
        [Alias("OutFile", "FileName")]
        [string]$FilePath,
        [switch]$EnableException
    )
    begin {
        $null = Test-ExportDirectory -Path $Path
    }
    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $FilePath = Get-ExportFilePath -Path $PSBoundParameters.Path -FilePath $PSBoundParameters.FilePath -Type sql -ServerName $instance
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
                Set-Content -Path $FilePath "EXEC sp_configure 'show advanced options' , 1;  RECONFIGURE WITH OVERRIDE"
            } catch {
                Stop-Function -Message "Can't write to $FilePath" -ErrorRecord $_ -Continue
            }

            foreach ($sourceprop in $server.Configuration.Properties) {
                $displayname = $sourceprop.DisplayName
                $configvalue = $sourceprop.ConfigValue
                Add-Content -Path $FilePath "EXEC sp_configure '$displayname' , $configvalue;"
            }

            if ($ShowAdvancedOptions -eq 0) {
                Add-Content -Path $FilePath "EXEC sp_configure 'show advanced options' , 0;"
                Add-Content -Path $FilePath "RECONFIGURE WITH OVERRIDE"

                $server.Configuration.ShowAdvancedOptions.ConfigValue = $false
                $server.Configuration.Alter($true)
            }
            Get-ChildItem -Path $FilePath
        }
    }
    end {
        Write-Message -Level Verbose -Message "Server configuration export finished"
    }
}